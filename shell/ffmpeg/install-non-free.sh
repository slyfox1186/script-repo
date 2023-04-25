#!/bin/bash

# Helper script to download and run the build-ffmpeg script.

clear

# VERIFY THE SCRIPT DOES NOT HAVE ROOT ACCESS BEFORE CONTINUING
# THIS CAN CAUSE ISSUES USING THE 'IF WHICH' COMMANDS IF RUN AS ROOT
if [ "${EUID}" -eq '0' ]; then
    echo 'You must run this script WITHOUT root/sudo'
    echo
    exit 1
fi

make_dir()
{
    if [ ! -d "${1}" ]; then
        if ! mkdir "${1}"; then            
            printf '\nFailed to create directory: %s' "${1}";
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

build_dir="${PWD}/ffmpeg-build"

if ! command_exists 'curl'; then
    echo 'curl command not installed.'
    echo
    exit 1
fi

echo 'ffmpeg-build-script-downloader v0.1'
echo '============================================='
echo

echo 'First we create the ffmpeg build directory'
echo '=============================================='
echo

make_dir "${build_dir}"

cd "${build_dir}" || exit 1

echo 'Now we download and execute the build script'
echo '=============================================='
echo

wget -qO 'build-ffmpeg' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/ffmpeg/build-ffmpeg'

if [ -f build-ffmpeg ]; then
    bash build-ffmpeg -b --enable-gpl-and-non-free --latest
else
    echo 'file not found: build-ffmpeg'
fi
