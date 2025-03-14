#!/bin/bash
# Shell options and behavior settings

# ====================
# SHELL OPTIONS
# ====================
# Check window size and update LINES/COLUMNS
shopt -s checkwinsize
# Enable ** pattern in pathname expansion
shopt -s globstar
# Include dotfiles in pattern matching
shopt -s dotglob
# Enable extended pattern matching
shopt -s extglob

# ====================
# TAB COMPLETION SETTINGS
# ====================
# Make tab-completion case-insensitive
bind "set completion-ignore-case on"
# List all matches when multiple completions possible
bind "set show-all-if-ambiguous on"
# Match hidden files without needing the leading dot
bind "set match-hidden-files on"
# Show tab completion options on first tab press
bind "set show-all-if-ambiguous on"

# ====================
# PERFORMANCE TWEAKS
# ====================
# Disable flow control (Ctrl+S/Ctrl+Q) to prevent terminal freezing
stty -ixon