#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2001,SC2162,SC2317

export user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

######################################################################################
## WHEN LAUNCHING CERTAIN PROGRAMS FROM THE TERMINAL, SUPPRESS ANY WARNING MESSAGES ##
######################################################################################

nn() { "$(type -P nano)" "${@}" &>/dev/null; }
nns() { "$(type -P sudo)" -H -u root "$(type -P nano)" "${@}" &>/dev/null; }

################################################
## GET THE OS AND ARCH OF THE ACTIVE COMPUTER ##
################################################

mypc()
{
    local os ver
    
    if [ -f '/etc/os-release' ]; then
        source '/etc/os-release'
        os="$NAME"
        ver="$VERSION_ID"
    else
        clear
        printf "%s\n\n" 'Unable to find the file: /etc/os-release'
        return 1
    fi

    clear
    printf "%s\n%s\n\n"           \
        "Operating System: ${os}" \
        "Specific Version: ${ver}"
}

###################
## FIND COMMANDS ##
###################

ffind()
{
    local fname fpath ftype
    clear

    read -p 'Enter the name to search for: ' fname
    echo
    read -p 'Enter a type of file (d|f|blank): ' ftype
    echo
    read -p 'Enter the starting path: ' fpath
    clear

    if [ -n "${fname}" ] && [ -z "${ftype}" ] && [ -z "${fpath}" ]; then
        sudo find "${PWD}" -iname "${fname}" | while read line; do echo "${line}"; done
    elif [ -n "${fname}" ] && [ -z "${ftype}" ] && [ -n "${fpath}" ]; then
        sudo find "${fpath}" -iname "${fname}" | while read line; do echo "${line}"; done
    elif [ -n "${fname}" ] && [ -n "${ftype}" ] && [ -n "${fpath}" ]; then
        sudo find "${fpath}" -type "${ftype}" -iname "${fname}" | while read line; do echo "${line}"; done
    elif [ -n "${fname}" ] && [ -z "${ftype}" ] && [ "${fpath}" ]; then
        sudo find "${PWD}" -iname "${fname}" | while read line; do echo "${line}"; done
    elif [ -n "${fname}" ] && [ -n "${ftype}" ] && [ "${fpath}" = '.' ]; then
        sudo find "${PWD}" -type "${ftype}" -iname "${fname}" | while read line; do echo "${line}"; done
     fi
}

######################
## UNCOMPRESS FILES ##
######################

untar()
{
    local ext gflag jflag xflag
    clear

    for i in *.*
    do
        ext="${i##*.}"

        [[ ! -d "${PWD}"/"${i%%.*}" ]] && mkdir -p "${PWD}"/"${i%%.*}"

        case "${ext}" in
            7z|zip)             7z x -o"${PWD}"/"${i%%.*}" "${PWD}"/"${i}";;
            bz2|gz|tgz|xz)
                                jflag=
                                gflag=
                                xflag=
                                [[ "${ext}" = 'bz2' && "${ext}" != 'gz' && "${ext}" != 'tgz' ]] && jflag='xfj'
                                [[ "${ext}" != 'bz2' && "${ext}" = 'gz' || "${ext}" = 'tgz' ]] && gflag='zxf'
                                [[ "${ext}" = 'xz' && "${ext}" != 'bz2' && "${ext}" != 'gz' && "${ext}" != 'tgz' ]] && xflag='xf'
                                tar -${xflag}${gflag}${jflag} "${PWD}"/"${i}" -C "${PWD}"/"${i%%.*}" 2>/dev/null
                                ;;
        esac
    done
}
            
##################
## CREATE FILES ##
##################

mdir()
{
    local dir
    clear

    if [[ -z "${1}" ]]; then
        read -p 'Enter directory name: ' dir
        clear
        mkdir -p  "${PWD}/$dir"
        cd "${PWD}/$dir" || exit 1
    else
        mkdir -p "${1}"
        cd "${PWD}/${1}" || exit 1
    fi

    clear; ls -1AhFv --color --group-directories-first
}

