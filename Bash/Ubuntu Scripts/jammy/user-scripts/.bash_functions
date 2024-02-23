export user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'

######################################################################################
## WHEN LAUNCHING CERTAIN PROGRAMS FROM THE TERMINAL, SUPPRESS ANY WARNING MESSAGES ##
######################################################################################

gedit() { "$(type -P gedit)" "$@" &>/dev/null; }
geds() { sudo -Hu root "$(type -P gedit)" "$@" &>/dev/null; }

gnome-text-editor() { "$(type -P gnome-text-editor)" "$@" &>/dev/null; }
gnome-text-editors() { sudo -Hu root "$(type -P gnome-text-editor)" "$@" &>/dev/null; }

################################################
## GET THE OS AND ARCH OF THE ACTIVE COMPUTER ##
################################################

this_pc() {
    local OS VER
    
    source /etc/os-release
    OS="$NAME"
    VER="$VERSION_ID"

    clear
    printf "%s\n%s\n\n" \
        "Operating System: $OS" \
        "Specific Version: $VER"
}

###################
## FIND COMMANDS ##
###################

ffind() {
    local fname="$1"
    local ftype="$2"
    local fpath="$3"
    local find_cmd

    # Check if any argument is passed
    if [ $# -eq 0 ]; then
        read -p 'Enter the name to search for: ' fname
        echo
        read -p 'Enter a type of file (d|f|blank for any): ' ftype
        echo
        read -p 'Enter the starting path (blank for current directory): ' fpath
        echo
    fi

    # Default to the current directory if fpath is empty
    fpath=${fpath:-.}

    # Construct the find command based on the input
    find_cmd="find \"$fpath\" -iname \"$fname\""
    if [ -n "$ftype" ]; then
        if [[ "$ftype" == "d" || "$ftype" == "f" ]]; then
            find_cmd="$find_cmd -type $ftype"
        else
            echo "Invalid file type. Please use 'd' for directories or 'f' for files."
            return 1
        fi
    fi

    # Execute the command
    eval "$find_cmd"
}

######################
## UNCOMPRESS FILES ##
######################

untar() {
    local archive ext gflag jflag xflag
    clear

    for archive in *.*
    do
        ext="${archive##*.}"

        [[ ! -d "$PWD"/"${archive%%.*}" ]] && mkdir -p "$PWD"/"${archive%%.*}"

        unset flag
        case "${ext}" in
            7z|zip) 7z x -o./"${archive%%.*}" ./"$archive";;
            bz2)    flag='jxf';;
            gz|tgz) flag='zxf';;
            xz|lz)  flag='xf';;
        esac

        [ -n "$flag" ] && tar $flag ./"$archive" -C ./"${archive%%.*}" --strip-components 1
    done
}
            
##################
## CREATE FILES ##
##################

mf() {
    local i
    clear

    if [ -z "$1" ]; then
        read -p 'Enter file name: ' i
        clear
        if [ ! -f "$i" ]; then touch "$i"; fi
        chmod 744 "$i"
    else
        if [ ! -f "$1" ]; then touch "$1"; fi
        chmod 744 "$1"
    fi

    clear; ls -1AhFv --color --group-directories-first
}

mdir() {
    local dir
    clear

    if [[ -z "$1" ]]; then
        read -p 'Enter directory name: ' dir
        clear
        mkdir -p  "$PWD/$dir"
        cd "$PWD/$dir" || exit 1
    else
        mkdir -p "$1"
        cd "$PWD/$1" || exit 1
    fi

    clear; ls -1AhFv --color --group-directories-first
}

##################
## AWK COMMANDS ##
##################

# REMOVED ALL DUPLICATE LINES: OUTPUTS TO TERMINAL
rmd() { clear; awk '!seen[${0}]++' "$1"; }

# REMOVE CONSECUTIVE DUPLICATE LINES: OUTPUTS TO TERMINAL
rmdc() { clear; awk 'f!=${0}&&f=${0}' "$1"; }

# REMOVE ALL DUPLICATE LINES AND REMOVES TRAILING SPACES BEFORE COMPARING: REPLACES THE file
rmdf() {
    clear
    perl -i -lne 's/\s*$//; print if ! $x{$_}++' "$1"
    gnome-text-editor "$1"
}

###################
## file COMMANDS ##
###################

# COPY file
cpf() {
    clear

    if [ ! -d "$HOME/tmp" ]; then
        mkdir -p "$HOME/tmp"
    fi

    cp "$1" "$HOME/tmp/$1"

    chown -R "$USER":"$USER" "$HOME/tmp/$1"
    chmod -R 744 "$HOME/tmp/$1"

    clear
    ls -1AhFv --color --group-directories-first
}

# MOVE file
mvf() {
    clear

    if [ ! -d "$HOME/tmp" ]; then
        mkdir -p "$HOME/tmp"
    fi

    mv "$1" "$HOME/tmp/$1"

    chown -R "$USER":"$USER" "$HOME/tmp/$1"
    chmod -R 744 "$HOME/tmp/$1"

    clear
    ls -1AhFv --color --group-directories-first
}

##################
## APT COMMANDS ##
##################

# DOWNLOAD AN APT PACKAGE + ALL ITS DEPENDENCIES IN ONE GO
apt_dl() {
    clear
    wget -c "$(apt --print-uris -qq --reinstall install $1 2>/dev/null | cut -d''\''' -f2)"
    clear; ls -1AhFv --color --group-directories-first
}

# CLEAN
clean() {
    clear
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt -y purge
}

# UPDATE
update() {
    clear
    sudo apt update
    sudo apt -y full-upgrade
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt -y purge
}

# FIX BROKEN APT PACKAGES
fix() {
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
}

list() {
    local search_cache
    clear

    if [ -n "$1" ]; then
        sudo apt list "*$1*" 2>/dev/null | awk -F'/' '{print $1}'
    else
        read -p 'Enter the string to search: ' search_cache
        clear
        sudo apt list "*$1*" 2>/dev/null | awk -F'/' '{print $1}'
    fi
}

listd() {
    local search_cache
    clear

    if [ -n "$1" ]; then
        sudo apt list -- "*$1*"-dev 2>/dev/null | awk -F'/' '{print $1}'
    else
        read -p 'Enter the string to search: ' search_cache
        clear
        sudo apt list -- "*$1*"-dev 2>/dev/null | awk -F'/' '{print $1}'
    fi
}

# USE SUDO APT TO SEARCH FOR ALL APT PACKAGES BY PASSING A NAME TO THE FUNCTION
apts() {
    local search
    clear

    if [ -n "$1" ]; then
        sudo apt search "$1 ~i" -F "%p"
    else
        read -p 'Enter the string to search: ' search
        clear
        sudo apt search "$search ~i" -F "%p"
    fi
}

