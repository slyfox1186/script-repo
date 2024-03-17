alias alien='sudo alien'
alias apt-get='sudo apt-get'
alias apt='sudo apt'
alias aptitude='sudo aptitude'
alias apt-key='sudo apt-key'
alias apt='sudo apt'
alias aria2c='sudo aria2c'
alias cat='sudo cat'
alias chmod='sudo chmod'
alias chown='sudo chown'
alias crontab='sudo crontab'
alias ddclient='sudo ddclient'
alias dmesg='sudo dmesg'
alias docker-compose='sudo docker-compose'
alias docker='sudo docker'
alias docker-compose='sudo docker-compose'
alias dos2unix='sudo dos2unix'
alias dpkg='sudo dpkg'
alias egrep='sudo egrep'
alias fgrep='sudo fgrep'
alias find='sudo find'
alias grep='sudo grep'
alias killall='sudo killall'
alias kill='sudo kill'
alias ldconfig='sudo ldconfig'
alias ln='sudo ln'
alias mainline='sudo mainline'
alias mount='sudo mount'
alias netplan='sudo netplan'
alias nordvpn='sudo nordvpn'
alias passwd='sudo passwd'
alias rpm='sudo rpm'
alias service='sudo service'
alias snap='sudo snap'
alias systemctl='sudo systemctl'
alias timeshift='sudo timeshift'
alias ufw='sudo ufw'
alias umount='sudo umount'
alias unzip='sudo unzip'
alias update-grub='sudo update-grub'
alias useradd='sudo useradd'
alias usermod='sudo usermod'
alias wget='sudo wget'

alias halt='sudo halt'
alias logout='gnome-session-quit --no-prompt'
alias poweroff='sudo poweroff'
alias reboot='sudo reboot'
alias shutdown='sudo shutdown -h now'
alias reboot-uefi='sudo systemctl reboot --firmware-setup'

if [ -x '/usr/bin/dircolors' ]; then
    test -r "$HOME/.dircolors" && eval "$(dircolors -b "$HOME"/.dircolors)" || eval "$(dircolors -b)"
        alias ls='ls -1AhFSv --color=auto --group-directories-first'
        alias grep='grep --color=auto'
        alias egrep='grep --color=auto -E'
        alias fgrep='grep --color=auto -F'
fi

export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

alias ll='ls'
alias c='clear'
alias cl='clear; ls'
alias cls='clear'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'

alias install='clear; apt -y install'
alias installr='clear; apt -y --reinstall install'
alias remove='clear; apt remove'
alias search='clear; apt search'

alias fixkey='clear; apt-key adv --keyserver keyserver.ubuntu.com --recv-keys'

alias d2u='dos2unix'

alias md='mkdir -p'
alias mkdir='mkdir -p'

alias psp='clear; echo -e $PATH//:/\\n'

alias crontab='crontab -e'

alias netplan_update='netplan apply; clear; ip -4 -c -d -h address'

alias gsyncup='clear; gravity-sync update'
alias gsync='clear; nano /etc/gravity-sync/gravity-sync.conf'

alias nss='clear; systemd-resolve --status'

alias nba='nano ~/.bash_aliases; cl'
alias nbf='nano ~/.bash_functions; cl'
alias nbrc='nano ~/.bashrc; cl'
alias npro='nano ~/.profile; cl'
alias napt='sudo nano /etc/apt/apt.conf; cl'
alias ncron='sudo nano /etc/crontab; cl'
alias nddc='sudo nano /etc/ddclient.conf; cl'
alias nhosts='sudo nano /etc/hosts; cl'
alias nlist='sudo nano /etc/apt/sources.list; cl'
alias nlogin='sudo nano /etc/gdm*/daemon.conf; cl'
alias nnano='sudo nano /etc/nanorc; cl'
alias nnet='sudo nano /etc/network/interfaces; cl'
alias nssh='sudo nano /etc/ssh/sshd_config; cl'
alias nsudo='sudo nano /etc/sudoers; cl'
alias nlang='sudo nano /usr/share/gtksourceview-*/language-specs/sh.lang; cl'

alias gba='gnome-text-editor ~/.bash_aliases; cl'
alias gbf='gnome-text-editor ~/.bash_functions; cl'
alias gbrc='gnome-text-editor ~/.bashrc; cl'
alias gpro='gnome-text-editor ~/.profile; cl'
alias g='gnome-text-editor'
alias gapt='sudo gnome-text-editor /etc/apt/apt.conf; cl'
alias gcron='sudo gnome-text-editor /etc/crontab; cl'
alias gddc='sudo gnome-text-editor /etc/ddclient.conf; cl'
alias ghosts='sudo gnome-text-editor /etc/hosts; cl'
alias glist='sudo gnome-text-editor /etc/apt/sources.list; cl'
alias glogin='sudo gnome-text-editor /etc/gdm*/daemon.conf; cl'
alias ggnome-text-editor='sudo gnome-text-editor /etc/gnome-text-editorrc; cl'
alias gnet='sudo gnome-text-editor /etc/network/interfaces; cl'
alias gssh='sudo gnome-text-editor /etc/ssh/sshd_config; cl'
alias gsudo='sudo gnome-text-editor /etc/sudoers; cl'
alias glang='sudo gnome-text-editor /usr/share/gtksourceview-*/language-specs/sh.lang; cl'

