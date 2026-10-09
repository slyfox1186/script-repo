#!/usr/bin/env bash
# Network-related aliases

# SSH control (Arch uses systemd; the unit is sshd.service)
alias nsshd='c; sudo nano /etc/ssh/sshd_config; cl'

# Network status and monitoring
alias ping='c; ping -c 10 -s 3'
alias ports='c; sudo ss -tulanp'

# NordVPN
alias vpn_on='nordvpn connect'
alias vpn_off='nordvpn disconnect'
