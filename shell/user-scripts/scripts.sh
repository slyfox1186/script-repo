#!/bin/bash

clear

# make a tmporary random directory
random_dir="/tmp/$(mktemp --directory)"

if [ ! -d "$random_dir" ]; then
    clear
    printf "%s\n\n%s\n\n%s\n\n" \
        "The temporary directory was not found: $random_dir" \
        'Please create a support ticket.' \
        'https://github.com/slyfox1186/script-repo/issues'
    exit 1
fi

# Change the working directory into the random directory to avoid deleting unintended files
cd "$random_dir"

# Download the user scripts from GitHub
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/user-scripts/scripts.txt'

# Delete all files except those that start with a '.' or end with '.sh'
find . ! \( -name '\.*' -o -name '*.sh' \) -type f -delete 2>/dev/null

# define script array
scriptArray=(.bash_aliases .bash_functions .bashrc)

# If the scripts exist, move each one to the users home directory
for script in ${scriptArray[@]}
do
    if [ -f "$script" ]; then
        mv -f "$script" "$HOME"
        if [ -f "$HOME/$script" ]; then
            sudo chown "$USER":"$USER" "$HOME/$script"
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

# Open each script that is now in each user's home folder with an editor
for script in "$HOME"/${scripts[@]}
do
    if [ -f "$script" ]; then
        if which gedit &>/dev/null; then
            gedit "$script"
        elif which nano &>/dev/null; then
            nano "$script"
        elif which vim &>/dev/null; then
            vim "$script"
        else
            vi "$script"
        fi
    fi
done
