#!/bin/bash

##########################################################
##
## GitHub: https://github.com/slyfox1186
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

# VERIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [[ "${EUID}" -gt '0' ]]; then
    echo 'You must run this script as root/sudo'
    echo
    exit 1
fi

######################
## FUNCTION SECTION ##
######################

##
## EXIT FUNCTION
##

exit_fn()
{
    echo
    echo 'The script has finished!'
    echo '============================'
    echo
    echo 'Make sure to star this repository to show your suppport!'
    echo 'https://github.com/slyfox1186/'
    echo
    # REMOVE THE INSTALLER SCRIPT ITSELF
    rm -f "${0}"
    exit 0
}

##
## FUNCTION TO CHECK INSTALLED PACKAGES AGAINST
##

installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

##############################
## INSTALL PPA REPOSITORIES ##
##############################

PPA_REPO='danielrichter2007/grub-customizer'

if ! grep -q "^deb .*${PPA_REPO}" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    echo "Now installing ppa:${PPA_REPO}"
    echo
    add-apt-repository ppa:"${PPA_REPO}"
    echo
    echo 'Updating APT packages.'
    sudo apt-get update
    echo
    echo "The PPA: ${PPA_REPO} has been installed."
    echo
else
    echo
    echo 'All PPA Repositories have been installed.'
    echo
fi
sleep 3
clear

##########################
## INSTALL APT PACKAGES ##
##########################

echo
echo 'Installing: APT Packages'
echo '=============================='
echo
sleep 3

PKGS=(alien aptitude aria2 autoconf autogen automake bat binutils bison build-essential ccdiff clang clang-tools cmake cmake-extras colordiff crossbuild-essential-amd64 curl dbus-x11 ddclient disktype dos2unix flex g++ gawk gcc-multilib gedit gedit-plugins gir1.2-gtksource-3.0 git git-all gnome-tweaks gnustep-gui-runtime golang gparted gperf grub-customizer gufw htop idn2 iftop libbz2-dev libdmalloc-dev libglib2.0-dev libgvc6 libheif-dev libjemalloc-dev liblilv-dev liblvm2-dev liblz-dev liblzma-dev liblzo2-dev libmimalloc2.0 libmimalloc-dev libncurses5 libncurses5-dev libnet-nslookup-perl libperl-dev libpstoedit-dev libraqm-dev libraw-dev librsvg2-dev librust-jemalloc-sys-dev librust-malloc-buf-dev libsdl-pango-dev libsox-dev libsox-fmt-all libsoxr-dev libsratom-dev libssl-dev libtalloc-dev libtbbmalloc2 libtool libtool-bin libzstd-dev libzzip-dev linux-source llvm llvm-dev lshw lv2-dev lzma-dev make man-db mono-devel nano net-tools network-manager npm openssh-client openssh-server openssl pcregrep php-cli php-curl php-intl php-sqlite3 pipenv python3 python3-idna python3-pip python3-talloc-dev rpm ruby-all-dev sqlite3 synaptic texinfo tk-dev tty-share unzip uuid-dev wget wget2-dev)

for PKG in ${PKGS[@]}
do
    if ! installed "${PKG}"; then
        MISSING_PKGS+=" ${PKG}"
    fi
done

if [ -n "${MISSING_PKGS}" ]; then
    for i in "${MISSING_PKGS}"
    do
        apt -y install ${i}
    done
    echo
    echo 'Any missing packages have been installed.'
else
    echo
    echo 'All of the packages were already installed.'
fi

sleep 3
exit_fn
