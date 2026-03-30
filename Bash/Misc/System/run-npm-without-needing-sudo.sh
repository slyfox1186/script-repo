#!/usr/bin/env bash

set -euo pipefail

NPM_GLOBAL_DIR="$HOME/.npm-global"

if ! command -v npm &>/dev/null; then
    echo "Error: npm is not installed."
    exit 1
fi

mkdir -p "$NPM_GLOBAL_DIR"

npm config set prefix "$NPM_GLOBAL_DIR"

# Determine the user's shell rc file
case "${SHELL:-/bin/bash}" in
    */zsh)  rc_file="$HOME/.zshrc" ;;
    */fish) echo "For fish shell, run: set -Ux fish_user_paths $NPM_GLOBAL_DIR/bin \$fish_user_paths"; exit 0 ;;
    *)      rc_file="$HOME/.bashrc" ;;
esac

export_line="export PATH=\"$NPM_GLOBAL_DIR/bin:\$PATH\""

if ! grep -qF "$NPM_GLOBAL_DIR/bin" "$rc_file" 2>/dev/null; then
    echo "$export_line" >> "$rc_file"
    echo "Added npm global path to $rc_file"
else
    echo "npm global path already present in $rc_file"
fi

echo "npm is configured to use $NPM_GLOBAL_DIR for global packages without sudo."
echo "Restart your terminal or run: source $rc_file"
