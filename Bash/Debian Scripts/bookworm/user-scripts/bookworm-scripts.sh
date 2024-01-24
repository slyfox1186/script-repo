#!/usr/bin/env bash
# shellcheck disable=SC2068,SC2162

clear

#
# DEFINE VARIABLES AND ARRAYS
#

random_dir="$(mktemp -d)"
url='https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Debian%20Scripts/bookworm/user-scripts/bookworm-scripts.txt'
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
script_array=('.bashrc' '.bash_aliases' '.bash_functions')

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

if ! sudo dpkg -l | grep -o wget &>/dev/null; then
    sudo apt -y install wget
    clear
fi

#
# CD INTO A RANDOM FOLDER TO HOLD AND EXECUTE THE TEMP FILES
#

cd "${random_dir}" || exit 1

#
# DOWNLOAD THE USER SCRIPTS FROM GITHUB
#

wget -U "${user_agent}" -qN - -i "${url}"

#
# DELETE ALL FILES EXCEPT THOSE THAT START WITH A "." OR END WITH ".sh"
#

find . ! \( -name '\.*' -o -name '*.sh' \) -type f -delete 2>/dev/null

#
# MOVE ".bashrc" TO THE USERS HOME FOLDER
#

for script in "${script_array[@]}"
do
    if ! mv -f "${script}" "${HOME}"; then
        fail_fn "Failed to move all user scripts to: ${HOME}. Line ${LINENO}"
    fi
done
unset script

#
# UPDATE THE OWNERSHIP OF EACH USER SCRIPT TO THE USER
#

for script in ${script_array[@]}
do
    if ! sudo chown "${USER}":"${USER}" "${HOME}/${script}"; then
        fail_fn "Failed to update the file permissions for: ${script}. Line ${LINENO}"
    fi
done

#
# OPEN EACH SCRIPT WITH AN EDITOR
#

cd "${HOME}" || exit 1
for fname in ${script_array[@]}
do
    if which gnome-text-editor &>/dev/null; then
        gnome-text-editor "${fname}"
    elif which gedit &>/dev/null; then
        gedit "${fname}"
    elif which nano &>/dev/null; then
        nano "${fname}"
    elif which vim &>/dev/null; then
        vim "${fname}"
    elif which vi &>/dev/null; then
        vi "${fname}"
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
