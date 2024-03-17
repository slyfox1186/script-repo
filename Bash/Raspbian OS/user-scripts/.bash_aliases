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

# reboot/halt/shutdown
alias halt='sudo halt'
alias poweroff='sudo poweroff'
alias reboot='sudo reboot'
alias rebootefi='sudo systemctl reboot --firmware-setup'
alias shutdown='sudo shutdown -h now'

# enable color support of ls and also add handy aliases
if [ -x '/usr/bin/dircolors' ]; then
    test -r "$HOME/.dircolors" && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
        # file navigation
        alias ls='ls -1AhFSv --color=always --group-directories-first'
        # grep commands
        alias grep='grep --color=always'
fi

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

alias ll='ls'
alias c='clear'
alias cl='clear; ls'
alias cls='clear'
alias dir='dir --color=always'
alias vdir='vdir --color=always'

# apt commands
alias install='clear; apt -y install'
alias remove='clear; apt remove'
alias search='clear; apt search'

# fix missing gnu keys used to update packages
alias fixkey='clear; apt-key adv --keyserver keyserver.ubuntu.com --recv-keys'

# dos2unix
alias d2u='dos2unix'

# mkdir aliases
alias md='mkdir -p'
alias mkdir='mkdir -p'

# mount commands
alias mount='mount | column -t'

# get system time
alias time='date +%r | cut -d '\'' '\'' -f1-2 | egrep '\''^.*$'\'''

# netplan commands
alias netplan_update='netplan apply; clear; ip -4 -c -d -h address'

# nameserver commands
alias nss='clear; systemd-resolve --status'

# clipboard
alias clip='xclip -sel clip'
alias paste='xclip -o'

# nano [ /home/jman ]
alias nba='nano ~/.bash_aliases; cl'
alias nbf='nano ~/.bash_functions; cl'
alias nbrc='nano ~/.bashrc; cl'
alias npro='nano ~/.profile; cl'
# nano [ /etc ]
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
# nano [ /usr ]
alias nlang='sudo nano /usr/share/gtksourceview-*/language-specs/sh.lang; cl'

# change directory
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

# change directory fast commands
alias cd.='cd ..; cl'
alias cd..='cd ..; cl'

# cat [ /home/jman ]
alias cba='cat ~/.bash_aliases; cl'
alias cbf='cat ~/.bash_functions; cl'
alias cbrc='cat ~/.bashrc; cl'
alias cpro='cat ~/.profile; cl'
# cat [ /etc ]
alias capt='clear; cat /etc/apt/sources.list'
alias cbasrc='clear; cat /etc/bash.bashrc'
alias ccat='clear; cat /etc/catrc'
alias ccron='clear; cat /etc/crontab'
alias cddc='clear; cat /etc/ddclient.conf'
alias chosts='clear; cat /etc/hosts'
alias clangs='clear; cat /usr/share/gtksourceview-*/language-specs/sh.lang'
alias clist='clear; cat /etc/apt/sources.list'
alias clogin='clear; cat /etc/gdm*/daemon.conf'
alias cmid='clear; cat /etc/machine-id' # get the machine-id number
alias cnano='clear; cat /etc/nanorc'
alias cnet='clear; cat /etc/network/interfaces'
alias cssh='clear; cat /etc/ssh/sshd_config'
alias csudo='clear; cat /etc/sudoers'

# ssh
alias nsshd='clear; nano /etc/ssh/sshd_config; cl'
alias nsshdk='clear; nano ~/.ssh/authorized_keys; cl'
alias sshoff='clear; service ssh stop; service --status-all'
alias sshon='clear; service ssh start; service --status-all'
alias sshq='clear; systemctl status ssh.service && service --status-all'
alias sshr='clear; service ssh restart && service sshd restart && service --status-all'

# ping 5 times or fast ping
alias ping='clear; ping -c 10 -s 3'

# show open ports
alias ports='clear; netstat -tulanp'
alias piports='clear; netstat -nltup | grep '\''Proto\|:53 \|:67 \|:80 \|:100 \|:41'\'''

# list internet interfaces
alias pse='clear; ip -4 -c -d -h address'
alias pse1='clear; ifconfig -s | egrep '\''^(e|l|w|i).*$'\'''
alias pse2='clear; lshw -class network'
alias pse3='clear; dnstop -4QRl 5 eth0'
alias pse4='clear; tcpdump -c 50 -i eth0'

# cpu commands
alias top='clear; iftop -i eth0 -B -F net/mask -P'
alias pscpu='clear; lscpu'
alias pscpu1='clear; ps auxf | head -c -0'

# memory commands
alias psmem='clear; free -m -l -t'
alias psmem1='clear; inxi -FxzR | egrep '\''^.*RAID:.*|^.*System:.*|^.*Memory:.*$'\'''

# gpu commands
alias psgpu='clear; lspci | grep -i vga'

# get system architechture
alias psarch='clear; dpkg --print-architecture'

# USB
alias psusb='lsblk -a | sort > ~/usb.txt'

# get system architechture
alias showarch='dpkg --print-architecture'

# ddclient commands
alias ddcu='ddclient -daemon=0 -debug -verbose -noquiet'

# find and kill process by pid or name
alias tk='sudo kill -9'

# SNAP COMMANDS
alias snap_on='snap set core snapshots.automatic.retention=yes' # turn on snap automatic snapshots
alias snap_off='snap set core snapshots.automatic.retention=no' # turn off snap automatic snapshots

# BAT (COLORIZED CAT COMMAND ALTERNATIVE)
alias cat='clear; /usr/bin/batcat -p' # remove line numbers
alias catn='clear; /usr/bin/batcat'   # show line numbers

# temporary commands... delete when done
alias runff='bash ~/tmp/test.sh --build --enable-gpl-and-non-free --latest'

# nordvpn commands
alias nc='nordvpn connect United_States Atlanta'
alias nqc='nordvpn connect'
alias nd='nordvpn disconnect'

# watch commands (system monitoring)
alias wmem='clear; watch free -m'
alias wtemp='clear; watch sensors'
alias wgpu='clear; watch ndivia-smi'

# FIX GPG KEY ERRORS DURING APT UPDATE THAT SHOWS THEY ARE "DEPRECIATED"
alias fix_gpg='sudo cp /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d'

# WATCH COMMAND
alias cwatch='watch -n0.5 ccache --print-stats'

# GET KERNEL VERSION
alias kv='cat '\''/proc/version'\'' | grep -Eo '\''([0-9\.\-]+-generic)'\'''

## SHOW THE TOP 10 PROCESSES BY CPU RESOURCE CONSUMPTION
alias cpu_leach='clear; ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n10'

## GET LIST OF ALL DIRECTORY SIZES
alias dir_size='clear; ncdu -q'

# PIHOLE
alias pis='clear; pihole status'
alias pir='clear; pihole restartdns'
alias pit='clear; pihole -t'
alias piu='clear; pihole -up'
alias piq='clear; pihole -q'
alias pig='clear; pihole -g'
alias pifix='clear; pihole -r'

# DIRECTORY SIZE
alias dirsize='clear; du -sh'

# SQUID
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
