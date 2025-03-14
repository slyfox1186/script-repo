#!/bin/bash
# System control aliases

# System shutdown/reboot commands
alias halt='sudo halt'
alias logout='gnome-session-quit --no-prompt'
alias poweroff='sudo poweroff'
alias reboot='sudo reboot'
alias shutdown='sudo shutdown -h now'
alias reboot-uefi='sudo systemctl reboot --firmware-setup'

# Process and resource monitoring
alias tk='kill -9'
alias tka='killall -9'
alias tkpid='clear; lsof +D ./ | awk '\''{print $2}'\'' | tail -n +2 | xargs -I{} sudo kill -9 {}'

# Temperature and system monitoring
alias twatch='clear; watch -n0.5 sudo sensors -u k10temp-pci-00c3'
alias wgpu='clear; watch ndivia-smi'
alias wmem='clear; watch free -m'
alias wtemp='clear; watch sensors'
alias cwatch='watch -n1 ccache --print-stats'

# System info
alias pscpu='clear; lscpu'
alias pscpu1='clear; ps auxf | head -c -0'
alias psmem='clear; free -m -l -t'
alias psmem1="clear; inxi -FxzR | egrep '^.*RAID:.*|^.*System:.*|^.*Memory:.*$'"
alias psgpu='clear; lspci | grep -i vga'
alias psarch='clear; dpkg --print-architecture'
alias psusb='lsblk -a | sort > ~/usb.txt'
alias showarch='dpkg --print-architecture'
alias uver="clear; lsb_release -d | grep -Eo 'Ubuntu [0-9\.]+.*$'"
alias kv='cat /proc/version | grep -Eo "([0-9\.\-]+-generic)"'
alias cpu_leach='clear; ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -10'

# Timeshift
alias tsb='clear; timeshift --create'

# Grub customizer
alias sgc='sudo grub-customizer'