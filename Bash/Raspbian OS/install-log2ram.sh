#!/usr/bin/env bash

clear

# VERIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [ "${EUID}" -gt '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exit 1
fi

echo 'Installing log2ram'
echo '=================='
echo
sleep 3
clear

echo 'Updating APT Packages'
echo '====================='
echo

apt update
apt -y full-upgrade
echo

if ! which mail &> /dev/null; then
    echo 'Install mailutils'
    echo '================='
    echo
    echo 'The required mailutils package is missing and must be installed for log2ram to function'
    echo
    read -p 'Press enter to install mailutils or press Ctr+Z to exit the script.'
    echo
    apt -y install mailutils
    echo
fi

if ! which rsync &> /dev/null; then
    echo 'Install RSync'
    echo '============='
    echo
    echo 'The required rsync package is missing and must be installed for log2ram to function'
    echo
    read -p 'Press enter to install rsync or press Ctr+Z to exit the script.'
    echo
    apt -y install rsync
    echo
fi

echo 'Downloading log2ram from the GitHub Repository'
echo '=============================================='
echo
sleep 3
echo

if [ ! -f 'log2ram.tar.gz' ]; then
    wget --show-progress -cqO 'log2ram.tar.gz' 'https://github.com/azlux/log2ram/archive/master.tar.gz'
fi

if [ ! -f 'log2ram.tar.gz' ]; then
    echo 'wget failed to download log2ram.tar.gz'
    echo
    exit 1
else
    echo 'Extracting log2ram tar.gz file'
    echo '=============================='
    echo
    tar -xf 'log2ram.tar.gz'
fi

if [ ! -d 'log2ram-master' ]; then
    clear
    echo 'The script failed to find the directory: log2ram-master'
    echo
    exit 1
else
    cd 'log2ram-master' || exit 1
    echo
fi

echo 'Executing install.sh'
echo '===================='
echo

if [ -f 'install.sh' ]; then
    ./install.sh
    echo
else
    echo 'Failed to cd into the log2ram-master directory'
    echo
    exit 1
echo

if service log2ram status &> /dev/null; then
    echo 'Stopping log2ram service before editing the conf file with sed'
    echo '=============================================================='
    echo
    service log2ram stop
fi

echo
echo 'Use the sed command to edit /etc/log2ram.conf'
echo '============================================='
echo

FILE='/etc/log2ram.conf'

if [ -f "${FILE}" ]; then
    sed -i 's/SIZE=40M/SIZE=512M/g' "${FILE}"
    sed -i 's/LOG_DISK_SIZE=256M/LOG_DISK_SIZE=1024M/g' "${FILE}"
fi

# FIND AN EDITOR TO OPEN THE CONF FILE
if which nano &>/dev/null; then
    nano "${FILE}"
elif which vim &>/dev/null; then
    vim "${FILE}"
elif which vi &>/dev/null; then
    vi "${FILE}"
else
    echo
    echo 'No editors were found to open the /etc/log2ram.conf file!'
    echo
    read -p 'Press enter to continue.'
    clear
fi

echo
echo 'You must reboot to enable log2ram'
echo '================================='
echo
echo 'Do you want to reboot now?'
echo
echo '[1] Yes'
echo '[2] No'
echo '[3] Exit'
echo
read -p 'Your choices are (1 to 3): ' ANSWER
clear

if [[ "${ANSWER}" -eq '1' ]]; then
    sudo reboot
elif [[ "${ANSWER}" -eq '2' ]]; then
    echo
elif [[ "${ANSWER}" -eq '3' ]]; then
    exit 0
fi
