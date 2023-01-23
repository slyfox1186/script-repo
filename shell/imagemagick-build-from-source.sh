#!/bin/bash

clear

## speed up things with parallel processing
CPUS="$(nproc)"

##
## create functions
##

exit_fn()
{
    echo
    echo 'The script has finished.'
    echo '========================'
    echo
    echo 'Make sure to star this repository to show your support!'
    echo 'https://github.com/slyfox1186/script-repo'
    echo
    rm -f "${0}"
    exit 0
}

del_files_fn()
{
    if [[ "${1}" -eq '1' ]]; then exit_fn
    elif [[ "${1}" -eq '2' ]]; then rm -fr "${2}" "${3}" "${4}" "${5}"
    else
        echo 'error: bad user input... exiting script.'
        sleep 4
        exit_fn
    fi
}

# function to determine if a package is installed or not
installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

##
## Required Developement Packages
##

echo
echo 'Installing: libpng-12 required developement packages'
echo '=========================================='

CUDA_PKGS=(build-essential libc6 libc6-dev libnuma-dev libnuma1 libtool unzip wget)

for CUDA_PKG in ${CUDA_PKGS[@]}
do
    if ! installed "${CUDA_PKG}"; then
        MISSING_CUDA_PKGS+=" ${CUDA_PKG}"
    fi
done

if [ -n "${MISSING_CUDA_PKGS}" ]; then
    sudo apt install "${MISSING_CUDA_PKGS}"
else
    echo 'The developement libraries required for libpng-12 have already been installed.'
    echo
fi

echo 'Starting libpng12 build'
echo '======================='
echo
sleep 2

# set variables for libpng12
LVER='1.2.59'
LURL="https://sourceforge.net/projects/libpng/files/libpng12/${LVER}/libpng-${LVER}.tar.xz/download"
LDIR="libpng-${LVER}"
LTAR="${LDIR}.tar.xz"

# download libpng12 source code
if [ ! -f "${LTAR}" ]; then wget --show-progress -cqO "${LTAR}" "${LURL}"; fi

# uncompress source code to folder
if ! tar -xf "${LTAR}"; then
    echo 'error: tar failed to extract the downloaded .xz file.'
    echo
    exit 1
fi

# change working directory to libpng's source code directory
cd "${LDIR}" || exit 1

# need to run autogen script first since this is a way newer system than these files are used to
./autogen.sh

# configure
./configure \
    --prefix='/usr/local'

# install libpng12
sudo make install

# change working directory back to parent folder
cd ../ || exit 1

##
## start imagemagick build
##
echo
echo 'Starting ImageMagick Build'
echo '=========================='
echo
sleep 2

# these are required and extra optional packages for imagemagick to build succesfully
echo
echo 'Install required and add-on packages required to build IM from source code'
echo '=========================='
echo
echo 'You must install most of these for the build to succeed.'
echo
sudo apt install \
    build-essential \
    lib*malloc-dev \
    libgl2ps-dev \
    libglib2.0* \
    libgoogle-perftools-dev \
    libheif-dev \
    libjpeg-dev \
    libmagickcore-6.q16* \
    libopenjp2-7-dev \
    libpng++-dev \
    libpng-dev \
    libpng-tools \
    libpng16-16 \
    libpstoedit-dev \
    libraw-dev \
    librust-bzip2-dev \
    librust-jpeg-decoder+default-dev \
    libtiff-dev \
    libwebp-dev \
    libzip-dev \
    pstoedit

# set variables for imagemagick
IMVER='7.1.0-57'
IMURL="https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${IMVER}.tar.gz"
IMDIR="ImageMagick-${IMVER}"
IMTAR="${IMDIR}.tar.gz"

# download imagemagick source code
if [ ! -f "${IMTAR}" ]; then wget --show-progress -cqO "${IMTAR}" "${IMURL}"; fi

# uncompress source code to folder
if [ ! -d "${IMDIR}" ]; then
    if ! tar -xf "${IMTAR}"; then
        echo 'error: tar command failed to extract files'
        echo
        exit 1
    fi
fi

# change working directory to imagemagick's source code directory
cd "${IMDIR}" || exit 1

PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_PATH
./configure \
    --enable-ccmalloc \
    --enable-legacy-support \
    --with-autotrace \
    --with-dmalloc \
    --with-flif \
    --with-gslib \
    --with-heic \
    --with-jemalloc \
    --with-modules \
    --with-perl \
    --with-tcmalloc \
    --with-quantum-depth=16

# running make command with parallel processing
echo "executing command: make -j$(CPUS)"
echo '================================='
echo
make "-j$(CPUS)"

# installing files to /usr/local/bin/
echo
echo 'executing command: sudo make install'
echo '===================================='
echo
sudo make install

# ldconfig must be run next in order to update file changes or the magick command will not work
echo
echo 'executing: ldconfig /usr/local/lib to update file changes.'
echo '=========================================================='
echo
sleep 3
ldconfig /usr/local/lib

# showing the newly installed magick version
if ! magick --version 2>/dev/null; then
    clear
    echo 'error: the script failed to execute the command '\''magick --version'\''.'
    echo
    echo 'info: try running the command manually to see if it will work, otherwise make a support ticket.'
    echo
    exit 1
fi

# change working directory back to parent folder
cd ../ || exit 1

# prompt user to clean up build files
echo
echo 'Input Required: File cleanup.'
echo '============================='
echo

echo 'Do you want to keep the build files?'

echo '[1] Yes'
echo '[2] No'
echo
read -p 'Your choices are (1 or 2): ' ANSWER
clear

del_files_fn "${ANSWER}" "${LDIR}" "${IMDIR}" "${LTAR}" "${IMTAR}"
exit_fn
