#!/bin/bash

clear

# Verify the script has root access before continuing
if [ "${EUID}" -ne '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exec sudo bash "${0}" "${@}"
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
        apt -y install ${i}
    done
else
    echo 'The GParted packages are already installed.'
    echo
fi

# make the script delete itself
rm "${0}"
