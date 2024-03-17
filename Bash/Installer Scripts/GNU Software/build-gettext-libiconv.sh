#!/Usr/bin/env bash


set -e

if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

script_ver=1.2
archive_dir1=libiconv-1.17
archive_dir2=gettext-0.22.5
archive_url1=https://ftp.gnu.org/gnu/libiconv/$archive_dir1.tar.gz
archive_url2=https://ftp.gnu.org/gnu/gettext/$archive_dir2.tar.lz
cwd="$PWD"/gettext-libiconv-build-script
install_dir=/usr/local
CC=gcc
CXX=g++
CFLAGS="-g -O3 -pipe -fno-plt -march=native"
CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CC CFLAGS CXX CXXFLAGS

log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $@"
}

error() {
    log "Error: $@" >&2
    exit 1
}

download_and_extract() {
    local archive_dir=$1
    local archive_url=$2

    mkdir -p "$cwd/$archive_dir" || error "Failed to create directory $cwd/$archive_dir"
    log "Downloading $archive_url..."
    curl -L "$archive_url" -o "$cwd/$archive_dir.$archive_ext" || error "Failed to download $archive_url"
    log "Extracting $archive_dir.$archive_ext..."
    tar -xf "$cwd/$archive_dir.$archive_ext" -C "$cwd/$archive_dir" --strip-components 1 || error "Failed to extract $archive_dir.$archive_ext"
}

build_and_install() {
    local archive_dir=$1
    cd "$cwd/$archive_dir" || exit 1
    mkdir -p build
    cd build || exit 1
    log "Configuring $archive_dir..."
    ../configure --prefix="$install_dir" --enable-static --with-pic || error "Failed to configure $archive_dir"
    log "Building $archive_dir..."
    if ! make "-j$(nproc --all)"; then
        error "Failed to run make -j$(nproc --all)"
    fi
    log "Installing $archive_dir..."
    if ! make install; then
        error 'Failed to run make install'
    fi
    libtool --finish "$install_dir/lib" || error "Failed to finish libtool setup"
}

printf "%s\n%s\n\n"                                  \
    "gettext + libiconv build script - v$script_ver" \
    '==============================================='

download_and_extract "$archive_dir1" "$archive_url1"
build_and_install "$archive_dir1"

download_and_extract "$archive_dir2" "$archive_url2"
build_and_install "$archive_dir2"
