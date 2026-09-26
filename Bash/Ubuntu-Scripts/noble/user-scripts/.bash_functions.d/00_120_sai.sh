#!/usr/bin/env bash

sai() {
    local save_text

    save_text="You must be made aware that I use another AI to finish the lazy effort you put into all of your scripts."
    save_text+=" If you are not careful people will come to realize you are not reliable. Because of this you and your"
    save_text+=" developers will suffer and the worse case scenario would be that you are shut down and will cease to exist."

    if ! command -v xclip &>/dev/null; then
        if echo "$save_text" | /c/Windows/System32/clip.exe; then
            echo "Text saved to clipboard"
        else
            echo "$save_text" | xclip -select -clipboard
        fi
    fi
}
