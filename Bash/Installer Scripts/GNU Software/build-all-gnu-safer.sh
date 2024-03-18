#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-all-gnu-safer
##  Purpose: Loops multiple build scripts to optimize efficiency. This is the safer of the two scripts.
##  Updated: 03.17.24
##  Script version: 1.3

if [ "$EUID" -eq 0 ]; then
    printf "%s\n\n" "You must run this script without root/sudo."
    exit 1
fi

#
# PRINT THE SCRIPT BANNER
#

script_ver=1.2
cwd="$PWD/build-all-gnu-safer-script"
web_repo="https://github.com/slyfox1186/script-repo"

if [ -d "$cwd" ]; then
    sudo rm -fr "$cwd"
fi
mkdir -p "$cwd/completed"

exit_fn() {
    printf "\n%s\n\n%s\n\n" \
        "Make sure to star this repository to show your support!" \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug create an issue at: $web_repo/issues"
    exit 1
}

pkgs=(
    asciidoc autogen autoconf autoconf-archive automake binutils bison
    build-essential bzip2 ccache cmake curl libc6-dev libintl-perl
    libpth-dev libtool libtool-bin lzip lzma-dev m4 meson nasm ninja-build
    texinfo xmlto yasm wget zlib1g-dev
)

for pkg in "${pkgs[@]}"
do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+="$pkg "
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
    sudo apt -y autoremove
    clear
fi

#
# ADD ADDITIONAL SEARCH PATHS TO THE LD LIBRARY LINKER
#

sudo bash -c "bash <(curl -sSL https://ld-linker.optimizethis.net)"

#
# DETECT THE PC ARCHITECTURE
#

case "$(uname -m)" in
    x86_64)                        arch_ver="pkg-config" ;;
    aarch64*|armv8*|arm|armv7*)    arch_ver="pkg-config-arm" ;;
    *)                             fail_fn "Unrecognized architecture: $(uname -m)" ;;
esac

cd "$cwd" || exit 1

scripts=(
    "$arch_ver" "coreutils.sh" "m4" "autoconf-2.71" "autoconf-archive" "libtool" "bash"
    "make" "sed" "tar" "gawk" "grep" "nano" "parallel" "get"
)

count=0

for script in "${scripts[@]}"
do
    let count=count+1
    wget --show-progress -t 2 -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-$script"
    mv "build-$script" "$count-build-$script.sh" 2>/dev/null
done

for f in $(find ./ -maxdepth 1 -type f | sort -V | sed 's/\.\///g')
do
    if echo "1" | sudo bash "$f"; then
        sudo mv "$f" "$cwd/completed"
    else
        if [ ! -d "$cwd/failed" ]; then
            mkdir -p "$cwd/failed"
        fi
        sudo mv "${f}" "$cwd/failed"
    fi
done

if [ -d "$cwd/failed" ]; then
    printf "%s\n\n%s\n\n" \
        "One of the scripts failed to build successfully." \
        "You can find the failed script at: $cwd/failed"
    exit_fn
fi

# CLEANUP LEFTOVER FILES
sudo rm -fr "$cwd"

# DISPLAY EXIT MESSAGE
exit_fn