##################
## AWK COMMANDS ##
##################

# REMOVED ALL DUPLICATE LINES: OUTPUTS TO TERMINAL
rmd() { clear; awk '!seen[${0}]++' "${1}"; }

# REMOVE CONSECUTIVE DUPLICATE LINES: OUTPUTS TO TERMINAL
rmdc() { clear; awk 'f!=${0}&&f=${0}' "${1}"; }

# REMOVE ALL DUPLICATE LINES AND REMOVES TRAILING SPACES BEFORE COMPARING: REPLACES THE file
rmdf()
{
    clear
    perl -i -lne 's/\s*$//; print if ! $x{$_}++' "${1}"
    nano "${1}"
}

##################
## APT COMMANDS ##
##################

# DOWNLOAD AN APT PACKAGE + ALL ITS DEPENDENCIES IN ONE GO
apt_dl()
{
    clear
    wget -c "$(apt --print-uris -qq --reinstall install ${1} 2>/dev/null | cut -d''\''' -f2)"
    clear; ls -1AhFv --color --group-directories-first
}

clean()
{
    clear
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt -y purge
}

update()
{
    clear
    sudo apt update
    sudo apt -y full-upgrade
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt -y purge
}

fix()
{
    clear
    if [ -f /tmp/apt.lock ]; then
        sudo rm /tmp/apt.lock
    fi
    sudo dpkg --configure -a
    sudo apt --fix-broken install
    sudo apt -f -y install
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt update
}

list()
{
    local search
    clear

    if [ -n "${1}" ]; then
        sudo apt list "*${1}*" 2>/dev/null | awk -F'/' '{print $1}'
    else
        read -p 'Enter the string to search: ' search
        clear
        sudo apt list "*${search}*" 2>/dev/null | awk -F'/' '{print $1}'
    fi
}

listd()
{
    local search
    clear

    if [ -n "${1}" ]; then
        sudo apt list -- "*${1}*"'-dev' 2>/dev/null | awk -F'/' '{print $1}'
    else
        read -p 'Enter the string to search: ' search
        clear
        sudo apt list -- "*${search}*"'-dev' 2>/dev/null | awk -F'/' '{print $1}'
    fi
}

# USE SUDO APT TO SEARCH FOR ALL APT PACKAGES BY PASSING A NAME TO THE FUNCTION
apts()
{
    local search
    clear

    if [ -n "${1}" ]; then
        sudo apt search "${1} ~i" -F "%p"
    else
        read -p 'Enter the string to search: ' search
        clear
        sudo apt search "${search} ~i" -F "%p"
    fi
}

# USE APT CACHE TO SEARCH FOR ALL APT PACKAGES BY PASSING A NAME TO THE FUNCTION
csearch()
{
    local cache
    clear

    if [ -n "${1}" ]; then
        apt-cache search --names-only "${1}.*" | awk '{print $1}'
    else
        read -p 'Enter the string to search: ' cache
        clear
        apt-cache search --names-only "${cache}.*" | awk '{print $1}'
    fi
}

# FIX MISSING GPNU KEYS USED TO UPDATE PACKAGES
fix_key()
{
    local file url
    clear

    if [[ -z "${1}" ]] && [[ -z "${2}" ]]; then
        read -p 'Enter the file name to store in /etc/apt/trusted.gpg.d: ' file
        echo
        read -p 'Enter the gpg key url: ' url
        clear
    else
        file="${1}"
        url="${2}"
    fi

    curl -S# "${url}" | gpg --dearmor | sudo tee "/etc/apt/trusted.gpg.d/${file}"

    if curl -S# "${url}" | gpg --dearmor | sudo tee "/etc/apt/trusted.gpg.d/${file}"; then
        echo 'The key was successfully added!'
    else
        echo 'The key failed to add!'
    fi
}

