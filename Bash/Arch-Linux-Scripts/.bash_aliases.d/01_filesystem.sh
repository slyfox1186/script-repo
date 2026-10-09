#!/usr/bin/env bash
# Filesystem and directory navigation aliases

# Directory listing and navigation
alias ls='ls -1AhFSv --color=always --group-directories-first'
alias c='clear'
alias cl='c; ls'
alias cls='c'
alias dir='dir --color=always'
alias vdir='vdir --color=always'
alias dir_size='clear; ncdu -q'

# Change directory shortcuts
alias cdd='pushd ~/Downloads/; cl'
alias cde='pushd ~/Desktop/; cl'
alias cdetc='pushd /etc/; cl'
alias cdf='pushd ~/Documents/; cl'
alias cdp='pushd ~/Pictures/; cl'
alias cdt='pushd ~/tmp/; cl'
alias cdv='pushd ~/Videos/; cl'
alias cd.='cd ..'
alias cd..='cd ..'
alias cd...='cd ..'
alias cd2='cd ../..'
alias cd3='cd ../../..'
alias cd4='cd ../../../..'
alias cd5='cd ../../../../..'

# Directory and file creation
alias mkdir='mkdir -p'
