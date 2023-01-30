#!/bin/bash

clear

############################################################################
##
## GitHub: https://github.com/slyfox1186
##
## Targeted OS: Ubuntu Jammy 22.04.1
##
## Purpose: Install packages that unlock extra functionality within GParted.
##          These options will no longer be "Greyed out".
##
############################################################################

##
## Define Functions
##

installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

##
## Install Missing Gparted Packages
##

echo 'Installing: Missing GParted Packages'
echo '===================================='
echo

PKGS=(exfat-fuse exfatprogs f2fs-tools hfsplus hfsprogs hfsutils ntfs2btrfs ntfs-3g)

for PKG in ${PKGS[@]}
do
    if ! installed "${PKG}"; then
        MISSING_PKGS+=" ${PKG}"
    fi
done

if [ -n "${MISSING_PKGS}" ]; then
    for i in "${MISSING_PKGS}"
    do
        sudo apt install "${i}"
    done
else
    echo 'The missing GParted packages are already installed.'
    echo
fi
