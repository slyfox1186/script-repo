#!/bin/bash

# Helper script to download and run the build-imagemagick.

clear

# verify the script does not have root access before continuing
if [ "${EUID}" -ne '0' ]; then
    exec sudo bash "${0}" "${@}"
fi

echo -e "\$ imagemagick-build-script downloader v1.0\\n"

echo -e "\$ creating the build directory\\n"

if ! mkdir "${PWD}/imagick-build"; then
    printf '\nfailed to create dir: %s' "${PWD}/imagick-build"
    echo
    exit 1
fi

cd "${PWD}/imagick-build" || exit 1

echo -e "\$ download and execute the build script\\n"

bash <(curl -sSL 'https://imagick.optimizethis.net') --build
