#!/usr/bin/env bash
set -Eeuo pipefail

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-curl.sh
# Purpose: Build the latest release version of cURL from source code including nghttp3 support
# Updated: 11.09.2025
# Version: 1.4

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Define logging functions
fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

run() {
    local rendered
    printf -v rendered '%q ' "$@"
    printf '%b[CMD ]%b %s\n' "$GREEN" "$NC" "${rendered% }"
    "$@"
}

require_commands() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
    done
}

detect_cpu_threads() {
    local threads
    threads=""

    if command -v nproc >/dev/null 2>&1; then
        threads="$(nproc 2>/dev/null || true)"
    fi

    if [[ -z "$threads" || ! "$threads" =~ ^[0-9]+$ || "$threads" -lt 1 ]]; then
        threads="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    fi

    if [[ -z "$threads" || ! "$threads" =~ ^[0-9]+$ || "$threads" -lt 1 ]]; then
        threads="1"
    fi

    printf '%s\n' "$threads"
}

ensure_sudo_access() {
    log "Validating sudo access..."
    run sudo -v
}

github_latest_tag() {
    local repo response tag_pattern
    repo="$1"
    tag_pattern="$2"

    response="$(
        curl -fsSL --retry 3 "https://api.github.com/repos/${repo}/tags?per_page=100" \
            | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' \
            | grep -E "$tag_pattern" \
            | head -n1
    )"

    [[ -n "$response" ]] || fail "Unable to determine latest tag for ${repo}"
    printf '%s\n' "$response"
}

# Define program variables
program="curl"
cwd="$PWD/curl-build-script"
curl_tag=""
version=""
formatted_version=""
ssh2_tag=""
ssh2_version=""
nghttp3_tag=""
nghttp3_version=""
tar_file=""
extract_dir=""
install_dir=""
install_dir_override=""
libssh2_install_dir=""
nghttp3_install_dir=""
install_mode="install"
compiler="gcc"
CPU_THREADS="${CPU_THREADS:-$(detect_cpu_threads)}"

# Define OpenSSL installation check
openssl_prefix=$(if [[ -d "/usr/local/ssl" ]]; then echo "/usr/local/ssl"; else echo "/usr"; fi)

# Define environment variables
set_env_vars() {
    case "$compiler" in
        clang)
            CC="${CC:-clang}"
            CXX="${CXX:-clang++}"
            ;;
        gcc)
            CC="${CC:-gcc}"
            CXX="${CXX:-g++}"
            ;;
        *)
            CC="${CC:-$compiler}"
            CXX="${CXX:-${compiler}++}"
            ;;
    esac
    CFLAGS="-O2 -pipe -march=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-I$openssl_prefix/include -I/usr/include/libxml2 -D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

apt_pkgs() {
    local -a apt_cmd available_packages install_cmd missing_packages pkgs unavailable_packages
    apt_cmd=(sudo env DEBIAN_FRONTEND=noninteractive apt)
    pkgs=(
        autoconf autoconf-archive autotools-dev build-essential curl libcurl4 libcurl4-openssl-dev
        libc-ares-dev libldap-dev libnghttp2-dev libpsl-dev libssh2-1-dev libssl-dev libtool
        libzstd-dev pkg-config sed sort tar zlib1g-dev
    )

    missing_packages=()
    available_packages=()
    unavailable_packages=()

    log "Checking package installation status..."

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    for pkg in "${missing_packages[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            available_packages+=("$pkg")
        else
            unavailable_packages+=("$pkg")
        fi
    done

    if [[ "${#unavailable_packages[@]}" -gt 0 ]]; then
        echo
        warn "Unavailable packages:"
        printf " %s\n" "${unavailable_packages[@]}"
    fi

    if [[ "${#available_packages[@]}" -gt 0 ]]; then
        echo
        log "Installing available missing packages:"
        printf " %s\n" "${available_packages[@]}"
        echo

        install_cmd=("${apt_cmd[@]}" install -y "${available_packages[@]}")
        if ! run "${install_cmd[@]}"; then
            warn "Direct apt install failed; refreshing package metadata and retrying."
            run "${apt_cmd[@]}" update
            run "${install_cmd[@]}"
        fi

        echo
    else
        log "No missing packages to install or all missing packages are unavailable."
        echo
    fi
}

resolve_versions() {
    if [[ "$install_mode" == "uninstall" && -z "$version" && -z "$install_dir_override" ]]; then
        return
    fi

    if [[ -n "$version" ]]; then
        if [[ "$version" == *.* ]]; then
            version="${version//./_}"
        fi
        curl_tag="curl-$version"
    else
        curl_tag="$(github_latest_tag "curl/curl" '^curl-[0-9_]+$')"
        version="${curl_tag#curl-}"
    fi

    formatted_version="${version//_/.}"
    ssh2_tag="$(github_latest_tag "libssh2/libssh2" '^libssh2-[0-9.]+$')"
    ssh2_version="${ssh2_tag#libssh2-}"
    nghttp3_tag="$(github_latest_tag "ngtcp2/nghttp3" '^v?[0-9.]+$')"
    nghttp3_version="${nghttp3_tag#v}"
}

