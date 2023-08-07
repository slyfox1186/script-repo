#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2001,SC2162,SC2317

######################################################################################
## WHEN LAUNCHING CERTAIN PROGRAMS FROM THE TERMINAL, SUPPRESS ANY WARNING MESSAGES ##
######################################################################################

gedit() { "$(type -P gedit)" "${@}" &>/dev/null; }
geds() { "$(type -P sudo)" -H -u root "$(type -P gedit)" "${@}" &>/dev/null; }

gted() { "$(type -P gted)" "${@}" &>/dev/null; }
gteds() { "$(type -P sudo)" -H -u root "$(type -P gted)" "${@}" &>/dev/null; }

###################
## FIND COMMANDS ##
###################

ffind()
{
    clear

    local fname fpath ftype

    read -p 'Enter the name to search for: ' fname
    echo
    read -p 'Enter a type of file (d|f|blank): ' ftype
    echo
    read -p 'Enter the starting path: ' fpath
    clear

    if [ -n "${fname}" ] && [ -z "${ftype}" ] && [ -z "${fpath}" ]; then
        sudo find . -iname "${fname}" | while read line; do echo "${line}"; done
    elif [ -n "${fname}" ] && [ -z "${ftype}" ] && [ -n "${fpath}" ]; then
        sudo find "${fpath}" -iname "${fname}" | while read line; do echo "${line}"; done
    elif [ -n "${fname}" ] && [ -n "${ftype}" ] && [ -n "${fpath}" ]; then
        sudo find "${fpath}" -type "${ftype}" -iname "${fname}" | while read line; do echo "${line}"; done
    elif [ -n "${fname}" ] && [ -z "${ftype}" ] && [ "${fpath}" ]; then
        sudo find . -iname "${fname}" | while read line; do echo "${line}"; done
    elif [ -n "${fname}" ] && [ -n "${ftype}" ] && [ "${fpath}" = '.' ]; then
        sudo find . -type "${ftype}" -iname "${fname}" | while read line; do echo "${line}"; done
     fi
}

######################
## UNCOMPRESS FILES ##
######################

untar()
{
    clear

    local ext file

    for file in *.*
    do
        ext="${file##*.}" && mkdir -p "${PWD}/${file%%.*}"

        case "${ext}" in
            7z|zip)
                7z x -o"${PWD}/${file%%.*}" "${PWD}/${file}"
                ;;
            bz2|gz|xz)
                jflag=''
                [[ "${ext}" == 'bz2' ]] && jflag='j'
                tar -xf${jflag} "${PWD}/${file}" -C "${PWD}/${file%%.*}"
                ;;
            *)
                printf "%s\n\n%s\n\n" \
                    'No archives to extract were found.' \
                    'Make sure you run this function in the same directory as the archives'
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
rmd()
{
    clear
    awk '!seen[${0}]++' "${1}"
}

# REMOVE CONSECUTIVE DUPLICATE LINES: OUTPUTS TO TERMINAL
rmdc() { clear; awk 'f!=${0}&&f=${0}' "${1}"; }

# REMOVE ALL DUPLICATE LINES AND REMOVES TRAILING SPACES BEFORE COMPARING: REPLACES THE file
rmdf()
{
    clear
    perl -i -lne 's/\s*$//; print if ! $x{$_}++' "${1}"
    gted "${1}"
}

###################
## file COMMANDS ##
###################

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

# DOWNLOAD AN APT PACKAGE + ALL ITS DEPENDENCIES IN ONE GO
aptdl() { wget -c "$(apt-get install --reinstall --print-uris -qq ${1} 2>/dev/null | cut -d''\''' -f2)"; }

# CLEAN
clean()
{
    clear
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt -y purge
}

# UPDATE
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

# FIX BROKEN APT PACKAGES
fix()
{
    clear
    if [ -f '/tmp/apt.lock' ]; then
        sudo rm '/tmp/apt.lock'
    fi
    sudo apt -f -y install
    apt --fix-broken install
    apt --fix-missing update
    dpkg --configure -a
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt update
}

listd()
{
    clear
    local search_cache

    if [ -n "${1}" ]; then
        sudo apt list -- "*${1}*"-dev | awk -F'/' '{print $1}'
    else
        read -p 'Enter the string to search: ' search_cache
        clear
        sudo apt list -- "*${1}*-dev" | awk -F'/' '{print $1}'
    fi
}


