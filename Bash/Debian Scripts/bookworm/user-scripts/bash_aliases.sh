#!/usr/bin/env bash

clear


printf "%s\n%s\n\n" \
    'Install ~/.bash_aliases' \
    '================================='

#
# SET VARIABLES
#

file="${HOME}"/.bash_aliases

#
# CREATE FUNCTIONS
#

script_fn()
{
cat > "${file}" <<'EOF'
    alias alien='sudo alien'
    alias apt-get='sudo apt-get'
    alias apt-fast='sudo apt-fast'
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
    # alias ='sudo '

    # reboot/halt/shutdown
    alias halt='sudo halt'
    alias logout='gnome-session-quit --no-prompt'
    alias poweroff='sudo poweroff'
    alias reboot='sudo reboot'
    alias shutdown='sudo shutdown -h now'
    alias reboot-uefi='sudo systemctl reboot --firmware-setup'

    # enable color support of ls and also add handy aliases
    if [ -x '/usr/bin/dircolors' ]; then
        test -r "${HOME}/.dircolors" && eval "$(dircolors -b "${HOME}"/.dircolors)" || eval "$(dircolors -b)"
            # file navigation
            alias ls='ls -1AhFSv --color=auto --group-directories-first'
            # grep commands
            alias grep='grep --color=auto'
            alias egrep='grep --color=auto -E'
            alias fgrep='grep --color=auto -F'
    fi

    # colored GCC warnings and errors
    export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

    alias ll='ls'
    alias c='clear'
    alias cl='clear; ls'
    alias cls='clear'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'

    # apt commands
    alias install="clear; apt -y install"
    alias remove="clear; apt remove"
    alias search="clear; apt search"

    # fix missing gnu keys used to update packages
    alias fixkey='clear; apt-key adv --keyserver keyserver.ubuntu.com --recv-keys'

    # dos2unix
    alias d2u='dos2unix'

    # mkdir aliases
    alias md='mkdir -p'
    alias mkdir='mkdir -p'

    # path commands
    alias psp='clear; echo -e ${PATH//:/\\n}'

    # mount commands
    alias mount='mount |column -t'

    # get system time
    #alias time='date +%r | cut -d " " -f1-2 | egrep '^.*$''

    # crontab commands
    alias crontab='crontab -e'

    # netplan commands
    alias netplan_update='netplan apply; clear; ip -4 -c -d -h address'

    # gravity sync
    alias gsyncup='clear; gravity-sync update'
    alias gsync='clear; nano /etc/gravity-sync/gravity-sync.conf'

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

    # gted [ /home/jman ]
    alias gba='gted ~/.bash_aliases; cl'
    alias gbf='gted ~/.bash_functions; cl'
    alias gbrc='gted ~/.bashrc; cl'
    alias gpro='gted ~/.profile; cl'
    # gted [ /etc ]
    alias g='gted'
    alias gapt='sudo gted /etc/apt/apt.conf; cl'
    alias gcron='sudo gted /etc/crontab; cl'
    alias gddc='sudo gted /etc/ddclient.conf; cl'
    alias ghosts='sudo gted /etc/hosts; cl'
    alias glist='sudo gted /etc/apt/sources.list; cl'
    alias glogin='sudo gted /etc/gdm*/daemon.conf; cl'
    alias ggted='sudo gted /etc/gtedrc; cl'
    alias gnet='sudo gted /etc/network/interfaces; cl'
    alias gssh='sudo gted /etc/ssh/sshd_config; cl'
    alias gsudo='sudo gted /etc/sudoers; cl'
    # gted [ /usr ]
    alias glang='sudo gted /usr/share/gtksourceview-*/language-specs/sh.lang; cl'

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
    alias cdp='pushd ~/Pictures ; cl'
    alias cdpi='pushd /etc/pihole; cl'
    alias cdr='pushd /; cl'
    alias cds='pushd ~/scripts; cl'
    alias cdtmp='pushd ~/tmp ; cl'
    alias cdt='pushd ~/.local/share/trash/; cl'
    alias cdb1='pushd /usr/bin; cl'
    alias cdb2='pushd /usr/local/bin; cl'
    alias cdv='pushd ~/Videos ; cl'

    # change directory fast commands
    alias cd.='cd ..; cl'
    alias cd..='cd ..; cl'

    # cat [ /home/jman ]
    alias cba='\cat ~/.bash_aliases; cl'
    alias cbf='\cat ~/.bash_functions; cl'
    alias cbrc='\cat ~/.bashrc; cl'
    alias cpro='\cat ~/.profile; cl'
    # cat [ /etc ]
    alias capt='clear; cat /etc/apt/sources.list'
    alias cbasrc='clear; cat /etc/bash.bashrc'
    alias ccat='clear; cat /etc/catrc'
    alias ccron='clear; cat /etc/crontab'
    alias cddc='clear; cat /etc/ddclient.conf'
    alias chosts='clear; cat /etc/hosts'
    alias clang='clear; cat /usr/share/gtksourceview-*/language-specs/sh.lang'
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
    alias piports="clear; netstat -nltup | grep 'Proto\|:53 \|:67 \|:80 \|:100 \|:41'"

    # list internet interfaces
    alias pse='clear; ip -4 -c -d -h address'
    alias pse1="clear; ifconfig -s | egrep '^(e|l|w|i).*$'"
    alias pse2='clear; lshw -class network'
    alias pse3='clear; dnstop -4QRl 5 eth0'
    alias pse4='clear; tcpdump -c 50 -i eth0'

    # cpu commands
    alias top='clear; iftop -i eth0 -B -F net/mask -P'
    alias pscpu='clear; lscpu'
    alias pscpu1='clear; ps auxf | head -c -0'

    # memory commands
    alias psmem='clear; free -m -l -t'
    alias psmem1="clear; inxi -FxzR | egrep '^.*RAID:.*|^.*System:.*|^.*Memory:.*$'"

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

    # UBUNTU VERSION
    alias uver="clear; lsb_release -d | grep -Eo 'Ubuntu [0-9\.]+.*$'"

    # FIX GPG KEY ERRORS DURING APT UPDATE THAT SHOWS THEY ARE "DEPRECIATED"
    alias fix_gpg='sudo cp /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d'

    # WATCH COMMAND
    alias cwatch='watch -n1 ccache --print-stats'

    # GET KERNEL VERSION
    alias kv='cat /proc/version | grep -Eo "([0-9\.\-]+-generic)"'

    # FFMPEG
    alias fft='clear; ./repo.sh'
    alias ffc='clear; ./configure --help'

    # TIMESHIFT BACKUP SNAPSHOTS
    alias tsb='clear; timeshift --create'

    # SHOW GCC NATIVE COMMANDS
    alias show_gcc='clear; gcc-12 -march=native -E -v - </dev/null 2>&1 | grep cc1'

    # START VIRTUAL MACHINE
    alias svm='clear; sudo virt-manager'

    ## SHOW THE TOP 10 PROCESSES BY CPU RESOURCE CONSUMPTION
    alias cpu_leach='clear; ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -10'

    ## GET LIST OF ALL DIRECTORY SIZES
    alias dir_size='clear; ncdu -q'

    # WINE
    alias wine32='env WINEARCH=win32 WINEPREFIX=~/.wine32 wine $*'

    # FIND AND KILL PROCESSES BY PID OR NAME
    alias tk='kill -9'
    alias tka='killall -9'
EOF
}

#
# GET USER INPUT
#

printf "%s\n\n%s\n%s\n\n" \
    'If apt-fast is installed do you want this script to use it instead of apt?' \
    '[1] Yes' \
    '[2] No'
read -p 'Your choices are (1 or 2): ' answer

case "${answer}" in
    1)
            script_fn
            sed -i "s/apt /apt-fast /g" "${file}"
            ;;
    2)      script_fn;;
    *)
            clear
            printf "%s\n\n" 'Bad user input. Please start over.'
            exit 1
            ;;
esac
