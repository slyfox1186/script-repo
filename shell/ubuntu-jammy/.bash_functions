_suppress()
{
    eval "${1}() { \$(which ${1}) \"\$@\" 2>&1 | tr -d '\r' | grep -v \"${2}\"; }"
}

# _supress all && _supress gedit && _supress gnome-terminal && _supress firefox
_suppress gedit          "Gtk-WARNING\|connect to accessibility bus"
_suppress gnome-terminal "accessibility bus\|stop working with a future version"
_suppress firefox        "g_slice_set_config"

###########################
## linux kernel commands ##
###########################

kernel_list() { clear; ls "/usr/src/linux-headers-$(uname -r)"; }
kernel_search() { clear; apt search "linux-headers-$(uname -r)"; }
kernel_update() { clear; apt install "linux-headers-$(uname -r)"; }

###################
## FIND COMMANDS ##
###################

ffind()
{
    clear

    local myFile myPath myType

    if [ -z "${1}" ]; then
        read -p 'Please enter the file name to search for: ' myFile
        echo
        read -p 'Please enter the file type [ d|f|blank ]: ' myType
        echo
        read -p 'Please enter the folder path to start from: ' myPath
        clear
        if [ -z "${myType}" ]; then
            find "${myPath}" -name "${myFile}" 2>/dev/null | xargs -I{} echo {}
        else
            find "${myPath}" -type "${myType}" -name "${myFile}" 2>/dev/null | xargs -I{} echo {}
        fi
    else
        find "${1}" -name "${2}" 2>/dev/null | xargs -I{} echo {}
    fi
}

######################
## UNCOMPRESS FILES ##
######################

untar()
{
    clear

    local EXT

    for file in *.*
    do
        EXT="${i##*.}"

        [[ ! -d "${PWD}/${file%%.*}" ]] && mkdir -p "${PWD}/${file%%.*}"

        case "${EXT}" in
            7z|zip)
                7z x -o"${PWD}/${file%%.*}" "${PWD}/${file}"
                ;;
            bz2|gz|xz)
                jflag=''
                [[ "${EXT}" == 'bz2' ]] && jflag='j'
                tar -xvf${jflag} "${PWD}/${file}" -C "${PWD}/${file%%.*}"
                ;;
        esac
    done
}

##################
## CREATE FILES ## 
##################

mf()
{
    clear

    local i

    if [ -z "${1}" ]; then
        read -p 'Enter file name: ' i
        clear
        if [ ! -f "${i}" ]; then touch "${i}"; fi
        chmod 744 "${i}"
    else
        if [ ! -f "${1}" ]; then touch "${1}"; fi
        chmod 744 "${1}"
    fi

    cl
}

mdir()
{
    clear

    local DIR

    if [[ -z "${1}" ]]; then
        read -p 'Enter directory name: ' DIR
        clear
        mkdir -pv "${PWD}/${DIR}"
        cd "${PWD}/${DIR}" || exit 1
    else
        mkdir -pv "${1}"
        cd "${PWD}/${1}" || exit 1
    fi

    cl
}

##################
## AWK COMMANDS ##
##################

# REMOVED ALL DUPLICATE LINES: OUTPUTS TO TERMINAL
rmd() { clear; awk '!seen[${0}]++' "${1}"; }

# REMOVE CONSECUTIVE DUPLICATE LINES: OUTPUTS TO TERMINAL
rmdc() { clear; awk 'f!=${0}&&f=${0}' "${1}"; }

# REMOVE ALL DUPLICATE LINES AND REMOVES TRAILING SPACES BEFORE COMPARING: REPLACES THE FILE
rmdf()
{
    clear
    perl -i -lne 's/\s*$//; print if ! $x{$_}++' "${1}"
    gedit "${1}"
}

###################
## FILE COMMANDS ##
###################

# COPY FILE
cp_file()
{
    clear

    if [ ! -d "${HOME}/tmp" ]; then
        mkdir -pv "${HOME}/tmp"
    fi

    cp "${1}" "${HOME}/tmp/${1}"

    chown -R "${USER}":"${USER}" "${HOME}/tmp/${1}"
    chmod -R 744 "${HOME}/tmp/${1}"

    clear
    cl
}

