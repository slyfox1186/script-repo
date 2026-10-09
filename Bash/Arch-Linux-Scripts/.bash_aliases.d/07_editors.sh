#!/usr/bin/env bash
# Editor-related aliases

# Nano editor shortcuts
# The monolithic ~/.bash_aliases and ~/.bash_functions are no longer sourced;
# the active config lives in the modular ~/.bash_{aliases,functions}.d/*.sh sets.
alias nba='nano ~/.bash_aliases.d/*.sh; cl'
alias nbf='nano ~/.bash_functions.d/*.sh; cl'
alias nbrc='nano ~/.bashrc; cl'
alias npro='nano ~/.profile; cl'
alias npac='sudo nano /etc/pacman.conf; cl'
alias ncron='sudo nano /etc/crontab; cl'
alias nddc='sudo nano /etc/ddclient.conf; cl'
alias nhosts='sudo nano /etc/hosts; cl'
alias nmirror='sudo nano /etc/pacman.d/mirrorlist; cl'
alias nlogin='sudo nano /etc/gdm/custom.conf; cl'
alias nnano='sudo nano /etc/nanorc; cl'
alias nnet='sudo nano /etc/systemd/network/; cl'
alias nssh='sudo nano /etc/ssh/sshd_config; cl'
alias nsudo='sudo nano /etc/sudoers; cl'

# Crontab
alias crontab='crontab -e'

# Gnome text editor shortcuts
alias gba='gnome-text-editor ~/.bash_aliases.d/*.sh; cl'
alias gbf='gnome-text-editor ~/.bash_functions.d/*.sh; cl'
alias gbrc='gnome-text-editor ~/.bashrc; cl'
alias gpro='gnome-text-editor ~/.profile; cl'
alias g='gnome-text-editor'
alias gpac='sudo gnome-text-editor /etc/pacman.conf; cl'
alias gcron='sudo gnome-text-editor /etc/crontab; cl'
alias gddc='sudo gnome-text-editor /etc/ddclient.conf; cl'
alias ghosts='sudo gnome-text-editor /etc/hosts; cl'
alias gmirror='sudo gnome-text-editor /etc/pacman.d/mirrorlist; cl'
alias glogin='sudo gnome-text-editor /etc/gdm/custom.conf; cl'
alias gnet='sudo gnome-text-editor /etc/systemd/network/; cl'
alias gssh='sudo gnome-text-editor /etc/ssh/sshd_config; cl'
alias gsudo='sudo gnome-text-editor /etc/sudoers; cl'

# Cat command shortcuts (clear first, then show the file and leave it on screen;
# a trailing '; cl' would clear+ls and instantly wipe the cat output)
alias cba='clear; cat ~/.bash_aliases.d/*.sh'
alias cbf='clear; cat ~/.bash_functions.d/*.sh'
alias cbrc='clear; cat ~/.bashrc'
alias cpro='clear; cat ~/.profile'
alias cpac='clear; cat /etc/pacman.conf'
alias cbasrc='clear; cat /etc/bash.bashrc'
alias ccron='clear; cat /etc/crontab'
alias cddc='clear; cat /etc/ddclient.conf'
alias chosts='clear; cat /etc/hosts'
alias cmirror='clear; cat /etc/pacman.d/mirrorlist'
alias clogin='clear; cat /etc/gdm/custom.conf'
alias cnano='clear; cat /etc/nanorc'
# alias cssh='clear; cat /etc/ssh/sshd_config'
alias csudo='clear; sudo cat /etc/sudoers'
