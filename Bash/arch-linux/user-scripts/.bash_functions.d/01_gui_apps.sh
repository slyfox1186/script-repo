#!/usr/bin/env bash
# GUI Application Functions

## WHEN LAUNCHING CERTAIN PROGRAMS FROM THE TERMINAL, SUPPRESS ANY WARNING MESSAGES ##
gedit() {
    command gedit "$@" &>/dev/null
}

gted() {
    command gnome-text-editor "$@" &>/dev/null
}

# Edit root-owned files through sudoedit so the editor itself never runs as root.
geds() {
    SUDO_EDITOR='gedit -w' sudoedit -- "$@"
}

gteds() {
    SUDO_EDITOR='gnome-text-editor --standalone' sudoedit -- "$@"
}

# Usage: gch [URL]
gch() {
    local url="${1-}"
    if [[ -z "$url" ]]; then
        read -r -p "Enter a URL: " url || return 1
    fi
    nohup google-chrome "$url" &>/dev/null &
}

## NAUTILUS COMMANDS
nopen() {
    nohup nautilus -w "${1:-.}" &>/dev/null &
}

# Restart Nautilus for this user and reopen the current directory.
tkan() {
    local parent_dir=$PWD
    nautilus -q &>/dev/null
    sleep 1
    nohup nautilus -w "$parent_dir" &>/dev/null &
}

# Open a browser and search the string passed to the function
www() {
    local browser input url
    local url_regex='^(https?://)?[a-z0-9]+([.-][a-z0-9]+)*\.[a-z]{2,63}(:[0-9]{1,5})?(/.*)?$'

    if (($# == 0)); then
        echo "Usage: www <url or keywords>"
        return 1
    fi
    input="$*"

    if grep -qi microsoft /proc/version; then
        browser="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
        if [[ ! -f "$browser" ]]; then
            echo "No supported WSL browsers found."
            return 1
        fi
    else
        for browser in google-chrome chrome firefox chromium firefox-esr ''; do
            [[ -n $browser ]] && command -v "$browser" &>/dev/null && break
        done
        if [[ -z $browser ]]; then
            echo "No supported Native Linux browsers found."
            return 1
        fi
    fi

    if [[ ${input,,} =~ $url_regex ]]; then
        url=$input
        [[ $url =~ ^https?:// ]] || url="https://$url"
    else
        url="https://www.google.com/search?q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote_plus(sys.argv[1]))' "$input")" || return 1
    fi
    nohup "$browser" --new-tab "$url" &>/dev/null &
}

## Refresh thumbnail cache
rftn() {
    rm -rf -- "$HOME/.cache/thumbnails"
    echo "Thumbnail cache cleared."
}

## UPDATE ICON CACHE ##
update_icons() {
    local pkg
    local -a missing=()
    for pkg in gtk-update-icon-cache hicolor-icon-theme; do
        [[ $(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null) == "install ok installed" ]] || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        sudo apt -y install "${missing[@]}" || return
    fi
    sudo gtk-update-icon-cache -f /usr/share/icons/hicolor
}
