#!/usr/bin/env bash

clear

# VERIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [ "${EUID}" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script WITH root/sudo'
    exit 1
fi

printf "%s\n%s\n\n"      \
    'Installing log2ram' \
    '==========================='
sleep 2

apt update
apt -y full-upgrade
echo

if ! sudo dpkg -l | grep -o 'mailutils' &>/dev/null; then
    apt -y install mailutils
    echo
fi

if ! sudo dpkg -l | grep -o 'rsync' &>/dev/null; then
    apt -y install rsync
    echo
fi

printf "%s\n%s\n\n"                                  \
    'Downloading log2ram from the GitHub Repository' \
    '=============================================='
sleep 2
echo

if [ ! -f 'log2ram.tar.gz' ]; then
    wget --show-progress -cqO 'log2ram.tar.gz' 'https://github.com/azlux/log2ram/archive/master.tar.gz'
fi

mkdir 'log2ram'
tar -zxf 'log2ram.tar.gz' -C 'log2ram' --strip-components 1
cd 'log2ram' || exit 1

./install.sh

if service log2ram status &>/dev/null; then
    service log2ram stop
fi


printf "\n%s\n%s\n\n"                               \
    'Use the sed command to edit /etc/log2ram.conf' \
    '============================================='

cfile='/etc/log2ram.conf'

if [ -f "${cfile}" ]; then
    sed -i 's/SIZE=40M/SIZE=512M/g' "${cfile}"
    sed -i 's/LOG_DISK_SIZE=256M/LOG_DISK_SIZE=1024M/g' "${cfile}"
fi

# FIND AN EDITOR TO OPEN THE CONF FILE
if which gedit &>/dev/null; then
    gedit "${cfile}"
elif which nano &>/dev/null; then
    nano "${cfile}"
elif which vim &>/dev/null; then
    vim "${cfile}"
elif which vi &>/dev/null; then
    vi "${cfile}"
fi

printf "\n%s\n%s\n\n%s\n\n%s\n%s\n\n"    \
    'You must reboot to enable log2ram'      \
    '======================================' \
    'Do you want to reboot now?'             \
    '[1] Yes'                                \
    '[2] No'
read -p 'Your choices are (1 or 2): ' choice
clear

case "${choice}" in
    1)      sudo reboot;;
    2)      exit 0;;
    *)
            clear
            printf "%s\n\n" 'Bad user input.'
            exit 1
            ;;
esac
