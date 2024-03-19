#!/usr/bin/env bash

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set variables
script_ver="1.2"
archive_dir="systemd-v255"
archive_url="https://github.com/systemd/systemd/archive/refs/tags/v255.tar.gz"
archive_name="${archive_dir}.tar.${archive_url##*.}"
cwd="$PWD/systemd-build-script"
install_dir="/usr/local/$archive_dir"

# Create logging functions
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

fail() {
    echo
    echo -e "${RED}[ERROR] $1${NC}"
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Check if running as root or with sudo
check_root() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi
}

# Display script information
display_info() {
    log "Systemd build script version $script_ver"
    echo "==============================================="
    echo
}

# Set compiler and optimization flags
set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-g -O3 -pipe -fno-plt -march=native"
    CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

# Set the path variables
set_path_variables() {
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/cuda/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
    LD_LIBRARY_PATH="/usr/local/lib64:/usr/local/lib:/usr/lib64:/usr/lib:/lib64:/lib:/usr/local/cuda-12.2/nvvm/lib64"
    export PATH PKG_CONFIG_PATH LD_LIBRARY_PATH
}

# Show exit message
exit_fn() {
    echo
    log "Make sure to star this repository to show your support!"
    log "https://github.com/slyfox1186/script-repo"
    exit 0
}

# Prompt user to clean up files
cleanup() {
    local choice

    echo
    echo -e "${GREEN}============================================${NC}"
    echo -e "  ${YELLOW}Do you want to clean up the build files?${NC}  "
    echo -e "${GREEN}============================================${NC}"
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choice (1 or 2): " choice

    case "$choice" in
        1) sudo rm -fr "$cwd";;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

# Install required apt packages
install_dependencies() {
    pkgs=(autoconf automake build-essential clang cmake curl git gperf libacl1-dev
          libapparmor-dev libaudit-dev libblkid-dev libbpf-dev libbz2-dev libcap-dev
          libcryptsetup-dev libcurl4-openssl-dev libdbus-1-dev libfdisk-dev libfido2-dev
          libglib2.0-dev libgnutls28-dev libkmod-dev liblz4-dev libmicrohttpd-dev libmount-dev
          libp11-kit-dev libpam0g-dev libpolkit-gobject-1-dev libpwquality-dev libqrencode-dev
          libseccomp-dev libssl-dev libtss2-dev libxkbcommon-dev meson ninja-build openssl
          python3 python3-jinja2 python3-pyparsing xsltproc libnghttp2-dev libssh2-1-dev
          libzstd-dev libiptc-dev libxen-dev libzip-dev bzip2 libbpf-dev libelf-dev)

    missing_pkgs=""
    for pkg in ${pkgs[@]}; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [[ -n "$missing_pkgs" ]]; then
        sudo apt-get update
        sudo apt-get install $missing_pkgs
    fi
}

# Download the archive file
download_archive() {
    if [[ ! -f "$cwd/$archive_name" ]]; then
        curl -Lso "$cwd/$archive_name" "$archive_url"
    fi
}

# Extract archive files
extract_archive() {
    if ! tar -zxf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
        fail "Failed to extract: $cwd/$archive_name"
    fi
}

# Build program from source
build_program() {
    cd "$cwd/$archive_dir" || fail "Failed to change directory to: $cwd/$archive_dir"
    set_compiler_flags
    set_path_variables
    meson setup build --prefix="$install_dir" \
                      --buildtype=release \
                      --default-library=static \
                      --pkg-config-path="$PKG_CONFIG_PATH" \
                      --strip \
                      -Dbacklight=true \
                      -Db_lto=true \
                      -Db_lto_threads=$(nproc --all) \
                      -Ddefault-user-shell=$(type -P bash) \
                      -Ddns-over-tls=auto \
                      -Defi=true \
                      -Dhibernate=false \
                      -Dhwdb=true \
                      -Dinstall-tests=true \
                      -Dldconfig=true \
                      -Drfkill=true \
                      -Dtests=unsafe \
                      -Dtranslations=false \
                      -Duser-path="$USER" \
                      -Dzstd=enabled \
                      -Dc_args="-O3 -pipe -fno-plt -fPIC -fPIE -march=native" \
                      -Dcpp_args="-O3 -pipe -fno-plt -fPIC -fPIE -march=native"
    make "-j$(nproc --all)" || fail "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
    if ! sudo make install; then
        fail "Failed to execute: sudo make install. Line: ${LINENO}"
    fi
}

# Create soft links
create_soft_links() {
    sudo ln -sf "$install_dir"/bin/* "/usr/local/bin/"
}

# Main script
main_menu() {
    check_root
    display_info
    install_dependencies
    [[ -d "$cwd/$archive_dir" ]] && sudo rm -fr "$cwd/$archive_dir"
    mkdir -p "$cwd/$archive_dir/build"
    download_archive
    extract_archive
    build_program
    create_soft_links
    cleanup
    exit_fn
}

main_menu