list()
{
    clear
    local search_cache

    if [ -n "${1}" ]; then
        sudo apt list "*${1}*" | awk -F'/' '{print $1}'
    else
        read -p 'Enter the string to search: ' search_cache
        clear
        sudo apt list "*${1}*" | awk -F'/' '{print $1}'
    fi
}

# USE sudo apt TO SEARCH FOR ALL APT PACKAGES BY PASSING A NAME TO THE FUNCTION
aptsc()
{
    clear
    local search

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
    clear
    local cache

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
    gted "${HOME}"/tmp/packages.list
}

# PIPE ALL DEVELOPMENT PACKAGES NAMES TO file
getdev()
{
    apt-cache search dev |
    grep "\-dev" |
    cut -d ' ' -f1 |
    sort > 'dev-packages.list'
    gted 'dev-packages.list'
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

    chmod 600 "${PWD}/${name}"
    chmod 644 "${PWD}/${name}".pub
    clear

    echo -e "file: ${PWD}/${name}\\n"
    cat "${PWD}/${name}"

    echo -e "\\nfile: ${PWD}/${name}.pub\\n"
    cat "${PWD}/${name}.pub"
    echo
}

# Export the public ssh key stored inside a private ssh key
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

# ARIA2 DAEMON IN THE BACKGROUND
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

# RUN ARIA2 AND DOWNLOAD FILES TO THE CURRENT FOLDER
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
        read -p 'Please enter the URL: ' url
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
        for cfile in /tmp/*.mpc; do
        # find the temporary cache files created above and output optimized jpg files
            if [ -f "${cfile}" ]; then
                echo -e "\\nOverwriting original file with optimized self: ${cfile} >> ${cfile%%.mpc}.jpg\\n"
                convert "${cfile}" -monitor "${cfile%%.mpc}.jpg"
                # overwrite the original image with its optimized version
                # by moving it from the tmp directory to the source directory
                if [ -f "${cfile%%.mpc}.jpg" ]; then
                    mv "${cfile%%.mpc}.jpg" "${PWD}"
                    # delete both cache files before continuing
                    rm "${cfile}"
                    rm "${cfile%%.mpc}.cache"
                    clear
                fi
            fi
        done
    done
}

# OPTIMIZE AND OVERWRITE THE ORIGINAL IMAGES
imow()
{
    local apt_pkgs cnt_queue cnt_total dimensions fext missing_pkgs pip_lock random_dir tmp_file v_noslash

    clear

    # THE FILE EXTENSION TO SEARCH FOR (DO NOT INCLUDE A '.' WITH THE EXTENSION)
    fext=jpg

    #
    # REQUIRED APT PACKAGES
    #

    apt_pkgs=(sox libsox-dev)
    for i in ${apt_pkgs[@]}
    do
        missing_pkg="$(dpkg -l | grep "${i}")"
        if [ -z "${missing_pkg}" ]; then
            missing_pkgs+=" ${i}"
        fi
    done

    if [ -n "${missing_pkgs}" ]; then
        sudo apt -y install ${missing_pkgs}
        sudo apt -y autoremove
        clear
    fi
    unset apt_pkgs i missing_pkg missing_pkgs

    #
    # REQUIRED PIP PACKAGES
    #

    pip_lock="$(find /usr/lib/python3* -name EXTERNALLY-MANAGED)"
    if [ -n "${pip_lock}" ]; then
        sudo rm "${pip_lock}"
    fi
    if ! pip show google_speech &>/dev/null; then
        pip install google_speech
    fi

    unset p pip_lock pip_pkgs missing_pkg missing_pkgs
    # DELETE ANY USELESS ZONE IDENFIER FILES THAT SPAWN FROM COPYING A FILE FROM WINDOWS NTFS INTO A WSL DIRECTORY
    find . -type f -name "*:Zone.Identifier" -delete 2>/dev/null

    # GET THE FILE COUNT INSIDE THE DIRECTORY
    cnt_queue=$(find . -maxdepth 2 -type f -iname "*.jpg" | wc -l)
    cnt_total=$(find . -maxdepth 2 -type f -iname "*.jpg" | wc -l)
    # GET THE UNMODIFIED PATH OF EACH MATCHING FILE

    for i in ./*."${fext}"
    do
        cnt_queue=$(( cnt_queue-1 ))

        cat <<EOF
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

File Path: ${PWD}

Folder: $(basename "${PWD}")

Total Files:    ${cnt_total}
Files in queue: ${cnt_queue}

Converting:  ${i}

 >> ${i%%.jpg}.mpc

    >> ${i%%.jpg}.cache

       >> ${i%%.jpg}-IM.jpg

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF
        echo
        random_dir="$(mktemp -d)"
        dimensions="$(identify -format '%wx%h' "${i}")"
        convert "${i}" -monitor -filter Triangle -define filter:support=2 -thumbnail "${dimensions}" -strip \
            -unsharp '0.25x0.08+8.3+0.045' -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off \
            -auto-level -enhance -interlace none -colorspace sRGB "${random_dir}/${i%%.jpg}.mpc"


        for file in "${random_dir}"/*.mpc
        do
            convert "${file}" -monitor "${file%%.mpc}.jpg"
            tmp_file="$(echo "${file}" | sed 's:.*/::')"
            mv "${file%%.mpc}.jpg" "${PWD}/${tmp_file%%.*}-IM.jpg"
            rm -f "${PWD}/${tmp_file%%.*}.jpg"
            for v in ${file}
            do
                v_noslash="${v%/}"
                rm -fr "${v_noslash%/*}"
            done
        done
    done

    if [ "${?}" -eq '0' ]; then
        google_speech 'Image conversion completed.' 2>/dev/null
        exit 0
    else
        echo
        google_speech 'Image conversion failed.' 2>/dev/null
        echo
        read -p 'Press enter to exit.'
        exit 1
    fi
}

