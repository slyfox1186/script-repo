#!/usr/bin/env bash

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
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Debian%20Scripts/bookworm/user-scripts/bookworm-scripts.txt'

# Delete all files except those that start with a '.' or end with '.sh'
find . ! \( -name '\.*' -o -name '*.sh' \) -type f -delete 2>/dev/null

if ! mv -f '.bashrc' "$HOME"; then
    fail_fn 'Failed to move the script .bashrc to the user'\''s $HOME directory.'
fi

#
# PROMPT THE USER TO INSTALL APT-FAST
#

clear

printf "%s\n\n%s\n%s\n\n" \
    'Do you want to install/enable apt-fast as the primary download utility?' \
    '[1] Yes' \
    '[2] No'
read -p 'Your choices are (1 or 2): ' answer
clear

case "$answer" in
    1)
            bash -c "$(curl -sL https://git.io/vokNn)"
            apt_flag=yes
            clear
            ;;
    2)      apt_flag=no;;
    *)
            clear
            printf "%s\n\n" 'Bad user input. Please start over.'
            exit 1
            ;;
esac
unset answer

shell_array=(bash_aliases.sh bash_functions.sh)
script_array=(.bash_aliases .bash_functions .bashrc)

for i in ${shell_array[@]}
do
    bash "$i" "$apt_flag"
done

for f in ${script_array[@]}
do
    if ! sudo chown "$USER":"$USER" "$HOME/$f"; then
        fail_fn "Failed to update the file permissions for: $f"
    fi
done

# Open each script that is now in each user's home folder with an editor
for v in ${script_array[@]}
do
    if which gnome-text-editor &>/dev/null; then
        cd "$HOME" || exit 1
        gnome-text-editor "$v"
    elif which gedit &>/dev/null; then
        cd "$HOME" || exit 1
        gedit "$v"
    elif which nano &>/dev/null; then
        cd "$HOME" || exit 1
        nano "$v"
    elif which vim &>/dev/null; then
        cd "$HOME" || exit 1
        vim "$v"
    elif which vi &>/dev/null; then
        cd "$HOME" || exit 1
        vi "$v"
    else
        fail_fn 'Could not find an EDITOR to open the user scripts.'
    fi
done

# Remove the installer script itself
#if [ -f "$0" ]; then
#    sudo rm "$0"
#fi