# MOVE FILE
mv_file()
{
    clear

    if [ ! -d "${HOME}/tmp" ]; then
        mkdir -pv "${HOME}/tmp"
    fi

    mv "${1}" "${HOME}/tmp/${1}"

    chown -R "${USER}":"${USER}" "${HOME}/tmp/${1}"
    chmod -R 744 "${HOME}/tmp/${1}"

    cl
}

##################
## APT COMMANDS ##
##################

# CLEAN
clean()
{
    clear
    apt clean
    apt -y autoremove
    apt autoclean
    apt -y purge
}

# UPDATE
update()
{
    clear
    apt update
    apt-get -y dist-upgrade
    apt -y full-upgrade
    apt clean
    apt -y autoremove
    apt autoclean
    apt -y purge
}

# FIX MISSING GPNU KEYS USED TO UPDATE PACKAGES
fix_key()
{
    clear

    local FILE URL

    if [[ -z "${1}" ]] && [[ -z "${2}" ]]; then
        read -p 'Enter the file name to store in /etc/apt/trusted.gpg.d: ' FILE
        echo
        read -p 'Enter the gpg key URL: ' URL
        clear
    else
        FILE="${1}"
        URL="${2}"
    fi

    curl -S# "${URL}" | gpg --dearmor | sudo tee "/etc/apt/trusted.gpg.d/${FILE}"
    
    if curl -S# "${URL}" | gpg --dearmor | sudo tee "/etc/apt/trusted.gpg.d/${FILE}"; then
        echo 'The key was successfully added!'
    else
        echo 'The key FAILED to add!'
    fi
}


##########################
# TAKE OWNERSHIP COMMAND #
##########################
toa()
{
    clear

    chown -R "${USER}":"${USER}" "${PWD}"
    chmod -R 744 "${PWD}"
    clear
    cl
}

#################
# DPKG COMMANDS #
#################
fix()
{
    clear
    apt --fix-missing install
    apt --fix-missing update
    apt -y install
    dpkg --configure -a
    apt clean
    apt -y autoremove
    apt autoclean
    apt -y purge
    if [ -f '/var/lib/apt/lists/lock' ];then sudo rm -f '/var/lib/apt/lists/lock'; fi
    if [ -f '/var/cache/apt/archives/lock' ];then sudo rm -f '/var/cache/apt/archives/lock'; fi
    apt update
}

da()
{
    if [ ! -d "${HOME}/tmp" ]; then mkdir -p "${HOME}/tmp"; fi
    dpkg --get-selections > "${HOME}/tmp/installed-packages.txt"
    gedit "${HOME}/tmp/installed-packages.txt"
}

df()
{
    clear
    dpkg -l |
    sort |
    grep -i "${@}"
}

## SHOW ALL INSTALLED PACKAGES
showpackages()
{
    dpkg --get-selections | grep -v deinstall > "${HOME}/tmp/packages.list"
    gedit "${HOME}/tmp/packages.list"
}

# PIPE ALL DEVELOPMENT PACKAGES NAMES TO FILE
getdev()
{
    apt-cache search dev |
    apt-cache search dev |
    grep "\-dev" |
    cut -d ' ' -f1 |
    sort > 'dev-packages.list'
    gedit 'dev-packages.list'
}

################
## SSH-KEYGEN ##
################

