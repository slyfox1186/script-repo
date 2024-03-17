#!/Usr/bin/env bash

clear

cwd="$PWD"
tmp_dir="$(mktemp -d)"
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'

cd "$tmp_dir" || exit 1

curl -A "$user_agent" -m 10 -Lso 'imow' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-and-overwrite.sh'

sudo mv 'imow' "$cwd"

sudo rm -fr "$tmp_dir"

cd "$cwd" || exit 1

sudo chown "$USER":"$USER" 'imow'
sudo chmod +rwx 'imow'
