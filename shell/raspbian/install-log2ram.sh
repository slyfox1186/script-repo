#!/bin/bash

clear

# VERIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [ "$EUID" -ne '0' ]; then
    printf "%s\n%s\n\n" 'You must run this script as root/sudo'
    exit 1
fi

printf "%s\n%s\n\n" \
    'Installing log2ram' \
    '===================================='

pkgs=(git mailutils rsync)

for i in ${pkgs[@]}
do
    missing_pkg="$(dpkg -l | grep $i)"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+=" $i"
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt -y install $missing_pkgs
    clear
fi

if [ -d zram-swap-config ]; then
    sudo rm -fr zram-swap-config
fi

printf "\n%s\n%s\n\n" \
    'Installing: zram-swap-config' \
    '===================================='

git clone https://github.com/StuartIanNaylor/zram-swap-config
cd zram-swap-config || exit 1
sudo chmod +rwx install.sh
sudo ./install.sh
cd ../ || exit 1
sudo rm -fr zram-swap-config

printf "\n%s\n%s\n\n" \
    'Installing: log2ram' \
    '===================================='

if [ ! -f log2ram.tar.gz ]; then
    if ! wget --show-progress -cqO log2ram.tar.gz https://github.com/azlux/log2ram/archive/master.tar.gz; then
        printf "%s\n\n" 'Failed to download: log2ram.tar.gz'
        exit 1
    fi
fi

if [ -d log2ram ]; then
    sudo rm -fr log2ram
fi

mkdir -p log2ram

if ! tar -zxf log2ram.tar.gz -C log2ram --strip-components 1 2>/dev/null; then
    printf "%s\n\n" 'Failed to extract: log2ram.tar.gz'
    exit 1
fi

cd log2ram || exit 1

sudo ./install.sh

if sudo service log2ram status &>/dev/null; then
    printf "%s\n%s\n\n" \
        'Stopping log2ram service' \
        '===================================='
    sudo service log2ram stop
fi

printf "\n%s\n%s\n\n" \
    'Editing file: /etc/log2ram.conf' \
    '===================================='

if [ -f /etc/log2ram.conf ]; then
    sudo sed -i 's/SIZE=40M/SIZE=512M/g' /etc/log2ram.conf
    sudo sed -i 's/LOG_DISK_SIZE=256M/LOG_DISK_SIZE=1024M/g' /etc/log2ram.conf
    sudo sed -i 's/ZL2R=false/ZL2R=true/g' /etc/log2ram.conf
    sudo sed -i 's/COMP_ALG=lz4/COMP_ALG=lzo/g' /etc/log2ram.conf
fi

# FIND AN EDITOR TO OPEN THE CONF FILE
if which nano &>/dev/null; then
    nano /etc/log2ram.conf
elif which vim &>/dev/null; then
    vim /etc/log2ram.conf
elif which vi &>/dev/null; then
    vi /etc/log2ram.conf
fi

printf "\n%s\n%s\n\n%s\n\n%s\n%s\n\n" \
    'You must reboot to enable log2ram' \
    '====================================' \
    'Do you want to reboot?' \
    '[1] Yes' \
    '[2] No'
read -p 'Your choices are (1 or 2): ' answer
clear

case "$answer" in
    1)      sudo reboot;;
    2)      exit 0;;
esac
