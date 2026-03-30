#!/usr/bin/env bash

set -euo pipefail

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

missing_pkgs=()
for pkg in "${pkgs[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
        missing_pkgs+=("$pkg")
    fi
done

if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
    echo "All APT packages are already installed."
    exit 0
fi

echo "Installing ${#missing_pkgs[@]} missing package(s)..."

if sudo apt install -y "${missing_pkgs[@]}"; then
    echo "The APT packages were successfully installed."
else
    echo "Failed to install some APT packages." >&2
    exit 1
fi
