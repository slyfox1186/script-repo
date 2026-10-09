#!/usr/bin/env bash
# Install the Ubuntu/APT dotfile snapshot stored at this historical repository path.
set -Eeuo pipefail
umask 077

base_url="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Arch-Linux-Scripts"
home_files=(.bashrc .bash_aliases .bash_functions)
functions_d=(
    01_gui_apps.sh 02_filesystem.sh 03_text_processing.sh 04_compression.sh
    05_package_management.sh 06_system_admin.sh 07_process_management.sh
    08_dev_tools.sh 09_file_analysis.sh 10_security.sh 11_networking.sh
    12_multimedia.sh 13_ai_tools.sh 14_utilities.sh
    startup/pyenv.sh startup/pip.sh README.md CLEANUP.md
)

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

command -v apt-get >/dev/null || fail 'This dotfile snapshot requires Ubuntu/Debian APT; it is not an Arch Linux configuration.'
if ! command -v wget >/dev/null; then
    sudo apt-get -y install wget || fail 'Could not install wget.'
fi

td=$(mktemp -d)
trap 'rm -r -- "$td"' EXIT
mkdir -p "$td/.bash_functions.d/startup"
for file in "${home_files[@]}"; do
    wget -q --output-document="$td/$file" -- "$base_url/$file" || fail "Download failed: $file"
    bash -n "$td/$file" || fail "Invalid Bash syntax: $file"
done
for file in "${functions_d[@]}"; do
    wget -q --output-document="$td/.bash_functions.d/$file" -- "$base_url/.bash_functions.d/$file" || fail "Download failed: $file"
    if [[ "$file" == *.sh ]]; then
        bash -n "$td/.bash_functions.d/$file" || fail "Invalid Bash syntax: $file"
    fi
done

# Keep previous files available and prevent leftover modules overriding this set.
backup_dir="$HOME/.local/state/bash-dotfiles-backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$backup_dir"
for file in "${home_files[@]}" .bash_functions.d .bash_aliases.d; do
    if [[ -e "$HOME/$file" || -L "$HOME/$file" ]]; then
        cp -a -- "$HOME/$file" "$backup_dir/$file" || fail "Backup failed: $file"
    fi
done

restore_on_error() {
    local file
    trap - ERR
    set +e
    for file in "${home_files[@]}"; do
        if [[ -e "$backup_dir/$file" || -L "$backup_dir/$file" ]]; then
            cp -a --remove-destination -- "$backup_dir/$file" "$HOME/$file"
        elif [[ -e "$HOME/$file" || -L "$HOME/$file" ]]; then
            mv -- "$HOME/$file" "$backup_dir/failed-$file"
        fi
    done
    for file in .bash_functions.d .bash_aliases.d; do
        if [[ -e "$HOME/$file" || -L "$HOME/$file" ]]; then
            mv -- "$HOME/$file" "$backup_dir/failed-$file"
        fi
        if [[ -e "$backup_dir/replaced-${file#.bash_}" || -L "$backup_dir/replaced-${file#.bash_}" ]]; then
            mv -- "$backup_dir/replaced-${file#.bash_}" "$HOME/$file"
        elif [[ -e "$backup_dir/$file" || -L "$backup_dir/$file" ]]; then
            cp -a -- "$backup_dir/$file" "$HOME/$file"
        fi
    done
    printf 'Installation failed; restoration attempted. Backup: %s\n' "$backup_dir" >&2
    exit 1
}
trap restore_on_error ERR
if [[ -e "$HOME/.bash_functions.d" || -L "$HOME/.bash_functions.d" ]]; then
    mv -- "$HOME/.bash_functions.d" "$backup_dir/replaced-functions.d"
fi
if [[ -e "$HOME/.bash_aliases.d" || -L "$HOME/.bash_aliases.d" ]]; then
    mv -- "$HOME/.bash_aliases.d" "$backup_dir/replaced-aliases.d"
fi
cp -a -- "$td/.bash_functions.d" "$HOME/.bash_functions.d"
for file in "${home_files[@]}"; do
    cp --remove-destination -- "$td/$file" "$HOME/$file"
    chmod 600 "$HOME/$file"
done
trap - ERR
printf 'Dotfiles installed. Backup: %s\nOpen a new terminal to load them.\n' "$backup_dir"
