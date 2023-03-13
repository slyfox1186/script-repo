#!/bin/bash

#################################################################
##
## GitHub: https://github.com/slyfox1186
##
## PURPOSE: BUILDS IMAGEMAGICK 7 FROM SOURCE CODE THAT IS
##          OBTAINED FROM THE OFFICIAL IMAGEMAGICK GITHUB PAGE.
##
## FUNCTION: IMAGEMAGICK IS THE LEADING OPEN SOURCE COMMAND LINE
##           IMAGE PROCESSOR. IT CAN BLUR, SHARPEN, WARP, REDUCE
##           FILE SIZE, ECT... IT IS FANTASTIC.
##
## LAST UPDATED: 03.15.23
##
#################################################################

clear
set -u

##
## VERIFY THAT THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
##

if [ "${EUID}" -gt '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exit 1
fi

##
## VERSION INFORMATION VARIABLES
##

sver='1.70'
imver='7.1.1-3'
pver='1.2.59'

######################
## CREATE FUNCTIONS ##
######################

##
## EXIT SCRIPT FUNCTION
##

exit_fn()
{
    clear

    # SHOW THE NEWLY INSTALLED MAGICK VERSION
    if ! magick -version 2>/dev/null; then
        clear
        echo 'Error: The script failed to execute the command "magick -version"'
        echo '====================================================================='
        echo
        echo 'Try running the command manually first and if needed create a support ticket by visiting:'
        echo 'https://github.com/slyfox1186/script-repo/issues'
        echo
        rm -f "${0}"
        exit 1
    fi

    echo
    echo 'The script has completed'
    echo '============================'
    echo
    echo 'Make sure to star this repository to show your support!'
    echo 'https://github.com/slyfox1186/script-repo'
    echo
    rm -f "${0}"
    exit 0
}

##
## DELETE FILES FUNCTION
##

del_files_fn()
{
    if [[ "${1}" -eq '1' ]]; then
        rm -fr "${2}" "${3}" "${4}" "${5}"
        exit_fn
    elif [[ "${1}" -eq '2' ]]; then
        exit_fn
    else
        echo 'Error: Bad user input'imtar
        echo '========================='
        echo
        read -p 'Press enter to exit'
        exit_fn
    fi
}

##
## FUNCTION TO DETERMINE IF A PACKAGE IS INSTALLED OR NOT
##
installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

##
## FAILED DOWNLOAD/EXTRACTIONS FUNCTION
##
extract_fail_fn()
{
    clear
    echo 'Error: The tar command failed to extract any files'
    echo '====================================================='
    echo
    echo 'To create a support ticket visit: https://github.com/slyfox1186/script-repo/issues'
    echo '====================================================================================='
    echo
    exit 1
}

##
## REQUIRED IMAGEMAGICK DEVELOPEMENT PACKAGES
##
magick_packages_fn()
{

    pkgs=(autoconf automake build-essential google-perftools libc-devtools libcpu-features-dev libcrypto++-dev libdmalloc-dev libdmalloc5 libgc-dev libgc1 libgl2ps-dev libglib2.0-dev libgoogle-perftools-dev libgoogle-perftools4 libheif-dev libjemalloc-dev libjemalloc2 libjpeg-dev libmagickcore-6.q16hdri-dev libmimalloc-dev libmimalloc2.0 libopenjp2-7-dev libpng++-dev libpng-dev libpng-tools libpng16-16 libpstoedit-dev libraw-dev librust-bzip2-dev librust-jpeg-decoder+default-dev libtcmalloc-minimal4 libtiff-dev libtool libwebp-dev libzip-dev pstoedit)

    for pkg in ${pkgs[@]}
    do
        if ! installed "${pkg}"; then
            missing_pkgs+=" ${pkg}"
        fi
    done

    if [ -n "${missing_pkgs-}" ]; then
        for i in "${missing_pkgs}"
        do
            apt -y install ${i}
        done
        echo
        echo 'IM'\''s Dev Libraries were successfully installed'
        echo '=========================================================='
    else
        echo
        echo 'IM'\''s Dev Libraries are already installed'
        echo '===================================================='
    fi
    sleep 2
}

echo
echo "Starting libpng12 Build: v${pver}"
echo '======================================'
echo
sleep 2

# SET LIBPNG12 VARIABLES
pngurl="https://sourceforge.net/projects/libpng/files/libpng12/${pver}/libpng-${pver}.tar.xz/download"
pngdir="libpng-${pver}"
pngtar="${pngdir}.tar.xz"

# DOWNLOAD LIBPNG12 SOURCE CODE
if [ ! -f "${pngtar}" ]; then
    wget --show-progress -cqO "${pngtar}" "${pngurl}"
fi

##
## UNCOMPRESS SOURCE CODE TO OUTPUT FOLDER
##
if ! tar -xf "${pngtar}"; then
    extract_fail_fn
fi

# CHANGE THE WORKING DIRECTORY TO LIBPNG'S SOURCE CODE PARENT FOLDER
cd "${pngdir}" || exit 1

# NEED TO RUN AUTOGEN SCRIPT FIRST SINCE THIS IS A WAY NEWER SYSTEM THAN THESE FILES ARE USED TO
echo
echo 'Executing: autogen.sh script'
echo '=============================='
echo
sleep 2
./autogen.sh

# RUN CONFIGURE SCRIPT
echo
echo 'Executing: ./configure script'
echo '==============================='
echo
sleep 2
./configure --prefix='/usr/local'

# INSTALL LIBPNG12
echo
echo 'Executing: make install'
echo '========================='
echo
sleep 2
make install

# CHANGE WORKING DIRECTORY BACK TO PARENT FOLDER
cd ../ || exit 1

#############################
## START IMAGEMAGICK BUILD ##
#############################

echo
echo "Installing ImagickMagick: v${imver}"
echo '====================================='
sleep 2
echo
echo 'Installing: IM'\''s Required Developement Libraries'
echo '====================================================='
sleep 2

# REQUIRED + EXTRA OPTIONAL PACKAGES FOR IMAGEMAGICK TO BUILD SUCCESSFULLY
magick_packages_fn

# SET VARIABLES FOR IMAGEMAGICK
imurl="https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${imver}.tar.gz"
imdir="ImageMagick-${imver}"
imtar="ImageMagick-${imver}.tar.gz"

# DOWNLOAD IMAGEMAGICK SOURCE CODE
if [ ! -f "${imtar}" ]; then
    echo 'Downloading: IM Source Code'
    echo '============================='
    echo
    wget --show-progress -cqO "${imtar}" "${imurl}"
    echo
fi

# EXTRACT TAR AND CD INTO DIRECTORY
if [ ! -d "${imdir}" ]; then
    mkdir -p "${imdir}"
else
    tar -xf "${imtar}" -C "${imdir}"
    cd "${imdir}/${imdir}" || exit 1
fi

# EXPORT THE pkg CONFIG PATHS TO ENABLE SUPPORT DURING THE BUILD
PKG_CONFIG_PATH='/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig'
export PKG_CONFIG_PATH

echo
echo 'Executing: configure script'
echo '============================='
echo
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

# RUNNING MAKE COMMAND WITH PARALLEL PROCESSING
echo "executing: make -j$(nproc)"
echo '============================'
echo
sleep 2
make "-j$(nproc)"

# INSTALLING FILES TO /usr/local/bin/
echo
echo 'executing: make install'
echo '========================='
echo
sleep 2
make install

# LDCONFIG MUST BE RUN NEXT IN ORDER TO UPDATE FILE CHANGES OR THE MAGICK COMMAND WILL NOT WORK
ldconfig /usr/local/lib 2>/dev/null

# CD BACK TO THE PARENT FOLDER
cd ../.. || exit 1

# PROMPT USER TO CLEAN UP BUILD FILES
echo
echo 'Do you want to remove the build files?'
echo '========================================'
echo
echo '[1] Yes'
echo '[2] No'
echo
read -p 'Your choices are (1 or 2): ' cleanup
clear

del_files_fn "${cleanup}" "${pngdir}" "${imdir}" "${pngtar}" "${imtar}"
