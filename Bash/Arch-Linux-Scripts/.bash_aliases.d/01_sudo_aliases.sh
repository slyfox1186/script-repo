#!/usr/bin/env bash
# Sudo command aliases
#
# Only commands that genuinely require root are aliased to their sudo form.
# Everyday read/inspect tools (cat, grep, find, kill, ln, chmod, chown, wget,
# ...) are intentionally NOT aliased to sudo: doing so forces needless password
# prompts, produces root-owned output, and silently rewrites other aliases that
# chain through them (e.g. chosts, cmirror, long_files). Prefix sudo explicitly
# when you actually need it.

# Package / system management (need root)
alias pacman='sudo pacman'
alias ldconfig='sudo ldconfig'
alias systemctl='sudo systemctl'
alias update-grub='sudo grub-mkconfig -o /boot/grub/grub.cfg'

# Mounting (needs root)
alias mount='sudo mount'
alias umount='sudo umount'

# User / auth management (need root)
alias passwd='sudo passwd'
alias useradd='sudo useradd'
alias usermod='sudo usermod'

# Kernel / diagnostics (dmesg is restricted to root on this kernel)
alias dmesg='sudo dmesg'

# Services / daemons (need root)
alias ddclient='sudo ddclient'
alias nordvpn='sudo nordvpn'
alias timeshift='sudo timeshift'
alias ufw='sudo ufw'

# Containers (default to root socket)
alias docker='sudo docker'
alias docker-compose='sudo docker-compose'
