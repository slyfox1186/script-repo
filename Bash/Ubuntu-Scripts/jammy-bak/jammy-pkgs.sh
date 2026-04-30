#!/usr/bin/env bash

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

# Source common utilities
source "$(dirname "$0")/common-utils.sh"

clear

# Verify the script is not running as root
check_root

# Set the apt command to use
exec_apt=$(get_apt_cmd)

######################
## FUNCTION SECTION ##
######################

# Install D language
install_other_fn() { 
    curl -Ssf 'https://dlang.org/install.sh' | bash -s dmd
}

install_apt_fn()
{
    local missing_pkgs=()
    
    # Define packages to install
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

    # Find missing packages and install them
    for pkg in "${pkgs[@]}"; do
        # Use install_pkg to check if it's installed and install if needed
        if ! installed "$pkg"; then
            echo "Installing package: $pkg"
            sudo $exec_apt -y install "$pkg"
            if [ $? -eq 0 ]; then
                echo "Successfully installed $pkg"
            else
                echo "Failed to install $pkg"
            fi
        fi
    done

    echo "All required packages have been checked and installed if needed."
}

install_ppa_fn()
{
    local apt_pkgs=()
    local ppa_added=false
    local ppa_repos=(
        'apt-fast/stable'
        'cappelikan/ppa'
        'danielrichter2007/grub-customizer'
        'git-core/ppa'
        'ubuntu-toolchain-r/ppa'
    )

    # Ensure sources.list.d directory exists
    if [ ! -d '/etc/apt/sources.list.d' ]; then
        sudo mkdir -p '/etc/apt/sources.list.d'
    fi

    # Check each PPA and add if missing
    for ppa in "${ppa_repos[@]}"; do
        ppa_list="$(grep -Eo "^deb .*$ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true)"
        if [ -z "$ppa_list" ]; then
            echo "Adding PPA: $ppa"
            sudo add-apt-repository -y "ppa:$ppa"
            ppa_added=true
            
            # Map PPA to package name
            case "$ppa" in
                'apt-fast/stable')                    apt_pkgs+=('apt-fast');;
                'cappelikan/ppa')                     apt_pkgs+=('mainline');;
                'danielrichter2007/grub-customizer')  apt_pkgs+=('grub-customizer');;
                'git-core/ppa')                       apt_pkgs+=('git');;
            esac
        fi
    done

    # Install packages from added PPAs
    if [ ${#apt_pkgs[@]} -gt 0 ]; then
        # Update package list if PPAs were added
        if [ "$ppa_added" = true ]; then
            echo "Updating package lists..."
            sudo $exec_apt update
        fi
        
        # Install each package using the common utility
        for pkg in "${apt_pkgs[@]}"; do
            echo "Installing package from PPA: $pkg"
            install_pkg "$pkg"
        done
        
        echo "PPA packages installed successfully"
    else
        echo "All required PPA repositories are already installed"
    fi
}

# install missing ppa repositories
install_ppa_fn

# install missing apt packages
install_apt_fn

# intall deb files
install_other_fn

# show exit message
exit_fn
