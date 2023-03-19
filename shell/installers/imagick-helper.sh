#!/bin/bash

# Helper script to download and run the build-imagemagick.

clear

# verify the script does not have root access before continuing
if [ "${EUID}" -ne '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exec sudo bash "${0}" "${@}"
fi

make_dir()
{
    if [ ! -d "${1}" ]; then
        if ! mkdir "${1}"; then            
            printf '\n Failed to create dir %s' "${1}";
            exit 1
        fi
    fi    
}

build_dir="${PWD}/imagemagick-build"
   
echo 'Imagemagick Build Script Downloader v1.0'
echo '============================================================='
echo

echo "Create the imagemagick build directory ${build_dir}"
echo '============================================================='
echo
make_dir "${build_dir}"
cd "${build_dir}" || exit 1

echo 'Now download and execute the build script'
echo '============================================================='
echo

bash <(curl -sSL 'https://imagick.optimizethis.net') --build
