#!/bin/bash

#################################################################
##
## GitHub: https://github.com/slyfox1186
##
## Purpose: Builds ImageMagick 7 from source code that is
##          obtained from their official GitHub page.
##
## Function: ImageMagick is the leading open source command line
##           image processor. It can blur, sharpen, warp, reduce,
##           file size, ect... It is fantastic.
##
## Last Updated: 01.25.23
##
#################################################################

clear

# VERIFY THAT THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [ "${EUID}" -gt '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exit 1
fi

##
## Latest ImageMagick Version
##

VERSION='7.1.0-59'

## speed up things with parallel processing
CPUS="$(nproc)"

##
## create functions
##

exit_fn()
{
    clear

    # showing the newly installed magick version
    if ! magick -version 2>/dev/null; then
        clear
        echo "Error: the script failed to execute the command 'magick -version'."
        echo
        echo 'Info: try running the command manually to see if it will work, otherwise make a support ticket.'
        echo
        exit 1
    fi

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
    if [[ "${1}" -eq '1' ]]; then
        exit_fn
    elif [[ "${1}" -eq '2' ]]; then
        rm -fr "${2}" "${3}" "${4}" "${5}"
    else
        echo 'Error: Bad user input.'
        echo
        read -p 'Press Enter to exit.'
        exit_fn
    fi
}

# function to determine if a package is installed or not
installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

##
## Required Developement Packages
##

echo
echo 'Installing: Required packages'
echo '============================='

PKGS=(build-essential libc6 libc6-dev libnuma-dev libnuma1 libtool unzip wget)

for PKG in ${PKGS[@]}
do
    if ! installed "${PKG}"; then
        MISSING_PKGS+=" ${PKG}"
    fi
done

##
## Required packages to build ImageMagick
##

if [ -n "${MISSING_PKGS}" ]; then
    for i in "${MISSING_PKGS}"
    do
        apt -y install ${i}
    done
else
    echo
    echo 'Required packages are already installed.'
    sleep 2
fi

clear
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
    echo 'Error: The tar command failed to extract the downloaded file.'
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

clear
echo 'Starting ImageMagick Build'
echo '=========================='
echo
sleep 2

# these are required and extra optional packages for imagemagick to build succesfully
echo
echo 'Install required and add-on packages required to build IM from source code'
echo '=========================='
echo
echo 'You must install these for the build to succeed.'
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
IMURL="https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${VERSION}.tar.gz"
IMDIR="ImageMagick-${VERSION}"
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

# Export the pkg config paths to enable support during the build
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
echo "executing: make -j$(CPUS)"
echo '===================================='
echo
make "-j$(CPUS)"

# installing files to /usr/local/bin/
echo
echo 'executing: sudo make install'
echo '===================================='
echo
sudo make install

# ldconfig must be run next in order to update file changes or the magick command will not work
ldconfig /usr/local/lib >dev/null

# change working directory back to parent folder
cd ../ || exit 1

# prompt user to clean up build files
echo
echo 'Input Required: File cleanup'
echo '============================'
echo

echo 'Do you want to keep the build files?'

echo '[1] Yes'
echo '[2] No'
echo
read -p 'Your choices are (1 or 2): ' ANSWER
clear

del_files_fn "${ANSWER}" "${LDIR}" "${IMDIR}" "${LTAR}" "${IMTAR}"
exit_fn
