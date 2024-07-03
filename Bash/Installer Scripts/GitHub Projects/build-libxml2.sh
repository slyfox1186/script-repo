#!/usr/bin/env bash

# Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-libxml2.sh
# Purpose: Build libxml2
# Updated: 07.03.24
# Script version: 1.7

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set the variables
script_ver="1.7"
prog_name="libxml2"
cwd="$PWD/$prog_name-build-script"
compiler="gcc"
debug="OFF"

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

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "  -v, --version VERSION       Set the version of $prog_name to install"
    echo "  -l, --list                  List available versions of $prog_name"
    echo "  -u, --uninstall             Uninstall $prog_name"
    echo "  -c, --compiler COMPILER     Set the compiler to use (clang) instead of the default: $compiler"
    echo "  -h, --help                  Display this help and exit"
}

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
        asciidoc autogen automake binutils bison build-essential bzip2
        ccache cmake curl libc6-dev libintl-perl libpth-dev libtool
        lzip lzma-dev nasm ninja-build texinfo xmlto yasm zlib1g-dev
        python3 python3-dev python3-pip
    )

    missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ "${#missing_pkgs[@]}" -gt 0 ]]; then
        sudo apt update
        sudo apt install -y "${missing_pkgs[@]}"
    fi
}

set_compiler_flags() {
    CC="$compiler"
    CXX="$compiler++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath,$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"

    # Set Python-related environment variables
    PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    PYTHON_INCLUDE_DIR=$(python3 -c "import sysconfig; print(sysconfig.get_path('include'))")
    PYTHON_CFLAGS=$(python3-config --cflags)
    PYTHON_LIBS=$(python3-config --libs)

    # Ensure CFLAGS includes the Python include directory
    CFLAGS+=" -I$PYTHON_INCLUDE_DIR"

    export CC CXX CFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH PYTHON_VERSION PYTHON_CFLAGS PYTHON_LIBS
}

verify_python_setup() {
    log "Verifying Python setup..."
    if [[ ! -f "$PYTHON_INCLUDE_DIR/Python.h" ]]; then
        fail "Python.h not found in $PYTHON_INCLUDE_DIR. Please ensure python3-dev is correctly installed."
    fi
    log "Python setup verified successfully"
}

download_archive() {
    wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    tar -jxf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"
    autoreconf -fi || fail "Failed to execute: autoreconf. Line: $LINENO"

    # Pass options to autogen.sh
    ./autogen.sh \
        --prefix="$install_dir" \
        --with-python="/usr/bin/python3" \
        --enable-static \
        --enable-shared \
        --with-threads \
        --with-history \
        --enable-ipv6 \
        PYTHON_CFLAGS="$PYTHON_CFLAGS" \
        PYTHON_LIBS="$PYTHON_LIBS" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS" || fail "Failed to execute: autogen.sh. Line: $LINENO"
}

compile_build() {
    make -j"$(nproc)" V=1 || fail "Failed to execute: make. Line: $LINENO"
}

install_build() {
    sudo make install || fail "Failed execute: make install. Line: $LINENO"
}

ld_linker_path() {
    echo "$install_dir/lib" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
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

verify_installation() {
    log "Verifying installation..."
    
    if [[ ! -d "$install_dir" ]]; then
        fail "Installation directory $install_dir not found"
    fi
    
    if [[ ! -f "$install_dir/lib/pkgconfig/libxml-2.0.pc" ]]; then
        fail "libxml-2.0.pc not found. Installation may have failed."
    fi
    
    if ! pkg-config --exists libxml-2.0; then
        fail "pkg-config cannot find libxml-2.0. Installation may have failed."
    fi
    
    log "Installation verified successfully"
}

uninstall_libxml2() {
    local libxml2_dir
    libxml2_dir="$install_dir"
    if [[ -d "$libxml2_dir" ]]; then
        log "Uninstalling $prog_name from $libxml2_dir"
        sudo rm -rf "$libxml2_dir"
        sudo rm "/etc/ld.so.conf.d/custom_$prog_name.conf"
        sudo ldconfig
        log "$prog_name has been uninstalled"
    else
        log "$prog_name is not installed"
    fi
}

list_versions() {
    log "Available versions of $prog_name:"
    echo
    curl -fsS "https://gitlab.gnome.org/GNOME/libxml2/-/tags" | grep -oP 'v\d+\.\d+\.\d+(?=\")' | grep -vE 'rc|beta' | sort -ruV
}

get_latest_version() {
    latest_version=$(curl -fsS "https://gitlab.gnome.org/GNOME/libxml2/-/tags" | grep -oP 'v\d+\.\d+\.\d+(?=\")' | grep -vE 'rc|beta' | sort -ruV | head -n 1 | tr -d 'v')
    log "Detected latest version: $latest_version"
}

main_menu() {
    # Parse command-line arguments
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -v|--version)
                version="$2"
                shift 2
                ;;
            -l|--list)
                list_versions
                exit 0
                ;;
            -u|--uninstall)
                uninstall_libxml2
                exit 0
                ;;
            -c|--compiler)
                compiler="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                fail "Invalid option: $1"
                ;;
        esac
    done

    if [[ -z "$version" ]]; then
        get_latest_version
        version="$latest_version"
        install_dir="/usr/local/programs/$prog_name-$version"
        log "No version specified, using latest version: $version"
    fi

    archive_name="$prog_name-$version"
    archive_url="https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$version/libxml2-v$version.tar.bz2"
    tar_file="$archive_name.tar.bz2"

    # Create output directory
    [[ -d "$cwd/$archive_name" ]] && sudo rm -fr "$cwd/$archive_name"
    mkdir -p "$cwd/$archive_name"

    required_packages
    set_compiler_flags
    verify_python_setup
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    if [[ ! -d "$install_dir/lib" ]]; then
        warn "Failed to locate lib directory. LD configuration skipped."
    else
        ld_linker_path
    fi
    create_soft_links
    verify_installation
    cleanup
    exit_function
}

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

main_menu "$@"
