#!/bin/bash

clear

# make a tmporary random directory
random_dir="$(mktemp --directory)"

static_dir="$random_dir"

# Change the working directory into the random directory to avoid deleting unintended files
cd "$static_dir" || exit 1

# Download the user scripts from GitHub
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/user-scripts/scripts.txt'

# Delete all files except those that start with a '.' or end with '.sh'
find . ! \( -name '\.*' -o -name '*.sh' \) -type f -delete 2>/dev/null

# define script array
scriptArray=(.bash_aliases .bash_functions .bashrc)

# If the scripts exist, move each one to the users home directory
for script in ${scriptArray[@]}
do
    if ! mv -f "$PWD/$script" "$HOME"; then
        echo 'Failed: 1'
        echo
        exit 1
    fi
    if ! sudo chown "$USER":"$USER" "$HOME/$script"; then
        echo 'Failed: 1'
        echo
        exit 1
    fi
done

# Open each script that is now in each user's home folder with an editor
for i in ${scriptArray[@]}
do
    if which gedit &>/dev/null; then
        gedit "$HOME/$i"
    elif which nano &>/dev/null; then
        nano "$HOME/$i"
    elif which vim &>/dev/null; then
        vim "$HOME/$i"
    else
        vi "$HOME/$i"
    fi
done

# Remove the installer script itself
if [ -f 'scripts.sh' ]; then
    sudo rm 'scripts.sh'
fi
