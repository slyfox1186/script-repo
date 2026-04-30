#!/usr/bin/env bash
# Package management aliases (Arch Linux / pacman)

# Pacman commands
alias install='clear; sudo pacman -S --noconfirm'
alias remove='clear; sudo pacman -Rns'
alias search='clear; pacman -Ss'
alias clean='clear; sudo pacman -Rns $(pacman -Qdtq) 2>/dev/null; sudo pacman -Scc --noconfirm'

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
alias show_gcc='clear; gcc -pipe -fno-plt -march=native -E -v - </dev/null 2>&1 | grep cc1'
alias runff='bash ~/tmp/test.sh --build --enable-gpl-and-non-free --latest'
alias fft='clear; ./repo.sh'
alias ffc='clear; ./configure --help'

# Wine
alias wine32='env WINEARCH=win32 WINEPREFIX=~/.wine32 wine $*'

# Update
alias update='sudo pacman -Syu --noconfirm'
