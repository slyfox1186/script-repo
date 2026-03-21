#!/usr/bin/env bash
set -Eeuo pipefail

# Build OpenSSL
# Updated: 04.30.24
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-openssl.sh
# Script Version: 1.6

list_versions_flag=0
list_commands_flag=0
enable_ipv6=false
jobs=""
keep_build=false
install_dir="/usr/local/programs/ssl"
make_install_command=("install_sw")
openssl_libdir="lib64"
version=""
cwd=""
src_dir=""
compiler_cc=""
compiler_cxx=""
CPU_THREADS=""

# Function to display the usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -6, --enable-ipv6          Enable IPv6 support (default: disabled)"
    echo "  -c, --command <command>    Specify the command(s) to use with 'sudo make install' (default: install_sw, comma-separated)"
    echo "  -h, --help                 Display this help message and exit"
    echo "  -j, --jobs <n>             Set the number of parallel jobs for compilation (default: number of CPU cores)"
    echo "  -k, --keep-build           Keep the build directory after installation"
    echo "  -l, --list                 List all available OpenSSL versions"
    echo "  -m, --list-commands        List available 'make install' commands and their descriptions"
    echo "  -p, --prefix <path>        Set the installation prefix (default: /usr/local/programs/ssl)"
    echo "  -v, --version <version>    Specify the OpenSSL version to install (default: latest stable release)"
    exit 0
}

log() {
    printf '[INFO] %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1" >&2
}

run() {
    local rendered
    printf -v rendered '%q ' "$@"
    printf '[CMD ] %s\n' "${rendered% }" >&2
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

fetch_url() {
    local url
    url="$1"
    run wget -qO- --tries=3 --waitretry=2 "$url"
}

download_file() {
    local destination url
    url="$1"
    destination="$2"
    run wget -O "$destination" --tries=3 --waitretry=2 "$url"
}

# Function to parse command-line arguments
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -6|--enable-ipv6)
                enable_ipv6=true
                shift
                ;;
            -c|--command)
                [[ $# -ge 2 && -n "$2" ]] || fail "The --command option requires a value."
                IFS=',' read -ra make_install_command <<< "$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            -j|--jobs)
                [[ $# -ge 2 && "$2" =~ ^[0-9]+$ && "$2" -gt 0 ]] || fail "The --jobs option requires a positive integer."
                jobs="$2"
                shift 2
                ;;
            -k|--keep-build)
                keep_build=true
                shift
                ;;
            -l|--list)
                list_versions_flag=1
                shift
                ;;
            -m|--list-commands)
                list_commands_flag=1
                shift
                ;;
            -p|--prefix)
                [[ $# -ge 2 && -n "$2" ]] || fail "The --prefix option requires a value."
                install_dir="$2"
                shift 2
                ;;
            -v|--version)
                [[ $# -ge 2 && -n "$2" ]] || fail "The --version option requires a value."
                version="$2"
                shift 2
                ;;
            *)
                warn "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Function to handle failure and display an error message
fail() {
    echo
    echo "$1" >&2
    echo "Please report errors at: https://github.com/slyfox1186/script-repo/issues" >&2
    exit 1
}

ensure_sudo_access() {
    log "Validating sudo access..."
    run sudo -v
}

# Function to install required packages
install_required_packages() {
    local -a apt_cmd install_cmd missing_packages pkgs
    apt_cmd=(sudo env DEBIAN_FRONTEND=noninteractive apt)
    pkgs=(
        autoconf autogen automake build-essential ca-certificates
        checkinstall clang libc-ares-dev libcurl4-openssl-dev
        libdmalloc-dev libgcrypt20-dev libgmp-dev libgpg-error-dev
        libjemalloc-dev libmbedtls-dev libsctp-dev libssh2-1-dev
        libssh-dev libssl-dev libtool libtool-bin libxml2-dev m4
        ccache perl wget zlib1g-dev
    )

    missing_packages=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='$Status' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ "${#missing_packages[@]}" -gt 0 ]]; then
        log "Installing missing packages: ${missing_packages[*]}"
        install_cmd=("${apt_cmd[@]}" install -y "${missing_packages[@]}")
        if ! run "${install_cmd[@]}"; then
            warn "Direct apt install failed; refreshing package metadata and retrying."
            run "${apt_cmd[@]}" update
            run "${install_cmd[@]}"
        fi
        echo
    else
        log "No missing packages to install."
        echo
    fi
}

get_highest_clang_version() {
    local candidate highest_version path version

    highest_version=""
    compiler_cc=""
    compiler_cxx=""

    for path in /usr/bin/clang-[0-9]*; do
        [[ -x "$path" ]] || continue
        candidate="${path##*/}"
        version="${candidate#clang-}"
        if [[ -z "$highest_version" ]] || [[ "$(printf '%s\n%s\n' "$highest_version" "$version" | sort -V | tail -n1)" == "$version" ]]; then
            highest_version="$version"
            compiler_cc="$candidate"
            compiler_cxx="clang++-$version"
        fi
    done

    if [[ -z "$compiler_cc" ]]; then
        if command -v clang >/dev/null 2>&1 && command -v clang++ >/dev/null 2>&1; then
            compiler_cc="clang"
            compiler_cxx="clang++"
        else
            fail "No suitable clang compiler was found."
        fi
    fi
}