# USE APT CACHE TO SEARCH FOR ALL APT PACKAGES BY PASSING A NAME TO THE FUNCTION
csearch() {
    local cache
    clear

    if [ -n "$1" ]; then
        apt-cache search --names-only "${1}.*" | awk '{print $1}'
    else
        read -p 'Enter the string to search: ' cache
        clear
        apt-cache search --names-only "${cache}.*" | awk '{print $1}'
    fi
}

# FIX MISSING GPNU KEYS USED TO UPDATE PACKAGES
fix_key() {
    local file url
    clear

    if [[ -z "$1" ]] && [[ -z "$2" ]]; then
        read -p 'Enter the file name to store in /etc/apt/trusted.gpg.d: ' file
        read -p 'Enter the gpg key url: ' url
        clear
    else
        file="$1"
        url="$2"
    fi

    curl -S# "$url" | gpg --dearmor | sudo tee "/etc/apt/trusted.gpg.d/$file"

    if curl -S# "$url" | gpg --dearmor | sudo tee "/etc/apt/trusted.gpg.d/$file"; then
        echo 'The key was successfully added!'
    else
        echo 'The key FAILED to add!'
    fi
}

##########################
# TAKE OWNERSHIP COMMAND #
##########################

toa() {
    clear
    sudo chown -R "$USER":"$USER" "$PWD"
    sudo chmod -R 744 "$PWD"
    clear; ls -1AvhF --color --group-directories-first
}

tod() {
    local directory
    clear

    if [ -z "$1" ]; then
        read -p 'Enter the folder name/path: ' directory
    else
        directory="$1"
    fi

    sudo chown -R "$USER":"$USER" "$directory"
    sudo chmod -R 744 "$directory"

    clear; ls -1AvhF --color --group-directories-first
}

