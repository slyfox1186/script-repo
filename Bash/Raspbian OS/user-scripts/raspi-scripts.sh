#!/usr/bin/env bash

clear

#
# DEFINE VARIABLES AND ARRAYS
#

random_dir="$(mktemp -d)"
dl_url='https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Raspbian%20OS/user-scripts/raspi-scripts.txt'
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36'

shell_array=(bash_aliases.sh bash_functions.sh)
script_array=(.bash_aliases .bash_functions .bashrc)

#
# CREATE FUNCTIONS
#

fail_fn()
{
    printf "\n%s\n\n" "${1}"
    exit 1
}

#
# DOWNLAOD REQUIRED APT PACKAGES
#

sudo apt -y install curl wget git ccache

#
# CD INTO A RANDOM FOLDER TO HOLD AND EXECUTE THE TEMP FILES
#

cd "${random_dir}" || exit 1

#
# DOWNLOAD THE USER SCRIPTS FROM GITHUB
#

wget -U "${user_agent}" -qN - -i "${dl_url}"

#
# DELETE ALL FILES EXCEPT THOSE THAT START WITH A "." OR END WITH ".sh"
#

find . ! \( -name '\.*' -o -name '*.sh' \) -type f -delete 2>/dev/null

#
# MOVE ".bashrc" TO THE USERS HOME FOLDER
#

if ! mv -f '.bashrc' "${HOME}"; then
    fail_fn "Failed to move the script \".bashrc\" to ${HOME}."
fi

#
# RUN EACH SHELL SCRIPT TO INSTALL THE USER SCRIPTS
#

for files in ${shell_array[@]}
do
    bash "${files}"
done

#
# UPDATE THE OWNERSHIP OF EACH USER SCRIPT TO THE USER
#

for scripts in ${script_array[@]}
do
    if ! sudo chown "${USER}":"${USER}" "${HOME}/${scripts}"; then
        fail_fn "Failed to update the file permissions for ${scripts}"
    fi
done

#
# OPEN EACH SCRIPT WITH AN EDITOR
#

for i in ${script_array[@]}
do
    if which nano &>/dev/null; then
        cd "${HOME}" || exit 1
        nano "${i}"
    elif which vim &>/dev/null; then
        cd "${HOME}" || exit 1
        vim "${i}"
    elif which vi &>/dev/null; then
        cd "${HOME}" || exit 1
        vi "${i}"
    else
        fail_fn 'Could not find an EDITOR to open the user scripts.'
    fi
done

#
# DELETE THE LEFTOVER TEMP FILES
#

if [ -d "${random_dir}" ]; then
    sudo rm -fr "${random_dir}"
fi
