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
    echo 'Make sure to star this repository to show your support!'
    echo 'https://github.com/slyfox1186/script-repo/'
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

ppa_repo='danielrichter2007/grub-customizer'

if ! grep -q "^deb .*${ppa_repo}" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    echo "Now installing ppa:${ppa_repo}"
    echo '==================================='
    echo
    add-apt-repository ppa:"${ppa_repo}"
    echo
    sudo apt-get update
    sleep 2
fi

##########################
## INSTALL APT PACKAGES ##
##########################

echo
echo 'Installing: APT Packages'
echo '============================'
echo
sleep 2

pkgs=(alien aptitude aria2 autoconf autogen automake bat binutils bison build-essential ccdiff clang clang-tools cmake cmake-extras colordiff crossbuild-essential-amd64 curl dbus-x11 ddclient dconf-editor disktype dos2unix flex g++ gawk gcc-multilib gedit gedit-plugins gir1.2-gtksource-3.0 git git-all gnome-tweaks gnustep-gui-runtime golang gparted gperf grub-customizer gufw htop idn2 iftop libbz2-dev libdmalloc-dev libglib2.0-dev libgvc6 libheif-dev libjemalloc-dev liblz-dev liblzma-dev liblzo2-dev libmimalloc2.0 libmimalloc-dev libncurses5 libncurses5-dev libnet-nslookup-perl libperl-dev libpstoedit-dev libraqm-dev libraw-dev librsvg2-dev librust-jemalloc-sys-dev librust-malloc-buf-dev libsdl-pango-dev libsox-dev libsox-fmt-all libsox-fmt-mp3 libsoxr-dev libssl-dev libtalloc-dev libtbbmalloc2 libtool libtool-bin libzstd-dev libzzip-dev linux-source lshw lzma-dev make man-db mono-devel nano net-tools network-manager npm openssh-client openssh-server openssl pcregrep php-cli php-curl php-intl php-sqlite3 pipenv python3 python3-idna python3-pip python3-talloc-dev rpm ruby-all-dev shellcheck sqlite3 synaptic texinfo tk-dev trash-cli tty-share unzip uuid-dev wget wget2-dev)

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
    echo 'Any missing APT packages were installed'
    echo '========================================'
else
    echo
    echo 'The APT packages are already installed'
    echo '======================================='
fi
sleep 3

exit_fn
