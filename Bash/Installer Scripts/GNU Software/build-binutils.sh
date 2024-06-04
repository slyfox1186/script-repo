#!/usr/bin/env bash

# GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-binutils.sh
# Purpose: build gnu binutils with GOLD enabled
# Updated: 05.12.24
# Script version: 2.1

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set the variables
script_ver=2.1
prog_name="binutils"
version=$(curl -fsS "https://ftp.gnu.org/gnu/$prog_name/" | grep -oP 'binutils-\K([0-9.])+(?=\.tar\..*)' | sort -ruV | head -n1)
archive_name="$prog_name-$version"
archive_url="https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar.xz"
archive_ext="${archive_url//*.}"
tar_file="$archive_name.tar.$archive_ext"
install_dir="/usr/local/$archive_name"
cwd="$PWD/$archive_name-build-script"

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

echo "$prog_name build script - version $script_ver"
echo "================================================="
echo

# Create functions
exit_fn() {
    echo
    log "The script has completed"
    log "${GREEN}Make sure to ${YELLOW}star ${GREEN}this repository to show your support!${NC}"
    log "${CYAN}https://github.com/slyfox1186/script-repo${NC}"
    exit 0
}

cleanup() {
    sudo rm -fr "$cwd"
}

required_packages() {
    local -a missing_pkgs pkgs
    local pkg
    pkgs=(
        autoconf autoconf-archive automake binutils bison build-essential
        ccache curl gettext libncursesw5-dev libpth-dev libreadline-dev
        libticonv-dev libtool lzip m4
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

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

install_autoconf() {
    if [[ ! -x "/tmp/autoconf-2.69/bin/autoconf" ]]; then
        log "Installing autoconf 2.69..."
        mkdir -p "/tmp/autoconf-2.69"
        wget -cqO "/tmp/autoconf-2.69/build-autoconf.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-autoconf.sh"
        cd "/tmp/autoconf-2.69" || exit 1
        bash build-autoconf.sh -v 2.69
        log "Autoconf 2.69 installed."
    else
        log "Autoconf 2.69 is already installed in the temporary directory."
    fi
    export PATH="/tmp/autoconf-2.69/autoconf-2.69/bin:$PATH"
}

download_archive() {
    wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    tar -Jxf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"
    autoreconf -fi
    cd build || exit 1
    ../configure --prefix="$install_dir" --disable-werror --with-zstd --with-system-zlib \
                 --enable-lto --enable-year2038 --enable-ld=yes --enable-gold=yes || fail "Failed to execute: configure. Line: $LINENO"
}

compile_build() {
    make "-j$(nproc --all)" || fail "Failed to execute: make build. Line: $LINENO"
}

install_build() {
    sudo make install || fail "Failed execute: make install. Line: $LINENO"
}

ld_linker_path() {
    echo "$install_dir/lib/usr/local/binutils-2.42/lib/bfd-plugins" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    echo "$install_dir/lib/usr/local/binutils-2.42/lib/gprofng" | sudo tee -a "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    sudo ldconfig
}

create_soft_links() {
    sudo ln -sf "$install_dir/bin/"* "/usr/local/bin/"
    sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    sudo ln -sf "$install_dir/include/"* "/usr/local/include/"
}

main_menu() {
    # Create output directory
    [[ -d "$cwd/$archive_name" ]] && sudo rm -fr "$cwd/$archive_name"
    mkdir -p "$cwd/$archive_name/build"

    required_packages
    set_compiler_flags
    install_autoconf
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    create_soft_links
    ld_linker_path
    cleanup
    exit_fn
}

main_menu "$@"
