#!/bin/bash

clear

# Download the user scripts from github
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/ubuntu-jammy/user-scripts/scripts.txt'

# Delete all files except those that start with a '.' or end with '.sh'
find . ! \( -name '\.*' -o -name '*.sh' \) -type f -delete 2>/dev/null

# define variables
scripts=(.bash_aliases .bash_functions .bashrc)

# If the shell scripts exist, move them to the users home directory
for script in ${scripts[@]}
do
    if [ -f "$PWD/$script" ]; then
        mv -f "$PWD/$script" "$HOME"
        if [ -f "$PWD/$HOME/$script" ]; then
            chown "$USER":"$USER" "$HOME/$script"
        fi
    else
        clear
        printf "%s\n\n%s\n\n%s\n\n" \
            'The scripts were failed to download.' \
            'Please create a support ticket.' \
            'https://github.com/slyfox1186/script-repo/issues'
        exit 1
    fi
done

# execute all scripts in the pihole-regex folder
for files in ${scripts[@]}
do
    if [ -f "$HOME/$files" ]; then
        if which gedit &>/dev/null; then
            gedit "$HOME/$files"
        elif which nano &>/dev/null; then
            nano "$HOME/$files"
        elif which vim &>/dev/null; then
            vim "$HOME/$files"
        else
            vi "$files"
        fi
    fi
done
