#!/bin/bash
# shellcheck disable=SC2016,SC2034,SC2046,SC2066,SC2068,SC2086,SC2162,SC2317

#####################################
##
## Install CMake v3.26.3
##
## Supported OS: Linux Debian based
##
#####################################

clear

if [ "$EUID" -eq '0' ]; then
    echo 'You must run this script WITHOUT root/sudo'
    echo
    exit 1
fi

##
## define global variables
##

parent_dir="$PWD"/cmake-build
packages="$parent_dir"/packages
tar_url='https://github.com/Kitware/CMake/releases/download/v3.26.3/cmake-3.26.3.tar.gz'

##
## define functions
##

fail_fn()
{
    printf "\n%s\n\n%s\n\n" \
        "$1" \
        'Please submit a support ticket in GitHub.'
    exit 1
}

cleanup_fn()
{
    cd "$parent_dir" || exit 1
    cd ../ || exit 1
    sudo rm -r 'cmake-build'
}

success_fn()
{
    clear
    printf "\n%s\n\n" \
        "$1"
    cmake --version
    echo
    echo '$ Sleeping 5 seconds.'
    sleep 5
    cleanup_fn
}

##
## create build folders
##

execute mkdir -p "$parent_dir" "$packages"
cd "$parent_dir" || exit 1

##
## install required apt packages
##

pkgs=(make ninja-build)

for pkg in ${pkgs[@]}
do
    if ! installed "$pkg"; then
        missing_pkgs+=" $pkg"
    fi
done

if [ -n "${missing_pkgs-}" ]; then
    for i in "$missing_pkgs"
    do
        sudo apt -y install $i
    done
fi

##
## download the cmake tar file and extract the files into the src directory
##

if ! curl -Lso "$packages"/cmake-3.26.3.tar.gz "$tar_url"; then
    fail_fn 'The tar file failed to download.'
else
    if [ ! -d "$packages"/cmake-3.26.3 ]; then
        mkdir -p "$packages"/cmake-3.26.3
        if ! tar -zxf "$packages"/cmake-3.26.3.tar.gz -C "$packages"/cmake-3.26.3 --strip-components 1; then
            fail_fn 'The tar command failed to extract any files.'
        fi
        cd "$packages"/cmake-3.26.3 || exit 1
    fi
fi

##
## run the bootstrap file to generate any required install files
##

printf "\n%s\n" \
    '$ This might take a minute... please be patient'
execute ./bootstrap --prefix=/usr/local --parallel="$(nproc --all)" --enable-ccache --generator=Ninjal

##
## run the ninja commands to install cmake system-wide
##

execute ninja
execute sudo ninja install

success_fn