# Function to set compiler flags
set_compiler_flags() {
    CC="$compiler_cc"
    CXX="$compiler_cxx"
    CFLAGS="-O3 -pipe -fstack-protector-strong -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro,-z,now"
    export CC CFLAGS CPPFLAGS CXX CXXFLAGS LDFLAGS
}

# Function to update the shared library cache
update_shared_library_cache() {
    run sudo ldconfig
}

# Function to add OpenSSL to the system path
add_openssl_to_path() {
    run sudo ln -sfn "$install_dir/bin/c_rehash" "/usr/local/bin/c_rehash"
    run sudo ln -sfn "$install_dir/bin/openssl" "/usr/local/bin/openssl"
}

# Function to create softlinks for pkgconfig files
create_pkgconfig_softlinks() {
    local openssl_pkgconfig_dir pkgconfig_dir
    pkgconfig_dir="/usr/local/lib/pkgconfig"
    openssl_pkgconfig_dir="$install_dir/$openssl_libdir/pkgconfig"

    if [[ ! -d "$openssl_pkgconfig_dir" && -d "$install_dir/lib/pkgconfig" ]]; then
        openssl_pkgconfig_dir="$install_dir/lib/pkgconfig"
    fi

    run sudo mkdir -p "$pkgconfig_dir"

    for pc_file in "$openssl_pkgconfig_dir"/*.pc; do
        if [[ -e "$pc_file" ]]; then
            local pc_filename="${pc_file##*/}"
            run sudo ln -sfn "$pc_file" "$pkgconfig_dir/$pc_filename"
        fi
    done
}

create_linker_config_file() {
    echo "$install_dir/$openssl_libdir" | sudo tee "/etc/ld.so.conf.d/custom_openssl_$version.conf" >/dev/null
    run sudo ldconfig
}

# Function to list available OpenSSL versions
list_versions() {
    echo "Available OpenSSL versions:"
    echo
    fetch_url "https://www.openssl.org/source/" | grep -oP 'openssl-\d+\.\d+\.\d+\.tar\.gz' | sed 's/openssl-//;s/\.tar\.gz//' | sort -uV
}

detect_latest_openssl_version() {
    local latest_version

    latest_version="$(
        fetch_url "https://www.openssl.org/source/" \
            | grep -oP 'openssl-\d+\.\d+\.\d+\.tar\.gz' \
            | sed 's/openssl-//;s/\.tar\.gz//' \
            | sort -uV \
            | tail -n1 \
            || true
    )"

    [[ -n "$latest_version" ]] || fail "Failed to detect the latest stable OpenSSL version from the downloads page."
    printf '%s\n' "$latest_version"
}

# Function to list available 'make install' commands
list_commands() {
    echo "Available 'make install' commands:"
    echo
    echo "  all                   Build all the software components and documentation"
    echo "  build_sw              Build all the software components (DEFAULT)"
    echo "  build_docs            Build all documentation components"
    echo "  clean                 Remove all build artifacts and return the directory to a clean state"
    echo "  depend                Rebuild the dependencies in the Makefiles (legacy option, not needed since OpenSSL 1.1.0)"
    echo "  install               Install all OpenSSL components"
    echo "  install_sw            Only install the OpenSSL software components"
    echo "  install_docs          Only install the OpenSSL documentation components"
    echo "  install_man_docs      Only install the OpenSSL man pages (Unix only)"
    echo "  install_html_docs     Only install the OpenSSL HTML documentation"
    echo "  install_fips          Install the FIPS provider module configuration file"
    echo "  list-tests            Print a list of all the self test names"
    echo "  test                  Build and run the OpenSSL self tests"
    echo "  uninstall             Uninstall all OpenSSL components"
}

# Function to download OpenSSL
download_openssl() {
    local openssl_url tar_file
    openssl_url="https://www.openssl.org/source/openssl-$version.tar.gz"
    tar_file="$cwd/openssl-$version.tar.gz"

    log "Targeting tar file: $tar_file"
    log "Downloading OpenSSL $version..."
    download_file "$openssl_url" "$tar_file"
    echo
}

