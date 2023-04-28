#!/bin/bash

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
## install required apt packages
##

pkgs=(make ninja-build wget)

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

if ! wget --show-progress -cq 'https://github.com/Kitware/CMake/releases/download/v3.26.3/cmake-3.26.3.tar.gz'; then
    echo
    echo 'The tar file failed to download.'
    echo
    exit 1
else
    if [ -d 'cmake-3.26.3' ]; then
        rm -r 'cmake-3.26.3'
    else
        mkdir 'cmake-3.26.3'
        tar -xf 'cmake-3.26.3.tar.gz' -C 'cmake-3.26.3' --strip-components 1
    fi
fi

##
## change into the source directory
##

cd 'cmake-3.26.3' || exit 1

##
## run the bootstrap file to generate any required install files
##

./bootstrap --parallel="$(nproc --all)" --generator='Ninja' --enable-ccache --prefix='/usr/local' @>/dev/null

##
## run the ninja commands to install cmake system-wide
##

if ninja @>/dev/null; then
    if sudo ninja install; then
        clear
        echo 'CMake v3.26.3 has successfully been installed.'
        echo
        cmake --version
    else
        echo
        echo 'Ninja failed to install CMake.'
        echo
        exit 1
    fi
else
    echo 'Ninja failed to generate the install files.'
    echo
    exit 1
fi