##########################
# TAKE OWNERSHIP COMMAND #
##########################
toa()
{
    clear
    chown -R "${USER}":"${USER}" "${PWD}"
    chmod -R 755 "${PWD}"
    clear
    ls -1AhFv --color --group-directories-first
}

#################
# DPKG COMMANDS #
#################

## SHOW ALL INSTALLED PACKAGES
showpkgs()
{
    dpkg --get-selections |
    grep -v deinstall > "${HOME}"/tmp/packages.list
    nano "${HOME}"/tmp/packages.list
}

# GZIP
gzip() { clear; gzip -d "${@}"; }

# GET SYSTEM TIME
get_time()
{
    clear
    date +%r | cut -d ' ' -f1-2 | grep -E '^.*$'
}

##################
## SOURCE FILES ##
##################

sbrc()
{
    clear
    source "${HOME}"/.bashrc && echo -e "The command was a success!\\n" || echo -e "The command failed!\\n"
}

spro()
{
    clear
    source "${HOME}"/.profile && echo -e "The command was a success!\\n" || echo -e "The command failed!\\n"
}

####################
## ARIA2 COMMANDS ##
####################

# ARIA2 DAEMON IN THE BACKGROUND
aria2_on()
{
    clear

    if aria2c --conf-path="${HOME}"/.aria2/aria2.conf; then
        printf "\n%s\n\n" 'Command successful!'
    else
        printf "\n%s\n\n" 'Command failed!'
    fi
}

# STOP ARIA2 DAEMON
aria2_off() { clear; sudo killall -9 aria2c; }

# RUN ARIA2 AND DOWNLOAD FILES TO THE CURRENT FOLDER
aria2()
{
    local file link
    clear

    if [[ -z "${1}" ]] && [[ -z "${2}" ]]; then
        read -p 'Enter the output file name: ' file
        echo
        read -p 'Enter the download url: ' link
        clear
    else
        file="${1}"
        link="${2}"
    fi

    aria2c --out="${file}" "${link}"
}

# PRINT LAN & WAN IP ADDRESSES
myip()
{
    clear
    printf "%s\n%s\n\n"                                   \
        "LAN: $(ip route get 1.2.3.4 | awk '{print $7}')" \
        "WAN: $(dig +short 'myip.opendns.com' @resolver1.opendns.com)"
}

###########################
## SHOW NVME TEMPERATURE ##
###########################

nvme_temp()
{
    local n0 n1 n2
    clear

    n0="$(sudo nvme smart-log /dev/nvme0n1)"
    n1="$(sudo nvme smart-log /dev/nvme1n1)"
    n2="$(sudo nvme smart-log /dev/nvme2n1)"

    printf "nvme0n1:\n\n%s\n\nnvme1n1:\n\n%s\n\nnvme2n1:\n\n%s\n\n" "${n0}" "${n1}" "${n2}"
}

####################
## GET FILE SIZES ##
####################

big_files()
{
    local cnt
    clear

    if [ -n "${1}" ]; then
        cnt="${1}"
    else
        read -p 'Enter how many files to list in the results: ' cnt
        clear
    fi

    printf "%s\n\n" "${cnt} largest files"
    sudo find "${PWD}" -type f -exec du -Sh {} + | sort -hr | head -n"${cnt}"
    echo
    printf "%s\n\n" "${cnt} largest folders"
    sudo du -Bm "${PWD}" 2>/dev/null | sort -hr | head -n"${cnt}"
}

big_vids()
{
    local cnt
    clear

    if [ -n "${1}" ]; then
        cnt="${1}"
    else
        read -p 'Enter the max number of results: ' cnt
        clear
    fi

    printf "%s\n\n" "Listing the ${cnt} largest videos"
    sudo find "${PWD}" -type f \( -iname '*.mkv' -o -iname '*.mp4' \) -exec du -Sh {} + | grep -Ev '\(x265\)' | sort -hr | head -n"${cnt}"
}

