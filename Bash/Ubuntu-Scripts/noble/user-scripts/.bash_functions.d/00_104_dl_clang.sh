#!/usr/bin/env bash

######################################
## DOWNLOAD CLANG INSTALLER SCRIPTS ##
######################################

dl_clang() {
    clear
    if [[ ! -d "$HOME/tmp" ]]; then
        mkdir -p "$HOME/tmp"
    fi
    wget --show-progress -cqO "$HOME/tmp/build-clang-16" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-16"
    wget --show-progress -cqO "$HOME/tmp/build-clang-17" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-17"
    sudo chmod rwx "$HOME/tmp/build-clang-16" "$HOME/tmp/build-clang-17"
    sudo chown "$USER":"$USER" "$HOME/tmp/build-clang-16" "$HOME/tmp/build-clang-17"
    clear
    ls -1AvhF--color --group-directories-first
}
