#!/usr/bin/env bash

gc() {
    local url
    if [[ -n "$1" ]]; then
        nohup google-chrome "$1"
    else
        read -r -p "Enter a URL: " url
        nohup google-chrome "$url" 2>&1
    fi
}