alias cdaptd='pushd /etc/apt/apt.conf.d; cl'
alias cdapt='pushd /etc/apt; cl'
alias cda='pushd ~/.aria2 ; cl'
alias cdb='pushd /bin; cl'
alias cddns='pushd /etc/dnsmasq.d; cl'
alias cdd='pushd ~/Downloads ; cl'
alias cde='pushd ~/Desktop ; cl'
alias cdetc='pushd /etc; cl'
alias cdf='pushd ~/Documents ; cl'
alias cdh='pushd ~; cl'
alias cdp='pushd ~/Pictures ; cl'
alias cdpi='pushd /etc/pihole; cl'
alias cdr='pushd /; cl'
alias cds='pushd ~/scripts; cl'
alias cdtmp='pushd ~/tmp ; cl'
alias cdt='pushd ~/tmp; cl'
alias cdb1='pushd /usr/bin; cl'
alias cdb2='pushd /usr/local/bin; cl'
alias cdv='pushd ~/Videos ; cl'

alias cd.='cd ..; cl'
alias cd..='cd ..; cl'

alias cba='cat ~/.bash_aliases; cl'
alias cbf='cat ~/.bash_functions; cl'
alias cbrc='cat ~/.bashrc; cl'
alias cpro='cat ~/.profile; cl'
alias capt='clear; cat /etc/apt/sources.list'
alias cbasrc='clear; cat /etc/bash.bashrc'
alias ccat='clear; cat /etc/catrc'
alias ccron='clear; cat /etc/crontab'
alias cddc='clear; cat /etc/ddclient.conf'
alias chosts='clear; cat /etc/hosts'
alias clangs='clear; cat /usr/share/gtksourceview-*/language-specs/sh.lang'
alias clist='clear; cat /etc/apt/sources.list'
alias clogin='clear; cat /etc/gdm*/daemon.conf'
alias cnano='clear; cat /etc/nanorc'
alias cnet='clear; cat /etc/network/interfaces'
alias cssh='clear; cat /etc/ssh/sshd_config'
alias csudo='clear; cat /etc/sudoers'

alias nsshd='clear; nano /etc/ssh/sshd_config; cl'
alias nsshdk='clear; nano ~/.ssh/authorized_keys; cl'
alias sshoff='clear; service ssh stop; service --status-all'
alias sshon='clear; service ssh start; service --status-all'
alias sshq='clear; systemctl status ssh.service && service --status-all'
alias sshr='clear; service ssh restart && service sshd restart && service --status-all'

alias ping='clear; ping -c 10 -s 3'

alias ports='clear; netstat -tulanp'
alias piports="clear; netstat -nltup | grep 'Proto\|:53 \|:67 \|:80 \|:100 \|:41'"

alias pse='clear; ip -4 -c -d -h address'
alias pse1="clear; ifconfig -s | egrep '^(e|l|w|i).*$'"
alias pse2='clear; lshw -class network'
alias pse3='clear; dnstop -4QRl 5 eth0'
alias pse4='clear; tcpdump -c 50 -i eth0'

alias top='clear; iftop -i eth0 -B -F net/mask -P'
alias pscpu='clear; lscpu'
alias pscpu1='clear; ps auxf | head -c -0'

alias psmem='clear; free -m -l -t'
alias psmem1="clear; inxi -FxzR | egrep '^.*RAID:.*|^.*System:.*|^.*Memory:.*$'"

alias psgpu='clear; lspci | grep -i vga'

alias psarch='clear; dpkg --print-architecture'

alias psusb='lsblk -a | sort > ~/usb.txt'

alias showarch='dpkg --print-architecture'

alias ddcu='ddclient -daemon=0 -debug -verbose -noquiet'

alias tk='sudo kill -9'



alias runff='bash ~/tmp/test.sh --build --enable-gpl-and-non-free --latest'

alias nc='nordvpn connect United_States Atlanta'
alias nqc='nordvpn connect'
alias nd='nordvpn disconnect'

alias cwatch='watch -n1 ccache --print-stats'
alias twatch='clear; watch -n0.5 sudo sensors -u k10temp-pci-00c3'
alias wgpu='clear; watch ndivia-smi'
alias wmem='clear; watch free -m'
alias wtemp='clear; watch sensors'

alias uver="clear; lsb_release -d | grep -Eo 'Ubuntu [0-9\.]+.*$'"

alias fix_gpg='sudo cp /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d'

alias kv='cat /proc/version | grep -Eo "([0-9\.\-]+-generic)"'

alias fft='clear; ./repo.sh'
alias ffc='clear; ./configure --help'

alias tsb='clear; timeshift --create'

alias show_gcc='clear; gcc-12 -pipe -fno-plt -march=native -E -v - </dev/null 2>&1 | grep cc1'

alias svm='clear; sudo virt-manager'

alias cpu_leach='clear; ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -10'

alias dir_size='clear; ncdu -q'

alias wine32='env WINEARCH=win32 WINEPREFIX=~/.wine32 wine $*'

alias tk='kill -9'
alias tka='killall -9'

alias ml='mainline'
alias mll='mainline list | sort -h'
alias mli='mainline install'
alias mlu='mainline uninstall'

alias sgc='sudo grub-customizer'

alias tkpid='clear; lsof +D ./ | awk '\''{print $2}'\'' | tail -n +2 | xargs -I{} sudo kill -9 {}'

alias v='xclip -o'

alias dcp='clear; docker-compose pull' 
alias dci='clear; docker-compose up -d'
alias dstart='clear; docker start'
alias dstop='clear; docker stop'
alias dr='clear; docker rm'
alias dl='clear; docker logs'
alias dps='clear; docker ps'
alias dpsa='clear; docker ps -a'
