#!/bin/bash

clear

# Delete any useless files that get downloaded.
if [ -f 'index.html' ]; then rm 'index.html'; fi
if [ -f 'urls.txt' ]; then rm 'urls.txt'; fi

# define variables
SCRIPTS='.bash_aliases .bash_functions .bashrc'
# If the shell scripts exist, move them to the pihole-regex dir
for i in ${SCRIPTS[@]}
do
    if [ -f "${i}" ]; then
        mv -f "${i}" "${HOME}"
    else
        clear
        echo 'Script error: The shell scripts were not found.'
        echo
        echo 'Please report this on my GitHub Issues page.'
        echo 'https://github.com/slyfox1186/pihole-regex/issues'
        echo
        exit 1
    fi
done

# execute all scripts in the pihole-regex folder
for FILES in ${SCRIPTS[@]}
do
    # Open in editor to verify file contents
    if which gedit &>/dev/null; then
        gedit "${FILES}"
    elif which nano &>/dev/null; then
        nano "${FILES}"
    elif which vim &>/dev/null; then
        vim "${FILES}"
    else
        vi "${FILES}"
    fi
done

# remove installer script
sudo rm "${0}"