# Function to extract OpenSSL
extract_openssl() {
    local extracted_dir tar_file
    tar_file="$cwd/openssl-$version.tar.gz"

    if [[ -d "$src_dir" ]]; then
        printf "\n%s\n\n" "OpenSSL $version source directory already exists, skipping extraction."
    else
        if [[ -f "$tar_file" ]]; then
            log "Verifying OpenSSL $version archive integrity..."
            if gzip -t "$tar_file"; then
                log "Extracting OpenSSL $version..."
                if run tar -xzf "$tar_file" -C "$cwd"; then
                    log "Extraction completed successfully."
                    echo
                    extracted_dir="${tar_file##*/}"
                    extracted_dir="${extracted_dir%.tar.gz}"
                    if [[ "$extracted_dir" != "${src_dir##*/}" ]]; then
                        log "Renaming extracted directory from $extracted_dir to ${src_dir##*/}..."
                        mv "$cwd/$extracted_dir" "$src_dir"
                        echo
                    fi
                else
                    warn "Extraction failed. Removing the corrupted archive and retrying..."
                    echo
                    rm -f "$tar_file"
                    download_openssl
                    extract_openssl
                fi
            else
                warn "OpenSSL $version archive is corrupted. Removing the archive and retrying..."
                echo
                rm -f "$tar_file"
                download_openssl
                extract_openssl
            fi
        else
            log "OpenSSL $version archive does not exist. Downloading..."
            echo
            download_openssl
            extract_openssl
        fi
    fi
}

# Function to configure OpenSSL
configure_openssl() {
    local -a config_options
    log "Configuring OpenSSL..."
    config_options=(
        "--libdir=$openssl_libdir"
        "-Wl,-rpath=$install_dir/$openssl_libdir"
        "-Wl,--enable-new-dtags"
        "--prefix=$install_dir"
        "--openssldir=$install_dir"
        "--release"
        "--with-zlib-include=/usr/include"
        "--with-zlib-lib=/usr/lib/x86_64-linux-gnu"
        "enable-ec_nistp_64_gcc_128"
        "enable-egd"
        "enable-fips"
        "enable-pic"
        "enable-shared"
        "enable-threads"
        "enable-zlib-dynamic"
        "no-async"
        "no-comp"
        "no-dso"
        "no-engine"
        "no-weak-ssl-ciphers"
    )

    if [[ "$enable_ipv6" == true ]]; then
        warn "OpenSSL ${version} does not expose an enable-ipv6 Configure option; continuing with the upstream default network support."
    fi

    if [[ "$version" =~ ^3\.2\. ]]; then
        config_options+=("enable-"{ktls,psk})
    fi

    if run "$src_dir/Configure" "${config_options[@]}"; then
        log "OpenSSL configuration completed successfully."
        echo
    else
        fail "OpenSSL configuration failed. Line: $LINENO"
    fi
}

install_fips_if_needed() {
    local target

    for target in "${make_install_command[@]}"; do
        case "$target" in
            install|install_fips)
                return
                ;;
        esac
    done

    run sudo make install_fips
}

# Function to build and install OpenSSL
build_and_install_openssl() {
    local build_jobs
    build_jobs="${jobs:-$CPU_THREADS}"

    log "Compiling OpenSSL..."
    run make "-j${build_jobs}"
    echo
    log "Installing OpenSSL..."
    echo
    run sudo make "${make_install_command[@]}"
    install_fips_if_needed
    echo
}

# Function to create and prepare the certificates directory
prepare_certificates_directory() {
    local certs_dir
    certs_dir="$install_dir/certs"
    log "Creating and preparing the certificates directory at $certs_dir..."
    run sudo mkdir -p "$certs_dir"
    run sudo bash -c "ln -sfn /etc/ssl/certs/* '$certs_dir/'"
    run sudo "$install_dir/bin/c_rehash" "$certs_dir"
    log "Certificates directory is ready."
}

# Main function
main() {
    local temp_dir

    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi

    CPU_THREADS="$(detect_cpu_threads)"
    require_commands apt dpkg-query grep gzip mktemp sed sort sudo tar wget
    parse_arguments "$@"

    if [[ "$list_versions_flag" == "1" ]]; then
        list_versions
        exit 0
    fi

    if [[ "$list_commands_flag" == "1" ]]; then
        list_commands
        exit 0
    fi

    ensure_sudo_access

    temp_dir=$(mktemp -d)
    cwd="$temp_dir/openssl-build"

    if [[ -z "$version" ]]; then
        version="$(detect_latest_openssl_version)"
    fi

    src_dir="$cwd/openssl-$version"

    echo
    install_required_packages
    require_commands perl
    get_highest_clang_version
    set_compiler_flags
    mkdir -p "$cwd"
    log "Targeting OpenSSL version $version"
    download_openssl
    extract_openssl

    if [[ -d "$src_dir" ]]; then
        cd "$src_dir" || fail "Failed to change directory to $src_dir. Line: $LINENO"
        configure_openssl
        build_and_install_openssl
        prepare_certificates_directory
        add_openssl_to_path
        update_shared_library_cache
        create_pkgconfig_softlinks
        create_linker_config_file
    else
        fail "OpenSSL source directory $src_dir does not exist. Line: $LINENO"
    fi

    [[ "$keep_build" == false ]] && run sudo rm -fr "$cwd"

    echo
    log "OpenSSL installation completed."
}

main "$@"
