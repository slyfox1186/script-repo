#!/bin/bash

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
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Debian%20Scripts/bookworm/user-scripts/bookworm-scripts.txt'

# Delete all files except those that start with a '.' or end with '.sh'
find . ! \( -name '\.*' -o -name '*.sh' \) -type f -delete 2>/dev/null

if ! mv -f '.bashrc' "$HOME"; then
    fail_fn 'Failed to move the script .bashrc to the user'\''s $HOME directory.'
fi

shell_array=(bash_aliases.sh bash_functions.sh)
script_array=(.bash_aliases .bash_functions .bashrc)

for i in ${shell_array[@]}
do
    if ! bash "${i}"; then
        fail_fn "Failed to execute: ${i}"
    fi
done
unset i

for i in ${script_array[@]}
    if ! sudo chown "$USER":"$USER" "$HOME/$i"; then
        fail_fn "Failed to update the file permissions for: $i"
    fi
done

# Open each script that is now in each user's home folder with an editor
for i in ${script_array[@]}
do
    if which gnome-text-editor &>/dev/null; then
        cd "$HOME" || exit 1
        gnome-text-editor "${i}"
    elif which gedit &>/dev/null; then
        cd "$HOME" || exit 1
        gedit "${i}"
    elif which nano &>/dev/null; then
        cd "$HOME" || exit 1
        nano "${i}"
    elif which vim &>/dev/null; then
        cd "$HOME" || exit 1
        vim "${i}"
    elif which vi &>/dev/null; then
        cd "$HOME" || exit 1
        vi "${i}"
    else
        fail_fn 'Could not find an EDITOR to open the user scripts.'
    fi
done

# Remove the installer script itself
if [ -f "$0" ]; then
    sudo rm "$0"
fi