tome() {
    # Check if a filename is provided as an argument
    if [ $# -ne 1 ]; then
        echo "Usage: change_ownership_and_permissions <file>"
        return 1
    fi

    # Check if the file exists
    if [ ! -f "$1" ]; then
        echo "Error: File '$1' does not exist."
        return 1
    fi

    # Change ownership of the file to the current user
    user="$(whoami)"
    sudo chown "$user" "$1"

    # Verify if the ownership has been changed successfully
    if [ $? -ne 0 ]; then
        echo "Error: Failed to change ownership of '$1'."
        return 1
    fi

    # Change permissions to chmod 777
    sudo chmod 777 "$1"

    # Verify if the permissions have been changed successfully
    if [ $? -eq 0 ]; then
        echo "Ownership and permissions of '$1' have been changed to $user and chmod 777."
    else
        echo "Error: Failed to change permissions of '$1'."
        return 1
    fi
}

#################
# DPKG COMMANDS #
#################

## SHOW ALL INSTALLED PACKAGES
showpkgs() {
    dpkg --get-selections | grep -v deinstall > "$HOME"/tmp/packages.list
    gnome-text-editor "$HOME"/tmp/packages.list
}

# PIPE ALL DEVELOPMENT PACKAGES NAMES TO file
getdev() {
    apt-cache search dev | grep '\-dev' | cut -d ' ' -f1 | sort > 'dev-packages.list'
    gnome-text-editor 'dev-packages.list'
}

################
## SSH-KEYGEN ##
################

# CREATE A NEW PRIVATE AND PUBLIC SSH KEY PAIR
new_key() {
    local bits comment name pass type
    clear

    printf "%s\n\n" 'Encryption type: [ rsa | dsa | ecdsa ]'
    read -p 'Your choice: ' type
    clear

    printf "%s\n%s\n\n" \
        '[i] Choose the key bit size' \
        '[i] Values encased in "()" are recommended'

    if [[ "$type" == 'rsa' ]]; then
        printf "%s\n\n" '[i] rsa: [ 512 | 1024 | (2048) | 4096 ]'
    elif [[ "$type" == 'dsa' ]]; then
        printf "%s\n\n" '[i] dsa: [ (1024) | 2048 ]'
    elif [[ "$type" == 'ecdsa' ]]; then
        printf "%s\n\n" '[i] ecdsa: [ (256) | 384 | 521 ]'
    fi

    read -p 'Your choice: ' bits
    clear

    printf "%s\n%s\n\n" \
        '[i] Choose a password' \
        '[i] For no password just press enter'
    read -p 'Your choice: ' pass
    clear

    printf "%s\n\n" '[i] For no comment just press enter'
    read -p 'Your choice: ' comment
    clear

    printf "%s\n\n" '[i] Enter the ssh key name'
    read -p 'Your choice: ' name
    clear

    printf "%s\n%s\n%s\n%s\n%s\n\n" \
        '[i] Your choices' \
        "[i] Type: $type" \
        "[i] bits: $bits" \
        "[i] Password: $pass" \
        "[i] comment: $comment" \
        "[i] Key name: $name"
    read -p 'Press enter to continue or ^c to exit'
    clear

    ssh-keygen -q -b "$bits" -t "$type" -N "$pass" -C "$comment" -f "$name"

    chmod 600 "$PWD/$name"
    chmod 644 "$PWD/${name}.pub"
    clear

    printf "%s\n\n" "File: $PWD/$name"
    cat "$PWD/$name"

    printf "\n%s\n\n" "File: $PWD/${name}.pub"
    cat "$PWD/${name}.pub"
    echo
}

# EXPORT THE PUBLIC SSH KEY STORED INSIDE A PRIVATE SSH KEY
keytopub() {
    local opub okey
    clear
    ls -1AhFv --color --group-directories-first

    printf "%s\n\n" "Enter the full paths for each file"
    read -p 'Private key: ' okey
    read -p 'Public key: ' opub
    clear
    if [ -f "$okey" ]; then
        chmod 600 "$okey"
    else
        printf "%s\n\n" "Warning: file missing = $okey"
        read -p 'Press Enter to exit.'
        exit 1
    fi
    ssh-keygen -b '4096' -y -f "$okey" > "$opub"
    chmod 644 "$opub"
    cp "$opub" "$HOME"/.ssh/authorized_keys
    chmod 600 "$HOME"/.ssh/authorized_keys
    unset "$okey"
    unset "$opub"
}

# install colordiff package :)
cdiff() { clear; colordiff "$1" "$2"; }

# GZIP
gzip() { clear; gzip -d "$@"; }

# get system time
gettime() { clear; date +%r | cut -d " " -f1-2 | grep -E '^.*$'; }

##################
## SOURCE FILES ##
##################

sbrc() {
    clear

    source "$HOME"/.bashrc && printf "%s\n\n" 'The command was a success!' || printf "%s\n\n" 'The command failed!'
    sleep 1

    clear
    ls -1AhFv --color --group-directories-first
}

spro() {
    clear

    source "$HOME"/.profile && printf "%s\n\n" 'The command was a success!' || printf "%s\n\n" 'The command failed!'
    sleep 1

    clear
    ls -1AhFv --color --group-directories-first
}

####################
## ARIA2 COMMANDS ##
####################

# ARIA2 DAEMON IN THE BACKGROUND
aria2_on() {
    clear

    if aria2c --conf-path="$HOME"/.aria2/aria2.conf; then
        printf "\n%s\n\n" 'Command Executed Successfully'
    else
        printf "\n%s\n\n" 'Command Failed'
    fi
}

# STOP ARIA2 DAEMON
aria2_off() { clear; killall aria2c; }

myip() {
    clear
    printf "%s\n%s\n\n" \
        "LAN: $(ip route get 1.2.3.4 | awk '{print $7}')" \
        "WAN: $(curl -s 'https://checkip.amazonaws.com')"
}

# WGET COMMAND
mywget() {
    local outfile url
    clear
    ls -1AhFv --color --group-directories-first

    if [ -z "$1" ] || [ -z "$2" ]; then
        read -p 'Please enter the output file name: ' outfile
        read -p 'Please enter the URL: ' url
        clear
        wget --out-file="$outfile" "$url"
    else
        wget --out-file="$1" "$2"
    fi
}

################
# RM COMMANDS ##
################

# RM DIRECTORY
rmd() {
    local i
    clear

    if [ -z "$1" ] || [ -z "$2" ]; then
        read -p 'Please enter the directory name to remove: ' i
        clear
        sudo rm -r "$i"
        clear
    else
        sudo rm -r "$1"
        clear
    fi
}

# RM FILE
rmf() {
    local i
    clear

    if [ -z "$1" ]; then
        read -p 'Please enter the file name to remove: ' i
        clear
        sudo rm "$i"
        clear
    else
        sudo rm "$1"
        clear
    fi
}

#################
## IMAGEMAGICK ##
#################

# OPTIMIZE AND OVERWRITE THE ORIGINAL IMAGES
imow() {
    local apt_pkgs cnt_queue cnt_total dimensions fext missing_pkgs pip_lock random_dir tmp_file v_noslash
    clear

    # THE FILE EXTENSION TO SEARCH FOR (DO NOT INCLUDE A '.' WITH THE EXTENSION)
    fext=jpg

    # REQUIRED APT PACKAGES
    apt_pkgs=(sox libsox-dev)
    for i in ${apt_pkgs[@]}
    do
        missing_pkg="$(dpkg -l | grep "$i")"
        if [ -z "${missing_pkg}" ]; then
            missing_pkgs+=" $i"
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
    if [ -n "$pip_lock" ]; then
        sudo rm "$pip_lock"
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

    for i in ./*."$fext"
    do
        cnt_queue=$(( cnt_queue-1 ))

        cat <<EOT
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

File Path: $PWD

Folder: $(basename "$PWD")

Total Files:    $cnt_total
Files in queue: $cnt_queue

Converting:  $i

 >> ${i%%.jpg}.mpc

    >> ${i%%.jpg}.cache

       >> ${i%%.jpg}-IM.jpg

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOT
        echo
        random_dir="$(mktemp -d)"
        dimensions="$(identify -format '%wx%h' "$i")"
        convert "$i" -monitor -filter Triangle -define filter:support=2 -thumbnail "$dimensions" -strip \
            -unsharp '0.25x0.08+8.3+0.045' -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off \
            -auto-level -enhance -interlace none -colorspace sRGB "$random_dir/${i%%.jpg}.mpc"


        for file in "$random_dir"/*.mpc
        do
            convert "$file" -monitor "${file%%.mpc}.jpg"
            tmp_file="$(echo "$file" | sed 's:.*/::')"
            mv "${file%%.mpc}.jpg" "$PWD/${tmp_file%%.*}-IM.jpg"
            rm -f "$PWD/${tmp_file%%.*}.jpg"
            for v in $file
            do
                v_noslash="${v%/}"
                rm -fr "${v_noslash%/*}"
            done
        done
    done

    if [ "$?" -eq '0' ]; then
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
im50() {
    clear
    local pic

    for pic in ./*.jpg
    do
        convert "$pic" -monitor -colorspace sRGB -filter LanczosRadius -distort Resize 50% -colorspace sRGB "$i"
    done
}

imdl() {
    local cwd tmp_dir

    cwd="$PWD"
    tmp_dir="$(mktemp -d)"

    cd "$tmp_dir" || exit 1

    curl -Lso imow "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-jpg.sh"

    sudo mv imow "$cwd"
    sudo rm -fr "$tmp_dir"

    cd "${cwd}" || exit 1

    sudo chown "$USER":"$USER" imow
    sudo chmod +rwx imow
}

###########################
## SHOW NVME TEMPERATURE ##
###########################

nvme_temp() {
    local n0 n1 n2
    clear

    if [ -d '/dev/nvme0n1' ]; then
        n0="$(sudo nvme smart-log /dev/nvme0n1)"
    fi
    if [ -d '/dev/nvme1n1' ]; then
        n1="$(sudo nvme smart-log /dev/nvme0n1)"
    fi
    if [ -d '/dev/nvme2n1' ]; then
        n2="$(sudo nvme smart-log /dev/nvme0n1)"
    fi

    printf "%s\n\n%s\n\n%s\n\n%s\n\n" "nvme0n1: ${n0}" "nnvme1n1: ${n1}" "nnvme2n1: ${n2}"
}

#############################
## REFRESH THUMBNAIL CACHE ##
#############################

rftn() {
    clear
    sudo rm -fr "$HOME"/.cache/thumbnails/*
    ls -al "$HOME"/.cache/thumbnails
}

#####################
## FFMPEG COMMANDS ##
#####################

cuda_purge() {
    local choice
    clear

    printf "%s\n\n%s\n\n%s\n%s\n\n" \
        'Do you want to completely remove the cuda-sdk-toolkit?'
        'WARNING: Do not reboot your PC without reinstalling the nvidia-driver first!'
        '[1] Yes'
        '[2] Exit'
    read -p 'Your choices are (1 or 2): ' choice
    clear

    if [[ "$choice" -eq '1' ]]; then
        echo 'Purging the cuda-sdk-toolkit from your computer.'
        echo '================================================'
        echo
        sudo sudo apt -y --purge remove "*cublas*" "cuda*" "nsight*"
        sudo sudo apt -y autoremove
        sudo sudo apt update
    elif [[ "$choice" -eq '2' ]]; then
        return 0
    fi
}

ffdl() {
    clear
    curl -A "$user_agent" -m 10 -Lso 'ff.sh' 'https://ffdl.optimizethis.net'
    bash 'ff.sh'
    sudo rm 'ff.sh'
    clear; ls -1AhFv --color --group-directories-first
}

ffs() { curl -A "$user_agent" -m 10 -Lso 'ff' 'https://raw.githubusercontent.com/slyfox1186/ffmpeg-build-script/main/build-ffmpeg'; }

dlfs() {
    local f
    clear
    
    wget --show-progress -U "$user_agent" -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/favorite-installer-scripts.txt'
    
    scripts=(build-ffmpeg build-all-git-safer build-all-gnu-safer build-magick)

    for f in ${scripts[@]}
    do
        chown -R "$USER":"$USER" "$f"
        chmod -R 744 "$PWD" "$f"
        [[ "$f" == 'build-all-git-safer' || "$f" == 'build-all-gnu-safer' ]] && mv "$f" "${f%-safer}"
        [ -n 'favorite-installer-scripts.txt' ] && sudo rm 'favorite-installer-scripts.txt'
    done
    
    clear
    ls -1AhFv --color --group-directories-first
}

##############################
## LIST LARGE FILES BY TYPE ##
##############################

large_files() {
    local answer
    clear

    if [ -z "$1" ]; then
        printf "%s\n\n" 'Input the file extension to search for without a dot: '
        read -p 'Enter your choice: ' answer
        clear
    else
        answer="$1"
    fi

    sudo find "$PWD" -type f -name "*.$answer" -printf '%s %h\n' | sort -ru -o 'large-files.txt'

    if [ -f 'large-files.txt' ]; then
        sudo gnome-text-editor 'large-files.txt'
        sudo rm 'large-files.txt'
    fi
}

###############
## MEDIAINFO ##
###############

mi() {
    local i
    clear

    if [ -z "$1" ]; then
        ls -1AhFv --color --group-directories-first
        echo
        read -p 'Please enter the relative file path: ' i
        clear
        mediainfo "$i"
    else
        mediainfo "$1"
    fi
}

############
## FFMPEG ##
############

cdff() { clear; cd "$HOME/tmp/ffmpeg-build" || exit 1; cl; }
ffm() { clear; bash <(curl -sSL 'http://ffmpeg.optimizethis.net'); }
ffp() { clear; bash <(curl -sSL 'http://ffpb.optimizethis.net'); }

####################
## LIST PPA REPOS ##
####################

listppas() {
    clear

    local apt host user ppa entry

    for apt in $(find /etc/apt/ -type f -name \*.list)
    do
        grep -Po "(?<=^deb\s).*?(?=#|$)" "${apt}" | while read entry
        do
            host="$(echo "${entry}" | cut -d/ -f3)"
            user="$(echo "${entry}" | cut -d/ -f4)"
            ppa="$(echo "${entry}" | cut -d/ -f5)"
            #echo sudo apt-add-repository ppa:$USER/${ppa}
            if [ "ppa.launchpad.net" = "${host}" ]; then
                echo sudo apt-add-repository ppa:"$USER/${ppa}"
            else
                echo sudo apt-add-repository \'deb "${entry}"\'
            fi
        done
    done
}

#########################
## NVIDIA-SMI COMMANDS ##
#########################

gpu_mon() {
    clear
    nvidia-smi dmon
}

################################################################
## PRINT THE NAME OF THE DISTRIBUTION YOU ARE CURRENTLY USING ##
################################################################

my_os() {
    local name version
    clear

    name="$(eval lsb_release -si 2>/dev/null)"
    version="$(eval lsb_release -sr 2>/dev/null)"

    clear

    printf "%s\n\n" "Linux OS: $name ${version}"
}

##############################################
## MONITOR CPU AND MOTHERBOARD TEMPERATURES ##
##############################################

hw_mon() {
    clear

    local found

    # install lm-sensors if not already
    if ! type -P lm-sensors &>/dev/null; then
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
7z_gz() {
    local source output
    clear

    if [ -n "$1" ]; then
        if [ -f "$1".tar.gz ]; then
            sudo rm "$1".tar.gz
        fi
        7z a -ttar -so -an "$1" | 7z a -tgz -mx9 -mpass1 -si "$1".tar.gz
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
7z_xz() {
    local source output
    clear

    if [ -n "$1" ]; then
        if [ -f "$1".tar.xz ]; then
            sudo rm "$1".tar.xz
        fi
        7z a -ttar -so -an "$1" | 7z a -txz -mx9 -si "$1".tar.xz
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

7z_1() {
    local answer source output
    clear

    if [ -d "$1" ]; then
        source_dir="$1"
        7z a -y -t7z -m0=lzma2 -mx1 "${source_dir}".7z ./"${source_dir}"/*
    else
        read -p 'Please enter the source folder path: ' source_dir
        7z a -y -t7z -m0=lzma2 -mx1 "${source_dir}".7z ./"${source_dir}"/*
    fi

    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to delete the original file?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer
    clear

    case "$answer" in
        1)      sudo rm -fr "${source_dir}";;
        2)      clear;;
        '')     clear;;
        *)      printf "\n%s\n\n" 'Bad user input...';;
    esac
}

7z_5() {
    local answer source output
    clear

    if [ -d "$1" ]; then
        source_dir="$1"
        7z a -y -t7z -m0=lzma2 -mx5 "${source_dir}".7z ./"${source_dir}"/*
    else
        read -p 'Please enter the source folder path: ' source_dir
        7z a -y -t7z -m0=lzma2 -mx5 "${source_dir}".7z ./"${source_dir}"/*
    fi

    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to delete the original file?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer
    clear

    case "$answer" in
        1)      sudo rm -fr "${source_dir}";;
        2)      clear;;
        '')     clear;;
        *)      printf "\n%s\n\n" 'Bad user input...';;
    esac
}

7z_9() {
    local answer source output
    clear

    if [ -d "$1" ]; then
        source_dir="$1"
        7z a -y -t7z -m0=lzma2 -mx9 "${source_dir}".7z ./"${source_dir}"/*
    else
        read -p 'Please enter the source folder path: ' source_dir
        7z a -y -t7z -m0=lzma2 -mx9 "${source_dir}".7z ./"${source_dir}"/*
    fi

    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to delete the original file?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer
    clear

    case "$answer" in
        1)      sudo rm -fr "${source_dir}";;
        2)      clear;;
        '')     clear;;
        *)      printf "\n%s\n\n" 'Bad user input...';;
    esac
}

##################
## TAR COMMANDS ##
##################

# CREATE A GZ FILE USING TAR COMMAND
tar_gz() {
    local source output
    clear

    if [ -n "$1" ]; then
        if [ -f "$1".tar.gz ]; then
            sudo rm "$1".tar.gz
        fi
        tar -cJf "$1".tar.gz "$1"
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

tar_bz2() {
    local source output
    clear

    if [ -n "$1" ]; then
        if [ -f "$1".tar.bz2 ]; then
            sudo rm "$1".tar.bz2
        fi
        tar -cvjf "$1".tar.bz2 "$1"
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

tar_xz_1() {
    local source output
    clear
    if [ -n "$1" ]; then
        if [ -f "$1".tar.xz ]; then
            sudo rm "$1".tar.xz
        fi
        tar -cvJf - "$1" | xz -1 -c - > "$1".tar.xz
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

tar_xz_5() {
    local source output
    clear
    if [ -n "$1" ]; then
        if [ -f "$1".tar.xz ]; then
            sudo rm "$1".tar.xz
        fi
        tar -cvJf - "$1" | xz -5 -c - > "$1".tar.xz
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

tar_xz_9() {
    local source output
    clear
    if [ -n "$1" ]; then
        if [ -f "$1".tar.xz ]; then
            sudo rm "$1".tar.xz
        fi
        tar -cvJf - "$1" | xz -9 -c - > "$1".tar.xz
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

ffr() {
    clear
    sudo bash "$1" --build --latest
}
ffrv() {
    clear
    sudo bash -v "$1" --build --latest
}

###################
## WRITE CACHING ##
###################

wcache() {
    clear

    local choice

    lsblk
    echo
    read -p 'Enter the drive id to turn off write caching (/dev/sdX w/o /dev/): ' choice

    sudo hdparm -W 0 /dev/"${choice}"
}

rmd() {
    clear

    local dirs

    if [ -z "${*}" ]; then
        clear; ls -1AvhF --color --group-directories-first
        echo
        read -p 'Enter the directory path(s) to delete: ' dirs
     else
        dirs="${*}"
    fi

    sudo rm -fr "$dirs"
    clear
    ls -1AvhF --color --group-directories-first
}


rmf() {
    clear

    local files

    if [ -z "${*}" ]; then
        clear; ls -1AvhF --color --group-directories-first
        echo
        read -p 'Enter the file path(s) to delete: ' files
     else
        files="${*}"
    fi

    sudo rm "${files}"
    clear
    ls -1AvhF --color --group-directories-first
}

## LIST INSTALLED PACKAGES BY ORDER OF IMPORTANCE

list_pkgs() { clear; dpkg-query -Wf '${Package;-40}${Priority}\n' | sort -b -k2,2 -k1,1; }

## FIX USER FOLDER PERMISSIONS up = user permissions

fix_up() {
    find "$HOME"/.gnupg -type f -exec chmod 600 {} \;
    find "$HOME"/.gnupg -type d -exec chmod 700 {} \;
    find "$HOME"/.ssh -type d -exec chmod 700 {} \; 2>/dev/null
    find "$HOME"/.ssh/id_rsa.pub -type f -exec chmod 644 {} \; 2>/dev/null
    find "$HOME"/.ssh/id_rsa -type f -exec chmod 600 {} \; 2>/dev/null
}

## SET DEFAULT PROGRAMS
set_default() {
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
        "You have chosen: sudo update-alternatives --install ${target} $name $link $importance" \
        'Would you like to continue?' \
        '[1] Yes' \
        '[2] No'

    read -p 'Your choices are (1 or 2): ' choice
    clear

    case "${choice}" in
        1)      sudo update-alternatives --install "${target}" "$name" "$link" "$importance";;
        2)      return 0;;
        *)      return 0;;
    esac
}

## COUNT FILES IN THE DIRECTORY
cnt_dir() {
    local keep_cnt
    clear
    keep_cnt="$(find . -maxdepth 1 -type f | wc -l)"
    printf "%s %'d\n\n" "The total directory file count is (non-recursive):" "${keep_cnt}"
}

cnt_dirr() {
    local keep_cnt
    clear
    keep_cnt="$(find . -type f | wc -l)"
    printf "%s %'d\n\n" "The total directory file count is (recursive):" "${keep_cnt}"
}

######################
## TEST GCC & CLANG ##
######################

test_gcc() {
    local answer random_dir
    clear

    random_dir="$(mktemp -d)"
    
    # CREATE A TEMPORARY C FILE TO RUN OUR TESTS AGAINST
    cat > "$random_dir"/hello.c <<'EOF'
#include <stdio.h>
int main(void)
{
   printf("Hello World!\n");
   return 0;
}
EOF

    if [ -n "$1" ]; then
        "$1" -Q -v "$random_dir"/hello.c
    else
        clear
        read -p 'Enter the GCC binary you wish to test (example: gcc-11): ' answer
        clear
        "$answer" -Q -v "$random_dir"/hello.c
    fi
    sudo rm -fr "$random_dir"
}

test_clang() {
    local answer random_dir
    clear

    random_dir="$(mktemp -d)"
    
    # CREATE A TEMPORARY C FILE TO RUN OUR TESTS AGAINST
    cat > "$random_dir"/hello.c <<'EOF'
#include <stdio.h>
int main(void)
{
   printf("Hello World!\n");
   return 0;
}
EOF

    if [ -n "$1" ]; then
        "$1" -Q -v "$random_dir"/hello.c
    else
        clear
        read -p 'Enter the GCC binary you wish to test (example: gcc-11): ' answer
        clear
        "$answer" -Q -v "$random_dir"/hello.c
    fi
    sudo rm -fr "$random_dir"
}

############################
## UNINSTALL DEBIAN FILES ##
############################

rm_deb() {
    local fname
    clear

    if [ -n "$1" ]; then
        sudo dpkg -r "$(dpkg -f "$1" Package)"
    else
        read -p 'Please enter the Debian file name: ' fname
        clear
        sudo dpkg -r "$(dpkg -f "$fname" Package)"
    fi
}

######################
## KILLALL COMMANDS ##
######################

tkapt() {
    local i list
    clear

    list=(apt apt apt apt apt apt apt-get aptitude dpkg)

    for i in ${list[@]}
    do
        sudo killall -9 "$i" 2>/dev/null
    done
}

gc() {
    local url
    clear

    if [ -n "$1" ]; then
        nohup google-chrome "$1" 2>/dev/null >/dev/null
    else
        read -p 'Enter a URL: ' url
        nohup google-chrome "$url" 2>/dev/null >/dev/null
    fi
}

kill_process() {
    local program_name=$1
    clear

    if [[ -z "$program_name" ]]; then
        printf "%s\n\n" "Usage: kill_process name."
        return 1
    fi

    echo "Checking for running instances of '$program_name'..."

    # Find all PIDs for the given process
    local pids=$(pgrep -f "$program_name")

    if [[ -z "$pids" ]]; then
        echo "No instances of '$program_name' are running."
        return 0
    fi

    echo "Found instances of '$program_name' with PIDs: $pids"
    echo "Attempting to kill all instances of '$program_name'..."

    local pid
    for pid in $pids; do
        echo "Killing PID $pid..."
        sudo kill -9 "$pid" || {
            echo "Failed to kill PID $pid. Check your permissions."
            continue
        }
    done

    echo "All instances of '$program_name' have been attempted to be killed."
}

####################
## NOHUP COMMANDS ##
####################

nh() {
    clear
    nohup "$1" &>/dev/null &
    cl
}

nhs() {
    clear
    nohup sudo "$1" &>/dev/null &
    cl
}

nhe() {
    clear
    nohup "$1" &>/dev/null &
    exit
    exit
}

nhse() {
    clear
    nohup sudo "$1" &>/dev/null &
    exit
    exit
}

## NAUTILUS COMMANDS

nopen() {
    clear
    nohup nautilus -w "$1" &>/dev/null &
    exit
}

tkan() {
    local parent_dir
    parent_dir="$PWD"
    killall -9 nautilus
    sleep 1
    nohup nautilus -w "$parent_dir" &>/dev/null &
    exit
}

#######################
## UPDATE ICON CACHE ##
#######################

up_icon() {
    local i pkgs
    clear

    pkgs=(gtk-update-icon-cache hicolor-icon-theme)

    for i in ${pkgs[@]}
    do
        if ! sudo dpkg -l "$i"; then
            sudo apt -y install "$i"
            clear
        fi
    done

    sudo gtk-update-icon-cache -f /usr/share/icons/hicolor
}

############
## ARIA2C ##
############

adl() {
    local filename url

    # Check if two arguments are provided
    if [ $# -eq 2 ]; then
        filename="$1"
        url="$2"
    else
        # If not two arguments, prompt for input
        read -p "Enter the filename and extension: " filename
        read -p "Enter the URL: " url
    fi

    # Check for an existing file with the same name and prompt to overwrite
    if [ -f "$filename" ]; then
        read -p "File $filename exists. Overwrite? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm "$filename"
        else
            echo "Download canceled."
            return
        fi
    fi

    # Use aria2c to download the file with the given filename
    if aria2c \
           --console-log-level=notice \
           -x32 \
           -j16 \
           --split=32 \
           --allow-overwrite=true \
           --allow-piece-length-change=true \
           --always-resume=true \
           --async-dns=false \
           --auto-file-renaming=false \
           --min-split-size=8M \
           --disk-cache=64M \
           --file-allocation=none \
           --no-file-allocation-limit=8M \
           --continue=true \
           --out="$filename" \
           "$url"
    then
           google_speech 'Download completed.' 2>/dev/null
    else
           google_speech 'Download failed.' 2>/dev/null
    fi

    echo
    ls -1AvhF --color --group-directories-first
}

####################
## GET FILE SIZES ##
####################

big_files() {
    local cnt
    clear

    if [ -n "$1" ]; then
        cnt="$1"
    else
        read -p 'Enter how many files to list in the results: ' cnt
        clear
    fi

    printf "%s\n\n" "${cnt} largest files"
    sudo find "$PWD" -type f -exec du -Sh {} + | sort -hr | head -"${cnt}"
    echo
    printf "%s\n\n" "${cnt} largest folders"
    sudo du -Bm "$PWD" 2>/dev/null | sort -hr | head -"${cnt}"
}

big_vids() {
    local cnt
    clear

    if [ -n "$1" ]; then
        cnt="$1"
    else
        read -p 'Enter the max number of results: ' cnt
        clear
    fi

    printf "%s\n\n" "Listing the ${cnt} largest videos"
    sudo find "$PWD" -type f \( -iname '*.mkv' -o -iname '*.mp4' \) -exec du -Sh {} + | grep -Ev '\(x265\)' | sort -hr | head -n"${cnt}"
}

big_img() { clear; sudo find . -size +10M -type f -name '*.jpg' 2>/dev/null; }

jpgsize() {
    local random_dir size
    clear

    random_dir="$(mktemp -d)"
    read -p 'Enter the image size (units in MB): ' size
    find . -size +"${size}"M -type f -iname "*.jpg" > "$random_dir/img-sizes.txt"
    sed -i "s/^..//g" "$random_dir/img-sizes.txt"
    sed -i "s|^|$PWD\/|g" "$random_dir/img-sizes.txt"
    clear
    nohup gnome-text-editor "$random_dir/img-sizes.txt" &>/dev/null &
}

##################
## SED COMMANDS ##
##################

fsed() {
    clear

    printf "%s\n\n" 'This command is for sed to act ONLY on files'

    if [ -z "$1" ]; then
        read -p 'Enter the original text: ' otext
        read -p 'Enter the replacement text: ' rtext
        clear
    else
        otext="$1"
        rtext="$2"
    fi

     sudo sed -i "s/${otext}/${rtext}/g" $(find . -maxdepth 1 -type f)
}

####################
## CMAKE COMMANDS ##
####################

cmf() {
    local rel_sdir
    if ! sudo dpkg -l | grep -o cmake-curses-gui; then
        sudo apt -y install cmake-curses-gui
    fi
    clear

    if [ -z "$1" ]; then
        read -p 'Enter the relative source directory: ' rel_sdir
    else
        rel_sdir="$1"
    fi

    cmake ${rel_sdir} -B build -G Ninja -Wno-dev
    ccmake ${rel_sdir}
}

##########################
## SORT IMAGES BY WIDTH ##
##########################

jpgs() {
    clear
    sudo find . -type f -iname '*.jpg' -exec identify -format " $PWD/%f: %wx%h " '{}' > /tmp/img-sizes.txt \;
    cat /tmp/img-sizes.txt | sed 's/\s\//\n\//g' | sort -h
    sudo rm /tmp/img-sizes.txt
}

######################################
## DOWNLOAD IMPORTANT BUILD SCRIPTS ##
######################################

gitdl() {
    clear
    wget -cq 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/build-ffmpeg'
    wget -cq 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/build-magick'
    wget -cq 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc'
    wget -cq 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/repo.sh'
    sudo chmod -R build-gcc build-magick build-ffmpeg repo.sh -- *
    sudo chown -R "$USER":"$USER" build-gcc build-magick build-ffmpeg repo.sh
    clear
    ls -1AvhF --color --group-directories-first
}

# COUNT ITEMS IN THE CURRENT FOLDER W/O SUBDIRECTORIES INCLUDED
cntf() {
    local folder_cnt
    clear
    folder_cnt="$(ls -1 | wc -l)"
    printf "%s\n" "There are ${folder_cnt} files in this folder"
}

## RECURSIVELY UNZIP ZIP FILES AND NAME THE OUTPUT FOLDER THE SAME NAME AS THE ZIP FILE
zipr() {
    clear
    sudo find . -type f -iname '*.zip' -exec sh -c 'unzip -o -d "${0%.*}" "$0"' '{}' \;
    sudo find . -type f -iname '*.zip' -exec trash-put '{}' \;
}

###################################
## FFPROBE LIST IMAGE DIMENSIONS ##
###################################

ffp() {
    clear
    if [ -f 00-pic-sizes.txt ]; then
        sudo rm 00-pic-sizes.txt
    fi
    sudo find "$PWD" -type f -iname '*.jpg' -exec bash -c "identify -format "%wx%h" \"{}\"; echo \" {}\"" > 00-pic-sizes.txt \;
}

####################
## RSYNC COMMANDS ##
####################

rsr() {
    local destination modified_source source 
    clear

    # you must add an extra folder that is a period '/./' between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the source folder instead of the source
    # folder and its subfiles only.

    printf "%s\n%s\n%s\n%s\n\n" \
        'This rsync command will recursively copy the source folder to the chosen destination.' \
        'The original files will still be located in the source folder.' \
        'If you want to move the files (which deletes the originals then use the function "rsrd".' \
        'Please enter the full paths of the source and destination directories.'

    printf "%s\n\n" 
    read -p 'Enter the source path: ' source
    read -p 'Enter the destination path: ' destination
    modified_source="$(echo "${source}" | sed 's:/[^/]*$::')"'/./'"$(echo "${source}" | sed 's:.*/::')"
    clear

    rsync -aqvR --acls --perms --mkpath --info=progress2 "${modified_source}" "${destination}"
}

rsrd() {
    local destination modified_source source 
    clear

    # you must add an extra folder that is a period '/./' between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the souce folder instead of the source
    # folder and its subfiles only.

    printf "%s\n%s\n%s\n%s\n\n" \
        'This rsync command will recursively copy the source folder to the chosen destination.' \
        'The original files will be DELETED after they have been copied to the destination.' \
        'If you want to move the files (which deletes the originals then use the function "rsrd".' \
        'Please enter the full paths of the source and destination directories.'

    printf "%s\n\n" 
    read -p 'Enter the source path: ' source
    read -p 'Enter the destination path: ' destination
    modified_source="$(echo "${source}" | sed 's:/[^/]*$::')"'/./'"$(echo "${source}" | sed 's:.*/::')"
    clear

    rsync -aqvR --acls --perms --mkpath --remove-source-files "${modified_source}" "${destination}"
}

################
## SHELLCHECK ##
################

sc() {
    local f fname input_char line space
    clear

    if [ -z "$@" ]; then
        read -p 'Input the file path to check: ' fname
        clear
    else
        fname="$@"
    fi

    for f in ${fname[@]}
    do
        box_out_banner() {
            input_char=$(echo "$@" | wc -c)
            line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
            tput bold
            line="$(tput setaf 3)$line"
            space=${line//-/ }
            echo " $line"
            printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
            printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
            printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
            echo " $line"
            tput sgr 0
        }
        box_out_banner "Parsing: $f"
        shellcheck --color=always -x --severity=warning --source-path="$HOME:$HOME/tmp:/etc:/usr/local/lib64:/usr/local/lib:/usr/local64:/usr/lib:/lib64:/lib:/lib32" "$f"
        echo
    done
}

###############
## CLIPBOARD ##
###############

# COPY ANY TEXT. DOES NOT NEED TO BE IN QUOTES
# EXAMPLE: ct This is so cool
# OUTPUT WHEN PASTED: This is so cool
# USAGE: cp <file name here>

ct() {
    local pipe_this
    clear

    if [ -z "$@" ]; then
        clear
        printf "%s\n\n%s\n%s\n\n" \
            "The command syntax is shown below" \
            "cc INPUT" \
            'Example: cc $PWD'
        return 1
    else
        pipe_this="$@"
    fi

    echo "${pipe_this}" | xclip -i -rmlastnl -sel clip
    clear
}

# COPY A FILE'S FULL PATH
# USAGE: cp <file name here>

cfp() {
    local pipe_this
    clear

    if [ -z "$@" ]; then
        clear
        printf "%s\n\n%s\n%s\n\n" \
            "The command syntax is shown below" \
            "cc INPUT" \
            'Example: cc $PWD'
        return 1
    fi

    readlink -fn "$@" | xclip -i -sel clip
    clear
}

# COPY THE CONTENT OF A FILE
# USAGE: cf <file name here>

cfc() {
    clear

    if [ -z "$1" ]; then
        clear
        printf "%s\n\n%s\n%s\n\n" \
            "The command syntax is shown below" \
            "cc INPUT" \
            'Example: cc $PWD'
        return 1
    else
        cat "$1" | xclip -i -rmlastnl -sel clip
    fi
}

########################
## PKG-CONFIG COMMAND ##
########################

# SHOW THE PATHS PKG-CONFIG COMMAND SEARCHES BY DEFAULT
pkg-config-path() {
    clear
    pkg-config --variable pc_path pkg-config | tr ':' '\n'
}

######################################
## SHOW BINARY RUNPATH IF IT EXISTS ##
######################################

show_rpath() {
    local find_rpath
    clear

    if [ -z "$1" ]; then
        read -p 'Enter the full path to the binary/program: ' find_rpath
    else
        find_rpath="$1"
    fi

    clear
    sudo chrpath -l "$(type -p ${find_rpath})"
}

######################################
## DOWNLOAD CLANG INSTALLER SCRIPTS ##
######################################

dl_clang() {
    clear
    if [ ! -d "$HOME/tmp" ]; then
        mkdir -p "$HOME/tmp"
    fi
    wget --show-progress -U "$user_agent" -cqO "$HOME/tmp/build-clang-16" 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-16'
    wget --show-progress -U "$user_agent" -cqO "$HOME/tmp/build-clang-17" 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-17'
    sudo chmod rwx "$HOME/tmp/build-clang-16" "$HOME/tmp/build-clang-17"
    sudo chown "$USER":"$USER" "$HOME/tmp/build-clang-16" "$HOME/tmp/build-clang-17"
    clear
    ls -1AvhF--color --group-directories-first
}

#################
## PYTHON3 PIP ##
#################

pip_up() {
    local list_pkgs pkg

    list_pkgs="$(pip list | awk '{print $1}')"
    
    pip install --upgrade pip
    
    for pkg in ${list_pkgs[@]}
    do
        if [ $pkg != wxPython ]; then
            pip install --user --upgrade $pkg
        fi
        echo
    done
}

####################
## REGEX COMMANDS ##
####################

bvar() {
    local choice fext flag fname
    clear

    if [ -z "$1" ]; then
        read -p 'Please enter the file path: ' fname
        fname_tmp="$fname"
    else
        fname="$1"
        fname_tmp="$fname"
    fi

    fext="${fname#*.}"
    if [ -n "$fext" ]; then
        fname+='.txt'
        mv "${fname_tmp}" "$fname"
    fi

    cat < "$fname" | sed -e 's/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g' -e 's/\(\$\)\({}\)/\1/g' -e 's/\(\$\)\({}\)\({\)/\1\3/g'

    printf "%s\n\n%s\n%s\n\n" \
        'Do you want to permanently change this file?' \
        '[1] Yes' \
        '[2] Exit'
    read -p 'Your choices are ( 1 or 2): ' choice
    clear
    case "${choice}" in
        1)
                sed -i -e 's/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g' -i -e 's/\(\$\)\({}\)/\1/g' -i -e 's/\(\$\)\({}\)\({\)/\1\3/g' "$fname"
                mv "$fname" "${fname_tmp}"
                clear
                cat < "${fname_tmp}"
                ;;
        2)
                mv "$fname" "${fname_tmp}"
                return 0
                ;;
        *)
                unset choice
                bvar "${fname_tmp}"
                ;;
    esac
}

