#!/bin/bash

#################################################################
##
## github: https://github.com/slyfox1186
##
## purpose: builds imagemagick 7 from source code that is
##          obtained from the official imagemagick github page.
##
## function: imagemagick is the leading open source command line
##           image processor. it can blur, sharpen, warp, reduce
##           file size, ect... it is fantastic.
##
## updated: 03.18.23
##
#################################################################

clear

# verify the script does not have root access before continuing
if [ "${EUID}" -ne '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exec sudo bash "${0}" "${@}"
fi

# find the latest version by querying github's api
github_api_fn()
{
    # scrape github website for latest repo version
    net_timeout='5'
    github_repo="${1}"
    curl_cmd=$(curl -m "${net_timeout}" -Ls "https://api.github.com/repos/${github_repo}/releases?per_page=1")
    if [ "${?}" -eq '0' ]; then
        github_ver=$(echo "${curl_cmd}" | jq -r '.[].name')
        github_ver=${github_ver#v}
    fi
}

# pass the github repo name to the function to find it's current release
github_api_fn 'ImageMagick/ImageMagick' 2>/dev/null

# set variables
sver='2.00'
imver="${github_ver}"
pver='1.2.59'
imurl="https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${imver}.tar.gz"
imdir="ImageMagick-${imver}"
imtar="ImageMagick-${imver}.tar.gz"

##
## create functions
##

## exit script
exit_fn()
{
    clear

    # show the newly installed magick version
    if ! magick -version 2>/dev/null; then
        clear
        echo '$ error the script failed to execute the command "magick -version"'
        echo
        echo '$ Try running the command manually first and if needed create a support ticket by visiting:'
        echo '$ https://github.com/slyfox1186/script-repo/issues'
        echo
        exit 1
    fi

    echo
    echo 'The script has completed'
    echo
    echo 'Make sure to star this repository to show your support!'
    echo 'https://github.com/slyfox1186/script-repo'
    echo
    exit 0
}

## delete files
del_files_fn()
{
    if [[ "${1}" -eq '1' ]]; then
        rm -fr "${0}" "${2}" "${3}" "${4}" "${5}"
        exit_fn
    elif [[ "${1}" -eq '2' ]]; then
        exit_fn
    else
        echo 'Error: Bad user input'
        echo
        read -p 'Press enter to exit'
        exit_fn
    fi
}

## determine if a package is installed or not
installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

## failed download/extraction
extract_fail_fn()
{
    clear
    echo 'Error: The tar command failed to extract any files'
    echo
    echo 'To create a support ticket visit: https://github.com/slyfox1186/script-repo/issues'
    echo
    exit 1
}

## required imagemagick developement packages
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
        echo 'The required packages were successfully installed'
    else
        echo 'The required packages are already installed'
    fi
}

echo '$ building libpng12'
echo '================================'
echo
# set libpng12 variables
pngurl="https://sourceforge.net/projects/libpng/files/libpng12/${pver}/libpng-${pver}.tar.xz/download"
pngdir="libpng-${pver}"
pngtar="${pngdir}.tar.xz"

# download libpng12 source code
if [ ! -f "${pngtar}" ]; then
    wget --show-progress -cqO "${pngtar}" "${pngurl}"
fi

if ! tar -xf "${pngtar}"; then
    extract_fail_fn
fi

# change the working directory to libpng's source code parent folder
cd "${pngdir}" || exit 1

# need to run autogen script first since this is a way newer system than these files are used to
echo
echo '$ executing ./autogen.sh'
./autogen.sh &> /dev/null
echo '$ executing ./configure'
./configure --prefix='/usr/local' &> /dev/null

# install libpng12
echo '$ executing make install'
make install &> /dev/null

# change working directory back to parent folder
cd ../ || exit 1

##
## start imagemagick build
##

echo
echo '$ installing required packages'
echo '================================'
echo

# required + extra optional packages for imagemagick to build successfully
magick_packages_fn

echo
echo '$ building imagemagick'
echo '================================'

# download the latest imagemagick source code
if [ ! -f "${imtar}" ]; then
    echo
    wget --show-progress -cqO "${imtar}" "${imurl}"
    echo
fi

## uncompress source code to output folder
if ! tar -xf "${imtar}"; then
    extract_fail_fn
fi

# extract tar and cd into directory
if [ ! -d "${imdir}" ]; then
    mkdir -p "${imdir}"
else
    tar -xf "${imtar}"
    cd "${imdir}" || exit 1
fi

# export the pkg config paths to enable support during the build
PKG_CONFIG_PATH="\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig:\
"
export PKG_CONFIG_PATH

echo '$ executing ./configure'
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
    --with-quantum-depth=16 &> /dev/null

# running make command with parallel processing
echo "\$ executing make -j$(nproc)"
make "-j$(nproc)" &> /dev/null

# installing files to /usr/local/bin
echo '$ executing make install'
make install &> /dev/null

# ldconfig must be run next in order to update file changes or the magick command will not work
ldconfig /usr/local/lib 2>/dev/null

# cd back to the parent folder
cd .. || exit 1

# prompt user to clean up build files
echo
echo '$ Do you want to remove the build files?'
echo
echo '[1] Yes'
echo '[2] No'
echo
read -p 'Your choices are (1 or 2): ' cleanup
clear

del_files_fn "${cleanup}" "${pngdir}" "${imdir}" "${pngtar}" "${imtar}"
