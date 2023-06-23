#!/bin/bash

clear

#
# CREATE FUNCTIONS
#

fail_fn()
{
    printf "\n%s\n\n" "$1"
    exit 1
}

# Create a tmporary random directory
random_dir="$(mktemp --directory)"

# Change the working directory into the random directory to avoid deleting unintended files
cd "$random_dir" || exit 1

# Delete all files except those that start with a '.' or end with '.sh'
find . ! \( -name '\.*' -o -name '*.sh' \) -type f -delete 2>/dev/null

# Download the user scripts from GitHub
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/user-scripts/lunar/lunar-scripts.txt'

# define script array
scriptArray=(.bash_aliases .bash_functions .bashrc)

# If the scripts exist, move each one to the users home directory
for script in ${scriptArray[@]}
do
    if ! mv -f "$PWD/$script" "$HOME"; then
        fail_fn "Failed to move scripts to: $HOME"
    fi
    if ! sudo chown "$USER":"$USER" "$HOME/$script"; then
        fail_fn "Failed to update file permissions to: $USER:$USER"
    fi
done

# Open each script that is now in each user's home folder with an editor
for i in ${scriptArray[@]}
do
    if which gnome-text-editor &>/dev/null; then
        gnome-text-editor "$HOME/$i"
    elif which gedit &>/dev/null; then
        gedit "$HOME/$i"
    elif which nano &>/dev/null; then
        nano "$HOME/$i"
    elif which vim &>/dev/null; then
        vi "$HOME/$i"
    else
        fail_fn 'Could not find an EDITOR to open the files with.'
    fi
done

# Remove the installer script itself
if [ -f 'scripts.sh' ]; then
    sudo rm 'scripts.sh'
fi
