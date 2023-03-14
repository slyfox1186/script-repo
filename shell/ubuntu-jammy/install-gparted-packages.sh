#!/bin/bash

clear

# VERIFY THE SCRIPT DOES HAVE ROOT ACCESS BEFORE CONTINUING
if [ "${EUID}" -gt '0' ]; then
    echo 'You must run this script as with root/sudo'
    echo
    exit 1
fi

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

pkgs=(exfat-fuse exfatprogs f2fs-tools hfsplus hfsprogs hfsutils jfsutils lvm2 nilfs-tools ntfs2btrfs ntfs-3g reiser4progs reiserfsprogs udftools xfsprogs)

for pkg in ${pkgs[@]}
do
    if ! installed "${pkg}"; then
        missing_pkgs+=" ${pkg}"
    fi
done

if [ -n "${missing_pkgs}" ]; then
    for i in "${missing_pkgs}"
    do
        apt install ${i}
    done
else
    echo 'The GParted packages are already installed.'
    echo
fi

# make the script delete itself
rm "${0}"
