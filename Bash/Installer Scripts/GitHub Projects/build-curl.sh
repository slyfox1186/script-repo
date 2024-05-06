#!/usr/bin/env bash

# GitHub: 
# Purpose: Build the latest release version of cURL from source code
# Updated: 05.06.24

# Set strict mode for bash
set -euo pipefail

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
version=$(curl -s "https://github.com/curl/curl/tags" | grep -oP 'curl-[0-9]+_[0-9]+_[0-9]+' | head -n1)
formatted_version=$(echo "$version" | sed "s/curl-//" | sed "s/_/\./g")
download_url="https://github.com/curl/curl/archive/refs/tags/$version.tar.gz"
tar_file="$cwd/$program-$formatted_version.tar.gz"
extract_dir="$cwd/$program-$formatted_version"
install_dir="/usr/local/$program-$formatted_version"
certs_dir="/etc/ssl/certs"
pem_file="cacert.pem"
pem_out="$certs_dir/$pem_file"
cleanup_flag="false"

mkdir -p "$cwd"

# Define environment variables
set_env_vars() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-I/usr/include/openssl -I/usr/include/libxml2 -D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PKG_CONFIG_PATH
}

# Check and install dependencies
apt_pkgs() {
    local -a missing_pkgs pkgs
    local pkg
    pkgs=(
        autoconf autoconf-archive autotools-dev build-essential curl
        libcurl4 libcurl4-openssl-dev libc-ares-dev libnghttp2-dev
        libpsl-dev libssh2-1-dev libssl-dev libtool libzstd-dev
        pkg-config zlib1g-dev
    )

    missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        sudo apt update
        sudo apt install "${missing_pkgs[@]}"
    fi
}

# Download and extract the source code
get_source() {
    if [[ ! -f "$tar_file" ]]; then
        log "Downloading $program version $formatted_version"
        wget "$download_url" -O "$tar_file"
    else
        log "The tar file $tar_file already exists, skipping download"
    fi

    if [[ -d "$extract_dir" ]]; then
        log "Removing existing directory $extract_dir"
        rm -rf "$extract_dir"
    fi

    log "Creating directory $extract_dir"
    mkdir -p "$extract_dir"

    log "Extracting $tar_file"
    tar -zxf "$tar_file" -C "$extract_dir" --strip-components=1

    cd "$extract_dir"
}

# Install ca certs from curl's official website
install_ca_certs() {
    if [[ ! -f "$pem_out" ]]; then
        curl -Lso "$pem_file" "https://curl.se/ca/$pem_file"
        sudo cp -f "$pem_file" "$pem_out"
    fi

    if type -P update-ca-certificates &>/dev/null; then
        sudo update-ca-certificates
    fi
}

# Configure, compile, and install the program
build_and_install() {
    local dopts=('--disable-'{get-easy-options,shared,verbose,versioned-symbols})
    local eopts=('--enable-'{alt-svc,ares,cookies,dict,dnsshuffle,doh,file,ftp,gopher})
    eopts+=('--enable-'{headers-api,hsts,http,http-auth,imap,ipv6,ldap,ldaps,libcurl-option,libgcc,manual})
    eopts+=('--enable-'{mime,mqtt,netrc,ntlm,ntlm-wb='/usr/bin/ntlm_auth',openssl-auto-load-config})
    eopts+=('--enable-'{optimize,pop3,progress-meter,proxy,pthreads,rtsp,smb,smtp,socketpair,sspi,static})
    eopts+=('--enable-'{telnet,tftp,threaded-resolver,tls-srp,unix-sockets,websockets})
    local wopts=('--with-'{libssh2,nghttp2,nghttp3,openssl,ssl,zlib})
    wopts+=('--with-'{ca-bundle="$pem_out",ca-fallback,ca-path="$certs_dir",secure-transport})

    # Generate configuration scripts
    autoreconf -fi

    # Create a build directory
    mkdir -p build; cd build || fail "Failed to change into the build directory. Line: $LINENO"

    # Run the configure script
    ../configure --prefix="$install_dir" \
                 "${dopts[@]}" \
                 "${eopts[@]}" \
                 "${wopts[@]}" \
                 CPPFLAGS="$CPPFLAGS" || fail "Configuration failed. Line: $LINENO"

    log "Compiling $program"
    make "-j$(nproc --all)" || fail "Compilation failed. Line: $LINENO"

    log "Installing $program"
    sudo make install || fail "Installation failed. Line: $LINENO"

    # Create soft links
    sudo ln -sf "$install_dir/bin/$program" "/usr/local/bin/"
}

create_linker_config_file() {
    echo "$install_dir/lib" | sudo tee "/etc/ld.so.conf.d/custom_curl_$version.conf" >/dev/null
    sudo ldconfig
}

# Display the installed version
display_version() {
    local version=$("$install_dir/bin/$program" --version | head -n1 | awk '{print $2}')
    log "The installed version of $program is: $version"
}

# Cleanup
cleanup() {
    sudo rm -fr "$cwd"
    log "$program installation completed successfully"
}

# Parse command line arguments
usage() {
    echo "Usage: ./$0 [OPTIONS]"
    echo "  -h, --help       Display this help message"
    echo "  -v, --version    Display the installed version of $program"
    echo
    echo "./$0"
    echo "./$0 -v"
    echo
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                display_version
                exit 0
                ;;
            *)  warn "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

# Main script
main() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo. Line: $LINENO"
    fi

    parse_args "$@"
    set_env_vars
    apt_pkgs
    get_source
    install_ca_certs
    build_and_install
    create_linker_config_file
    display_version
    cleanup
}

main "$@"
