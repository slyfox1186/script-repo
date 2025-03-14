#!/bin/bash
# Package management aliases

# APT commands
alias install='clear; apt -y install'
alias installr='clear; apt -y --reinstall install'
alias remove='clear; apt remove'
alias search='clear; apt search'

# Key management
alias fixkey='clear; apt-key adv --keyserver keyserver.ubuntu.com --recv-keys'

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
alias show_gcc='clear; gcc-12 -pipe -fno-plt -march=native -E -v - </dev/null 2>&1 | grep cc1'
alias runff='bash ~/tmp/test.sh --build --enable-gpl-and-non-free --latest'
alias fft='clear; ./repo.sh'
alias ffc='clear; ./configure --help'

# Wine
alias wine32='env WINEARCH=win32 WINEPREFIX=~/.wine32 wine $*'