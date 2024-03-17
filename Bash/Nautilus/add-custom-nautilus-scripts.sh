#!/usr/bin/env bash

clear

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi


cd "$HOME/.local/share/nautilus/scripts" || exit 1


printf "%s\n\n%s\n%s\n\n" \
    "Do you want to delete any scripts already in the Nautilus scripts folder?" \
    '[1] Yes' \
    '[2] No'
read -p 'Your choices are (1 or 2): ' choice
clear

case "$choice" in
    1)    sudo rm *;
    2)    clear;
    *)
          clear
          printf "%s\n\n" 'Bad user input. Please re-run the script.'
          exit 1
          ;;
esac


cat > 'Open in New Window' <<'EOF'
#!/usr/bin/env bash
clear
nohup nautilus -w "$PWD/$1" >/dev/null 2>&1 &
EOF


cat > 'Empty Trash' <<'EOF'
#!/usr/bin/env bash
clear
pushd "$HOME"/.local/share/Trash/files || exit 1
sudo rm -fr *
popd
clear
ls -1AhFv --color --group-directories-first
EOF


cat > 'Open with Tilix' <<'EOF'
#!/usr/bin/env bash
clear
if which gnome-text-editor; then
    editor=gnome-text-editor
elif which gedit; then
    editor=gedit
elif which nano; then
    editor=nano
elif which vim; then
    editor=vim
elif which vi; then
    editor=vi
else
    clear
    printf "%s\n\n" 'No editor was found so the script cannot work. Please install an editor such as gedit or nano.'
fi
fpath="$PWD/$1"
fname="$(basename "$fpath")"
case "$fext" in
    sh)             tilix -w "$PWD" -e bash "$fname";;
    bak|log|txt)    tilix -w "$PWD" -e $editor "$fname";;
    *)              tilix -w "$PWD" -e bash "$fname";;
esac
EOF

chown "$USER":"$USER" 'Open with Tilix'
chown "$USER":"$USER" 'Empty Trash'
chown "$USER":"$USER" 'Open in New Window'

chmod +rwx 'Open with Tilix'
chmod +rwx 'Empty Trash'
chmod +rwx 'Open in New Window'