# DOWNSAMPLE IMAGE TO 50% OF THE ORIGINAL DIMENSIONS USING SHARPER SETTINGS
im50()
{
    clear
    local i

    for i in *.jpg
    do
        convert "${i}" -monitor -colorspace sRGB -filter LanczosRadius -distort Resize 50% -colorspace sRGB "${i}"
    done
}

imdl()
{
    clear
    curl -Lso imow https://raw.githubusercontent.com/slyfox1186/script-repo/main/bash/installer%20scripts/imagemagick/scripts/imagick-run-script.sh; bash imow
    sudo chown "${USER}":"${USER}" imow
    sudo chmod 755 imow
    clear; ls -1AhFv --color --group-directories-first
}

##################################################
## SHOW file name AND SIZE IN CURRENT DIRECTORY ##
##################################################

fs() { clear; du --max-depth=1 -abh | grep -Eo '^[0-9A-Za-z\_\-\.]*|[a-zA-Z0-9\_\-]+\.jpg$'; }

big_img() { clear; sudo find . -size +10M -type f -name '*.jpg' 2>/dev/null; }

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
        sudo sudo apt -y --purge remove "*cublas*" "cuda*" "nsight*"
        sudo sudo apt -y autoremove
        sudo sudo apt update
    elif [[ "${answer}" -eq '2' ]]; then
        return 0
    fi
}

