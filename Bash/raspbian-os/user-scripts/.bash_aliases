alias alien='sudo alien'
alias apt-get='sudo apt-get'
alias apt-key='sudo apt-key'
alias apt='sudo apt'
alias aptitude='sudo aptitude'
alias cat='sudo cat'
alias crontab='sudo crontab'
alias ddclient='sudo ddclient'
alias dmesg='sudo dmesg'
alias docker-compose='sudo docker-compose'
alias docker='sudo docker'
alias dos2unix='sudo dos2unix'
alias dpkg='sudo dpkg'
alias find='sudo find'
alias grep='sudo grep'
alias ifdown='sudo ifdown'
alias ifup='sudo ifup'
alias kill='sudo kill'
alias killall='sudo killall'
alias ldconfig='sudo ldconfig'
alias ln='sudo ln'
alias mainline='sudo mainline'
alias mount='sudo mount'
alias netplan='sudo netplan'
alias nordvpn='sudo nordvpn'
alias passwd='sudo passwd'
alias pihole='sudo pihole'
alias rpm='sudo rpm'
alias service='sudo service'
alias snap='sudo snap'
alias systemctl='sudo systemctl'
alias tail='sudo tail'
alias ufw='sudo ufw'
alias umount='sudo umount'
alias unzip='sudo unzip'
alias update-grub='sudo update-grub'
alias useradd='sudo useradd'
alias usermod='sudo usermod'

alias halt='sudo halt'
alias poweroff='sudo poweroff'
alias reboot='sudo reboot'
alias rebootefi='sudo systemctl reboot --firmware-setup'
alias shutdown='sudo shutdown -h now'

if [ -x '/usr/bin/dircolors' ]; then
    test -r "$HOME/.dircolors" && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
        alias ls='ls -1AhFSv --color=always --group-directories-first'
        alias grep='grep --color=always'
fi

export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

alias ll='ls'
alias c='clear'
alias cl='clear; ls'
alias cls='clear'
alias dir='dir --color=always'
alias vdir='vdir --color=always'

alias install='clear; apt -y install'
alias remove='clear; apt remove'
alias search='clear; apt search'

alias fixkey='clear; apt-key adv --keyserver keyserver.ubuntu.com --recv-keys'

alias d2u='dos2unix'

alias md='mkdir -p'
alias mkdir='mkdir -p'

alias mount='mount | column -t'

alias time='date +%r | cut -d '\'' '\'' -f1-2 | egrep '\''^.*$'\'''

alias netplan_update='netplan apply; clear; ip -4 -c -d -h address'

alias nss='clear; systemd-resolve --status'

alias clip='xclip -sel clip'
alias paste='xclip -o'

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
alias cdp='pushd /etc/pihole; cl'
alias cdr='pushd /; cl'
alias cds='pushd ~/scripts; cl'
alias cdt='pushd ~/tmp ; cl'
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
alias piports='clear; netstat -nltup | grep '\''Proto\|:53 \|:67 \|:80 \|:100 \|:41'\'''

alias pse='clear; ip -4 -c -d -h address'
alias pse1='clear; ifconfig -s | egrep '\''^(e|l|w|i).*$'\'''
alias pse2='clear; lshw -class network'
alias pse3='clear; dnstop -4QRl 5 eth0'
alias pse4='clear; tcpdump -c 50 -i eth0'

alias top='clear; iftop -i eth0 -B -F net/mask -P'
alias pscpu='clear; lscpu'
alias pscpu1='clear; ps auxf | head -c -0'

alias psmem='clear; free -m -l -t'
alias psmem1='clear; inxi -FxzR | egrep '\''^.*RAID:.*|^.*System:.*|^.*Memory:.*$'\'''

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

alias wmem='clear; watch free -m'
alias wtemp='clear; watch sensors'
alias wgpu='clear; watch ndivia-smi'

alias fix_gpg='sudo cp /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d'

alias cwatch='watch -n0.5 ccache --print-stats'

alias kv='cat '\''/proc/version'\'' | grep -Eo '\''([0-9\.\-]+-generic)'\'''

alias cpu_leach='clear; ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n10'

alias dir_size='clear; ncdu -q'

alias pis='clear; pihole status'
alias pir='clear; pihole restartdns'
alias pit='clear; pihole -t'
alias piu='clear; pihole -up'
alias piq='clear; pihole -q'
alias pig='clear; pihole -g'
alias pifix='clear; pihole -r'

alias dirsize='clear; du -sh'

alias sqtl='clear; tail -f '\''/var/log/squid/access.log'\'''
alias sqtc='clear; tail -f '\''/var/log/squid/cache.log'\'''
alias sqr='clear; service squid restart && service squid status'
alias sq1='clear; service squid stop && service squid status'
alias sq2='clear; service squid start && service squid status'
alias sqcs='clear; sudo du -ch '\''/var/spool/squid'\'''
alias sparse='clear; sudo squid -k parse'
alias sqcf='clear; sudo nano squid.conf && sudo squid -k parse'
alias sqs='clear; sudo service squid status'
alias cds='clear; cd /etc/squid'
alias nsq='clear; sudo nano /etc/squid/squid.conf'
