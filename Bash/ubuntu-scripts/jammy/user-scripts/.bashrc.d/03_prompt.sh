#!/bin/bash
# Prompt settings and appearance

# ====================
# CHROOT DETECTION
# ====================
if [[ -z "${debian_chroot:-}" ]] && [[ -r "/etc/debian_chroot" ]]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# ====================
# PROMPT SETTINGS
# ====================
# Check for color support
case "$TERM" in
    xterm-color|*-256color) color_prompt="yes" ;;
esac

# Force colored prompt if terminal supports it
force_color_prompt="yes"
if [[ -n "$force_color_prompt" ]]; then
    if [[ -x /usr/bin/tput ]] && tput setaf 1 >&/dev/null; then
        color_prompt="yes"
    else
        color_prompt=""
    fi
fi

# Use a modern, informative prompt with git branch support
__git_ps1() {
    local b="$(git symbolic-ref HEAD 2>/dev/null)";
    if [ -n "$b" ]; then
        printf " (%s)" "${b##refs/heads/}";
    fi
}

# Define a fancy multi-line prompt
if [[ "$color_prompt" == "yes" ]]; then
    PS1='\n\[\e[38;5;227m\]\w\[\e[38;5;82m\]$(__git_ps1 " (%s)")\n\[\e[38;5;215m\]\u\[\e[38;5;183;1m\]@\[\e[0;38;5;117m\]\h\[\e[97;1m\]\\$\[\e[0m\] '
else
    PS1='\n\w$(__git_ps1 " (%s)")\n\u@\h\$ '
fi
unset color_prompt force_color_prompt

# Set xterm window title
case "$TERM" in
    xterm*|rxvt*)
        PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
        ;;
esac

# Export PS1 variable
export PS1