#!/usr/bin/env bash

clear

#
# DEFINE VARIABLES AND ARRAYS
#

randir="$(mktemp -d)"
dl_url='https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Debian%20Scripts/bookworm/user-scripts/bookworm-scripts.txt'
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36'

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
# CREATE A RANDOM FOLDER TO HOLD AND EXECUTE THE TEMP FILES
#

cd "${randir}" || exit 1

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
# PROMPT THE USER TO INSTALL APT-FAST
#

clear
printf "%s\n\n%s\n%s\n\n" \
    'Do you want to install and enable apt-fast as the primary download utility?' \
    '[1] Yes' \
    '[2] No'
read -p 'Your choices are (1 or 2): ' answer
clear

case "${answer}" in
    1)
            bash -c "$(curl -sL https://git.io/vokNn)"
            apt_flag=yes
            ;;
    2)      apt_flag=no;;
    *)
            clear
            printf "%s\n\n" 'Bad user input. Please start over.'
            exit 1
            ;;
esac
unset answer
clear

#
# RUN EACH SHELL SCRIPT TO INSTALL THE USER SCRIPTS
#

for i in ${shell_array[@]}
do
    bash "${i}" "${apt_flag}"
done
unset i

#
# UPDATE THE OWNERSHIP OF EACH USER SCRIPT TO THE USER
#

for i in ${script_array[@]}
do
    if ! sudo chown "${USER}":"${USER}" "${HOME}/${i}"; then
        fail_fn "Failed to update the file permissions for ${i}"
    fi
done
unset i

#
# OPEN EACH SCRIPT WITH AN EDITOR
#

for i in "${script_array[@]}"
do
    if which gted &>/dev/null; then
        cd "${HOME}" || exit 1
        gted "${i}"
    elif which gedit &>/dev/null; then
        cd "${HOME}" || exit 1
        gedit "${i}"
    elif which nano &>/dev/null; then
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

if [ -d "${randir}" ]; then
    sudo rm -fr "${randir}"
fi
