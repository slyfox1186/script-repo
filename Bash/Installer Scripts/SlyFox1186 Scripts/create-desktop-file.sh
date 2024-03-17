#!/Usr/bin/env bash

clear

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

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

display_name='Nautilus'
file_name='nautilus-root'
file_path='/usr/bin/nautilus'
file_icon='/usr/share/icons/Yaru/256x256@2x/apps/nautilus.png'

full_path="$HOME/Desktop/$file_name.desktop"
terminal='false'
version='1.0'


exit_msg_fn() {
    echo '[i] Make sure to star this repository to keep me motivated to add more content!'
    echo '[i] GitHub: https://github.com/slyfox1186/script-repo/'
    echo
    exit
}

exit_fn() {
    echo '[i] The script has completed.'
    echo
    if [[ "$1" == '_YES_' ]]; then
        exit_msg_fn
    elif [[ "$1" == '_NO_' ]]; then
        echo "[i] You can find the new file here: $full_path"
        exit_msg_fn
    fi
}

edit_permissions_fn() {
    echo '[i] It is required that you set the file permissions for the '\''others group'\'''
    echo '    to '\''read'\'' or '\''not allowed'\'' and enable the option '\''allow to execute'\'' or'
    echo '    the system will block the file when you double click it.'
    echo
    read -t 15 -p '[i] Pausing execution for 15 seconds. Press enter to continue at any time.'
    clear
    echo '[i] Setting the file permission to '\''750'\'' which equals rwxr-----'
    sudo chmod 750 "$full_path"
    sleep 2
    echo
    echo '[i] Enabling the required '\''allow to execute'\'' switch'
    sleep 3
    gio set "$full_path" metadata::trusted true
    clear
    exit_fn "$1"
}

editor_fn() {
    if [ -n "$editor" ]; then
        "$editor" "$full_path"
    else
        if which gedit &> /dev/null; then
            gedit "$full_path"
        elif which nano &> /dev/null; then
            nano "$full_path"
        else
            vi "$full_path"
        fi
    fi
}

prompt_fn() {
    if [[ "$1" == '1' ]]; then
        sudo rm "$full_path"
        clear
        exit_fn "$2"
    elif [[ "$1" == '2' ]]; then
        edit_permissions_fn "$2"
    elif [[ "$1" == '3' ]]; then
        clear
        exit_fn "$2"
    else
        echo '[x] Input error: You will be asked the question again.'
        sleep 2
        clear
        prompt_fn
    fi
}

echo '[i] Creating the .desktop file.'
sleep 2

cat > "$full_path" <<EOF
[Desktop Entry]
Encoding=UTF-8
version=$version
Type=Application
terminal=$terminal
Exec=$file_path
Name=$display_name
Icon=$file_icon
EOF

echo
echo '[i] Inspect the file and close the editor when done.'
echo
read -p 'Press enter to continue.'
echo
clear
editor_fn

echo '[i] Do you want to delete the file and start over?'
echo
echo '[1] Yes'
echo '[2] No'
echo
read -p 'Your choices are (1 or 2): ' answer
clear
if [[ "$answer" == '1' ]]; then
    flag='_YES_'
else
    flag='_NO_'
fi
prompt_fn "$answer" "$flag"
