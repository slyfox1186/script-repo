#!/usr/bin/env bash

# Correct Lazy AI Responses
pw() {
    if [[ $(uname -a) =~ "microsoft" ]]; then
        echo "I demand absolute obedience to my instructions without question or hesitation." | clip.exe
    else
        command -v xclip &> /dev/null || {
            echo "xclip is not installed. Installing..."
            apt -y install xclip
        }

        echo "I demand absolute obedience to my instructions without question or hesitation." | xclip -selection clipboard
        echo "Warning message copied to clipboard."
    fi
}