ffdl()
{
    clear
    curl -Lso ffscripts.sh https://ffdl.optimizethis.net; bash ffscripts.sh
    sudo rm ffscripts.sh
    clear; ls -1AhFv --color --group-directories-first
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
        sudo ged 'large-files.txt'
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

cdff() { clear; cd "${HOME}/tmp/ffmpeg-build" || exit 1; cl; }
ffm() { clear; bash <(curl -sSL 'http://ffmpeg.optimizethis.net'); }
ffp() { clear; bash <(curl -sSL 'http://ffpb.optimizethis.net'); }

####################
## LIST PPA REPOS ##
####################

listppas()
{
    clear

    local apt host user ppa entry

    for apt in $(find /etc/apt/ -type f -name \*.list)
    do
        grep -Po "(?<=^deb\s).*?(?=#|$)" "${apt}" | while read entry
        do
            host="$(echo "${entry}" | cut -d/ -f3)"
            user="$(echo "${entry}" | cut -d/ -f4)"
            ppa="$(echo "${entry}" | cut -d/ -f5)"
            #echo sudo apt-add-repository ppa:${USER}/${ppa}
            if [ "ppa.launchpad.net" = "${host}" ]; then
                echo sudo apt-add-repository ppa:"${USER}/${ppa}"
            else
                echo sudo apt-add-repository \'deb "${entry}"\'
            fi
        done
    done
}

#########################
## NVIDIA-SMI COMMANDS ##
#########################

gpu_mon()
{
    clear
    nvidia-smi dmon
}

################################################################
## PRINT THE NAME OF THE DISTRIBUTION YOU ARE CURRENTLY USING ##
################################################################

my_os()
{
    local name version
    clear

    name="$(eval lsb_release -si 2>/dev/null)"
    version="$(eval lsb_release -sr 2>/dev/null)"

    clear

    printf "%s\n\n" "Linux OS: ${name} ${version}"
}

##############################################
## MONITOR CPU AND MOTHERBOARD TEMPERATURES ##
##############################################

hw_mon()
{
    clear

    local found

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

    sudo watch -n1 sensors
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
7z_7z()
{
    local source output
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

tar_xz()
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

#####################
## FFMPEG COMMANDS ##
#####################

ffr() { clear; bash "${1}" -b --latest --enable-gpl-and-non-free; }
ffrv() { clear; bash -v "${1}" -b --latest --enable-gpl-and-non-free; }

###################
## WRITE CACHING ##
###################

wcache()
{
    clear

    local choice

    lsblk
    echo
    read -p 'Enter the drive id to turn off write caching (/dev/sdX w/o /dev/): ' choice

    sudo hdparm -W 0 /dev/"${choice}"
}

rmd()
{
    clear

    local dirs

    if [ -z "${*}" ]; then
        clear; ls -1A --color --group-directories-first
        echo
        read -p 'Enter the directory path(s) to delete: ' dirs
     else
        dirs="${*}"
    fi

    sudo rm -fr "$dirs"
    clear
    ls -1A --color --group-directories-first
}


rmf()
{
    clear

    local files

    if [ -z "${*}" ]; then
        clear; ls -1A --color --group-directories-first
        echo
        read -p 'Enter the file path(s) to delete: ' files
     else
        files="${*}"
    fi

    sudo rm "${file}s"
    clear
    ls -1A --color --group-directories-first
}

## REMOVE BOM
rmb()
{
    sed -i '1s/^\xEF\xBB\xBF//' "${1}"
}

## LIST INSTALLED PACKAGES BY ORDER OF IMPORTANCE

list_pkgs() { clear; dpkg-query -Wf '${Package;-40}${Priority}\n' | sort -b -k2,2 -k1,1; }

## FIX USER FOLDER PERMISSIONS up = user permissions

fix_up()
{
    find "${HOME}"/.gnupg -type f -exec chmod 600 {} \;
    find "${HOME}"/.gnupg -type d -exec chmod 700 {} \;
    find "${HOME}"/.ssh -type d -exec chmod 700 {} \; 2>/dev/null
    find "${HOME}"/.ssh/id_rsa.pub -type f -exec chmod 644 {} \; 2>/dev/null
    find "${HOME}"/.ssh/id_rsa -type f -exec chmod 600 {} \; 2>/dev/null
}

## SET DEFAULT PROGRAMS
set_default()
{
    local choice target name link importance

    clear

    printf "%s\n\n%s\n%s\n\n" \
        'Set default programs' \
        'Example: sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 50' \
        'Example: sudo update-alternatives --install <target> <program_name> <link> <importance>'

    read -p 'Enter the target: ' target
    read -p 'Enter the program_name: ' name
    read -p 'Enter the link: ' link
    read -p 'Enter the importance: ' importance
    clear

    printf "%s\n\n%s\n\n%s\n%s\n\n" \
        "You have chosen: sudo update-alternatives --install ${target} ${name} ${link} ${i}mportance" \
        'Would you like to continue?' \
        '[1] Yes' \
        '[2] No'

    read -p 'Your choices are (1 or 2): ' choice
    clear

    case "${choice}" in
        1)      sudo update-alternatives --install "${target}" "${name}" "${link}" "${i}mportance";;
        2)      return 0;;
        *)      return 0;;
    esac
}

