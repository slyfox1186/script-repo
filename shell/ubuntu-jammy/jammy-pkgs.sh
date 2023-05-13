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
if [ $EUID -ne 0 ]; then
    echo 'You must run this script as root/sudo.'
    echo
    exit 1
fi

######################
## FUNCTION SECTION ##
######################

installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

exit_fn()
{
    printf "\n%s\n%s\n%s\n%s\n\n" \
    "$1" \
    "$2" \
    '[i] Make sure to star this repository to show your support!' \
    '[i] https://github.com/slyfox1186/script-repo/'
    # rm "${0}"
    exit 0
}

deb_fn()
{
    curl -fsS 'https://dlang.org/install.sh' | bash -s dmd
}

pkgs_fn()
{
    pkgs=(alien apt-file aptitude aria2 autoconf autogen automake bat binutils \
          bison build-essential ccache ccdiff checkinstall clang clang-tools cmake \
          cmake-extras cmake-qt-gui colordiff cpu-checker curl cvs dbus dbus-x11 \
          dconf-editor ddclient debhelper devscripts dh-make disktype dos2unix dpkg-dev \
          exfat-fuse exfatprogs f2fs-tools fakeroot flatpak flex gcc gcc-12 g++ g++-12 \
          gawk gcc gedit gedit-plugins gh gir1.2-gtksource-3.0 git git-all git-buildpackage \
          git-hub gnome-shell-extension-manager gnome-tweaks gnustep-gui-runtime golang gparted \
          gperf grub-customizer gufw hfsplus hfsprogs hfsutils htop idn2 iftop iw jfsutils \
          jq libbz2-dev libdmalloc-dev libglib2.0-dev libgvc6 libheif-dev libjemalloc-dev liblz-dev \
          libasan6-amd64-cross liblzma-dev liblzo2-dev libboost-all-dev libmimalloc-dev libncurses5-dev \
          libnet-nslookup-perl libnuma-dev libperl-dev libpstoedit-dev libraqm-dev libraw-dev \
          librsvg2-dev librust-jemalloc-sys-dev librust-malloc-buf-dev libsdl-pango-dev libsox-dev \
          libsoxr-dev libssl-dev libtalloc-dev libtbbmalloc2 libtool libtool-bin libzstd-dev \
          libzzip-dev linux-headers-generic linux-source lm-sensors lsb-core lshw lvm2 lzma-dev \
          mainline make man-db mercurial meson mono-devel nano netplan.io net-tools network-manager \
          nilfs-tools npm ntfs2btrfs ntfs-3g nvme-cli openssh-client openssh-server openssl patchutils \
          pbuilder pcregrep php-cli php-sqlite3 pipenv plank ppa-purge pristine-tar psensor python3 \
          python3-pip quilt reiser4progs reiserfsprogs rpm ruby-all-dev samba shellcheck smbclient \
          sox sqlite3 subversion synaptic texinfo tilix tofrodos trash-cli tty-share udftools unzip \
          uuid-dev wget xclip xfsprogs xsel yasm)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "$missing_pkgs-" ]; then
        for i in "$missing_pkgs"
        do
            apt -y install $i
        done
        printf "\n%s\n\n%s\n\n" \
            'The required packages were successfully installed.' \
            'Please execute the script again to finish installing ImageMagick.'
        exit 0
    else
        echo 'The required packages are already installed.'
    fi
}

ppa_fn()
{
    local i missing_pkgs pkg pkgs ppa_repo

    if [ ! -d '/etc/apt/sources.list.d' ]; then
        mkdir -p '/etc/apt/sources.list.d'
    fi

    ppa_repo='cappelikan/ppa danielrichter2007/grub-customizer git-core/ppa'

    for pkg in ${ppa_repo[@]}
    do
        ppa_list="$(grep -Eo "^deb .*$pkg" /etc/apt/sources.list /etc/apt/sources.list.d/*)"
        if [ -z "$ppa_list" ]; then
            add-apt-repository -y ppa:$pkg
            for i in "$pkg"
            do
                case "$i" in
                        'danielrichter2007/grub-customizer')        apt_ppa+='grub-customizer';;
                        'git')                                      apt_ppa+=' git';;
                 esac
            done
        fi
    done

    if [ -n "$apt_ppa" ]; then
        apt update
        apt -y install $apt_ppa
        exit_msg1='[i] Any missing ppa repositories were installed'
    else
        exit_msg1='[i] The ppa repositories are already installed'
    fi
}

# install missing ppa repositories
ppa_fn

# install missing apt packages
pkgs_fn

# intall deb files
deb_fn

# show exit message
exit_fn
