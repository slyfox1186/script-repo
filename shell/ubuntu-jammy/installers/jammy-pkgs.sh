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

installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

exit_fn()
{
    printf "\\n%s\\n%s\\n\n%s\\n\n%s\\n\\n" \
    'Script complete!' \
    '====================' \
    'Make sure to star this repository to show your support!' \
    'https://github.com/slyfox1186/script-repo/'
    # rm "${0}"
    exit 0
}

pkgs_fn()
{
    pkgs=(alien aptitude aria2 autoconf autogen automake bat binutils bison build-essential ccdiff clang clang-tools cmake cmake-extras colordiff \
    curl dbus-x11 ddclient dconf-editor disktype dos2unix flex g++ gawk gcc-multilib gedit gedit-plugins gir1.2-gtksource-3.0 git git-all \
    gnome-tweaks gnustep-gui-runtime golang gparted gperf grub-customizer gufw htop idn2 iftop iw libbz2-dev libdmalloc-dev libglib2.0-dev \
    libgvc6 libheif-dev libjemalloc-dev liblz-dev liblzma-dev liblzo2-dev libmimalloc2.0 libmimalloc-dev libncurses5 libncurses5-dev \
    libnet-nslookup-perl libnuma-dev libperl-dev libpstoedit-dev libraqm-dev libraw-dev librsvg2-dev librust-jemalloc-sys-dev \
    librust-malloc-buf-dev libsdl-pango-dev libsox-dev libsox-fmt-all libsox-fmt-mp3 libsoxr-dev libssl-dev libtalloc-dev libtbbmalloc2 \
    libtool libtool-bin libzstd-dev libzzip-dev linux-source lm-sensors lshw lzma-dev make man-db mono-devel nano netplan.io net-tools \
    network-manager npm openssh-client openssh-server openssl pcregrep php-cli php-sqlite3 pipenv psensor python3 python3-idna python3-pip \
    python3-talloc-dev rpm ruby-all-dev shellcheck sox sqlite3 synaptic texinfo tk-dev trash-cli tty-share unzip uuid-dev wget xclip xsel)

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

ppa_fn()
{
    local i missing_pkgs pkg pkgs ppa_repo

    ppa_repo='danielrichter2007/grub-customizer videolan/master-daily'

    for pkg in ${ppa_repo[@]}
    do
        ppa_list="$(grep -Eo "^deb .*$pkg" /etc/apt/sources.list /etc/apt/sources.list.d/*)"
        if [ -z "$ppa_list" ]; then
            add-apt-repository -y ppa:$pkg
            for i in "$pkg"
            do
                case "$i" in
                    'danielrichter2007/grub-customizer') apt_ppa+='grub-customizer';;
                    'videolan/master-daily') apt_ppa+=' vlc';;
                 esac
            done
        fi
    done

    apt update

    if [ -n "$apt_ppa" ]; then
        sudo apt -y install $apt_ppa
        echo
        echo '$ Any missing ppa repositories were installed'
        echo
    else
        echo
        echo '$ The ppa repositories are already installed'
        echo
    fi
}

# install missing ppa repositories
ppa_fn

# install missing apt packages
pkgs_fn

# show exit message
exit_fn
