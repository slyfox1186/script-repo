#!/usr/bin/env bash

# Smart package install. Replaces the old `install` alias.
# Behavior:
#   1. If pkg is installed under that exact name -> sudo pacman -S (updates if newer is available)
#   2. If pkg is provided by another installed package -> skip with notice;
#      and if the provider ends in -git, rebuild it from upstream HEAD via yay
#   3. Otherwise -> sudo pacman -S to install fresh
# This avoids the conflict error when installing names already provided by an AUR variant
# (e.g. `install imagemagick` when imagemagick-essentials-git is installed).
install() {
    clear
    if (( $# == 0 )); then
        printf 'Usage: install <package> [package...]\n' >&2
        return 1
    fi

    # Snapshot the installed-package DB once so we can scan it cheaply per target
    local installed_db
    installed_db=$(LC_ALL=C pacman -Qi 2>/dev/null) || {
        printf 'install: could not read pacman database\n' >&2
        return 1
    }

    local -a pacman_pkgs=() rebuild_pkgs=() notes=()
    local pkg provider

    for pkg in "$@"; do
        # Exact-name match. `pacman -Qq foo` also succeeds when foo is only
        # provided (not installed under that name), so grep for an exact line.
        if pacman -Qq -- "$pkg" 2>/dev/null | grep -Fxq -- "$pkg"; then
            pacman_pkgs+=("$pkg")
            continue
        fi

        provider=$(_install_find_provider "$pkg" "$installed_db")
        if [[ -n $provider ]]; then
            notes+=("'$pkg' already provided by '$provider'")
            [[ $provider == *-git ]] && rebuild_pkgs+=("$provider")
            continue
        fi

        pacman_pkgs+=("$pkg")
    done

    (( ${#notes[@]} )) && printf '%s\n' "${notes[@]}"

    local rc=0
    if (( ${#pacman_pkgs[@]} )); then
        sudo pacman -S --noconfirm -- "${pacman_pkgs[@]}" || rc=$?
    fi
    if (( ${#rebuild_pkgs[@]} )); then
        if command -v yay &>/dev/null; then
            printf 'Rebuilding AUR -git providers from upstream HEAD: %s\n' "${rebuild_pkgs[*]}"
            yay -S --rebuild --noconfirm -- "${rebuild_pkgs[@]}" || rc=$?
        else
            printf 'install: yay not found, skipping rebuild of: %s\n' "${rebuild_pkgs[*]}" >&2
            rc=1
        fi
    fi
    return $rc
}

# Helper: print the installed package whose Provides list contains $1, or nothing.
# $2 is a pre-fetched `pacman -Qi` snapshot (avoids reparsing per call).
_install_find_provider() {
    local target=$1 db=$2
    awk -v t="$target" '
        /^Name[[:space:]]*:/ { name=$NF; next }
        /^Provides[[:space:]]*:/ {
            line = $0
            sub(/^Provides[[:space:]]*:[[:space:]]*/, "", line)
            if (line == "None") next
            n = split(line, a, /[[:space:]]+/)
            for (i = 1; i <= n; i++) {
                p = a[i]
                sub(/=.*/, "", p)   # strip =version constraint
                if (p == t) { print name; exit }
            }
        }
    ' <<< "$db"
}

list() {
    local param
    if [[ -z "$1" ]]; then
        read -rp "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    pacman -Ss "$param" 2>/dev/null | grep -v '^\s' | awk '{print $1}' | sort -fuV
}

listd() {
    local param
    if [[ -z "$1" ]]; then
        read -rp "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    pacman -Ss "(${param}-dev|${param}-devel)" 2>/dev/null | grep -v '^\s' | awk '{print $1}' | sort -fuV
}