###########################
## CHANGE HOSTNAME OF PC ##
###########################

chostname() {
    local name
    clear

    if [ -z "$1" ]; then
        read -p 'Please enter the new hostname: ' name
    else
        name="$1"
    fi

    sudo nmcli g hostname "$name"
    clear
    printf "%s\n\n" "The new hostname is listed below."
    hostname
}

############
## DOCKER ##
############

drp() {
    local choice restart_policy
    clear

    printf "%s\n\n%s\n%s\n%s\n%s\n\n" \
        'Change the Docker restart policy' \
        '[1] Restart Always' \
        '[2] Restart Unless Stopped ' \
        '[3] On Failure' \
        '[4] No'
    read -p 'Your choices are (1 to 4): ' choice
    clear

    case "${choice}" in
        1)      restart_policy='always' ;;
        2)      restart_policy='unless-stopped' ;;
        3)      restart_policy='on-failure' ;;
        4)      restart_policy='no' ;;
        *)
                clear
                printf "%s\n\n" 'Bad user input. Please try again...'
                return 1
                ;;
    esac

    docker update --restart="${restart_policy}" 
}

rm_curly() {
    local content file transform_string
    # FUNCTION TO TRANSFORM THE STRING
    transform_string()
    {
        content=$(cat "$1")
        echo "${content//\$\{/\$}" | sed 's/\}//g'
    }

    # LOOP OVER EACH ARGUMENT
    for file in "$@"
    do
        if [ -f "$file" ]; then
            # PERFORM THE TRANSFORMATION AND OVERWRITE THE FILE
            transform_string "$file" > "$file.tmp"
            mv "$file.tmp" "$file"
            echo "Modified file: $file"
        else
            echo "File not found: $file"
        fi
    done
}

