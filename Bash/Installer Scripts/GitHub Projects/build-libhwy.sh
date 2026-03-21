#!/usr/bin/env bash

##  Github: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-libhwy.sh
##  Purpose: build libhwy
##  Updated: 07.03.24
##  Script version: 1.3

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "\\n${YELLOW}[WARNING]${NC} $1"
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
    log "Installing dependencies..."
    pkgs=(
         autoconf autoconf-archive autogen automake autotools-dev
         build-essential ccache cmake curl libgtest-dev libtool
         libtool-bin m4 ninja-build pkg-config
    )

    missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ "${#missing_pkgs[@]}" -gt 0 ]]; then
        sudo apt update
        sudo apt install "${missing_pkgs[@]}"
        sudo apt -y autoremove
    fi
}

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-rpath=$install_dir/lib64:$install_dir/lib"
    PKG_CONFIG="$(command -v pkg-config)"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG PKG_CONFIG_PATH
}

download_archive() {
    wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    tar -xf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"
    CFLAGS+=" -DHWY_COMPILE_ALL_ATTAINABLE"
    CXXFLAGS+="$CFLAGS"
    cmake -S . -B build \
          -DCMAKE_INSTALL_PREFIX="$install_dir" \
          -DCMAKE_BUILD_TYPE=Release \
          -DHWY_ENABLE_TESTS=OFF \
          -DBUILD_TESTING=OFF \
          -DHWY_ENABLE_EXAMPLES=OFF \
          -DHWY_FORCE_STATIC_LIBS=ON \
          -G Ninja -Wno-dev || fail "Failed to execute: cmake configure. Line: $LINENO"
}

compile_build() {
    cmake --build build -j "$(nproc --all)" || fail "Failed to execute: cmake build. Line: $LINENO"
}

install_build() {
    sudo cmake --install build || fail "Failed execute: cmake install. Line: $LINENO"
}

ld_linker_path() {
    echo -e "$install_dir/lib64\\n$install_dir/lib" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    sudo ldconfig
}

create_soft_links() {
    # Create bin links
    if [[ -d "$install_dir/bin" ]]; then
        for file in "$install_dir/bin"/*; do
            if [[ -f "$file" && -x "$file" ]]; then
                sudo ln -sf "$file" "/usr/local/bin/${file##*/}"
                log "Created link for binary: ${file##*/}"
            fi
        done
    else
        warn "No bin directory found in $install_dir"
    fi

    # Create pkgconfig links
    if [[ ! -d "/usr/local/lib/pkgconfig" ]]; then
        sudo mkdir -p "/usr/local/lib/pkgconfig"
        log "Created /usr/local/lib/pkgconfig directory"
    fi
    if [[ -d "$install_dir/lib/pkgconfig" ]]; then
        pc_files=("$install_dir/lib/pkgconfig"/*.pc)
        if [[ ${#pc_files[@]} -eq 0 ]]; then
            warn "No .pc files found in $install_dir/lib/pkgconfig"
        else
            for file in "${pc_files[@]}"; do
                if [[ -f "$file" ]]; then
                    sudo ln -sf "$file" "/usr/local/lib/pkgconfig/${file##*/}"
                    log "Created link for pkg-config file: ${file##*/}"
                fi
            done
        fi
    else
        warn "No pkgconfig directory found in $install_dir/lib"
    fi

    # Create include links
    if [[ -d "$install_dir/include" ]]; then
        for file in "$install_dir/include"/*; do
            if [[ -f "$file" ]]; then
                sudo ln -sf "$file" "/usr/local/include/${file##*/}"
                log "Created link for header: ${file##*/}"
            fi
        done
    else
        warn "No include directory found in $install_dir"
    fi

    log "Soft link creation process completed"
}

show_usage() {
    echo "Usage: ${0##*/} [OPTIONS]"
    echo "Build libhwy from source."
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -v, --version    Specify the version of libhwy to build (default: latest)"
    echo
    echo "Example:"
    echo "  $0 -v 1.0.3"
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            shift
            libhwy_version="$1"
            ;;
        *)
            log "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    shift
done

main_menu() {
    script_ver=1.3
    prog_name="libhwy"
    version=$(curl -fsS "https://github.com/google/highway/tags" | grep -oP '/tag/\K\d+\.\d+\.\d+' | sort -ruV | head -n1)
    archive_name="$prog_name-$version"
    install_dir="/usr/local/programs/$archive_name"
    cwd="$PWD/$archive_name-build-script"

    # Create output directory
    [[ -d "$cwd/$archive_name" ]] && sudo rm -fr "$cwd/$archive_name"
    mkdir -p "$cwd/$archive_name"

    if [[ -n "$libhwy_version" ]]; then
        archive_url="https://github.com/google/highway/archive/refs/tags/$libhwy_version.tar.gz"
    else
        archive_url="https://github.com/google/highway/archive/refs/tags/$version.tar.gz"
    fi
    tar_file="$archive_name.tar.gz"

    required_packages
    set_compiler_flags
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    ld_linker_path
    create_soft_links
    cleanup
    exit_function
}

main_menu "$@"