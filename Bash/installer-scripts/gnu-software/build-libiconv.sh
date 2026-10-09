#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Ee -o pipefail
trap 'printf "Build failed at line %s. Build files were retained for inspection.\n" "$LINENO" >&2; exit 1' ERR

gnu_curl() {
    command curl -q --fail --location --show-error --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 600 --proto '=https' --proto-redir '=https' \
        --user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$@"
}

gnu_wget() {
    command wget --timeout=30 --tries=3 --https-only \
        --user-agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$@"
}

gnu_link_dir() {
    local source_dir="$1" destination="$2" pattern="${3:-*}" file target
    [[ -d "$source_dir" ]] || return 0
    for file in "$source_dir"/*; do
        [[ -e "$file" || -L "$file" ]] || continue
        # The caller supplies a filename glob, for example *.pc.
        # shellcheck disable=SC2053
        [[ "${file##*/}" == $pattern ]] || continue
        target="$destination/${file##*/}"
        [[ ! -d "$target" || -L "$target" ]] || { printf 'Cannot replace directory %s with a symlink.\n' "$target" >&2; return 1; }
        sudo mkdir -p -- "$destination"
        sudo ln -sfn -- "$file" "$target"
    done
}

gnu_new_workdir() {
    local base="${TMPDIR:-/tmp}"
    [[ "$base" == /* && -d "$base" ]] || { printf 'TMPDIR must be an existing absolute directory.\n' >&2; return 1; }
    mktemp -d -- "$base/${0##*/}.XXXXXX"
}

gnu_jobs="${JOBS:-$(nproc)}"
[[ "$gnu_jobs" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer.\n' >&2; exit 1; }

#  Purpose: Build libiconv
#  Changed: Static build to libiconv
#  Updated: 06.19.24
#  Script version: 1.0

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

script_ver="1.0"
prog_name="libiconv"
version=$(gnu_curl -fsS "https://ftp.gnu.org/gnu/libiconv/" | grep -oP 'libiconv-\K[0-9]+(\.[0-9]+)+(?=\.tar\.)' | sort -ruV | sed -n '1p')
archive_name="$prog_name-$version"
archive_url="https://ftp.gnu.org/gnu/libiconv/$archive_name.tar.gz"
archive_ext="${archive_url##*.}"
tar_file="$archive_name.tar.$archive_ext"
install_dir="/usr/local/programs"
cwd="$PWD/$prog_name-build-script"

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

echo "libiconv build script - version $script_ver"
echo "=========================================="
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
    rm -rf -- "$cwd"
}

# Define environment variables
set_env_vars() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS PATH PKG_CONFIG_PATH
}

required_packages() {
    local -a missing_pkgs pkgs
    local pkg
    pkgs=(
        autoconf autoconf-archive automake build-essential
        libc6-dev libtool m4 pkg-config
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


# Helper function to download and extract archives
download_archive() {
    local archive_name archive_url tar_file
    archive_name="$1"
    archive_url="$2"
    tar_file="$3"

    log "Downloading \"$archive_url\" saving as \"$tar_file\""

    gnu_wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "WGET failed to download \"$tar_file\". Line: $LINENO"
}

extract_archive() {
    local archive_name tar_file
    archive_name="$1"
    tar_file="$2"

    log "Extracting $cwd/$tar_file..."
    tar -xf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

build_and_install() {
    local archive_name install_dir LDFLAGS
    archive_name="$1"
    install_dir="$2"
    LDFLAGS="$3"

    cd "$cwd/$archive_name/build" || exit 1

    log "Configuring $archive_name..."
    ../configure --prefix="$install_dir/$archive_name" --enable-static --with-pic || fail "Failed to execute: configure $archive_name. Line: $LINENO"

    log "Building $archive_name..."
    make "-j$gnu_jobs" || fail "Failed to execute: make -j$gnu_jobs. Line: $LINENO"

    log "Installing $archive_name..."
    sudo make install || fail "Failed execute: sudo make install. Line: $LINENO"

    log "Finishing the install with libtool.."
    sudo libtool --finish "$install_dir/$archive_name/lib" || fail "Failed execute: sudo libtool --finish $install_dir/$archive_name/lib. Line: $LINENO"
}

create_soft_links() {
    local archive_name="$1" install_dir="$2"
    gnu_link_dir "$install_dir/$archive_name/bin" /usr/local/bin
    gnu_link_dir "$install_dir/$archive_name/lib/pkgconfig" /usr/local/lib/pkgconfig '*.pc'
    gnu_link_dir "$install_dir/$archive_name/include" /usr/local/include
}

ld_linker_path() {
    local archive_name install_dir prog_name
    archive_name="$1"
    install_dir="$2"
    prog_name="$3"

    echo "$install_dir/$archive_name/lib" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    sudo ldconfig
}

main_menu() {
    # Create output directory
    cwd=$(gnu_new_workdir)
    mkdir -p "$cwd/$archive_name/build"

    # Install the required apt packages
    required_packages

    # Set the compilers and their flags
    set_env_vars

    # Download the source code archives
    download_archive "$archive_name" "$archive_url" "$tar_file"

    # Extract the source code from the archives
    extract_archive "$archive_name" "$tar_file"

    # Install the program
    build_and_install "$archive_name" "$install_dir" "$LDFLAGS"

    # Create the softlinks in /usr/local/bin so they will be found in most users default PATH
    create_soft_links "$archive_name" "$install_dir"

    # Create the softlinks
    ld_linker_path "$archive_name" "$install_dir" "$prog_name"

    cleanup
    exit_fn
}

main_menu "$@"
