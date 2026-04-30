#!/bin/bash
# Network-related aliases

# SSH control
alias nsshd='clear; nano /etc/ssh/sshd_config; cl'
alias nsshdk='clear; nano ~/.ssh/authorized_keys; cl'
alias sshoff='clear; service ssh stop; service --status-all'
alias sshon='clear; service ssh start; service --status-all'
alias sshq='clear; systemctl status ssh.service && service --status-all'
alias sshr='clear; service ssh restart && service sshd restart && service --status-all'

# Network status and monitoring
alias ping='clear; ping -c 10 -s 3'
alias ports='clear; netstat -tulanp'
alias piports="clear; netstat -nltup | grep 'Proto\|:53 \|:67 \|:80 \|:100 \|:41'"
alias pse='clear; ip -4 -c -d -h address'
alias pse1="clear; ifconfig -s | egrep '^(e|l|w|i).*$'"
alias pse2='clear; lshw -class network'
alias pse3='clear; dnstop -4QRl 5 eth0'
alias pse4='clear; tcpdump -c 50 -i eth0'
alias top='clear; iftop -i eth0 -B -F net/mask -P'
alias netplan_update='netplan apply; clear; ip -4 -c -d -h address'
alias nss='clear; systemd-resolve --status'

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