update_paths() {
    if [[ -n "$formatted_version" ]]; then
        tar_file="$cwd/$program-$formatted_version.tar.gz"
        extract_dir="$cwd/$program-$formatted_version"
    else
        tar_file=""
        extract_dir=""
    fi

    if [[ -n "$install_dir_override" ]]; then
        install_dir="$install_dir_override"
    elif [[ -n "$formatted_version" ]]; then
        install_dir="/usr/local/programs/$program-$formatted_version"
    else
        install_dir=""
    fi

    if [[ -n "$ssh2_version" ]]; then
        libssh2_install_dir="$cwd/libssh2-$ssh2_version"
    else
        libssh2_install_dir=""
    fi

    if [[ -n "$nghttp3_version" ]]; then
        nghttp3_install_dir="$cwd/nghttp3-$nghttp3_version"
    else
        nghttp3_install_dir=""
    fi
}

# Download and build libssh2
get_libssh2_source() {
    run curl -fL --retry 3 --retry-delay 2 -o "$cwd/libssh2-$ssh2_version.tar.gz" "https://github.com/libssh2/libssh2/archive/refs/tags/${ssh2_tag}.tar.gz"
    rm -rf "$libssh2_install_dir"
    mkdir -p "$libssh2_install_dir"
    run tar -zxf "$cwd/libssh2-$ssh2_version.tar.gz" -C "$libssh2_install_dir" --strip-components=1
    (
        cd "$libssh2_install_dir" || fail "Failed to change directory to $libssh2_install_dir"
        run autoreconf -fi
        run ./configure --prefix="$libssh2_install_dir" --with-openssl
        run make -j"$CPU_THREADS"
        run sudo make install
    )
}

# Download and build nghttp3
get_nghttp3_source() {
    log "Downloading nghttp3 source..."
    run curl -fL --retry 3 --retry-delay 2 -o "$cwd/nghttp3-$nghttp3_version.tar.gz" "https://github.com/ngtcp2/nghttp3/archive/refs/tags/${nghttp3_tag}.tar.gz"
    rm -rf "$nghttp3_install_dir"
    mkdir -p "$nghttp3_install_dir"
    run tar -zxf "$cwd/nghttp3-$nghttp3_version.tar.gz" -C "$nghttp3_install_dir" --strip-components=1
    (
        cd "$nghttp3_install_dir" || fail "Failed to change directory to $nghttp3_install_dir"
        run autoreconf -fi
        run ./configure --prefix="$nghttp3_install_dir" --enable-lib-only
        run make -j"$CPU_THREADS"
        run sudo make install
    )
}

# Download and build cURL with nghttp3 support
build_and_install_curl() {
    local -a dopts eopts wopts
    dopts=('--disable-'{get-easy-options,shared,verbose,versioned-symbols})
    eopts=('--enable-'{alt-svc,cookies,dict,dnsshuffle,doh,file,ftp,gopher})
    eopts+=('--enable-'{headers-api,hsts,http,http-auth,imap,ipv6,ldap,ldaps,libcurl-option,libgcc,manual})
    eopts+=('--enable-'{mime,mqtt,netrc,ntlm,ntlm-wb='/usr/bin/ntlm_auth',openssl-auto-load-config})
    eopts+=('--enable-'{optimize,pop3,progress-meter,proxy,pthreads,rtsp,smb,smtp,socketpair,sspi,static})
    eopts+=('--enable-'{telnet,tftp,threaded-resolver,tls-srp,unix-sockets,websockets})
    wopts=('--with-'{libssh2="$libssh2_install_dir",nghttp2=/usr,openssl="$openssl_prefix",ssl,zlib})
    wopts+=('--with-'{ca-bundle="/etc/ssl/certs/cacert.pem",ca-fallback,ca-path="/etc/ssl/certs"})
    if [[ "$(uname -s)" == "Darwin" ]]; then
        wopts+=('--with-secure-transport')
    fi

    run curl -fL --retry 3 --retry-delay 2 -o "$tar_file" "https://github.com/curl/curl/archive/refs/tags/${curl_tag}.tar.gz"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    run tar -zxf "$tar_file" -C "$extract_dir" --strip-components=1
    (
        cd "$extract_dir" || fail "Failed to change directory to $extract_dir"
        run autoreconf -fi
        run ./configure --prefix="$install_dir" "${dopts[@]}" "${eopts[@]}" "${wopts[@]}"
        run make -j"$CPU_THREADS"
        run sudo make install
    )
}

