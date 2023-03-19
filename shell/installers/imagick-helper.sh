#!/bin/bash

# Helper script to download and run the build-imagemagick.

clear

# verify the script does not have root access before continuing
if [ "${EUID}" -ne '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exec sudo bash "${0}" "${@}"
fi

echo -e "\$ Imagemagick Build Script Downloader v1.0\\n"
echo -e "\$ Creating build directory\\n"

if ! mkdir "${PWD}/imagick-build"; then            
    printf '\n Failed to create dir %s' "${1}"
    echo
    exit 1
fi

cd "${PWD}/imagick-build" || exit 1

echo -e "\$ Download and execute the build script\\n"

bash <(curl -sSL 'https://imagick.optimizethis.net') --build
