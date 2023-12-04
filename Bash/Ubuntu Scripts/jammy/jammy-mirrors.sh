#!/usr/bin/env bash

clear

fname='/etc/apt/sources.fname'

# make a backup of the file
if [ ! -f "${fname}.bak" ]; then
    cp -f "${fname}" "${fname}.bak"
fi

cat > "${fname}" <<EOF
deb https://mirror.enzu.com/ubuntu/ jammy main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirror.enzu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOF

# OPEN AN EDITOR TO VIEW THE CHANGES
if type -P gnome-text-editor &>/dev/null; then
    sudo gnome-text-editor "${fname}"
elif type -P gedit &>/dev/null; then
    sudo gedit "${fname}"
elif type -P nano &>/dev/null; then
    sudo nano "${fname}"
elif type -P vi &>/dev/null; then
    sudo vi "${fname}"
else
    printf "\n%s\n\n" "Could not find an EDITOR to open the file: ${fname}"
    exit 1
fi

if [ -f 'jammy-mirrors.sh' ]; then
    sudo rm 'jammy-mirrors.sh'
fi
