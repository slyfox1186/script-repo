#!/bin/bash

##########################################################
##
## GitHub: https://github.com/slyfox1186/script-repo
##
## Install Packages Lite Version
##
## A list of packages which I consider to be some of
## the most useful when running Ubuntu. Aimed at
## developers but useful for the casual user as well.
##
## If you think there should be modification of the list
## Please create a support ticket under the Issues tab.
##   
##########################################################

clear

# Verify the script has root access before continuing
if [ "${EUID}" -ne '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exec sudo bash "${0}" "${@}"
fi

######################
## FUNCTION SECTION ##
######################

installed()
{
    return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 |
    awk '/ok installed/{print 0;exit}{print 1}')
}

exit_fn()
{
    printf "\\n %s\\n\\n %s\\n\n %s\\n\\n" \
    'The script has finished!' \
    'Make sure to star this repository to show your support!' \
    'https://github.com/slyfox1186/script-repo/'
    rm -f "${0}"
    exit 0
}

apt_pkgs_fn()
{
    pkgs='alien aptitude aria2 autoconf autogen automake bat binutils bison build-essential ccdiff clang clang-tools cmake cmake-extras colordiff curl dbus-x11 ddclient dconf-editor disktype dos2unix flex g++ gawk gcc-multilib gedit gedit-plugins gir1.2-gtksource-3.0 git git-all gnome-tweaks gnustep-gui-runtime golang gparted gperf grub-customizer gufw htop idn2 iftop libbz2-dev libdmalloc-dev libglib2.0-dev libgvc6 libheif-dev libjemalloc-dev liblz-dev liblzma-dev liblzo2-dev libmimalloc2.0 libmimalloc-dev libncurses5 libncurses5-dev libnet-nslookup-perl libnuma-dev libperl-dev libpstoedit-dev libraqm-dev libraw-dev librsvg2-dev librust-jemalloc-sys-dev librust-malloc-buf-dev libsdl-pango-dev libsox-dev libsox-fmt-all libsox-fmt-mp3 libsoxr-dev libssl-dev libtalloc-dev libtbbmalloc2 libtool libtool-bin libzstd-dev libzzip-dev linux-source lm-sensors lshw lzma-dev make man-db mono-devel nano net-tools network-manager npm openssh-client openssh-server openssl pcregrep php-cli php-sqlite3 pipenv psensor python3 python3-idna python3-pip python3-talloc-dev rpm ruby-all-dev shellcheck sox sqlite3 synaptic texinfo tk-dev trash-cli tty-share unzip uuid-dev wget xclip xsel'

    for pkg in ${pkgs[@]}
    do
        if ! installed "${pkg}"; then
            missing_pkgs+=" ${pkg}"
        fi
    done

    if [ -n "${missing_pkgs}" ]; then
        for i in "${missing_pkgs}"
        do
            apt -y install ${i}
        done
        echo
        echo '$ Any missing apt packages were installed'
    else
        echo
        echo '$ The apt packages are already installed'
    fi
}

ppa_repo='danielrichter2007/grub-customizer'
if ! grep -q "^deb .*${ppa_repo}" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    echo "\$ Executing ppa:${ppa_repo}"
    echo
    add-apt-repository ppa:"${ppa_repo}"
    echo
    apt-get update
    echo
fi

echo '$ Executing apt'
apt_pkgs_fn
exit_fn
