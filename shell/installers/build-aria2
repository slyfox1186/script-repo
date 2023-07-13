#!/bin/bash

clear

#
# SET PROGRAM NAME + VERSION
#

archive_dir=aria2-1.36.0
archive_url=https://github.com/aria2/aria2/releases/download/release-1.36.0/aria2-1.36.0.tar.gz
archive_ext="${archive_url//*.}"
cwd="$PWD"/aria2-build-script
packages="$cwd"/packages

#
# SET THE C+CPP COMPILERS
#

export CC=clang CXX=clang++

#
# EXPORT COMPILER OPTIMIZATION FLAGS
#

export {CFLAGS,CXXFLAGS}='-g -O3 -march=native'

#
# CREATE FUNCTIONS
#

exit_fn() { printf "\n%s\n\n" 'The script has completed.'; }

fail_fn()
{
    printf "%s\n\n" "$1"
    exit 1
}

cleanup_fn() { sudo rm -fr "$cwd"; }

installed() { return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

#
# INSTALL REQUIRED APT PACKAGES
#

pkgs=(autoconf autogen automake build-essential ca-certificates ccache clang curl libaria2-0 libaria2-0-dev
      libc-ares-dev libdmalloc-dev libgcrypt20-dev libgmp-dev libgnutls28-dev libgpg-error-dev libjemalloc-dev
      libmbedtls-dev libnghttp2-dev librust-openssl-dev libsqlite3-dev libssh2-1-dev libssh-dev libssl-dev
      libxml2-dev pkg-config zlib1g-dev)

for pkg in ${pkgs[@]}
do
    if ! installed "$pkg"; then
        missing_pkgs+=" $pkg"
    fi
done

if [ -n "$missing_pkgs" ]; then
    if sudo apt -y install $missing_pkgs; then
        echo 'The required APT packages were installed.'
    else
        fail_fn "These required APT packages failed to install: $missing_pkgs"
    fi
else
    echo 'The required APT packages are already installed.'
fi

#
# DOWNLOAD ARCHIVE FILE
#

mkdir -p "$packages"
cd $packages || exit 1

archive_name="$archive_dir.tar.$archive_ext"

if [ ! -f "$archive_name" ]; then
    if ! curl -Lso "$archive_name" "$archive_url"; then
        fail_fn "Failed to download: $archive_url as $archive_name"
    fi
fi

#
# MAKE GIT DIRECTORY
#

if [ -d "$packages/$archive_dir" ]; then
    sudo rm -fr "$packages/$archive_dir"
fi

#
# CREATE DIRECTORIES
#

mkdir -p "$packages/$archive_dir/build"

#
# EXTRACT ARCHIVE FILES
#

if ! tar -xf "$archive_name" -C "$packages/$archive_dir" --strip-components 1; then
    fail_fn "Failed to extract: $archive_name"
fi

#
# BUILD PROGRAM FROM SOURCE
#

clear

cd "$packages/$archive_dir/build" || exit 1
../configure --prefix=/usr/local             \
             --disable-nls                   \
             --disable-shared                \
             --disable-werror                \
             --enable-libaria2               \
             --enable-static                 \
             --with-ca-bundle="$pem_target"  \
             --with-libgcrypt                \
             --with-libuv                    \
             --with-jemalloc                 \
             --with-openssl                  \
             --without-gnutls                \
             --without-libnettle
make "-j$(nproc --all)"
if ! sudo make install; then
    make clean
    fail_fn 'Failed to execute: sudo make install'
fi

cleanup_fn
exit_fn
