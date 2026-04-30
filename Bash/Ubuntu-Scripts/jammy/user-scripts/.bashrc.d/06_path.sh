#!/bin/bash
# PATH configuration

# ====================
# PATH CONFIGURATION
# ====================
# Set the PATH variable with commonly used directories
PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
$HOME/.npm-global/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin:\
/usr/local/games:\
/usr/games:\
/snap/bin"

# Add Windows paths if running in WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
    PATH="$PATH:\
/c/Windows/System32:\
/c/Program Files:\
/c/Program Files (x86)"
fi

export PATH