# create a new private and public ssh key pair
new_key()
{
    clear

    local BITS COMMENT NAME PASS TYPE

    echo -e "Encryption type: [ rsa | dsa | ecdsa ]\\n"
    read -p 'Your choice: ' TYPE
    clear

    echo '[i] Choose the key bit size'
    echo '[i] Values encased in() are recommended'

    if [ "${TYPE}" == 'rsa' ]; then
        echo -e "[i] rsa: [ 512 | 1024 | (2048) | 4096 ]\\n"
    elif [ "${TYPE}" == 'dsa' ]; then
        echo -e "[i] dsa: [ (1024) | 2048 ]\\n"
    elif [ "${TYPE}" == 'ecdsa' ]; then
        echo -e "[i] ecdsa: [ (256) | 384 | 521 ]\\n"
    fi

    read -p 'Your choice: ' BITS
    clear

    echo '[i] Choose a password'
    echo -e "[i] For no password just press enter\\n"
    read -p 'Your choice: ' PASS
    clear

    echo '[i] Choose a comment'
    echo -e "[i] For no comment just press enter\\n"
    read -p 'Your choice: ' COMMENT
    clear

    echo -e "[i] Enter the ssh key name\\n"
    read -p 'Your choice: ' NAME
    clear

    echo -e "[i] Your choices\\n"
    echo -e "[i] Type: ${TYPE}"
    echo -e "[i] Bits: ${BITS}"
    echo -e "[i] Password: ${PASS}"
    echo -e "[i] Comment: ${COMMENT}"
    echo -e "[i] Key Name: ${NAME}\\n"
    read -p 'Press enter to continue or ^c to exit'
    clear

    ssh-keygen -q -b "${BITS}" -t "${TYPE}" -N "${PASS}" -C "${COMMENT}" -f "${NAME}"

    chmod 600 "$PWD/${NAME}"
    chmod 644 "$PWD/${NAME}.pub"
    clear

    echo -e "[i] File: $PWD/${NAME}\\n"
    cat "$PWD/${NAME}"

    echo -e "\\n[i] File: $PWD/${NAME}.pub\\n"
    cat "$PWD/${NAME}.pub"

    echo
}

# export the public ssh key stored inside a private ssh key
keytopub()
{
    clear

    local oPub oKey

    echo -e "Enter the full paths for each file\\n"
    read -p 'Private key: ' oKey
    read -p 'Public key: ' oPub
    clear
    if [ -f "${oKey}" ]; then
        chmod 600 "${oKey}"
    else
        echo -e "Warning: file missing = ${oKey}\\n"
        read -p 'Press Enter to exit.'
        exit 1
    fi
    ssh-keygen -b '4096' -y -f "${oKey}" > "${oPub}"
    chmod 644 "${oPub}"
    cp "${oPub}" "${HOME}/.ssh/authorized_keys"
    chmod 600 "${HOME}/.ssh/authorized_keys"
    unset "${oKey}"
    unset "${oPub}"
}

# install colordiff package :)
cdiff() { clear; colordiff "${1}" "${2}"; }

# GZIP
gzip() { clear; gzip -d "${@}"; }

# get system time
show_time() { clear; date +%r | cut -d " " -f1-2 | grep -E '^.*$'; }

# CHANGE DIRECTORY
cdsys() { pushd "${HOME}/system" || exit 1; cl; }

##################
## SOURCE FILES ##
##################

sbrc()
{
    clear
    source "${HOME}/.bashrc" && echo -e "The command was a success!\\n" || echo -e "The command failed!\\n"
    sleep 1
    cl
}

spro()
{
    clear
    source "${HOME}/.profile" && echo -e "The command was a success!\\n" || echo -e "The command failed!\\n"
    sleep 1
    clear
    cl
}

####################
## ARIA2 COMMANDS ##
####################

# ARIA2 DAEMON IN BACKGROUND
aria2_on()
{
    clear

    # aria2c --conf-path="${HOME}/.aria2/aria2.conf"


    if aria2c --conf-path="${HOME}/.aria2/aria2.conf"; then
        echo -e "\\nCommand Executed Successfully\\n"
    else
        echo -e "\\nCommand Failed\\n"
    fi
}

# STOP ARIA2 DAEMON
aria2_off() { clear; killall aria2c; }

# RUN ARIA2 AND DOWNLOAD FILES TO CURRENT FOLDER
aria2()
{
    clear

    local FILE LINK

    if [[ -z "${1}" ]] && [[ -z "${2}" ]]; then
        read -p 'Enter the output file name: ' FILE
        echo
        read -p 'Enter the download URL: ' LINK
        clear
    else
        FILE="${1}"
        LINK="${2}"
    fi

    aria2c --out="${FILE}" "${LINK}"
}

# PRINT LAN/WAN IP
myip()
{
    clear
    LAN="$(hostname -I)"
    WAN="$(dig +short myip.opendns.com @resolver1.opendns.com)"
    clear
    echo "Internal IP (LAN) address: ${LAN}"
    echo "External IP (WAN) address: ${WAN}"
}

# FIND AND KILL PROCESSES BY PID OR NAME
tkpid() { clear; ps aux | grep "${@}"; }

