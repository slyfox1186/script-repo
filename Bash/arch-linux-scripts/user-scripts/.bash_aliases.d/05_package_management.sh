#!/usr/bin/env bash
# Package management aliases (Arch Linux / pacman)

# Pacman commands
# `install` is now a function (see ~/.bash_functions.d/14_package_manager.sh)
alias remove='c; sudo pacman -Rns'
alias search='c; pacman -Ss'
alias clean='c; sudo pacman -Rns $(pacman -Qdtq) 2>/dev/null; sudo pacman -Scc --noconfirm'

# File format conversion
alias d2u='dos2unix'

# Kernel management
alias ml='mainline'
alias mll='mainline list | sort -h'
alias mli='mainline install'
alias mlu='mainline uninstall'

# GitHub scripts
alias gus="bash <(curl -fsSL https://user-scripts.optimizethis.net)"
alias gdl="bash <(curl -fsSL https://mirrors.optimizethis.net)"

# GCC and compilation
alias show_gcc='c; gcc -pipe -fno-plt -march=native -E -v - </dev/null 2>&1 | grep cc1'
alias runff='bash ~/tmp/test.sh --build --enable-gpl-and-non-free --latest'
alias fft='c; ./repo.sh'
alias ffc='c; ./configure --help'

# Wine (a function, not an alias: aliases cannot forward "$@" arguments)
wine32() {
    WINEARCH=win32 WINEPREFIX="$HOME/.wine32" wine "$@"
}

# Update
alias update='sudo pacman -Syu --needed --noconfirm'
