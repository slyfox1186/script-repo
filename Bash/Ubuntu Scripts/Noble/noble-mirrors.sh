#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

file_old="/etc/apt/sources.list"
file="/etc/apt/sources.list.d/ubuntu.sources"

mv "$file_old" "${file_old}.bak"

cat > $file <<'EOF'
Types: deb
URIs: https://atl.mirrors.clouvider.net/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://us.archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://mirror.team-cymru.org/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://mirror.steadfastnet.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

if type -P gnome-text-editor &>/dev/null; then
	gnome-text-editor $file
elif type -P gedit &>/dev/null; then
	gedit $file
elif type -P nano &>/dev/null; then
	nano $file
else
	echo "Unable to open the sources.list file because the script could not find a text EDITOR."
fi
