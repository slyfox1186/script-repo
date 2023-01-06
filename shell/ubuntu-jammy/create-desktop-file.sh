#!/bin/bash

clear

##########################################
## VERIFY THE SCRIPT'S PERMISSION LEVEL ##
##########################################
if [[ "${EUID}" -lt '1' ]]; then
    echo 'You must run this script as without root/sudo.'
    echo
    exit 1
fi

#######################################
## PROMPT THE USER WITH INSTRUCTIONS ##
#######################################
echo '[i] You must change the "custom variables" section of this script to match your needs before executing.'
echo '[i] It is advised to leave the "static variables" as they are unless you have a good reason to do so.'
echo
echo '[i] Do you want to edit this script before continuing?'
echo
echo '[1] Yes'
echo '[2] No'
echo
read -p 'Your choices are (1 or 2): '
clear

######################
## CUSTOM VARIABLES ##
######################
DISPLAY_NAME='Nautilus'
FILE_NAME='nautilus-root'
FILE_PATH='/usr/bin/nautilus'
FILE_ICON='/usr/share/icons/Yaru/256x256@2x/apps/nautilus.png'

######################
## STATIC VARIABLES ##
######################
FULL_PATH="${HOME}/Desktop/${FILE_NAME}.desktop"
TERMINAL='false'
VERSION='1.0'

#####################
## DEFINE FUNTIONS ##
#####################

exit_msg_fn()
{
    echo '[i] Make sure to star this repository to keep me motivated to add more content!'
    echo '[i] GitHub: https://github.com/slyfox1186/script-repo/'
    echo
    exit
}

exit_fn()
{
    echo '[i] The script has completed.'
    echo
    if [[ "${1}" == '_YES_' ]]; then
        exit_msg_fn
    elif [[ "${1}" == '_NO_' ]]; then
        echo "[i] You can find the new file here: ${FULL_PATH}"
        exit_msg_fn
    fi
}

edit_permissions_fn()
{
    echo '[i] It is required that you set the file permissions for the '\''others group'\'''
    echo '    to '\''read'\'' or '\''not allowed'\'' and enable the option '\''allow to execute'\'' or'
    echo '    the system will block the file when you double click it.'
    echo
    read -t 15 -p '[i] Pausing execution for 15 seconds. Press enter to continue at any time.'
    clear
    echo '[i] Setting the file permission to '\''750'\'' which equals rwxr-----'
    sudo chmod 750 "${FULL_PATH}"
    sleep 2
    echo
    echo '[i] Enabling the required '\''allow to execute'\'' switch'
    sleep 3
    gio set "${FULL_PATH}" metadata::trusted true
    clear
    exit_fn "${1}"
}

editor_fn()
{
    if [ -n "${EDITOR}" ]; then
        "${EDITOR}" "${FULL_PATH}"
    else
        if which gedit &> /dev/null; then
            gedit "${FULL_PATH}"
        elif which nano &> /dev/null; then
            nano "${FULL_PATH}"
        else
            vi "${FULL_PATH}"
        fi
    fi
}

prompt_fn()
{
    if [[ "${1}" == '1' ]]; then
        sudo rm "${FULL_PATH}"
        clear
        exit_fn "${2}"
    elif [[ "${1}" == '2' ]]; then
        edit_permissions_fn "${2}"
    elif [[ "${1}" == '3' ]]; then
        clear
        exit_fn "${2}"
    else
        echo '[x] Input error: You will be asked the question again.'
        sleep 2
        clear
        prompt_fn
    fi
}

# CREATE THE FILE
echo '[i] Creating the .desktop file.'
sleep 2

cat > "${FULL_PATH}" <<EOF
[Desktop Entry]
Encoding=UTF-8
Version=${VERSION}
Type=Application
Terminal=${TERMINAL}
Exec=${FILE_PATH}
Name=${DISPLAY_NAME}
Icon=${FILE_ICON}
EOF

# OPEN THE NEWLY CREATED FILE FOR INSPECTION
# JUST CLOSE THE EDITOR IF EVERYTHING LOOKS GOOD
echo
echo '[i] Inspect the file and close the editor when done.'
echo
read -p 'Press enter to continue.'
echo
clear
editor_fn

# ASK THE USER FOR PERMISSION TO DELETE IF REQUIRED
echo '[i] Do you want to delete the file and start over?'
echo
echo '[1] Yes'
echo '[2] No'
echo
read -p 'Your choices are (1 or 2): ' ANSWER
clear
if [[ "${ANSWER}" == '1' ]]; then
    FLAG='_YES_'
else
    FLAG='_NO_'
fi
prompt_fn "${ANSWER}" "${FLAG}"
