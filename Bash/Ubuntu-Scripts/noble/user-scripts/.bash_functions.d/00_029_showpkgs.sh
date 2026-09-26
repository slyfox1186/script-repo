#!/usr/bin/env bash

# DPKG COMMANDS #

## Show all installed packages
showpkgs() {
    dpkg --get-selections | grep -v deinstall > "$HOME/tmp/packages.list"
    gnome-text-editor "$HOME/tmp/packages.list"
}