create_softlinks() {
    [[ -f "$install_dir/bin/curl" ]] && run sudo ln -sfn "$install_dir/bin/curl" "/usr/local/bin/curl"

    # Create pkgconfig directory if it doesn't exist
    run sudo mkdir -p "/usr/local/lib/pkgconfig/"

    # Find and link libcurl.pc if it exists
    if [[ -f "$install_dir/lib/pkgconfig/libcurl.pc" ]]; then
        run sudo ln -sfn "$install_dir/lib/pkgconfig/libcurl.pc" "/usr/local/lib/pkgconfig/libcurl.pc"
        printf "\n%s\n\n" "Successfully created the softlink for the file 'libcurl.pc'."
    elif [[ -f "$install_dir/lib64/pkgconfig/libcurl.pc" ]]; then
        run sudo ln -sfn "$install_dir/lib64/pkgconfig/libcurl.pc" "/usr/local/lib/pkgconfig/libcurl.pc"
        printf "\n%s\n\n" "Successfully created the softlink for the file 'libcurl.pc' (from lib64)."
    else
        printf "\n%s\n\n" "Warning: libcurl.pc not found. Skipping softlink creation."
    fi
}

uninstall_curl() {
    local curl_link curl_target pkgconfig_link
    curl_link="/usr/local/bin/curl"
    pkgconfig_link="/usr/local/lib/pkgconfig/libcurl.pc"

    if [[ -z "$install_dir" ]]; then
        if [[ -L "$curl_link" ]]; then
            curl_target="$(readlink -f "$curl_link")"
            if [[ "$curl_target" == /usr/local/programs/curl-*/bin/curl ]]; then
                install_dir="${curl_target%/bin/curl}"
            fi
        fi
    fi

    [[ -n "$install_dir" ]] || fail "Unable to determine which cURL installation to remove. Use --version or --preset."

    if [[ -L "$curl_link" ]] && [[ "$(readlink -f "$curl_link")" == "$install_dir/bin/curl" ]]; then
        run sudo rm -f "$curl_link"
    fi

    if [[ -L "$pkgconfig_link" ]] && [[ "$(readlink -f "$pkgconfig_link")" == "$install_dir"/lib*/pkgconfig/libcurl.pc ]]; then
        run sudo rm -f "$pkgconfig_link"
    fi

    if [[ -d "$install_dir" ]]; then
        run sudo rm -rf "$install_dir"
    else
        warn "Install directory not found: $install_dir"
    fi
}

# Parse command line arguments
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Arguments:"
    echo "  -h, --help       Display this help message"
    echo "  -v, --version    Set the version of cURL to install"
    echo "  -l, --list       List available versions of cURL"
    echo "  -p, --preset     Set the installation path for cURL (default: /usr/local/curl-version)"
    echo "  -c, --compiler   Set the compiler type (gcc or clang, default: gcc)"
    echo "  -u, --uninstall  Uninstall cURL instead of installing"
    echo
    echo "Examples:"
    echo "  $0 --version 7.88.1"
    echo "  $0 --preset /opt/curl --compiler clang"
    echo "  $0 --uninstall"
    echo
}

list_versions() {
    echo "Available versions:"
    curl -fsSL "https://api.github.com/repos/curl/curl/tags?per_page=100" \
        | sed -n 's/.*"name": *"curl-\([0-9_]\+\)".*/\1/p' \
        | sed 's/_/\./g' \
        | sort -ruV
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                [[ $# -ge 2 && -n "$2" ]] || fail "The --version option requires a value."
                version="$2"
                shift
                ;;
            -l|--list)
                list_versions
                exit 0
                ;;
            -p|--preset)
                [[ $# -ge 2 && -n "$2" ]] || fail "The --preset option requires a value."
                install_dir_override="$2"
                shift
                ;;
            -c|--compiler)
                [[ $# -ge 2 && -n "$2" ]] || fail "The --compiler option requires a value."
                compiler="$2"
                shift
                ;;
            -u|--uninstall)
                install_mode="uninstall"
                ;;
            *)  warn "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

# Main function to run tasks
main() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi

    require_commands apt apt-cache curl dpkg-query grep sed sort sudo tar
    ensure_sudo_access
    parse_args "$@"
    resolve_versions
    update_paths

    if [[ "$install_mode" == "uninstall" ]]; then
        uninstall_curl
        log "$program uninstallation completed successfully"
        exit 0
    fi

    set_env_vars
    apt_pkgs
    require_commands autoreconf make pkg-config
    mkdir -p "$extract_dir" "$libssh2_install_dir" "$nghttp3_install_dir"
    get_libssh2_source
    get_nghttp3_source
    build_and_install_curl
    create_softlinks
    if [[ "$install_mode" == "install" ]]; then
        log "$program installation completed successfully at $install_dir"
    else
        log "$program uninstallation completed successfully"
    fi
    run sudo rm -rf "$cwd"
}

main "$@"