big_imgs()
{
    local max_img_size
    clear

    if [ -n "${1}" ]; then
        max_img_size="${1}"
    else
        read -p 'Please enter the max image size to search (Units are in MB. Example: 10): ' max_img_size
    fi

    clear    
    sudo find "${PWD}" -size +"${max_img_size}"M -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null
}

################################################################
## PRINT THE NAME OF THE DISTRIBUTION YOU ARE CURRENTLY USING ##
################################################################

myos()
{
    local name ver
    clear
    name="$(eval lsb_release -si 2>/dev/null)"
    ver="$(eval lsb_release -sr 2>/dev/null)"
    clear
    printf "%s\n\n" "Linux OS: ${name} ${ver}"
}

##############################################
## MONITOR CPU AND MOTHERBOARD TEMPERATURES ##
##############################################

twatch()
{
    local found
    clear

    # install lm-sensors if not already
    if ! which lm-sensors &>/dev/null; then
        sudo apt -y install lm-sensors
    fi

    # Add modprobe to system startup tasks if not already added
    found="$(grep -o 'drivetemp' '/etc/modules')"
    if [ -z "${found}" ]; then
        echo 'drivetemp' | sudo tee -a '/etc/modules'
    else
        sudo modprobe drivetemp
    fi

    watch -n0.5 sudo sensors -u
}

###################
## 7ZIP COMMANDS ##
###################

# CREATE A GZ FILE WITH MAX COMPRESSION SETTINGS
7z_gz()
{
    local source output
    clear

    if [ -n "${1}" ]; then
        if [ -f "${1}".tar.gz ]; then
            sudo rm "${1}".tar.gz
        fi
        7z a -ttar -so -an "${1}" | 7z a -tgz -mx9 -mpass1 -si "${1}".tar.gz
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".tar.gz ]; then
            sudo rm "${output}".tar.gz
        fi
        7z a -ttar -so -an "${source}" | 7z a -tgz -mx9 -mpass1 -si "${output}".tar.gz
    fi
}

# CREATE A XZ FILE WITH MAX COMPRESSION SETTINGS USING 7ZIP
7z_xz()
{
    local source output
    clear

    if [ -n "${1}" ]; then
        if [ -f "${1}".tar.xz ]; then
            sudo rm "${1}".tar.xz
        fi
        7z a -ttar -so -an "${1}" | 7z a -txz -mx9 -si "${1}".tar.xz
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".tar.xz ]; then
            sudo rm "${output}".tar.xz
        fi
        7z a -ttar -so -an "${source}" | 7z a -txz -mx9 -si "${output}".tar.xz
    fi
}