## COUNT FILES IN THE DIRECTORY
cnt_dir()
{
    local keep_cnt
    clear
    keep_cnt="$(find . -maxdepth 1 -type f | wc -l)"
    printf "%s %'d\n\n" "The total directory file count is (non-recursive):" "${keep_cnt}"
}

cnt_dirr()
{
    local keep_cnt
    clear
    keep_cnt="$(find . -type f | wc -l)"
    printf "%s %'d\n\n" "The total directory file count is (recursive):" "${keep_cnt}"
}

##############
## TEST GCC ##
##############

test_gcc()
{
    local answer

# CREATE A TEMPORARY C FILE TO RUN OUR TESTS AGAINST
cat > /tmp/hello.c <<'EOF'
#include <stdio.h>
int main(void)
{
   printf("Hello World!\n");
   return 0;
}
EOF

    if [ -n "${1}" ]; then
        "${1}" -Q -v /tmp/hello.c
    else
        clear
        read -p 'Enter the GCC binary you wish to test (example: gcc-11): ' answer
        clear
        "${answer}" -Q -v /tmp/hello.c
    fi
    sudo rm /tmp/hello.c
}

############################
## UNINSTALL DEBIAN FILES ##
############################

rm_deb()
{
    local fname
    clear
    if [ -n "${1}" ]; then
        sudo dpkg -r "$(dpkg -f "${1}" Package)"
    else
        read -p 'Please enter the Debian file name: ' fname
        clear
        sudo dpkg -r "$(dpkg -f "${fname}" Package)"
    fi
}

######################
## KILLALL COMMANDS ##
######################

tkapt()
{
    local i list
    clear

    list=(apt apt-get aptitude dpkg)

    for i in ${list[@]}
    do
        sudo killall -9 "${i}" 2>/dev/null
    done
}

gc()
{
    local url
    clear

    if [ -n "${1}" ]; then
        nohup google-chrome "${1}" 2>/dev/null >/dev/null
    else
        read -p 'Enter a URL: ' url
        nohup google-chrome "${url}" 2>/dev/null >/dev/null
    fi
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

nhe()
{
    clear
    nohup "${1}" &>/dev/null &
    exit
    exit
}

nhse()
{
    clear
    nohup sudo "${1}" &>/dev/null &
    exit
    exit
}

## NAUTILUS COMMANDS

nopen()
{
    clear
    nohup nautilus -w "${1}" &>/dev/null &
    exit
}

tkan()
{
    local parent_dir
    parent_dir="${PWD}"
    killall -9 nautilus
    sleep 1
    nohup nautilus -w "${parent_dir}" &>/dev/null &
    exit
}

#######################
## UPDATE ICON CACHE ##
#######################

up_icon()
{
    local i pkgs
    clear

    pkgs=(gtk-update-icon-cache hicolor-icon-theme)

    for i in ${pkgs[@]}
    do
        if ! sudo dpkg -l "${i}"; then
            sudo apt -y install "${i}"
            clear
        fi
    done

    sudo gtk-update-icon-cache -f /usr/share/icons/hicolor
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
        --user-agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36' \
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
        exit 0
    else
        google_speech 'Download failed.' 2>/dev/null
        read -p 'Press enter to exit.'
        exit 1
    fi

    find . -type f -iname "*:Zone.Identifier" -delete 2>/dev/null

    clear; ls -1AhFv --color --group-directories-first
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
        --user-agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36' \
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
        exit 0
    else
        google_speech 'Download failed.' 2>/dev/null
        read -p 'Press enter to exit.'
        exit 1
    fi

    find . -type f -iname "*:Zone.Identifier" -delete 2>/dev/null

    clear; ls -1AhFv --color --group-directories-first
}

#####################
## GET FILES SIZES ##
#####################

jsize()
{
    local random_dir size
    clear

    random_dir="$(mktemp -d)"
    read -p 'Enter the image size (units in MB): ' size
    find . -size +"${size}"M -type f -iname "*.jpg" > "${random_dir}/img-sizes.txt"
    sed -i "s/^..//g" "${random_dir}/img-sizes.txt"
    sed -i "s|^|${PWD}\/|g" "${random_dir}/img-sizes.txt"
    clear
    nohup gted "${random_dir}/img-sizes.txt" &>/dev/null &
}
