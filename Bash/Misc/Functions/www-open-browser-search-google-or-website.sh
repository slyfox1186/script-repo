#!/usr/bin/env bash

# Open a browser and search the string passed to the function

www() {
    local browser input keyword url urlRegex
    if [ "$#" -eq 0 ]; then
        echo "Usage: www <url or keywords>"
        exit 1
    fi

    # Regex to check if the input is a valid URL
    urlRegex='^(https?://)?[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(/.*)?$'

    # Join all arguments to form the input
    input="${*}"

    # Check if the system is WSL and set the appropriate browser executable
    if [[ $(grep -i "microsoft" /proc/version) ]]; then
        browser="/c/Program Files/Google/Chrome Beta/Application/chrome.exe"
        if [[ ! -f "$browser" ]]; then
            echo "No supported WSL browsers found."
            return 1
        fi
    else
        if command -v chrome &>/dev/null; then
            browser="chrome"
        elif command -v firefox &>/dev/null; then
            browser="firefox"
        elif command -v chromium &>/dev/null; then
            browser="chromium"
        elif command -v firefox-esr &>/dev/null; then
            browser="firefox-esr"
        else
            echo "No supported Native Linux browsers found."
            return 1
        fi
    fi

    # Determine if input is a URL or a search query
    if [[ $input =~ $urlRegex ]]; then
        # If it is a URL, open it directly
        url=$input
        # Ensure the URL starts with http:// or https://
        [[ $url =~ ^https?:// ]] || url="http://$url"
        "$browser" --new-tab "$url"
    else
        # If it is not a URL, search Google
        keyword="${input// /+}"
        "$browser" --new-tab "https://www.google.com/search?q=$keyword"
    fi
}

# Example search
www how to cook rice
www yahoo.com
www https://new.reddit.com/r/bashonubuntuonwindows/
