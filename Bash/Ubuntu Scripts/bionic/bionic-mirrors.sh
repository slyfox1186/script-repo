#!/usr/bin/env bash

clear

list='/etc/apt/sources.list'

if [ ! -f "$list.bak" ]; then
    cp -f "$list" "$list.bak"
fi

cat > "$list" <<EOF
deb https://atl.mirrors.clouvider.net/ubuntu/ bionic main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ bionic-updates main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ bionic-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ bionic-security main restricted universe multiverse
EOF

if which gedit &>/dev/null; then
    sudo gedit "$list"
elif which nano &>/dev/null; then
    sudo nano "$list"
elif which vi &>/dev/null; then
    sudo vi "$list"
else
    printf "\n%s\n\n" "Could not find an EDITOR to open the file: $list"
    exit 1
fi

sudo rm "$0"
