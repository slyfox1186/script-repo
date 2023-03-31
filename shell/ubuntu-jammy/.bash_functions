
##################################################################################
## WHEN LAUNCHING CERTAIN PROGRAMS FROM TERMINAL, SUPPRESS ANY WARNING MESSAGES ##
##################################################################################

_suppress() { eval "${1}() { \$(which ${1}) \"\$@\" 2>&1 | tr -d '\r' | grep -v \"${2}\"; }"; }

_suppress gedit          "Gtk-WARNING\|connect to accessibility bus"
_suppress gnome-terminal "accessibility bus\|stop working with a future version"
_suppress firefox        "g_slice_set_config"

###################
## FIND COMMANDS ##
###################

ffind()
{
    clear

    local file path type

    read -p 'Enter a file to search for: ' file
    echo
    read -p 'Enter the type of file (d|f|blank): ' type
    echo
    read -p 'Enter the search path: ' path
    clear

    if [ -z "${type}" ]; then
        find "${path}" -name "${file}" 2>/dev/null | xargs -I{} echo {}
    elif [ -z "${type}" ] && [ -z "${path}" ]; then
        find . -name "${file}" 2>/dev/null | xargs -I{} echo {}
    else
        find "${path}" -type "${type}" -name "${file}" 2>/dev/null | xargs -I{} echo {}
    fi
}

######################
## UNCOMPRESS FILES ##
######################

untar()
{
    clear

    local ext

    for file in *.*
    do
        ext="${i##*.}"

        [[ ! -d "${PWD}/${file%%.*}" ]] && mkdir -p "${PWD}/${file%%.*}"

        case "${ext}" in
            7z|zip)
                7z x -o"${PWD}/${file%%.*}" "${PWD}/${file}"
                ;;
            bz2|gz|xz)
                jflag=''
                [[ "${ext}" == 'bz2' ]] && jflag='j'
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

    clear; ls -1AhFv --color --group-directories-first
}

mdir()
{
    clear

    local dir

    if [[ -z "${1}" ]]; then
        read -p 'Enter directory name: ' dir
        clear
        mkdir -p  "${PWD}/${dir}"
        cd "${PWD}/${dir}" || exit 1
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
    gedit "${1}"
}

###################
## file COMMANDS ##
###################

# COPY TO CLIPBOARD


# COPY file
cpf()
{
    clear

    if [ ! -d "${HOME}/tmp" ]; then
        mkdir -p "${HOME}/tmp"
    fi

    cp "${1}" "${HOME}/tmp/${1}"

    chown -R "${USER}":"${USER}" "${HOME}/tmp/${1}"
    chmod -R 744 "${HOME}/tmp/${1}"

    clear; ls -1AhFv --color --group-directories-first
}

# MOVE file
mvf()
{
    clear

    if [ ! -d "${HOME}/tmp" ]; then
        mkdir -p "${HOME}/tmp"
    fi

    mv "${1}" "${HOME}/tmp/${1}"

    chown -R "${USER}":"${USER}" "${HOME}/tmp/${1}"
    chmod -R 744 "${HOME}/tmp/${1}"

    clear; ls -1AhFv --color --group-directories-first
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
    apt-get -y install ubuntu-advantage-tools
    apt -y full-upgrade
    apt clean
    apt -y autoremove
    apt autoclean
    apt -y purge
}

# FIX BROKEN APT PACKAGES
fix()
{
    clear
    apt --fix-broken install
    apt --fix-missing update
    apt -y install
    dpkg --configure -a
    apt -y autoremove
    apt clean
    apt autoclean
    apt -y purge
    apt update
}

# FIX MISSING GPNU KEYS USED TO UPDATE PACKAGES
fix_key()
{
    clear

    local file url

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

    clear; ls -1AhFv --color --group-directories-first
}

#################
# DPKG COMMANDS #
#################

## SHOW ALL INSTALLED PACKAGES
showpkgs()
{
    dpkg --get-selections |
    grep -v deinstall > "${HOME}"/tmp/packages.list
    gedit "${HOME}"/tmp/packages.list
}