# WGET COMMAND
mywget()
{
    clear

    local oFile URL

    if [ -z "${1}" ] || [ -z "${2}" ]; then
        read -p 'Please enter the output file name: ' oFile
        echo
        read -p 'Please enter the URL: ' URL
        clear
        wget --out-file="${oFile}" "${URL}"
    else
        wget --out-file="${1}" "${2}"
    fi
}

################
# RM COMMANDS ##
################

# RM DIRECTORY
rmd()
{
    clear

    local i

    if [ -z "${1}" ] || [ -z "${2}" ]; then
        read -p 'Please enter the directory name to remove: ' i
        clear
        sudo rm -r "${i}"
        cl
    else
        sudo rm -r "${1}"
        cl
    fi
}

# RM FILE
rmf()
{
    clear

    local i

    if [ -z "${1}" ]; then
        read -p 'Please enter the file name to remove: ' i
        clear
        sudo rm "${i}"
        cl
    else
        sudo rm "${1}"
        cl
    fi
}

#################
## IMAGEMAGICK ##
#################
imo()
{
    clear

    local i
    # find all jpg files and create temporary cache files from them
    for i in *.jpg; do
        echo -e "\\nCreating two temporary cache files: ${i%%.jpg}.mpc + ${i%%.jpg}.cache\\n"
        dimension="$(identify -format '%wx%h' "${i}")"
        convert "${i}" -monitor -filter Triangle -define filter:support=2 -thumbnail $dimension -strip \
        -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off \
        -auto-level -enhance -interlace none -colorspace sRGB "/tmp/${i%%.jpg}.mpc"
        clear
        for i in /tmp/*.mpc; do
        # find the temporary cache files created above and output optimized jpg files
            if [ -f "${i}" ]; then
                echo -e "\\nOverwriting orignal file with optimized self: ${i} >> ${i%%.mpc}.jpg\\n"
                convert "${i}" -monitor "${i%%.mpc}.jpg"
                # overwrite the original image with it's optimized version
                # by moving it from the tmp directory to the source directory
                if [ -f "${i%%.mpc}.jpg" ]; then
                    mv "${i%%.mpc}.jpg" "$PWD"
                    # delete both cache files before continuing
                    rm "${i}"
                    rm "${i%%.mpc}.cache"
                    clear
                fi
            fi
        done
    done
}

imow()
{

    clear

    local answer i wxh

    echo 'This will overwrite the files, continue?'
    echo
    echo '[1] Yes'
    echo '[2] No'
    echo
    read -p 'Your choices are (1 or 2): ' answer
    clear

    if [[ "${answer}" -eq '1' ]]; then
        clear
    elif [[ "${answer}" -eq '2' ]]; then
        return
    fi

    # find all jpg files and create temporary cache files from them
    for pics in *.{jpg,JPG,jpeg,JPEG,png,PNG}
    do
        echo -e "\\nCreating two temporary cache files: ${pics%%.jpg}.mpc + ${pics%%.jpg}.cache\\n"
        wxh="$(identify -format '%wx%h' "${pics}")"
        convert "${pics}" -monitor -filter Triangle -define filter:support=2 -thumbnail "${wxh}" \
        -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off \
        -define png:compression-filter=5 -define png:compression-level=9 -define png:compression-strategy=1 \
        -define png:exclude-chunk=all -interlace none -colorspace sRGB "/tmp/${pics%%.jpg}.mpc"
        echo
        for i in /tmp/*.mpc
        do
            if [ -f "${pics}" ]; then
                echo -e "\\nOverwriting orignal file with optimized self: ${pics} >> ${pics%%.mpc}.jpg\\n"
                convert "${pics}" -monitor "${pics%%.mpc}.jpg"
                if [ -f "${pics%%.mpc}.jpg" ]; then
                    mv "${pics%%.mpc}.jpg" "${PWD}"
                    # delete both cache files before continuing
                    rm "${pics}"
                    rm "${pics%%.mpc}.cache"
                    clear
                fi
            fi
        done
    done
}

##################################################
## SHOW FILE NAME AND SIZE IN CURRENT DIRECTORY ##
##################################################

fsize() { clear; du -abh | grep -Eo '^[0-9A-Za-z\.]*|[a-zA-Z0-9\_]+\.jpg$'; }
