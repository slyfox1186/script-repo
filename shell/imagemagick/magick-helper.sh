#!/bin/bash

# Helper script to download and run build-magick.sh

clear

# Verify the script has root access before continuing
if [ "$EUID" -eq '0' ]; then
    echo 'This script must be run WITHOUT root/sudo.'
    echo
    exit 1
fi

echo 'Imagemagick Build Script Downloader v1.0'
echo '=========================================='

echo -e "\\nNow creating the temporary output build directory..."

if ! mkdir -p "$PWD"/magick-build; then
    echo
    echo "Failed to create the build directory: $PWD/magick-build"
    echo
    exit 1
fi

printf "\n%s\n\n" \
    'Executing the build script'

# change into the temporary build directory, and run the master install script
cd "$PWD"/magick-build || exit 1

bash <(curl -sSL https://build-magick.optimizethis.net) -b
