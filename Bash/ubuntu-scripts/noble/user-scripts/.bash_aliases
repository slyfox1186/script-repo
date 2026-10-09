if [[ -x /usr/bin/dircolors ]]; then
    if [[ -r "$HOME/.dircolors" ]]; then
        eval "$(dircolors -b "$HOME/.dircolors")"
    else
        eval "$(dircolors -b)"
    fi
    alias ls='ls -1AhFSv --color=always --group-directories-first'
    alias grep='grep --color=always'
    alias egrep='grep --color=always -E'
    alias fgrep='grep --color=always -F'
fi

GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export GCC_COLORS

alias cl='clear; ls'
alias cls='clear'
alias dir='dir --color=always'
alias vdir='vdir --color=always'

alias install='apt -y install'

alias nba='nano ~/.bash_aliases; cl'
alias nbf='nano ~/.bash_functions; cl'
alias nbrc='nano ~/.bashrc; cl'
alias npro='nano ~/.profile; cl'

alias g='gnome-text-editor'
alias gba='g ~/.bash_aliases; cl'
alias gbf='g ~/.bash_functions; cl'
alias gbrc='g ~/.bashrc; cl'
alias gpro='g ~/.profile; cl'

alias cd..='cd ..; cl'
alias cdd='pushd ~/Downloads; cl'
alias cde='pushd ~/Desktop; cl'
alias cdg='pushd ~/tmp/thatsgemma/; cl'
alias cdt='pushd ~/tmp; cl'
alias cdq='pushd ~/tmp/local_llm_projects/qwen3.8-gguf && cl'

alias cba='cat ~/.bash_aliases'
alias cbf='cat ~/.bash_functions'
alias cbrc='cat ~/.bashrc'
alias cpro='cat ~/.profile'

alias wgpu='watch nvidia-smi'
alias wmem='watch free -m'
alias wtemp='watch sensors'

alias sgc='sudo grub-customizer'

alias killall='sudo killall -9'
alias kill='sudo kill -9'

alias logout='gnome-session-quit --no-prompt'
alias reboot='sudo reboot'
alias shutdown='sudo shutdown -h now'
alias rebootu='sudo systemctl reboot --firmware-setup'