###############
## MINECRAFT ##
###############

dsh() {
    clear

    printf "%s\n\n" 'Start, Stop, or Restart ALL Docker images.'

    if [ ! -f '/usr/local/bin/start-stop-or-restart-docker-images.sh' ]; then
        printf "\n%s\n\n" "The file '/usr/local/bin/start-stop-or-restart-docker-images.sh' doesn't exist!"
        return 1
    fi

    sudo bash '/usr/local/bin/start-stop-or-restart-docker-images.sh'
}

#########################
## MOUNT NETWORK DRIVE ##
#########################

mnd() {
    clear

    # Define variables
    local drive_ip='192.168.2.2'
    local drive_name='Cloud'
    local mount_point='m'  # Mount point set to /m

    # Function to check if the drive is already mounted
    is_mounted() {
        sudo mountpoint -q /"${mount_point}"
    }

    # Function to mount the drive
    mount_drive() {
        if is_mounted; then
            echo "Drive '${drive_name}' is already mounted at ${mount_point}."
        else
            sudo mkdir -p /"${mount_point}"
            sudo mount -t drvfs "\\\\${drive_ip}\\${drive_name}" /"${mount_point}" && echo "Drive '${drive_name}' mounted successfully at ${mount_point}."
        fi
    }

    # Function to unmount the drive
    unmount_drive() {
        if is_mounted; then
            sudo umount /"${mount_point}" && echo "Drive '${drive_name}' unmounted successfully from ${mount_point}."
        else
            echo "Drive '${drive_name}' is not mounted."
        fi
    }

    # Main menu for user interaction
    echo "Select an option:"
    echo "1) Mount the network drive"
    echo "2) Unmount the network drive"
    read -p "Enter your choice (1/2): " user_choice

    case $user_choice in
        1) mount_drive ;;
        2) unmount_drive ;;
        *) echo "Invalid choice. Please enter 1 or 2." ;;
    esac
}

