#!/usr/bin/env bash
# Editor-related aliases

# Nano editor shortcuts
# The monolithic ~/.bash_aliases and ~/.bash_functions are no longer sourced;
# the active config lives in the modular ~/.bash_{aliases,functions}.d/*.sh sets.
alias nba='c; nano ~/.bash_aliases.d/*.sh; cl'
alias nbf='c; nano ~/.bash_functions.d/*.sh; cl'
alias nbrc='c; nano ~/.bashrc; cl'
alias npro='c; nano ~/.profile; cl'
alias nnano='c; sudo nano /etc/nanorc; cl'
alias nssh='c; sudo nano /etc/ssh/sshd_config; cl'
alias nsudo='c; sudo nano /etc/sudoers; cl'

# Crontab
alias crontab='c; sudo crontab -e; cl'

# Gnome text editor shortcuts
alias g='gnome-text-editor'
alias gba='g ~/.bash_aliases.d/*.sh; cl'
alias gbf='g ~/.bash_functions.d/*.sh; cl'
alias gbrc='g ~/.bashrc; cl'
alias gpro='g ~/.profile; cl'
alias gssh='sudo g /etc/ssh/sshd_config; cl'
alias gsudo='sudo g /etc/sudoers; cl'

# Cat command shortcuts (clear first, then show the file and leave it on screen;
# a trailing '; cl' would clear+ls and instantly wipe the cat output)
alias cba='c; cat ~/.bash_aliases.d/*.sh'
alias cbf='c; cat ~/.bash_functions.d/*.sh'
alias cbrc='c; cat ~/.bashrc'
alias cpro='c; cat ~/.profile'
alias cbasrc='c; cat /etc/bash.bashrc'
alias cssh='c; cat /etc/ssh/sshd_config'
alias csudo='c; sudo cat /etc/sudoers'
