#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-curl.sh
# Purpose: Build the latest release version of cURL from source code
# Updated: 05.11.24

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
version=$(curl -fsS "https://github.com/curl/curl/tags/" | grep -oP 'curl-([0-9_])+' | head -n1)
ssh2_version=$(curl -fsS "https://github.com/libssh2/libssh2/tags/" | grep -oP 'libssh2-\K([0-9.])+' | head -n1)
formatted_version=$(echo "$version" | sed "s/curl-//" | sed "s/_/\./g")
tar_file="$cwd/$program-$formatted_version.tar.gz"
extract_dir="$cwd/$program-$formatted_version"
install_dir="/usr/local/$program-$formatted_version"
certs_dir="/etc/ssl/certs"
pem_file="cacert.pem"
pem_out="$certs_dir/$pem_file"

# Check if OpenSSL is installed at /usr/local/ssl
if [[ -d "/usr/local/ssl" ]]; then
    openssl_prefix="/usr/local/ssl"
else
    openssl_prefix="/usr"
fi

# Define environment variables
set_env_vars() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-I$openssl_prefix/include -I/usr/include/libxml2 -D_FORTIFY_SOURCE=2"
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

    if [ "${#missing_pkgs[@]}" -gt 0 ]; then
        sudo apt update
        sudo apt install "${missing_pkgs[@]}"
    fi
}

# Check if libcurl4 is installed, remove it, and reinstall it
check_libcurl4() {
    if dpkg-query -W -f='${Status}' libcurl4 2>/dev/null | grep -q "ok installed"; then
        log "Removing libcurl4"
        sudo apt -y remove --purge libcurl4
        log "Reinstalling libcurl4"
        sudo apt -y install libcurl4
    fi
}

# Download and extract the libssh2 source code
get_libssh2_source() {
    local ssh2_tar_file="$cwd/libssh2-$ssh2_version.tar.gz"
    local ssh2_extract_dir="$cwd/libssh2-$ssh2_version"

    if [[ ! -f "$ssh2_tar_file" ]]; then
        log "Downloading libssh2 version $ssh2_version"
        wget --show-progress -cqO "$ssh2_tar_file" "https://github.com/libssh2/libssh2/archive/refs/tags/libssh2-$ssh2_version.tar.gz"
    else
        log "The libssh2 tar file $ssh2_tar_file already exists, skipping download"
    fi

    if [[ -d "$ssh2_extract_dir" ]]; then
        log "Removing existing directory $ssh2_extract_dir"
        rm -rf "$ssh2_extract_dir"
    fi

    log "Creating directory $ssh2_extract_dir"
    mkdir -p "$ssh2_extract_dir"

    log "Extracting $ssh2_tar_file"
    if ! tar -zxf "$ssh2_tar_file" -C "$ssh2_extract_dir" --strip-components=1; then
        sudo rm -f "$ssh2_tar_file"
        fail "The tar command was unable to extract the libssh2 archive so it was deleted. Re-run the script."
    fi

    cd "$ssh2_extract_dir" || exit 1
}

# Configure, compile, and install libssh2
build_and_install_libssh2() {
    local ssh2_install_dir
    ssh2_install_dir="/usr/local/libssh2-$ssh2_version"

    # Generate configuration scripts
    autoreconf -fi

    # Create a build directory
    mkdir -p build; cd build || fail "Failed to change into the libssh2 build directory. Line: $LINENO"

    # Run the configure script
    ../configure --prefix="$ssh2_install_dir" \
                 --with-crypto=openssl \
                 --with-libssl-prefix="$openssl_prefix" \
                 --with-libz \
                 --with-libz-prefix=/usr \
                 --enable-static \
                 --disable-examples-build \
                 CPPFLAGS="$CPPFLAGS" || fail "libssh2 configuration failed. Line: $LINENO"

    log "Compiling libssh2"
    make "-j$(nproc --all)" || fail "libssh2 compilation failed. Line: $LINENO"

    log "Installing libssh2"
    sudo make install || fail "libssh2 installation failed. Line: $LINENO"

    # Create soft links
    [[ ! -d "/usr/local/lib64/pkgconfig" ]] && sudo mkdir -p "/usr/local/lib64/pkgconfig"
    sudo ln -sf "$ssh2_install_dir/lib/pkgconfig/"*.pc "/usr/local/lib64/pkgconfig"
}

