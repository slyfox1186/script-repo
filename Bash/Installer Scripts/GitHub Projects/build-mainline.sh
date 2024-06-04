#!/usr/bin/env bash
# shellcheck disable=SC2162,SC2317

##  Install Mainline from source code
##  Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GitHub%20Projects/build-mainline.sh
##  Github Repo: https://github.com/bkw777/mainline/tree/master
##  Updated: 10.03.23
##  Script version: 1.0

clear

if [ "${EUID}" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set variables
script_ver=1.0
parent_dir="$PWD"
cwd="${parent_dir}"/mainline-build-script
web_repo=https://github.com/slyfox1186/script-repo

printf "%s\n%s\n\n" \
    "OpenSSL Build Script - v${script_ver}" \
    '==============================================='

# Create output directory
[[ ! -d "$cwd" ]] && mkdir -p "$cwd"

# Set the c+cpp compilers
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export CC CXX CFLAGS CXXFLAGS PATH PKG_CONFIG_PATH

# Create functions
exit_function() {
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n\n%s\n\n%s\n\n%s\n\n" \
        "$1" \
        'To report a bug please create an issue at:' \
        "$web_repo/issues"
    exit 1
}

cleanup_fn() {
    local choice

    printf "%s\n%s\n%s\n\n%s\n%s\n\n" \
        '============================================' \
        '  Do you want to clean up the build files?  ' \
        '============================================' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice

    case "${choice}" in
        1)
                sudo rm -fr "$cwd"
                cd "${parent_dir}" || exit 1
                if [ -f "$pem_file" ]; then
                    sudo rm "$pem_file"
                fi
                ;;
        2)      clear;;
        *)
                clear
                printf "%s\n\n" 'Bad user input. Reverting script...'
                sleep 3
                unset choice
                clear
                cleanup_fn
                ;;
    esac
}

# Install required apt packages

pkgs=(autoconf autoconf-archive autogen automake build-essential curl
      libtool libtool-bin git-all libgee-0.8-dev libvte-2.91-dev m4
      pkg-config valac)

for i in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "${i}")"

    if [ -z "${missing_pkg}" ]; then
        missing_pkgs+=" ${i}"
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
    clear
fi
unset i missing_pkgs

# Create archive output folder or clean existing
if [ ! -d mainline ]; then
    git clone https://github.com/bkw777/mainline.git
fi

clear
cd mainline || exit 1
ls -1A --color --group-directories-first
echo

# Install mainline
make distclean
if ! make "-j$(nproc --all)"; then
    fail_fn "The command \"make -j$(nproc --all)\" failed. Line: ${LINENO}"
fi

if sudo make "-j$(nproc --all)" install; then
    fail_fn "The command \"sudo make -j$(nproc --all) install\" failed. Line: ${LINENO}"
fi

# Prompt user to clean up files
cleanup_fn

# Show exit message
exit_function
