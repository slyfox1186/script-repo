#!/Usr/bin/env bash

clear


exit_success_fn() {
    echo
    echo 'The script has finished.'
    exit
}

exit_fail_ssh_copy_fn() {
    echo
    echo 'The script failed to succesfully copy the ssh key file to the remote pc.'
    echo
    echo 'Please check your script code and user input for errors.'
    echo
    read -p 'Press enter to continue.'
    clear
    exit 1
}

exit_fail_ssh_keygen_fn() {
    echo 'Failed to create the ssh key pair.'
    echo
    echo 'Please check your script code and user input for errors.'
    echo
    read -p 'Press enter to continue.'
    clear
    exit 1
}

create_ssh_keypair_fn() {
    clear

    echo 'User input is required to create the new ssh key pair.'
    echo
    echo 'Available options and examples are located inside the parenthesis.'
    echo
    read -p 'Enter the bit size ( 2048 | 4096 ): ' SSH_BITS
    echo
    read -p 'Enter the type ( dsa | rsa ): ' SSH_TYPE
    echo
    read -p "Enter a comment ( $USER@$(uname -n) ): " SSH_COMMENT
    echo
    read -p "Enter the full output file path ( $HOME/.ssh/id_rsa ): " SSH_DIR
    echo
    ssh-keygen -b "$SSH_BITS" -t "$SSH_TYPE" -C "$SSH_COMMENT" -f "$SSH_DIR"

    if [ $? -ne '0' ]; then
        exit_fail_ssh_keygen_fn
    fi

    main_menu_fn
}

copy_ssh_key_fn() {
    clear

    local SSH_IP SSH_PORT SSH_USER
    echo 'User input is required to copy the public ssh key to a remote computer.'
    echo
    echo 'Available options and examples are located inside the parenthesis.'
    echo
    read -p 'Port (default is 22): ' SSH_PORT
    echo
    read -p "User ( $(whoami) ): " SSH_USER
    echo
    read -p 'IP Address ( 192.168.1.2 | 10.0.1.0 ): ' SSH_IP
    echo

    ssh-copy-id -p "$SSH_PORT" -i "$HOME/.ssh/id_rsa.pub" "$SSH_USER"@"$SSH_IP"
    echo
    read -p 'Press enter to continue.'
    clear

    if [ $? -ne '0' ]; then
        exit_fail_ssh_copy_fn
    fi

    main_menu_fn
}

check_for_ssh_keys_fn() {
    clear

    local ANSWER

    if [ -f "$HOME"/.ssh/id_rsa ] && [ -f "$HOME"/.ssh/id_rsa.pub ]; then
        echo
        echo 'The ssh key pair files were found. No need to recreate.'
        echo
        echo 'You can select copy ssh key pairs to remote pc now.'
        echo
        read -p 'Press enter to continue.'
        clear
        return 0
    else
        printf "The ssh key pairs are missing:\n\n%s\n%s\n" "$HOME"/.ssh/id_rsa "$HOME"/.ssh/id_rsa.pub
        echo
        echo '============================================='
        echo
        echo 'You must generate a new private keypair before'
        echo 'attempting to copy the public key to another computer.'
        echo
        echo 'Would you like to create them now?'
        echo
        echo '[1] Yes'
        echo '[2] No'
        echo '[3] Main Menu'
        echo
        read -p 'You choices are (1 to 3): ' ANSWER
        clear
        if [ "$ANSWER" -eq '1' ]; then
            create_ssh_keypair_fn
        elif [ "$ANSWER" -eq '2' ] || [ "$ANSWER" -eq '3' ]; then
            main_menu_fn
        fi
    fi
}


main_menu_fn() {
    clear

    local CHOICE

    echo 'Choose what to do: '
    echo
    echo '1) Check if ssh key pairs exist (id_rsa and id_rsa.pub)'
    echo '2) Copy this pc'\''s ssh public key to a remote computer'
    echo '3) Exit script'
    echo

    read -p 'Your choices (1 to 3): ' CHOICE
    echo

    case $CHOICE in
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
