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

exit_fn()
{
    clear
    printf "%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        'https://github.com/slyfox1186/script-repo/'
    exit 0
}

cleanup_fn()
{
    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to cleanup the build files?' \
        '[1] Yes' \
        '[2] No'
        read -p 'Your choices are (1 or 2): ' cchoice
        case "$cchoice" in
            1)
                    cd "$parent_dir" || exit 1
                    cd ../ || exit 1
                    sudo rm -r 'cmake-build'
                    exit_fn
                    ;;
            2)
                    exit_fn
                    ;;
            *)
                    read -p 'Bad user input. Press enter to try again'
                    clear
                    cleanup_fn
                    ;;
        esac         
}

success_fn()
{
    clear
    printf "\n%s\n\n" \
        "$1"
    cmake --version
    cleanup_fn
}

##
## create build folders
##

mkdir -p "$parent_dir" "$packages"
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

if ! curl -LSso "$packages"/cmake-3.26.3.tar.gz "$tar_url"; then
    fail_fn 'The tar file failed to download.'
else
    if [ -d "$packages"/cmake-3.26.3 ]; then
        rm -r "$packages"/cmake-3.26.3
    else
        mkdir -p "$packages"/cmake-3.26.3
        if ! tar -zxf "$packages"/cmake-3.26.3.tar.gz -C "$packages"/cmake-3.26.3 --strip-components 1; then
            fail_fn 'The tar command failed to extract any files.'
        fi
    fi
fi

##
## change into the source directory
##

cd "$packages"/cmake-3.26.3 || exit 1

##
## run the bootstrap file to generate any required install files
##

echo
echo 'This might take a minute... please be patient'
./bootstrap --prefix='/usr/local' --parallel="$(nproc --all)" --enable-ccache --generator='Ninja' &>/dev/null

##
## run the ninja commands to install cmake system-wide
##

if ninja &>/dev/null; then
    if ! sudo ninja install &>/dev/null; then
        fail_fn 'Ninja failed to install CMake.'
    else
        success_fn 'CMake has successfully been installed.'
    fi
else
    echo 'Ninja failed to generate the install files.'
    echo
    exit 1
fi