# CREATE A 7ZIP FILE WITH MAX COMPRESSION SETTINGS
7z_1()
{
    local answer source output
    clear

    if [ -n "${1}" ]; then
        if [ -f "${1}".7z ]; then
            sudo rm "${1}".7z
        fi
        7z a -t7z -m0=lzma2 -mx1 "${1}".7z ./"${1}"/*
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".7z ]; then
            sudo rm "${output}".7z
        fi
        7z a -t7z -m0=lzma2 -mx1 "${output}".7z ./"${source}"/*
    fi

    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to delete the original file?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer
    clear

    if [ -n "${1}" ]; then
        source="${1}"
    fi

    case "${answer}" in
        1)      sudo rm -fr "${source}";;
        2)      clear;;
        '')     sudo rm -fr "${source}";;
        *)      printf "\n%s\n\n" 'Bad user input...';;
    esac
}

7z_5()
{
    local answer source output
    clear

    if [ -n "${1}" ]; then
        if [ -f "${1}".7z ]; then
            sudo rm "${1}".7z
        fi
        7z a -t7z -m0=lzma2 -mx5 "${1}".7z ./"${1}"/*
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".7z ]; then
            sudo rm "${output}".7z
        fi
        7z a -t7z -m0=lzma2 -mx5 "${output}".7z ./"${source}"/*
    fi

    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to delete the original file?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer
    clear

    if [ -n "${1}" ]; then
        source="${1}"
    fi

    case "${answer}" in
        1)      sudo rm -fr "${source}";;
        2)      clear;;
        '')     sudo rm -fr "${source}";;
        *)      printf "\n%s\n\n" 'Bad user input...';;
    esac
}

7z_9()
{
    local answer source output
    clear

    if [ -n "${1}" ]; then
        if [ -f "${1}".7z ]; then
            sudo rm "${1}".7z
        fi
        7z a -t7z -m0=lzma2 -mx9 "${1}".7z ./"${1}"/*
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".7z ]; then
            sudo rm "${output}".7z
        fi
        7z a -t7z -m0=lzma2 -mx9 "${output}".7z ./"${source}"/*
    fi

    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to delete the original file?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer
    clear

    if [ -n "${1}" ]; then
        source="${1}"
    fi

    case "${answer}" in
        1)      sudo rm -fr "${source}";;
        2)      clear;;
        '')     sudo rm -fr "${source}";;
        *)      printf "\n%s\n\n" 'Bad user input...';;
    esac
}

##################
## TAR COMMANDS ##
##################

# CREATE A GZ FILE USING TAR COMMAND
tar_gz()
{
    local source output
    clear

    if [ -n "${1}" ]; then
        if [ -f "${1}".tar.gz ]; then
            sudo rm "${1}".tar.gz
        fi
        tar -cJf "${1}".tar.gz "${1}"
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".tar.gz ]; then
            sudo rm "${output}".tar.gz
        fi
        tar -cJf "${output}".tar.gz "${source}"
    fi
}

tar_bz2()
{
    local source output
    clear

    if [ -n "${1}" ]; then
        if [ -f "${1}".tar.bz2 ]; then
            sudo rm "${1}".tar.bz2
        fi
        tar -cvjf "${1}".tar.bz2 "${1}"
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".tar.bz2 ]; then
            sudo rm "${output}".tar.bz2
        fi
        tar -cvjf "${output}".tar.bz2 "${source}"
    fi
}

tar_xz_1()
{
    local source output
    clear
    if [ -n "${1}" ]; then
        if [ -f "${1}".tar.xz ]; then
            sudo rm "${1}".tar.xz
        fi
        tar -cvJf - "${1}" | xz -1 -c - > "${1}".tar.xz
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".tar.xz ]; then
            sudo rm "${output}".tar.xz
        fi
        tar -cvJf - "${source}" | xz -1 -c - > "${output}".tar.xz
    fi
}

tar_xz_5()
{
    local source output
    clear
    if [ -n "${1}" ]; then
        if [ -f "${1}".tar.xz ]; then
            sudo rm "${1}".tar.xz
        fi
        tar -cvJf - "${1}" | xz -5 -c - > "${1}".tar.xz
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".tar.xz ]; then
            sudo rm "${output}".tar.xz
        fi
        tar -cvJf - "${source}" | xz -5 -c - > "${output}".tar.xz
    fi
}

tar_xz_9()
{
    local source output
    clear
    if [ -n "${1}" ]; then
        if [ -f "${1}".tar.xz ]; then
            sudo rm "${1}".tar.xz
        fi
        tar -cvJf - "${1}" | xz -9 -c - > "${1}".tar.xz
    else
        read -p 'Please enter the source folder path: ' source
        echo
        read -p 'Please enter the destination archive path (w/o extension): ' output
        clear
        if [ -f "${output}".tar.xz ]; then
            sudo rm "${output}".tar.xz
        fi
        tar -cvJf - "${source}" | xz -9 -c - > "${output}".tar.xz
    fi
}

###################
## WRITE CACHING ##
###################

wcache()
{
    local choice
    clear
    
    lsblk
    echo
    read -p 'Enter the drive id to turn off write caching (don'\''t include "/dev/"): ' choice
    clear
    
    sudo hdparm -W 0 /dev/"${choice}"
}

## FIX USER FOLDER PERMISSIONS UP = USER PERMISSIONS

fix_up()
{
    find "${HOME}"/.gnupg -type f -exec chmod 600 {} \;
    find "${HOME}"/.gnupg -type d -exec chmod 700 {} \;
    find "${HOME}"/.ssh -type d -exec chmod 700 {} \; 2>/dev/null
    find "${HOME}"/.ssh/id_rsa.pub -type f -exec chmod 644 {} \; 2>/dev/null
    find "${HOME}"/.ssh/id_rsa -type f -exec chmod 600 {} \; 2>/dev/null
}

## COUNT FILES IN THE DIRECTORY
cnt_dir()
{
    local cnt
    clear

    cnt="$(find "${PWD}" -maxdepth 1 -type f | wc -l)"
    printf "%s %'d\n\n" "The total directory file count is (non-recursive):" "${cnt}"
}

cnt_dirr()
{
    local cnt
    clear
    cnt="$(find "${PWD}" -type f | wc -l)"
    printf "%s %'d\n\n" "The total directory file count is (recursive):" "${cnt}"
}

######################
## KILLALL COMMANDS ##
######################

tkapt()
{
    local list prog
    clear

    list=(apt apt-get aptitude dpkg)

    for prog in ${list[@]}
    do
        sudo killall -9 "${prog}"
    done
}

# FIND WHICH PROCESSES ARE BEING HELD UP AND KILL THEM
tkpid()
{
    clear
    lsof +D ./ |
    awk '{print $2}' |
    tail -n +2 |
    xargs -I{} sudo kill -9 {}
}

####################
## NOHUP COMMANDS ##
####################

nh()
{
    clear
    nohup "${1}" &>/dev/null &
    cl
}

nhs()
{
    clear
    nohup sudo "${1}" &>/dev/null &
    cl
}

############
## ARIA2C ##
############

adl()
{
    local isWSL name url
    clear

    # FIND OUT IF WSL OR NATIVE LINUX IS RUNNING BECAUSE WE HAVE TO CHANGE THE FILE ALLOCATION DEPENDING ON WHICH IS RUNNING
    isWSL="$(echo "$(uname -a)" | grep -o 'WSL2')"
    if [ -n "${isWSL}" ]; then
        setalloc=prealloc
    else
        setalloc=falloc
    fi

    if [ -z "${1}" ]; then
        read -p 'Enter the file name (w/o extension): ' name
        read -p 'Enter download URL: ' url
        clear
    else
        name="${1}"
        url="${2}"
    fi

    aria2c \
        --console-log-level=notice \
        --user-agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' \
        -x16 \
        -j5 \
        --split=32 \
        --allow-overwrite=true \
        --allow-piece-length-change=true \
        --always-resume=true \
        --async-dns=false \
        --auto-file-renaming=false \
        --min-split-size=8M \
        --disk-cache=64M \
        --file-allocation=${setalloc} \
        --no-file-allocation-limit=8M \
        --continue=true \
        --out="${name}" \
        "${url}"

    if [ "${?}" -eq '0' ]; then
        google_speech 'Download completed.' 2>/dev/null
    else
        google_speech 'Download failed.' 2>/dev/null
    fi

    find "${PWD}" -type f -iname "*:Zone.Identifier" -delete 2>/dev/null
    clear
    ls -1AhFv --color --group-directories-first
}

adlm()
{
    local name url
    clear

    if [ -z "${1}" ]; then
        read -p 'Enter the video name (w/o extension): ' name
        read -p 'Enter download URL: ' url
        clear
    else
        name="${1}"
        url="${2}"
    fi

    aria2c \
        --console-log-level=notice \
        --user-agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' \
        -x16 \
        -j5 \
        --split=32 \
        --allow-overwrite=true \
        --allow-piece-length-change=true \
        --always-resume=true \
        --async-dns=false \
        --auto-file-renaming=false \
        --min-split-size=8M \
        --disk-cache=64M \
        --file-allocation=prealloc \
        --no-file-allocation-limit=8M \
        --continue=true \
        --out="${name}"'.mp4' \
        "${url}"

    if [ "${?}" -eq '0' ]; then
        google_speech 'Download completed.' 2>/dev/null
    else
        google_speech 'Download failed.' 2>/dev/null
    fi

    find "${PWD}" -type f -iname "*:Zone.Identifier" -delete 2>/dev/null
    clear; ls -1AhFv --color --group-directories-first
}

####################
## RSYNC COMMANDS ##
####################

rsr()
{
    local destination modded_source source 
    clear

    # you must add an extra folder that is a period '/./' between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the source folder instead of the source
    # folder and its subfiles only.

    printf "%s\n%s\n%s\n%s\n\n"                                                                    \
        'This rsync command will recursively copy the source folder to the chosen destination.'    \
        'The original files will still be located in the source folder.'                           \
        'If you want to move the files (which deletes the originals then use the function "rsrd".' \
        'Please enter the full paths of the source and destination directories.'

    printf "%s\n\n" 
    read -p 'Enter the source path: ' source
    read -p 'Enter the destination path: ' destination
    modded_source="$(echo "${source}" | sed 's:/[^/]*$::')"'/./'"$(echo "${source}" | sed 's:.*/::')"
    clear

    rsync -aqvR --acls --perms --mkpath --info=progress2 "${modded_source}" "${destination}"
}

