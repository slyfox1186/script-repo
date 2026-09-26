#!/usr/bin/env bash

box_out_banner() {
    local line message space width
    message="$*"
    width=$((${#message} + 2))
    printf -v space '%*s' "$width" ''
    line=${space// /-}

    if [[ -t 1 ]] && command -v tput &>/dev/null; then
        tput bold
        tput setaf 3
    fi
    printf ' %s\n|%s|\n| ' "$line" "$space"
    if [[ -t 1 ]] && command -v tput &>/dev/null; then
        tput setaf 4
    fi
    printf '%s' "$message"
    if [[ -t 1 ]] && command -v tput &>/dev/null; then
        tput setaf 3
    fi
    printf ' |\n|%s|\n %s\n' "$space" "$line"
    if [[ -t 1 ]] && command -v tput &>/dev/null; then
        tput sgr0
    fi
}
