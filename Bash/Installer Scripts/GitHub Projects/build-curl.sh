#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-curl.sh
# Purpose: Build the latest release version of cURL from source code including nghttp3 support
# Updated: 05.12.24

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

# Define program variables
program="curl"
cwd="$PWD/curl-build-script"
version=$(curl -fsS "https://github.com/curl/curl/tags/" | grep -oP 'curl-\K([0-9_])+' | head -n1)
ssh2_version=$(curl -fsS "https://github.com/libssh2/libssh2/tags/" | grep -oP 'libssh2-\K([0-9.])+' | head -n1)
nghttp3_version=$(curl -fsS "https://github.com/ngtcp2/nghttp3/tags/" | grep -oP 'v?\K([0-9.])+(?=\.tar\.[a-z]+)' | head -n1)
formatted_version=$(echo "$version" | sed "s/_/\./g")
tar_file="$cwd/$program-$formatted_version.tar.gz"
extract_dir="$cwd/$program-$formatted_version"
install_dir="/usr/local/$program-$formatted_version"
libssh2_install_dir="$cwd/libssh2-$ssh2_version"
nghttp3_install_dir="$cwd/nghttp3-$nghttp3_version"

# Define OpenSSL installation check
openssl_prefix=$(if [[ -d "/usr/local/ssl" ]]; then echo "/usr/local/ssl"; else echo "/usr"; fi)

# Define environment variables
set_env_vars() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-I$openssl_prefix/include -I/usr/include/libxml2 -D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    PKG_CONFIG_PATH="$libssh2_install_dir/lib/pkgconfig:$nghttp3_install_dir/lib/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PKG_CONFIG_PATH
}

apt_pkgs() {
    local pkgs=(
        autoconf autoconf-archive autotools-dev build-essential curl libcurl4 libcurl4-openssl-dev
        libc-ares-dev libnghttp2-dev libpsl-dev libssh2-1-dev libssl-dev libtool libzstd-dev
        pkg-config zlib1g-dev
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

    if [ "${#unavailable_packages[@]}" -gt 0 ]; then
        echo
        warn "Unavailable packages:"
        printf " %s\n" "${unavailable_packages[@]}"
    fi

    if [ "${#available_packages[@]}" -gt 0 ]; then
        echo
        log "Installing available missing packages:"
        printf " %s\n" "${available_packages[@]}"
        echo

        sudo apt update
        sudo apt install -y "${available_packages[@]}"

        echo
    else
        log "No missing packages to install or all missing packages are unavailable."
        echo
    fi
}

# Download and build libssh2
get_libssh2_source() {
    wget --show-progress -cqO "$cwd/libssh2-$ssh2_version.tar.gz" "https://github.com/libssh2/libssh2/archive/refs/tags/libssh2-$ssh2_version.tar.gz"
    tar -zxf "$cwd/libssh2-$ssh2_version.tar.gz" -C "$libssh2_install_dir" --strip-components 1
    cd "$libssh2_install_dir"
    autoreconf -fi
    ./configure --prefix="$libssh2_install_dir" --with-openssl
    make "-j$(nproc --all)" && sudo make install
}

# Function to clone nghttp3 and initialize submodules
get_nghttp3_source() {
    echo "Cloning nghttp3 with all submodules..."
    git clone --recurse-submodules "https://github.com/ngtcp2/nghttp3.git" "$nghttp3_install_dir"

    # Navigate into the cloned directory
    cd "$nghttp3_install_dir"

    # Additional build steps
    autoreconf -fi
    ./configure --prefix="$nghttp3_install_dir" --enable-lib-only
    make "-j$(nproc --all)" && \
    sudo make install
}

# Download and build cURL with nghttp3 support
build_and_install_curl() {
    wget --show-progress -cqO "$tar_file" "https://github.com/curl/curl/archive/refs/tags/curl-$version.tar.gz"
    tar -zxf "$tar_file" -C "$extract_dir" --strip-components=1
    cd "$extract_dir"
    autoreconf -fi
    local dopts=('--disable-'{get-easy-options,shared,verbose,versioned-symbols})
    local eopts=('--enable-'{alt-svc,ares,cookies,dict,dnsshuffle,doh,file,ftp,gopher})
    eopts+=('--enable-'{headers-api,hsts,http,http-auth,imap,ipv6,ldap,ldaps,libcurl-option,libgcc,manual})
    eopts+=('--enable-'{mime,mqtt,netrc,ntlm,ntlm-wb='/usr/bin/ntlm_auth',openssl-auto-load-config})
    eopts+=('--enable-'{optimize,pop3,progress-meter,proxy,pthreads,rtsp,smb,smtp,socketpair,sspi,static})
    eopts+=('--enable-'{telnet,tftp,threaded-resolver,tls-srp,unix-sockets,websockets})
    local wopts=('--with-'{libssh2="$libssh2_install_dir",ngtcp2=/usr,nghttp2=/usr,nghttp3="$nghttp3_install_dir",openssl="$openssl_prefix",ssl,zlib})
    wopts+=('--with-'{ca-bundle="/etc/ssl/certs/cacert.pem",ca-fallback,ca-path="/etc/ssl/certs",secure-transport})
    ./configure --prefix="$install_dir" "${dopts[@]}" "${eopts[@]}" "${wopts[@]}" CPPFLAGS="-I$nghttp3_install_dir/include $CPPFLAGS" \
    LDFLAGS="-L$nghttp3_install_dir/lib $LDFLAGS"
    make "-j$(nproc --all)" && sudo make install
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
    curl -fsS "https://github.com/curl/curl/tags/" | grep -oP 'curl-\K([0-9_])+' | sed "s/_/\./g" | sort -ruV
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                version="$2"
                if [[ "$version" =~ \. ]]; then
                    version="${version//\./_}"
                fi
                shift
                ;;
            -l|--list)
                list_versions
                exit 0
                ;;
            -p|--preset)
                install_dir="$2"
                shift
                ;;
            -c|--compiler)
                CC="$2"
                CXX="$2++"
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
        echo "You must run this script without root or with sudo."
        exit 1
    fi
    parse_args "$@"
    set_env_vars
    apt_pkgs
    mkdir -p "$extract_dir" "$libssh2_install_dir" "$nghttp3_install_dir"
    get_libssh2_source
    get_nghttp3_source
    build_and_install_curl
    if [[ "$install_mode" == "install" ]]; then
        log "$program installation completed successfully at $install_dir"
    else
        log "$program uninstallation completed successfully"
    fi
    sudo rm -rf "$cwd"
}

main "$@"
