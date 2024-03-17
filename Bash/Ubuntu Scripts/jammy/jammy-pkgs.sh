#!/usr/bin/env bash


clear

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    echo
    exit 1
fi


if which 'apt-fast' &>/dev/null; then
    exec_apt='apt-fast'
elif which 'aptitude' &>/dev/null; then
    exec_apt='aptitude'
else
    exec_apt='apt'
fi


installed() { return $(dpkg-query -W -f '$Status\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

exit_fn() {
    printf "\n%s\n\n%s\n\n" \
        '[i] Make sure to star this repository to show your support!' \
        '[i] https://github.com/slyfox1186/script-repo/'
    exit 0
}

install_other_fn() { curl -Ssf 'https://dlang.org/install.sh' | bash -s dmd; }

install_apt_fn() {
    pkgs=(alien apt-file aptitude aria2 autoconf autoconf-archive autogen automake bat binutils bison
          build-essential ccache ccdiff checkinstall clang cmake cmake-extras cmake-qt-gui colordiff cpu-checker
          curl cvs dbus-x11 dconf-editor ddclient debhelper devscripts dh-make disktype dos2unix dpkg-dev
          exfat-fuse exfatprogs f2fs-tools fakeroot flatpak flex gawk gcc g++ gcc-12 gedit gedit-plugins gh
          gir1.2-gtksource-3.0 git-all git-buildpackage gnome-shell-extension-manager gnome-tweaks gnustep-gui-runtime
          golang gparted gperf gufw hfsplus hfsprogs hfsutils htop idn2 iftop iw jfsutils jq libasan6-amd64-cross
          libboost-all-dev libbz2-dev libdmalloc-dev libglib2.0-dev libgvc6 libheif-dev libjemalloc-dev liblz-dev
          liblzma-dev liblzo2-dev libmimalloc-dev libncurses5-dev libnet-nslookup-perl libnuma-dev libperl-dev
          libpstoedit-dev libraqm-dev libraw-dev librsvg2-dev librust-jemalloc-sys-dev librust-malloc-buf-dev
          libsdl-pango-dev libsox-dev libssl-dev libtalloc-dev libtbbmalloc2 libtool libtool-bin libzstd-dev
          libzzip-dev linux-headers-generic linux-source lm-sensors lsb-core lshw lvm2 lzma-dev make man-db mercurial
          meson nano nasm neofetch netplan.io net-tools network-manager ninja-build ntfs2btrfs ntfs-3g nvme-cli
          openssh-client openssh-server openssl patchutils pbuilder pcregrep pipenv plank ppa-purge preload pristine-tar
          psensor python3-pip quilt reiser4progs reiserfsprogs rpm ruby-all-dev samba shellcheck smbclient sqlite3 subversion
          synaptic texinfo tofrodos trash-cli tty-share udftools unzip usb-creator-gtk uuid-dev wget xclip xsel yasm)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "$missing_pkgs-" ]; then
        for i in "$missing_pkgs"
        do
            $exec_apt -y install $i
        done
        printf "\n%s\n\n" \
            'The required packages were successfully installed.'
        exit 0
    else
        echo 'The required packages are already installed.'
    fi
}

install_ppa_fn() {
    local i missing_pkgs pkg pkgs ppa_repo

    if [ ! -d '/etc/apt/sources.list.d' ]; then
        sudo mkdir -p '/etc/apt/sources.list.d'
    fi

    ppa_repo='apt-fast/stable cappelikan/ppa danielrichter2007/grub-customizer git-core/ppa ubuntu-toolchain-r/ppa'

    for pkg in ${ppa_repo[@]}
    do
        ppa_list="$(grep -Eo "^deb .*$pkg" /etc/apt/sources.list /etc/apt/sources.list.d/*)"
        if [ -z "$ppa_list" ]; then
            sudo add-apt-repository -y ppa:$pkg
            for i in "$pkg"
            do
                case "$i" in
                        'apt-fast/stable')                         apt_pkg='apt-fast';;
                        'cappelikan/ppa')                          apt_pkg+=' mainline';;
                        'danielrichter2007/grub-customizer')       apt_pkg+=' grub-customizer';;
                        'git-core/ppa')                            apt_pkg+=' git';;
                 esac
            done
        fi
    done

    if [ -n "$apt_pkg" ]; then
        sudo $exec_apt update
        if sudo $exec_apt -y install $apt_pkg; then
            printf "%s\n\n" \
                '$ Any missing ppa repositories were installed'
                sleep 2
        else
            printf "%s\n\n" \
                '$ The ppa repositories are already installed'
                sleep 2
        fi
    fi
}

install_ppa_fn

install_apt_fn

install_other_fn

exit_fn
