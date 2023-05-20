#!/bin/bash

# Helper script to download and run the build-curl script.

clear

# VERIFY THE SCRIPT DOES NOT HAVE ROOT ACCESS BEFORE CONTINUING
# THIS CAN CAUSE ISSUES USING THE 'IF WHICH' COMMANDS IF RUN AS ROOT
if [ "$EUID" -eq '0' ]; then
    echo 'You must run this script WITHOUT root/sudo'
    echo
    exit 1
fi

make_dir()
{
    if [ ! -d "$1" ]; then
        if ! mkdir "$1"; then            
            printf '\nFailed to create directory: %s' "$1";
            exit 1
        fi
    fi    
}

command_exists()
{
    if ! [[ -x $(command -v "$1") ]]; then
        return 1
    fi

    return 0
}

build_dir="$PWD/curl-build-script"

if ! command_exists 'curl'; then
    sudo apt-get -qq -y install curl
fi

echo 'This is the curl-build-script-helper v1.0'
echo '============================================='
echo

echo 'Creating the curl build directory'
echo '============================================='
echo

make_dir "$build_dir"

cd "$build_dir" || exit 1

echo 'Downloading and executing the build script'
echo '============================================='
echo

bash <(curl -sSL https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/installers/build-curl)
