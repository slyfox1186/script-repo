#!/usr/bin/env bash
# System control aliases

# System shutdown/reboot commands
alias logout='gnome-session-quit --no-prompt'
alias poweroff='sudo systemctl poweroff -i'
alias reboot='sudo systemctl reboot -i'
alias shutdown='sudo shutdown -h now'
alias rebootu='sudo systemctl reboot --firmware-setup'

# Process and resource monitoring
alias kill='sudo kill -9'
alias killall='sudo killall -9'

# Temperature and system monitoring
alias wgpu='watch nvidia-smi'
alias wmem='watch free -m'
alias wtemp='watch sensors'

# Grub customizer
alias gc='sudo grub-customizer'
