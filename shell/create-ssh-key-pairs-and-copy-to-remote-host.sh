#!/bin/bash

clear

######################
## CREATE FUNCTIONS ##
######################

exit_success_fn()
{
    echo
    echo 'The script has finished.'
    echo
    exit
}

exit_fail_ssh_copy_fn()
{
    echo
    echo 'The script failed to succesfully copy the ssh key file to the remote pc.'
    echo
    echo 'Please check your script code and user input for errors.'
    echo
    read -p 'Press enter to continue.'
    clear
    exit 1
}

exit_fail_ssh_keygen_fn()
{
    echo 'Failed to create the ssh key pair.'
    echo
    echo 'Please check your script code and user input for errors.'
    echo
    read -p 'Press enter to continue.'
    clear
    exit 1
}

create_ssh_keypair_fn()
{

    clear

    ssh-keygen -b '4096' -t 'rsa' -C 'jman@JDESKTOP-U' -f "${HOME}"/.ssh/id_rsa

    if [ ${?} -ne '0' ]; then
        exit_fail_ssh_keygen_fn
    fi

    main_menu_fn
}

copy_ssh_key_fn()
{
    clear

    local SSH_IP SSH_PORT SSH_USER
    echo 'Enter the remote PC'\''s information:'

    read -p 'Port: ' SSH_PORT
    echo
    read -p 'User: ' SSH_USER
    echo
    read -p 'IP Address: ' SSH_IP
    echo

    ssh-copy-id -p "${SSH_PORT}" -i "${HOME}"/.ssh/id_rsa.pub "${SSH_USER}"@"${SSH_IP}"
    echo
    read -p 'Press enter to continue.'
    clear

    if [ ${?} -ne '0' ]; then
        exit_fail_ssh_copy_fn
    fi

    main_menu_fn
}

check_for_ssh_keys_fn()
{
    clear

    local ANSWER

    # Verify that the public ssh key '~/.ssh/id_rsa.pub' exists before continuing
    if [ -f "${HOME}"/.ssh/id_rsa.pub ]; then
        echo
        echo 'The ssh key pair files were found. No need to recreate.'
        echo
        echo 'You can select copy ssh key pairs to remote pc now.'
        echo
        read -p 'Press enter to continue.'
        clear
        return 0
    else
        echo "The public ssh key is missing: ${HOME}/.ssh/id_rsa.pub"
        echo
        echo 'You must generate a private keypair before you can run this script.'
        echo
        echo 'Would you like to do that now?'
        echo
        echo '[1] Yes'
        echo '[2] No'
        echo '[3] Exit'
        echo
        read -p 'You choices are (1 to 3): ' ANSWER
        clear
        if [ "${ANSWER}" -eq '1' ]; then
            create_ssh_keypair_fn

            if [ ${?} -ne '0' ]; then
                exit_fail_ssh_keygen_fn
            else
                main_menu_fn
            fi

            if [ "${ANSWER}" -eq '2' ] || [ "${ANSWER}" -eq '3' ]; then
                exit_success_fn
            fi
        fi
    fi
}

###############
## Main Menu ##
###############

main_menu_fn()
{

    clear

    local CHOICE

    echo 'Choose what to do: '
    echo
    echo '1) Check if ssh key pairs exist (id_rsa and id_rsa.pub)'
    echo '2) Copy this pc'\''s ssh public key to a remote computer'
    echo '3) Exit back to terminal'
    echo

    read -p 'Your choices (1 to 3): ' CHOICE
    echo

    # case code
    case ${CHOICE} in
        1)
            check_for_ssh_keys_fn
            main_menu_fn
            exit
            ;;
        2)
            copy_ssh_key_fn
            main_menu_fn
            ;;
        3)
            exit_success_fn
            ;;
        *)
            echo 'Invalid selection... reloading the menu in 3 seconds.'
            sleep 3
            main_menu_fn
            ;;
    esac
}

main_menu_fn
