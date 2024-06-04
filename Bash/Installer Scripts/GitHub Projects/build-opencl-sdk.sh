#!/usr/bin/env bash

# Github script for building opencl sdk
# Script version: 1.0
# Updated: 01.08.24
# Url: https://github.com/slyfox1186/script-repo/blob/main/bash/installer%20scripts/github%20projects/build-opencl-sdk

clear

# Check for root privileges
if [[ $EUID -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the script variables
script_ver=1.0
archive_dir=OpenCL-SDK
archive_url="https://github.com/KhronosGroup/OpenCL-SDK.git"
cwd="$PWD/opencl-sdk-build-script"
install_dir=/usr/local

# Set compiler variables
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export CC CXX CFLAGS CXXFLAGS PATH PKG_CONFIG_PATH


# Install required apt packages
pkgs=(
      autoconf autoconf-archive autogen automake binutils bison build-essential bzip2 ccache
      curl install-info libc6-dev libglew-dev libtool libtool-bin libudev-dev libzstd-dev m4
      nasm python3 python3-pip texinfo xz-utils zlib1g-dev zstd yasm
)

for pkg in ${pkgs[@]}
do
    if ! sudo dpkg -l | grep -oq "$pkg"; then
        missing_pkgs="$pkg "
    fi
done

if [ -n $missing_pkgs ]; then
    sudo apt install $missing_pkgs
fi

# Remove any leftover files from previous runs
sudo rm -fr "$cwd/$archive_dir"

# Clone the repository
git clone --recursive "$archive_url" "$cwd/$archive_dir" || { echo "Clone failed"; exit 1; }

# Build the sdk
cd "$cwd" || exit 1
cmake -S OpenCL-SDK -B build                   \
      -DCMAKE_INSTALL_PREFIX="$install_dir"    \
      -DCMAKE_BUILD_TYPE=Release               \
      -DBUILD_SHARED_LIBS=ON                   \
      -DBUILD_TESTING=OFF                      \
      -DBUILD_DOCS=OFF                         \
      -DBUILD_EXAMPLES=OFF                     \
      -DOPENCL_SDK_BUILD_SAMPLES=ON            \
      -DCMAKE_C_FLAGS="${CFLAGS}"              \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS}"          \
      -DOPENCL_HEADERS_BUILD_CXX_TESTS=OFF     \
      -DOPENCL_ICD_LOADER_BUILD_SHARED_LIBS=ON \
      -DOPENCL_SDK_BUILD_OPENGL_SAMPLES=OFF    \
      -DOPENCL_SDK_BUILD_SAMPLES=OFF           \
      -DTHREADS_PREFER_PTHREAD_FLAG=ON         \
      -G Ninja -Wno-dev

if ! ninja "-j$(nproc --all)" -C build; then
    printf "\n%s\n\n" "Ninja build failed"
    exit 1
fi

if ! sudo ninja -C build install; then
    printf "\n%s\n\n" "Ninja install failed"
    exit 1
fi

# Clean up files
read -p "Do you want to remove build directories? (y/n): " choice
case "$choice" in 
    [yY]|[yY][eE][sS])  sudo rm -fr "$cwd";;
    *)                  printf "\n%s\n\n" "Build directories retained.";;
esac

# Exit message
printf "\n%s\n\n" "OpenCL SDK build process completed."
