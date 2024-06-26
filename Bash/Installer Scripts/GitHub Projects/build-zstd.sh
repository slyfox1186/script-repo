#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-zstd.sh
##  Purpose: Build zstd compression software
##  Features: Static and shared build
##  Changed: Static build to both
##  Updated: 05.06.24
##  Script version: 1.3

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Set the variables
script_ver=1.3
prog_name="zstd"
version=$(curl -fsS "https://github.com/facebook/$prog_name/tags/" | grep -oP 'href="[^"]*/tag/v?\K([0-9.])+' | sort -ruV | head -n1)
archive_name="$prog_name-$version"
archive_url="https://github.com/facebook/$prog_name/archive/refs/tags/v$version.tar.gz"
archive_ext="${archive_url//*.}"
tar_file="$archive_name.tar.$archive_ext"
install_dir="/usr/local/programs/$archive_name"
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
exit_function() {
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
        autoconf autoconf-archive automake build-essential ccache
        cmake curl git libdmalloc-dev libjemalloc-dev liblz4-dev
        liblzma-dev libtool m4 meson ninja-build
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

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -fPIC -fPIE -mtune=native -DNDEBUG -fstack-protector-strong -Wno-unused-parameter"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

download_archive() {
    wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    tar -zxf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

configure_build() {
    cd "$cwd/$archive_name/build/meson" || fail "cd into $cwd/$archive_name/build/meson. Line: $LINENO"
    meson setup build --prefix="$install_dir" --buildtype=release --default-library=both -Dbin_tests=false || fail "Failed to execute: meson setup. Line: $LINENO"
}

compile_build() {
    ninja "-j$(nproc --all)" -C build || fail "Failed to execute: ninja build. Line: $LINENO"
}

install_build() {
    sudo ninja -C build install || fail "Failed execute: ninja install. Line: $LINENO"
}

create_soft_links() {
    local -a files
    local file
    files=(zstd zstdgrep zstdless zstd-frugal)
    for file in ${files[@]}; do
        sudo ln -sf "$install_dir/bin/$file" "/usr/local/bin/"
    done

    sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    sudo ln -sf "$install_dir/include/"* "/usr/local/include/"
}

ld_linker_path() {
    echo "$install_dir/lib/x86_64-linux-gnu" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    sudo ldconfig
}

main_menu() {
    # Create output directory
    [[ -d "$cwd" ]] && sudo rm -fr "$cwd/$archive_name"
    mkdir -p "$cwd/$archive_name"

    required_packages
    set_compiler_flags
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    create_soft_links
    ld_linker_path
    cleanup
    exit_function
}

main_menu "$@"
