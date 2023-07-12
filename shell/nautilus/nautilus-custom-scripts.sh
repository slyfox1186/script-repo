#!/bin/bash

clear

if [ "$EUID" -eq '0' ]; then
    printf "%s\n\n" 'You must run this script WITHOUT root/sudo.'
    exit 1
fi

#
# CHANGE THE WORKING DIRECTORY TO THE NAUTILUS SCRIPTS DIRECTORY
#

cd "$HOME/.local/share/nautilus/scripts" || exit 1

#
# DELETE ANY FOUND SCRIPTS
#

sudo rm *

#
# CREATE OPEN NAUTILUS IN NEW WINDOW SCRIPT
#

cat > 'Open in New Window' <<'EOF'
#!/bin/bash
clear
nohup nautilus -w "$PWD/$1" >/dev/null 2>&1 &
EOF

#
# CREATE EMPTY TRASH SCRIPT
#

cat > 'Empty Trash' <<'EOF'
#!/bin/bash
clear
pushd "$HOME"/.local/share/Trash/files || exit 1
sudo rm -fr *
popd
clear
ls -1AhFv --color --group-directories-first
EOF

#
# CREATE OPEN WITH TILIX SCRIPT
#

cat > 'Open with Tilix' <<'EOF'
#!/bin/bash
clear
if which gted; then
    editor=gted
elif which gedit; then
    editor=gedit
elif which nano; then
    editor=nano
elif which vim; then
    editor=vim
elif which vi; then
    editor=vi
fi
fpath="$PWD/$1"
fname="$(basename "$fpath")"
fext="${fname##*.}"
case "$fext" in
    sh)             tilix -w "$PWD" -e bash "$fname";;
    bak|log|txt)    tilix -w "$PWD" -e $editor "$fname";;
    *)              tilix -w "$PWD" -e bash "$fname";;
esac
EOF

# SET FILE OWNERSHIP PERMISSIONS
chown "$USER":"$USER" 'Open with Tilix'
chown "$USER":"$USER" 'Empty Trash'
chown "$USER":"$USER" 'Open in New Window'

# SET FILE READ, WRITE, AND EXECUTE PERMISSIONS
chmod +rwx 'Open with Tilix'
chmod +rwx 'Empty Trash'
chmod +rwx 'Open in New Window'
