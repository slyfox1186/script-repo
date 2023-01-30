#!/bin/bash

clear

##
## Functions
##

installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

##
## Install Missing Gparted Packages
##

echo 'Installing: Missing GParted Packages'
echo '===================================='
echo

PKGS=(exfat-fuse exfatprogs f2fs-tools hfsplus hfsprogs hfsutils jfsutils lvm2 nilfs-tools ntfs2btrfs ntfs-3g reiser4progs reiserfsprogs udftools xfsprogs)

for PKG in ${PKGS[@]}
do
    if ! installed "${PKG}"; then
        MISSING_PKGS+=" ${PKG}"
    fi
done

if [ -n "${MISSING_PKGS}" ]; then
    for i in "${MISSING_PKGS}"
    do
        apt install ${i}
    done
else
    echo 'The missing GParted packages are already installed.'
    echo
fi
