#!/usr/bin/env bash
# Network-related aliases

# SSH control (Arch uses systemd; the unit is sshd.service)
alias nsshd='clear; sudo nano /etc/ssh/sshd_config; cl'
alias nsshdk='clear; nano ~/.ssh/authorized_keys; cl'
alias sshoff='clear; sudo systemctl stop sshd; systemctl status sshd --no-pager'
alias sshon='clear; sudo systemctl start sshd; systemctl status sshd --no-pager'
alias sshq='clear; systemctl status sshd --no-pager'
alias sshr='clear; sudo systemctl restart sshd; systemctl status sshd --no-pager'

# Network status and monitoring
alias ping='clear; ping -c 10 -s 3'
alias ports='clear; sudo ss -tulanp'
alias piports="clear; sudo ss -nltup | grep ':53 \|:67 \|:80 \|:100 \|:41'"
alias pse='clear; ip -4 -c -d -h address'
alias pse1='clear; ip -br address'
alias nss='clear; resolvectl status'

# DDNS client
alias ddcu='ddclient -daemon=0 -debug -verbose -noquiet'

# NordVPN
alias nc='nordvpn connect United_States Atlanta'
alias nqc='nordvpn connect'
alias nd='nordvpn disconnect'

# Gravity Sync
alias gsyncup='clear; gravity-sync update'
alias gsync='clear; nano /etc/gravity-sync/gravity-sync.conf'

# Virtualization
alias svm='clear; sudo virt-manager'
