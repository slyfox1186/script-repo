#!/usr/bin/env bash

clear

list=/etc/apt/sources.list

if [ ! -f "$list".bak ]; then
    sudo cp -f "$list" "$list".bak
fi

cat > "$list" <<EOF
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
deb http://atl.mirrors.clouvider.net/debian/ bullseye main contrib non-free
deb http://atl.mirrors.clouvider.net/debian/ bullseye-updates main contrib non-free
deb http://atl.mirrors.clouvider.net/debian/ bullseye-backports main contrib non-free
EOF

if which gedit &>/dev/null; then
    sudo gedit "$list"
elif which nano &>/dev/null; then
    sudo nano "$list"
elif which vim &>/dev/null; then
    sudo vim "$list"
elif which vi &>/dev/null; then
    sudo vi "$list"
else
    printf "\n%s\n\n" "Could not find an EDITOR to open: $list"
    exit 1
fi

sudo rm "$0"
