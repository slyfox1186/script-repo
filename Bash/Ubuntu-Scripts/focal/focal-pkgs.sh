#!/usr/bin/env bash


clear

if [ "$EUID" -ne '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exec sudo bash "$0" "${@}"
fi


installed() { return $(dpkg-query -W -f '$Status\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

exit_fn() {
    printf "\\n%s\\n%s\\n\n%s\\n\n%s\\n\\n" \
    'Script complete!' \
    '====================' \
    'Make sure to star this repository to show your support!' \
    'https://github.com/slyfox1186/script-repo/'
    exit 0
}

pkgs_fn() {
    pkgs=(alien apt-file aptitude aria2 autoconf autogen automake bat binutils bison build-essential ccache ccdiff checkinstall clang \
          clang-tools cmake cmake-extras cmake-qt-gui colordiff cpu-checker curl cvs dbus dbus-x11 dconf-editor ddclient debhelper devscripts \
          dh-make disktype dos2unix dpkg-dev exfat-fuse f2fs-tools fakeroot flatpak flex g++ gawk gcc gcc-multilib gedit gedit-plugins \
          gir1.2-gtksource-3.0 git git-all git-buildpackage gnome-tweaks gnustep-gui-runtime golang gparted gperf grub-customizer gufw \
          hfsplus hfsprogs hfsutils htop idn2 iftop iw jfsutils jq libbz2-dev libdmalloc-dev libglib2.0-dev libgvc6 libheif-dev \
          libjemalloc-dev liblz-dev liblzma-dev liblzo2-dev libncurses5-dev libnet-nslookup-perl libnuma-dev libperl-dev libpstoedit-dev \
          libraqm-dev libraw-dev librsvg2-dev librust-jemalloc-sys-dev librust-malloc-buf-dev libsdl-pango-dev libsox-dev libsoxr-dev \
          libssl-dev libtalloc-dev libtool libtool-bin libvmmalloc-dev libvmmalloc1 libzstd-dev libzzip-dev lien linux-headers-generic \
          linux-source lm-sensors lsb-core lshw lvm2 lzma-dev make man-db mercurial meson nano net-tools netplan.io network-manager \
          nilfs-tools npm ntfs-3g nvme-cli openssh-client openssh-server openssl patchutils pbuilder pcregrep php-cli php-sqlite3 pipenv plank \
          ppa-purge pristine-tar psensor python3 python3-pip quilt reiser4progs reiserfsprogs rpm ruby-all-dev samba shellcheck smbclient sox \
          sqlite3 subversion synaptic texinfo tk-dev tofrodos trash-cli udftools unzip uuid-dev wget xclip xfsprogs xsel yasm)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        for i in "$missing_pkgs"
        do
            apt -y install $i
        done
        echo
        echo '$ Any missing apt packages were installed'
    else
        echo
        echo '$ The apt packages are already installed'
    fi
}

ppa_fn() {
    local i missing_pkgs pkg pkgs ppa_repo

    if [ ! -d '/etc/apt/sources.list.d' ]; then
        mkdir -p '/etc/apt/sources.list.d'
    fi

    ppa_repo='danielrichter2007/grub-customizer videolan/master-daily git-core/ppa'

    for pkg in ${ppa_repo[@]}
    do
        ppa_list="$(grep -Eo "^deb .*$pkg" /etc/apt/sources.list /etc/apt/sources.list.d/*)"
        if [ -z "$ppa_list" ]; then
            add-apt-repository -y ppa:$pkg
            for i in "$pkg"
            do
                case "$i" in
                    'danielrichter2007/grub-customizer')      apt_ppa+='grub-customizer';;
                    'videolan/master-daily')                  apt_ppa+=' vlc';;
                    'git')                                    apt_ppa+=' git';;
                 esac
            done
        fi
    done

    if [ -n "$apt_ppa" ]; then
        apt update
        apt -y install $apt_ppa
        echo
        echo '$ Any missing ppa repositories were installed'
        echo
    else
        echo
        echo '$ The ppa repositories are already installed'
        echo
    fi
}

ppa_fn
pkgs_fn
exit_fn
