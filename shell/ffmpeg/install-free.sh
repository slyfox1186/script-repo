#!/bin/bash

# Helper script to download and run the build-ffmpeg script.

clear

# VERIFY THE SCRIPT DOES NOT HAVE ROOT ACCESS BEFORE CONTINUING
# THIS CAN CAUSE ISSUES USING THE 'IF WHICH' COMMANDS IF RUN AS ROOT
if [ "${EUID}" -lt '1' ]; then
    echo 'You must run this script as WITHOUT root/sudo'
    echo
    exit 1
fi

make_dir ()
{
    if [ ! -d "${1}" ]; then
        if ! mkdir "${1}"; then            
            printf '\n Failed to create dir %s' "${1}";
            exit 1
        fi
    fi    
}

command_exists()
{
    if ! [[ -x $(command -v "${1}") ]]; then
        return 1
    fi

    return 0
}

BUILD_DIR='ffmpeg-build'

if ! command_exists 'curl'; then
    echo 'curl command not installed.'
    echo
    exit 1
fi

echo 'ffmpeg-build-script-downloader v0.1'
echo '===================================='
echo

echo 'First we create the ffmpeg build directory' "${BUILD_DIR}"
echo '========================================================'
echo
make_dir "${BUILD_DIR}"
cd "${BUILD_DIR}" || exit 1

echo 'Now we download and execute the build script'
echo '============================================'
echo

bash <(curl -s 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/ffmpeg/build-ffmpeg') --build --latest
