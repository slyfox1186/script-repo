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

# Create and cd into a random directory
cd "$(mktemp --directory)" || exit 1

# Download the user scripts from GitHub
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/user-scripts/bookworm/bookworm-scripts.txt'

# Delete all files except those that start with a '.' or end with '.sh'
find . ! \( -name '\.*' -o -name '*.sh' \) -type f -delete 2>/dev/null

# define script array
script_array=(.bash_aliases .bash_functions .bashrc)

# If the scripts exist, move each one to the users home directory
for i in ${script_array[@]}
do
    if ! mv -f "$i" "$HOME"; then
        fail_fn 'Failed to move the scripts to the user'\''s $HOME directory.'
    fi
    if ! sudo chown "$USER":"$USER" "$HOME/$i"; then
        fail_fn "Failed to update the file permissions for: $i"
    fi
done

# Open each script that is now in each user's home folder with an editor
for i in ${script_array[@]}
do
    if which gnome-text-editor &>/dev/null; then
        cd "$HOME" || exit 1
        gnome-text-editor "$script_array"
    elif which gedit &>/dev/null; then
        cd "$HOME" || exit 1
        gedit "$script_array"
    elif which nano &>/dev/null; then
        cd "$HOME" || exit 1
        nano "$script_array"
    elif which vim &>/dev/null; then
        cd "$HOME" || exit 1
        vim "$script_array"
    elif which vi &>/dev/null; then
        cd "$HOME" || exit 1
        vi "$script_array"
    else
        fail_fn 'Could not find an EDITOR to open the user scripts.'
    fi
done

# Remove the installer script itself
if [ -f "$0" ]; then
    sudo rm "$0"
fi