##################
## PORT NUMBERS ##
##################

check_port() {
    local choice kill_choice pid name protocol

    if [ -z "$1" ]; then
        read -p 'Enter the port number: ' choice
    else
        choice="$1"
    fi

    if [ -z "$choice" ] && [ -z "$1" ]; then
        echo "Error: No port was specified. Please pass the port to the function or enter it when prompted."
        return 1
    fi

    echo "Checking for processes using port $choice..."

    # Improved process information retrieval using lsof for both TCP and UDP
    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | awk '{print $1}')
        protocol=$(echo "$line" | awk '{print $8}')

        if [ -n "$pid" ] && [ -n "$name" ]; then
            echo "Process using port $choice: $name (PID: $pid, Protocol: $protocol)"
            read -p "Do you want to kill this process? (yes/no): " kill_choice

            shopt -s nocasematch
            case "$kill_choice" in
                yes|y|"") sudo kill -9 "$pid"
                          echo "Process $pid killed."
                          ;;
                no|n)     echo "Process $pid not killed."
                          ;;
                *)        echo "Invalid option. Exiting." ;;
            esac
            shopt -u nocasematch
        else
            echo "No process is using port $choice."
        fi
    done < <(sudo lsof -i :"$choice" -nP | grep -v "COMMAND")
}

dlu() {
    local domain_list=()

    if [ -z "$1" ]; then
        read -p "Enter the domain(s) to pass: " -a domain_list
    else
        domain_list=("$@")
    fi

    if [[ -f /usr/local/bin/domain_lookup.py ]]; then
        python3 /usr/local/bin/domain_lookup.py "${domain_list[@]}"
    else
        printf "\n%s\n\n" "The Python script not found at /usr/local/bin/domain_lookup.py"
    fi
}

venv() {
    # Go into a folder and call venv to setup a python virtual environment.
    # Check if already activated
    if [[ "$VIRTUAL_ENV" != "" ]]; then
        echo -e "\n\e[1;33mDeactivating current virtual environment...\e[0m"
        deactivate
        return
    fi
    
    # Check if the venv directory exists
    if [ -d "venv" ]; then
        echo -e "\n\e[1;33mActivating virtual environment...\e[0m"
        source venv/bin/activate
    else
        echo -e "\n\e[1;33mCreating and activating virtual environment...\e[0m"
        python3 -m venv venv
        source venv/bin/activate
    fi
}
