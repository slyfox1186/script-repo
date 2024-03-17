#!/usr/bin/env bash

clear

pkgs=(alien aptitude aria2 autoconf autoconf-archive autogen automake bat binutils bison build-essential
      ccdiff clang clang-tools cmake cmake-extras colordiff curl dbus dbus-x11 dconf-cli dconf-editor ddclient
      desktopfolder disktype dos2unix exfat-fuse exfatprogs f2fs-tools flatpak flex g++-multilib gawk gcc-multilib
      gedit gedit-plugins git-all gnome-shell-extension-manager gnome-tweaks gnustep-gui-runtime golang gparted gperf
      grub-customizer gsettings-desktop-schemas gufw hfsplus hfsutils htop idn2 iftop iw jfsutils jq libbz2-dev libcurl4-openssl-dev
      libdmalloc-dev libglib2.0-dev libgvc6 libheif-dev libjemalloc-dev liblz-dev liblzma-dev liblzo2-dev libncurses5-dev
      libnet-nslookup-perl libnotify-bin libnuma-dev libperl-dev libpstoedit-dev libraqm-dev libraw-dev librsvg2-dev librust-malloc-buf-dev
      libsdl-pango-dev libsox-dev libssl-dev libtalloc-dev libtool libtool-bin libzstd-dev libzzip-dev linux-source lm-sensors
      lshw lvm2 lzma-dev m4 make man-db mono-devel nano net-tools netplan.io network-manager nilfs-tools npm ntfs-3g openssh-client
      openssh-server openssl pcregrep php-cli php-sqlite3 pipenv preload psensor python3 python3-pip reiser4progs reiserfsprogs
      rpm ruby-all-dev shellcheck slack snapd sqlite3 synaptic texinfo tk-dev trash-cli tty-share udftools unzip uuid-dev wget
      xclip xfsprogs xsel)

for pkg in ${pkgs[@]}
do
    if ! sudo dpkg | grep "$pkg" &>/dev/null; then
        missing_pkgs+=" $pkg"
    fi
done

if [ -n "$missing_pkgs" ]; then
    if sudo apt -y install $missing_pkgs; then
        sudo apt -y autoremove
        printf "\n%s\n\n" 'The APT packages were successfully installed.'
    else
        echo
        printf "%s\n\n" 'The missing APT packages failed to install.'
        exit 1
    fi
    printf "\n%s\n\n" 'The APT packages are already installed.'
fi
