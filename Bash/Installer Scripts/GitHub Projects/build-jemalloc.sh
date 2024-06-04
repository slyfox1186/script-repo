#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/util-linux/Installer%20Scripts/GNU%20Software/build-jemalloc.sh
##  Purpose: Build jemalloc
##  Updated: 12.03.23
##  Script version: 1.0

if [ "$EUID" -eq 0 ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables

script_ver=1.0
jemalloc_ver=5.3.0
archive_dir="jemalloc-$jemalloc_ver"
archive_url="https://github.com/jemalloc/jemalloc/archive/refs/tags/$jemalloc_ver.tar.gz"
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.${archive_ext}"
cwd="$PWD/jemalloc-build-script"
install_dir=/usr/local

CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -mtune=native"
CXXFLAGS="$CFLAGS"
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH

# Create output directory jemalloc
[[ -d "$cwd/$archive_dir" ]] && sudo rm -fr "$cwd/$archive_dir"
mkdir -p "$cwd/$archive_dir/build"

# Download the archive file jemalloc

if [[ ! -f "$cwd/$archive_dir.tar.gz" ]]; then
    curl -Lso "$cwd/$archive_dir.tar.gz" "${archive_url}"
fi

# Extract the archive file jemalloc

if ! tar -zxf "$cwd/$archive_dir.tar.gz" -C "$cwd/$archive_dir" --strip-components 1; then
    fail_fn "Failed to extract: $cwd/$archive_dir.tar.gz"
fi

# Install jemalloc

printf "\n%s\n%s\n\n" \
    "Installing Jemalloc - v$jemalloc_ver" \
    '==============================================='

cd "$cwd/$archive_dir" || exit 1
./autogen.sh
cd build || exit 1
../configure --prefix="$install_dir" \
             --disable-debug \
             --disable-doc \
             --disable-fill \
             --disable-initial-exec-tls  \
             --disable-log \
             --disable-prof \
             --disable-stats \
             --enable-autogen \
             --enable-static \
             --enable-xmalloc
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
fi
echo
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: ${LINENO}"
fi

# Update the library paths that the ld linker searches
sudo bash -c 'bash <(curl -sSL https://ld-linker.optimizethis.net)'
sudo ldconfig -v
