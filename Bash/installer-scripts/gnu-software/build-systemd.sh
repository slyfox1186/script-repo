#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Ee -o pipefail
trap 'printf "Build failed at line %s. Build files were retained for inspection.\n" "$LINENO" >&2; exit 1' ERR

gnu_curl() {
    command curl -q --fail --location --show-error --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 600 --proto '=https' --proto-redir '=https' \
        --user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$@"
}

gnu_new_workdir() {
    local base="${TMPDIR:-/tmp}"
    [[ "$base" == /* && -d "$base" ]] || { printf 'TMPDIR must be an existing absolute directory.\n' >&2; return 1; }
    mktemp -d -- "$base/${0##*/}.XXXXXX"
}

gnu_jobs="${JOBS:-$(nproc)}"
[[ "$gnu_jobs" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer.\n' >&2; exit 1; }

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
install_dir="/usr/local/programs/$archive_dir"

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
    CFLAGS="-g -O2 -pipe -fno-plt -march=native"
    CXXFLAGS="-g -O2 -pipe -fno-plt -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

# Set the path variables
set_path_variables() {
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    LD_LIBRARY_PATH="/usr/local/lib64:/usr/local/lib:/usr/lib64:/usr/lib:/lib64:/lib:/usr/local/cuda-12.2/nvvm/lib64"
    export LD_LIBRARY_PATH PKG_CONFIG_PATH PATH
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
    local response
    while true; do
        if ! read -r -p "Remove build directory '$cwd'? [y/N] " response; then
            printf '\nBuild files retained at %s\n' "$cwd"
            return 0
        fi
        case "$response" in
            1|y|Y|yes|YES) rm -rf -- "$cwd"; return 0 ;;
            2|n|N|no|NO|"") printf 'Build files retained at %s\n' "$cwd"; return 0 ;;
            *) printf 'Enter y or n.\n' >&2 ;;
        esac
    done
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

    missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        sudo apt-get update
        sudo apt-get install "${missing_pkgs[@]}"
    fi
}

# Download the archive file
download_archive() {
    if [[ ! -f "$cwd/$archive_name" ]]; then
        gnu_curl -Lso "$cwd/$archive_name" "$archive_url"
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
                      -Db_lto_threads="$gnu_jobs" \
                      -Ddefault-user-shell="$(type -P bash)" \
                      -Ddns-over-tls=auto \
                      -Defi=true \
                      -Dhibernate=false \
                      -Dhwdb=true \
                      -Dinstall-tests=true \
                      -Dldconfig=true \
                      -Drfkill=true \
                      -Dtests=unsafe \
                      -Dtranslations=false \
                      -Duser-path="/usr/local/bin:/usr/bin:/bin" \
                      -Dzstd=enabled \
                      -Dc_args="-O3 -pipe -fno-plt -fPIC -fPIE -march=native" \
                      -Dcpp_args="-O3 -pipe -fno-plt -fPIC -fPIE -march=native"
    ninja -C build "-j$gnu_jobs" || fail "Failed to build systemd."
    if ! sudo ninja -C build install; then
        fail "Failed to execute: sudo ninja -C build install. Line: ${LINENO}"
    fi
}

# Create soft links
create_soft_links() {
    for file in "$install_dir"/bin/*; do
        [[ -e "$file" || -L "$file" ]] || continue
        sudo mkdir -p "/usr/local/bin/"
        sudo ln -sfn -- "$file" "/usr/local/bin/"
    done
}

# Main script
main_menu() {
    check_root
    display_info
    install_dependencies

    cwd=$(gnu_new_workdir)

    mkdir -p "$cwd/$archive_dir/build"
    download_archive
    extract_archive
    build_program
    create_soft_links
    cleanup
    exit_fn
}

main_menu
