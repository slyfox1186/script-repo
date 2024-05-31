#!/usr/bin/env bash

# Ensure the script is run as root
if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

# Define file paths
old_file=/etc/apt/sources.list
file=/etc/apt/sources.list.d/ubuntu.sources

# Backup the old sources list if it exists
if [[ -f "${old_file}" ]]; then
    mv "${old_file}" "${old_file}.bak"
fi

# Create the new sources list file
cat > ${file} <<'EOF'
Types: deb
URIs: https://atl.mirrors.clouvider.net/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# Types: deb
# URIs: http://us.archive.ubuntu.com/ubuntu/
# Suites: noble noble-updates noble-backports
# Components: main restricted universe multiverse
# Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# Types: deb
# URIs: http://mirror.team-cymru.org/ubuntu/
# Suites: noble noble-updates noble-backports
# Components: main restricted universe multiverse
# Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# Types: deb
# URIs: http://mirror.steadfastnet.com/ubuntu/
# Suites: noble noble-updates noble-backports
# Components: main restricted universe multiverse
# Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

# Open the new sources list file with the available text editor
if command -v gnome-text-editor &>/dev/null; then
    gnome-text-editor "${file}"
elif command -v gedit &>/dev/null; then
    gedit "${file}"
elif command -v nano &>/dev/null; then
    nano "${file}"
else
    echo "Unable to open the sources.list file because no text editor was found."
fi
