#!/usr/bin/env bash
# GUI Application Functions

## WHEN LAUNCHING CERTAIN PROGRAMS FROM THE TERMINAL, SUPPRESS ANY WARNING MESSAGES ##
gedit() {
    command gedit "$@" &>/dev/null
}

geds() {
    sudo -Hu root gedit "$@" &>/dev/null
}

gted() {
    [[ ! -f /usr/bin/gted ]] && sudo ln -s /usr/bin/gnome-text-editor /usr/bin/gted
    command gnome-text-editor "$@" &>/dev/null
}

gteds() {
    [[ ! -f /usr/bin/gted ]] && sudo ln -s /usr/bin/gnome-text-editor /usr/bin/gted
    sudo -Hu root gnome-text-editor "$@" &>/dev/null
}