# PIPE ALL DEVELOPMENT PACKAGES NAMES TO file
getdev()
{
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

    local bits comment name pass type

    echo -e "Encryption type: [ rsa | dsa | ecdsa ]\\n"
    read -p 'Your choice: ' type
    clear

    echo '[i] Choose the key bit size'
    echo '[i] Values encased in() are recommended'

    if [[ "${type}" == 'rsa' ]]; then
        echo -e "[i] rsa: [ 512 | 1024 | (2048) | 4096 ]\\n"
    elif [[ "${type}" == 'dsa' ]]; then
        echo -e "[i] dsa: [ (1024) | 2048 ]\\n"
    elif [[ "${type}" == 'ecdsa' ]]; then
        echo -e "[i] ecdsa: [ (256) | 384 | 521 ]\\n"
    fi

    read -p 'Your choice: ' bits
    clear

    echo '[i] Choose a password'
    echo -e "[i] For no password just press enter\\n"
    read -p 'Your choice: ' pass
    clear

    echo '[i] Choose a comment'
    echo -e "[i] For no comment just press enter\\n"
    read -p 'Your choice: ' comment
    clear

    echo -e "[i] Enter the ssh key name\\n"
    read -p 'Your choice: ' name
    clear

    echo -e "[i] Your choices\\n"
    echo -e "[i] Type: ${type}"
    echo -e "[i] bits: ${bits}"
    echo -e "[i] Password: ${pass}"
    echo -e "[i] comment: ${comment}"
    echo -e "[i] Key name: ${name}\\n"
    read -p 'Press enter to continue or ^c to exit'
    clear

    ssh-keygen -q -b "${bits}" -t "${type}" -N "${pass}" -C "${comment}" -f "${name}"

    chmod 600 "$PWD/${name}"
    chmod 644 "$PWD/${name}".pub
    clear

    echo -e "file: $PWD/${name}\\n"
    cat "$PWD/${name}"

    echo -e "\\nfile: $PWD/${name}.pub\\n"
    cat "$PWD/${name}.pub"

    echo
}

# export the public ssh key stored inside a private ssh key
keytopub()
{
    clear; ls -1AhFv --color --group-directories-first

    local opub okey

    echo -e "Enter the full paths for each file\\n"
    read -p 'Private key: ' okey
    read -p 'Public key: ' opub
    clear
    if [ -f "${okey}" ]; then
        chmod 600 "${okey}"
    else
        echo -e "Warning: file missing = ${okey}\\n"
        read -p 'Press Enter to exit.'
        exit 1
    fi
    ssh-keygen -b '4096' -y -f "${okey}" > "${opub}"
    chmod 644 "${opub}"
    cp "${opub}" "${HOME}"/.ssh/authorized_keys
    chmod 600 "${HOME}"/.ssh/authorized_keys
    unset "${okey}"
    unset "${opub}"
}

# install colordiff package :)
cdiff() { clear; colordiff "${1}" "${2}"; }

# GZIP
gzip() { clear; gzip -d "${@}"; }

# get system time
show_time() { clear; date +%r | cut -d " " -f1-2 | grep -E '^.*$'; }

# CHANGE DIRECTORY
cdsys() { pushd "${HOME}"/system || exit 1; cl; }

##################
## SOURCE FILES ##
##################

sbrc()
{
    clear

    source "${HOME}"/.bashrc && echo -e "The command was a success!\\n" || echo -e "The command failed!\\n"
    sleep 1

    clear; ls -1AhFv --color --group-directories-first
}

spro()
{
    clear

    source "${HOME}"/.profile && echo -e "The command was a success!\\n" || echo -e "The command failed!\\n"
    sleep 1

    clear; ls -1AhFv --color --group-directories-first
}

####################
## ARIA2 COMMANDS ##
####################