rsrd()
{
    local destination modded_source source 
    clear

    # you must add an extra folder that is a period '/./' between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the souce folder instead of the source
    # folder and its subfiles only.

    printf "%s\n%s\n%s\n%s\n\n"                                                                    \
        'This rsync command will recursively copy the source folder to the chosen destination.'    \
        'The original files will be DELETED after they have been copied to the destination.'       \
        'If you want to move the files (which deletes the originals then use the function "rsrd".' \
        'Please enter the full paths of the source and destination directories.'

    printf "%s\n\n" 
    read -p 'Enter the source path: ' source
    read -p 'Enter the destination path: ' destination
    modded_source="$(echo "${source}" | sed 's:/[^/]*$::')"'/./'"$(echo "${source}" | sed 's:.*/::')"
    clear

    rsync -aqvR --acls --perms --mkpath --remove-source-files "${modded_source}" "${destination}"
}

##########################
## SQUID PROXY COMMANDS ##
##########################

sqdc()
{
    local choice
    clear

    printf "%s\n%s\n\n%s\n%s\n\n"                                \
        'This will delete the squid proxy cache and rebuild it.' \
        'Are you sure you want to proceed?'                      \
        '[1] Yes'                                                \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice
    clear

    case "${choice}" in
        1)
            sudo squid -k shutdown
            sudo rm -fr '/var/spool/squid/'
            sudo mkdir -p '/var/spool/squid/'
            sudo chown proxy:proxy '/var/spool/squid/'
            sudo squid -z
            sudo service squid start
            ;;
        2)  return 0;;
        *)  return 0;;
    esac
}


##################################
## DETECT THE PC'S ARCHITECTURE ##
##################################

get_arch()
{
    local architecture
    unset architecture
    clear

    case "$(uname -m)" in
        i386|i686)      pc_arch=386;;
        x86_64)         pc_arch=amd64;;
        aarch64|arm)    sudo dpkg --print-architecture | grep -q arm64 && pc_arch=arm64 || pc_arch=arm;;
        *)
                        clear
                        printf "%s\n\n" 'Failed to detect this pc'\''s architecture using the command: "${uname -m}"'
                        return 1
                        ;;
    esac

    clear
    printf "%s\n\n" "The pc's architecture is: ${pc_arch}/$(uname -m)"
}
