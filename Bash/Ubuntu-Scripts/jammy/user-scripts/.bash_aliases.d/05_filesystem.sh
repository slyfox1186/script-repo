#!/bin/bash
# Filesystem and directory navigation aliases

# Directory listing and navigation
alias ls='ls -1AhFSv --color=auto --group-directories-first'
alias ll='ls'
alias c='clear'
alias cl='clear; ls'
alias cls='clear'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias dir_size='clear; ncdu -q'

# Change directory shortcuts
alias cdaptd='pushd /etc/apt/apt.conf.d; cl'
alias cdapt='pushd /etc/apt; cl'
alias cda='pushd ~/.aria2; cl'
alias cdb='pushd /bin; cl'
alias cddns='pushd /etc/dnsmasq.d; cl'
alias cdd='pushd ~/Downloads; cl'
alias cde='pushd ~/Desktop; cl'
alias cdetc='pushd /etc; cl'
alias cdf='pushd ~/Documents; cl'
alias cdh='pushd ~; cl'
alias cdp='pushd ~/Pictures; cl'
alias cdpi='pushd /etc/pihole; cl'
alias cdr='pushd /; cl'
alias cds='pushd ~/scripts; cl'
alias cdtmp='pushd ~/tmp; cl'
alias cdt='pushd ~/tmp; cl'
alias cdb1='pushd /usr/bin; cl'
alias cdb2='pushd /usr/local/bin; cl'
alias cdv='pushd ~/Videos; cl'
alias cd.='cd ..; cl'
alias cd..='cd ..; cl'

# Directory and file creation
alias md='mkdir -p'
alias mkdir='mkdir -p'

# Path display
alias psp='clear; echo -e $PATH//:/\\n'

# Clipboard utilities
alias v='xclip -o'