# Download and extract the curl source code
get_curl_source() {
    if [[ ! -f "$tar_file" ]]; then
        log "Downloading $program version $formatted_version"
        wget --show-progress -cqO "$tar_file" "https://github.com/curl/curl/archive/refs/tags/$version.tar.gz"
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
    if ! tar -zxf "$tar_file" -C "$extract_dir" --strip-components=1; then
        sudo rm -f "$tar_file"
        fail "The tar command was unable to extract the curl archive so it was deleted. Re-run the script."
    fi

    cd "$extract_dir" || exit 1
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

set_custom_ld_linker_paths() {
    wget --show-progress -cqO "/tmp/ld-custom-paths.sh" "https://ld.optimizethis.net"
    if sudo bash "/tmp/ld-custom-paths.sh"; then
        sudo rm "/tmp/ld-custom-paths.sh"
    else
        echo "Failed to install the custom ld linker paths. Line: $LINENO"
        exit 1
    fi
    sudo ldconfig
}

# Configure, compile, and install curl
build_and_install_curl() {
    local dopts=('--disable-'{get-easy-options,shared,verbose,versioned-symbols})
    local eopts=('--enable-'{alt-svc,ares,cookies,dict,dnsshuffle,doh,file,ftp,gopher})
    eopts+=('--enable-'{headers-api,hsts,http,http-auth,imap,ipv6,ldap,ldaps,libcurl-option,libgcc,manual})
    eopts+=('--enable-'{mime,mqtt,netrc,ntlm,ntlm-wb='/usr/bin/ntlm_auth',openssl-auto-load-config})
    eopts+=('--enable-'{optimize,pop3,progress-meter,proxy,pthreads,rtsp,smb,smtp,socketpair,sspi,static})
    eopts+=('--enable-'{telnet,tftp,threaded-resolver,tls-srp,unix-sockets,websockets})
    local wopts=('--with-'{libssh2,nghttp2,nghttp3,openssl,ssl,zlib})
    wopts+=('--with-'{ca-bundle="$pem_out",ca-fallback,ca-path="$certs_dir",secure-transport})
    wopts+=('--with-ssl="$openssl_prefix"')

    # Generate configuration scripts
    autoreconf -fi

    # Create a build directory
    mkdir -p build; cd build || fail "Failed to change into the curl build directory. Line: $LINENO"

    # Run the configure script
    ../configure --prefix="$install_dir" \
                 "${dopts[@]}" \
                 "${eopts[@]}" \
                 "${wopts[@]}" \
                 CPPFLAGS="$CPPFLAGS" || fail "curl configuration failed. Line: $LINENO"

    log "Compiling $program"
    make "-j$(nproc --all)" || fail "curl compilation failed. Line: $LINENO"

    log "Installing $program"
    sudo make install || fail "curl installation failed. Line: $LINENO"

    # Create soft links
    sudo ln -sf "$install_dir/bin/$program" "/usr/local/bin/"
    [[ ! -d "/usr/local/lib64/pkgconfig" ]] && sudo mkdir -p "/usr/local/lib64/pkgconfig"
    sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib64/pkgconfig"
}

# Display the installed version
display_version() {
    local version
    version=$("$install_dir/bin/$program" --version | head -n1 | awk '{print $2}')
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
    done
}

# Main script
main() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo. Line: $LINENO"
    fi

    mkdir -p "$cwd"

    parse_args "$@"
    set_env_vars
    apt_pkgs
    get_libssh2_source
    build_and_install_libssh2
    get_curl_source
    install_ca_certs
    build_and_install_curl
    set_custom_ld_linker_paths
    check_libcurl4
    display_version
    cleanup
}

main "$@"
