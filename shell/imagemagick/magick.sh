#!/bin/bash

# Helper script to download and run build-magick.sh

clear

# Verify the script has root access before continuing
if [ "${EUID}" -ne '0' ]; then
    exec sudo bash "${0}" "${@}"
fi

echo -e "Imagemagick Build Script Downloader v1.0\\n"

echo -e "Creating the build directory\\n"

if ! mkdir "${PWD}/build-magick"; then
    printf '\nFailure to create the build directory: %s' "${PWD}/build-magick"
    echo
    exit 1
fi

# cd into the build directory
cd "${PWD}/build-magick" || exit 1

echo -e "Downloading and executing the build script\\n"

sudo bash <(curl -sSL https://build-magick.optimizethis.net) --build
