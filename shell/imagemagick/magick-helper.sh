#!/bin/bash

# Helper script to download and run build-magick.sh

clear

# Verify the script has root access before continuing
if [ "${EUID}" -ne '0' ]; then
    exec sudo bash "$0" "$@"
fi

echo 'Imagemagick Build Script Downloader v1.0'
echo '=========================================='

echo -e "Now creating the temporary output build directory..."

if ! mkdir -p "$PWD/magick-build"; then
    printf '\n%s\n\n' "Failure to create the build directory: $PWD/magick-build"                   
    exit 1
fi

printf "%s\n\n" \
    'Executing the master build script'

# change into the temporary build directory, and run the master install script
cd "$PWD/magick-build" || exit 1

bash <(curl -sSL https://build-magick.optimizethis.net) --build