# ARIA2 DAEMON IN BACKGROUND
aria2_on()
{
    clear

    if aria2c --conf-path="${HOME}"/.aria2/aria2.conf; then
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

    local file link

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

# PRINT lan/wan IP
myip()
{
    clear
    lan="$(hostname -I)"
    wan="$(dig +short myip.opendns.com @resolver1.opendns.com)"
    clear
    echo "Internal IP (lan) address: ${lan}"
    echo "External IP (wan) address: ${wan}"
}

# WGET COMMAND
mywget()
{
    clear; ls -1AhFv --color --group-directories-first

    local outfile url

    if [ -z "${1}" ] || [ -z "${2}" ]; then
        read -p 'Please enter the output file name: ' outfile
        echo
        read -p 'Please enter the url: ' url
        clear
        wget --out-file="${outfile}" "${url}"
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
        clear
    else
        sudo rm -r "${1}"
        clear
    fi
}

# RM file
rmf()
{
    clear

    local i

    if [ -z "${1}" ]; then
        read -p 'Please enter the file name to remove: ' i
        clear
        sudo rm "${i}"
        clear
    else
        sudo rm "${1}"
        clear
    fi
}

#################
## IMAGEMAGICK ##
#################

# OPTIMIZE WITHOUT OVERWRITING THE ORIGINAL IMAGES
imo()
{
    clear

    local i
    # find all jpg files and create temporary cache files from them
    for i in *.jpg; do
        echo -e "\\nCreating two temporary cache files: ${i%%.jpg}.mpc + ${i%%.jpg}.cache\\n"
        dimensions="$(identify -format '%wx%h' "${i}")"
        convert "${i}" -monitor -filter Triangle -define filter:support=2 -thumbnail "${dimensions}" -strip \
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

# OPTIMIZE AND OVERWRITE THE ORIGINAL IMAGES
imow()
{
    clear
    local i dimensions random v v_noslash

    # Delete any useless zone idenfier files that spawn from copying a file from windows ntfs into a WSL directory
    find . -name "*:Zone.Identifier" -type f -delete 2>/dev/null

    # find all jpg files and create temporary cache files from them
    for i in *.jpg
    do
        # create a variable to hold a randomized directory name to protect against crossover if running
        # this function more than once at a time
        random="$(mktemp --directory)"
        echo '========================================================================================================='
        echo
        echo "Working Directory: ${PWD}"
        echo
        printf "Converting: %s\n             >> %s\n              >> %s\n               >> %s\n" "${i}" "${i%%.jpg}.mpc" "${i%%.jpg}.cache" "${i%%.jpg}-IM.jpg"
        echo
        echo '========================================================================================================='
        echo
        dimensions="$(identify -format '%wx%h' "${i}")"
        convert "${i}" -monitor -filter 'Triangle' -define filter:support='2' -thumbnail "${dimensions}" -strip \
            -unsharp '0.25x0.08+8.3+0.045' -dither None -posterize '136' -quality '82' -define jpeg:fancy-upsampling='off' \
            -define png:compression-filter='5' -define png:compression-level='9' -define png:compression-strategy='1' \
            -define png:exclude-chunk='all' -auto-level -enhance -interlace 'none' -colorspace 'sRGB' "${random}/${i%%.jpg}.mpc"
        clear
        for i in "${random}"/*.mpc
        do
            if [ -f "${i}" ]; then
                convert "${i}" -monitor "${i%%.mpc}.jpg"
                if [ -f "${i%%.mpc}.jpg" ]; then
                    CWD="$(echo "${i}" | sed 's:.*/::')"
                    mv "${i%%.mpc}.jpg" "${PWD}/${CWD%%.*}-IM.jpg"
                    rm -f "${PWD}/${CWD%%.*}.jpg"
                    for v in "${i}"
                    do
                        v_noslash="${v%/}"
                        rm -fr "${v_noslash%/*}"
                        clear
                    done
                else
                    clear
                    echo 'Error: Unable to find the optimized image.'
                    echo
                    return 1
                fi
            fi
        done
    done

    # The text-to-speech below requries the following packages:
    # pip install gTTS; sudo apt -y install sox libsox-fmt-all
    if [ "${?}" -eq '0' ]; then
        google_speech 'Image conversion completed.'
        return 0
    else
        google_speech 'Image conversion failed.'
        return 1
    fi
}

# DOWNSAMPLE IMAGE TO 50% OF THE ORIGINAL DIMENSIONS USING SHARPER SETTINGS
im50()
{
    clear
    local i

    for i in *.jpg
    do
        convert "${i}" -monitor -colorspace sRGB -filter 'LanczosRadius' -distort Resize 50% -colorspace sRGB "${i}"
    done
}

##################################################
## SHOW file name AND SIZE IN CURRENT DIRECTORY ##
##################################################

fs() { clear; du --max-depth=1 -abh | grep -Eo '^[0-9A-Za-z\_\-\.]*|[a-zA-Z0-9\_\-]+\.jpg$'; }

big_img()
{
    clear
    sudo find . -size +10M -type f -name *.jpg 2>/dev/null
}

###########################
## SHOW NVME TEMPERATURE ##
###########################

nvme_temp()
{
    clear

    local n0 n1 n2

    n0="$(sudo nvme smart-log /dev/nvme0n1)"
    n1="$(sudo nvme smart-log /dev/nvme1n1)"
    n2="$(sudo nvme smart-log /dev/nvme2n1)"

    printf "nvme0n1:\n\n%s\n\nnvme1n1:\n\n%s\n\nnvme2n1:\n\n%s\n\n" "${n0}" "${n1}" "${n2}"
}

#############################
## REFRESH THUMBNAIL CACHE ##
#############################

rftn()
{
    clear
    sudo rm -fr "${HOME}"/.cache/thumbnails/*
    ls -al "${HOME}"/.cache/thumbnails
}

#######################
## NAUTILUS COMMANDS ##
#######################

nopen()
{
    nohup nautilus -w "${1}" &>/dev/null &
}

#####################
## FFMPEG COMMANDS ##
#####################

cuda_purge()
{
    clear

    local answer

    echo 'Do you want to completely remove the cuda-sdk-toolkit?'
    echo
    echo 'WARNING: Do not reboot your PC without reinstalling the nvidia-driver first!'
    echo
    echo '[1] Yes'
    echo '[2] Exit'
    echo
    read -p 'Your choices are (1 or 2): ' answer
    clear

    if [[ "${answer}" -eq '1' ]]; then
        echo 'Purging the cuda-sdk-toolkit from your computer.'
        echo '================================================'
        echo
        sudo apt-get -y --purge remove "*cublas*" "cuda*" "nsight*" 
        sudo apt -y autoremove
        sudo apt update
    elif [[ "${answer}" -eq '2' ]]; then
        return 0
    fi
}

##############################
## LIST LARGE FILES BY TYPE ##
##############################

large_files()
{
    clear

    local answer

    echo 'Input the file extension to search for without a dot: '
    echo
    read -p 'Enter your choice: ' answer
    clear
    find "${PWD}" -type f -name "*.${answer}" -printf '%h\n' | sort -u -o 'large-files.txt'
    if [ -f 'large-files.txt' ]; then
        sudo gedit 'large-files.txt'
    fi
}

###############
## MEDIAINFO ##
###############

mi()
{
    clear

    local i

    if [ -z "${1}" ]; then
        ls -1AhFv --color --group-directories-first
        echo
        read -p 'Please enter the relative file path: ' i
        clear
        mediainfo "${i}"
    else
        mediainfo "${1}"
    fi
}

############
## FFMPEG ##
############

ffm() { clear; bash <(curl -sSL 'http://ffmpeg.optimizethis.net'); }
ffp() { clear; bash <(curl -sSL 'http://ffpb.optimizethis.net'); }


############################
## DEL FILES BY EXTENSION ##
############################

# SHELL FILES
rm_sh()
{
    local del_ans i
    clear

    for i in '*.sh'
    do
        echo ${i[@]}
        echo
        echo 'Do you want to delete these files?'
        echo
        echo '[1] Yes'
        echo '[2] No'
        echo
        read -p 'Your choices are (1 or 2): ' del_ans
        clear
        case "$del_ans" in
            1)
                sudo rm -r ${i[@]}
                cl
                break
                ;;
            2)
                break
                ;;
            *)
                clear
                echo 'Error: Bad user input. Try the command again.'
                echo
                break
                ;;
        esac
    done
}

# TAR FILES
rm_tar()
{
    local del_ans i
    clear

    for i in '*.tar'
    do
        echo ${i[@]}
        echo
        echo 'Do you want to delete these files?'
        echo
        echo '[1] Yes'
        echo '[2] No'
        echo
        read -p 'Your choices are (1 or 2): ' del_ans
        clear
        case "$del_ans" in
            1)
                sudo rm -r ${i[@]}
                cl
                break
                ;;
            2)
                break
                ;;
            *)
                clear
                echo 'Error: Bad user input. Try the command again.'
                echo
                break
                ;;
        esac
    done
}

# PYTHON FILES
rm_py()
{
    local del_ans i
    clear

    for i in '*.py'
    do
        echo ${i[@]}
        echo
        echo 'Do you want to delete these files?'
        echo
        echo '[1] Yes'
        echo '[2] No'
        echo
        read -p 'Your choices are (1 or 2): ' del_ans
        clear
        case "$del_ans" in
            1)
                sudo rm -r ${i[@]}
                cl
                break
                ;;
            2)
                break
                ;;
            *)
                clear
                echo 'Error: Bad user input. Try the command again.'
                echo
                break
                ;;
        esac
    done
}

# REMOVE DIRECTORIES
rm_dir()
{
    local del_ans i
    clear

    for i in '*/'
    do
        echo ${i[@]}
        echo
        echo 'Do you want to delete these files?'
        echo
        echo '[1] Yes'
        echo '[2] No'
        echo
        read -p 'Your choices are (1 or 2): ' del_ans
        clear
        case "$del_ans" in
            1)
                sudo rm -fr ${i[@]}
                cl
                break
                ;;
            2)
                break
                ;;
            *)
                clear
                echo 'Error: Bad user input. Try the command again.'
                echo
                break
                ;;
        esac
    done
}


##########################
## XCLIP COPY AND PASTE ##
##########################

cp_text() { echo "$@" | xclip -sel clip; }

cp_file() { cat "$1" | xclip -sel clip; }

pclip() { xclip -sel clip -o; }
