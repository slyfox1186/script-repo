#!/bin/bash

clear

# VERIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [[ "${EUID}" -gt '0' ]]; then
    echo 'You must run this script as root/sudo'
    exit 1
fi

# CREATE FUNCTIONS
installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }


##############################
## INSTALL PPA REPOSITORIES ##
##############################

PPA_REPO='danielrichter2007/grub-customizer'

if ! grep -q "^deb .*${PPA_REPO}" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    echo "Now installing ppa:${PPA_REPO}"
    echo
    sudo add-apt-repository ppa:"${PPA_REPO}"
    echo
    echo 'Updating APT packages.'
    sudo apt-get update
    echo
    echo "The PPA: ${PPA_REPO} has been installed."
else
    echo 'All PPA Repositories have been installed.'
    echo
    sleep 2
    clear
fi

# DOWNLOAD ALL REDUCED PACKAGE REPOS IF NOT INSTALLED
echo
echo 'Installing: Development Packages'
echo '=========================================='
PKGS=(alien aptitude aria2 bat build-essential colordiff curl dbus-x11 dos2unix gedit-plugins gir1.2-gtksource-3.0 git git-all gnome-tweaks gparted grub-customizer htop iftop man-db net-tools network-manager openssh-client openssh-server p7zip-rar php-sqlite3 pipenv python3-idna python3-pip sqlite3 synaptic unzip xournalpp wget)

for PKG in ${PKGS[@]}
do
    if ! $(installed ${PKG}); then
        MISSING_PKGS+=" ${PKG}"
    fi
done

if [ -n "${MISSING_PKGS}" ]; then
    CMD="sudo apt install -y ${MISSING_PKGS}"
    ${CMD}
    if ! ${CMD}; then
        echo 'Failed to install the required development packages. check the script for errors in spelling.'
        echo
        exit 1
    fi
else
    echo 'The Development Packages are already installed.'
    echo
fi
