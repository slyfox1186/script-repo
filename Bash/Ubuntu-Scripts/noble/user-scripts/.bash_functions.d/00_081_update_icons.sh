#!/usr/bin/env bash

## UPDATE ICON CACHE ##
update_icons() {
    local pkg pkgs
    pkgs=(gtk-update-icon-cache hicolor-icon-theme)
    for pkg in "${pkgs[@]}"; do
        if ! sudo dpkg -l | grep -q "$pkg"; then
            sudo apt -y install "$pkg"
            echo
        fi
    done

    sudo gtk-update-icon-cache -f /usr/share/icons/hicolor
}
