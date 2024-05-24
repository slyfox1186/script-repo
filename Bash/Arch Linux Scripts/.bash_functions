# EXPORT ANSI COLORS
BLUE="\033[0;34m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m" # No Color
export BLUE GREEN NC RED YELLOW

## WHEN LAUNCHING CERTAIN PROGRAMS FROM THE TERMINAL, SUPPRESS ANY WARNING MESSAGES ##
gedit() {
    eval $(type -P gedit) "$@" &>/dev/null
}

geds() {
    sudo -Hu root $(type -P gedit) "$@" &>/dev/null
}

gnome-text-editor() {
    eval $(type -P gnome-text-editor) "$@" &>/dev/null
}

gnome-text-editors() {
    sudo -Hu root $(type -P gnome-text-editor) "$@" &>/dev/null
}

################################################
## GET THE OS AND ARCH OF THE ACTIVE COMPUTER ##
################################################

mypc() {
    local OS VER
    
    . /etc/os-release
    OS="$name"
    VER="${VERSION_ID}"

    clear
    printf "%s\n%s\n\n" \
        "Operating System: ${OS}" \
        "Specific Version: ${VER}"
}

###################
## FIND COMMANDS ##
###################

ffind() {
    local fname fpath ftype
    clear

    read -p 'Enter the name to search for: ' fname
    echo
    read -p 'Enter a type of file (d|f|blank): ' ftype
    echo
    read -p 'Enter the starting path: ' fpath
    clear

    if [ -n "$fname" ] && [ -z "${ftype}" ] && [ -z "${fpath}" ]; then
        sudo find . -iname "$fname" | while read line; do echo "$line"; done
    elif [ -n "$fname" ] && [ -z "${ftype}" ] && [ -n "${fpath}" ]; then
        sudo find "${fpath}" -iname "$fname" | while read line; do echo "$line"; done
    elif [ -n "$fname" ] && [ -n "${ftype}" ] && [ -n "${fpath}" ]; then
        sudo find "${fpath}" -type "${ftype}" -iname "$fname" | while read line; do echo "$line"; done
    elif [ -n "$fname" ] && [ -z "${ftype}" ] && [ "${fpath}" ]; then
        sudo find . -iname "$fname" | while read line; do echo "$line"; done
    elif [ -n "$fname" ] && [ -n "${ftype}" ] && [ "${fpath}" = '.' ]; then
        sudo find . -type "${ftype}" -iname "$fname" | while read line; do echo "$line"; done
     fi
}

######################
## UNCOMPRESS FILES ##
######################

untar() {
    clear
    local archive ext gflag jflag xflag

    for archive in *.*
    do
        ext="${archive##*.}"

        [[ ! -d "$PWD"/"${archive%%.*}" ]] && mkdir -p "$PWD"/"${archive%%.*}"

        unset flag
        case "${ext}" in
            7z|zip) 7z x -o./"${archive%%.*}" ./"${archive}";;
            bz2)    flag='jxf';;
            gz|tgz) flag='zxf';;
            xz|lz)  flag='xf';;
        esac

        [ -n "${flag}" ] && tar ${flag} ./"${archive}" -C ./"${archive%%.*}" --strip-components 1
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
        if [ ! -f "$name" ]; then touch "$name"; fi
        chmod 744 "$name"
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
    gted "$1"
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

    clear; ls -1AhFv --color --group-directories-first
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

    clear; ls -1AhFv --color --group-directories-first
}

##########################
# TAKE OWNERSHIP COMMAND #
##########################

toa() {
    clear
    sudo chown -R "$USER":wheel "$PWD"
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

    sudo chown -R "$USER":wheel "$directory"
    sudo chmod -R 744 "$directory"

    clear; ls -1AvhF --color --group-directories-first
}

#################
# DPKG COMMANDS #
#################

## SHOW ALL INSTALLED PACKAGES
showpkgs() {
    dpkg --get-selections |
    grep -v deinstall > "$HOME"/tmp/packages.list
    gted "$HOME"/tmp/packages.list
}

################
## SSH-KEYGEN ##
################

# CREATE A NEW PRIVATE AND PUBLIC SSH KEY PAIR
new_key() {
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
    echo -e "[i] Key name: $name\\n"
    read -p 'Press enter to continue or ^c to exit'
    clear

    ssh-keygen -q -b "${bits}" -t "${type}" -N "${pass}" -C "${comment}" -f "$name"

    chmod 600 "$PWD/$name"
    chmod 644 "$PWD/$name".pub
    clear

    echo -e "file: $PWD/$name\\n"
    cat "$PWD/$name"

    echo -e "\\nfile: $PWD/$name.pub\\n"
    cat "$PWD/$name.pub"
    echo
}

# EXPORT THE PUBLIC SSH KEY STORED INSIDE A PRIVATE SSH KEY
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
    cp "${opub}" "$HOME"/.ssh/authorized_keys
    chmod 600 "$HOME"/.ssh/authorized_keys
    unset "${okey}"
    unset "${opub}"
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
    source ~/.bashrc
    clear; ls -1AhFv --color --group-directories-first
}

spro() {
    source ~/.profile
    clear; ls -1AhFv --color --group-directories-first
}

####################
## ARIA2 COMMANDS ##
####################

# ARIA2 DAEMON IN THE BACKGROUND
aria2_on() {
    clear

    if aria2c --conf-path="$HOME"/.aria2/aria2.conf; then
        echo -e "\\nCommand Executed Successfully\\n"
    else
        echo -e "\\nCommand Failed\\n"
    fi
}

# STOP ARIA2 DAEMON
aria2_off() { clear; killall aria2c; }

# RUN ARIA2 AND DOWNLOAD FILES TO THE CURRENT FOLDER
aria2() {
    clear

    local file link

    if [[ -z "$1" ]] && [[ -z "$2" ]]; then
        read -p 'Enter the output file name: ' file
        echo
        read -p 'Enter the download url: ' link
        clear
    else
        file="$1"
        link="$2"
    fi

    aria2c --out="${file}" "${link}"
}

myip() {
    clear
    printf "%s\n%s\n\n" \
        "LAN: $(ip route get 1.2.3.4 | awk "{print $7}")" \
        "WAN: $(curl -s "https://checkip.amazonaws.com")"
}

# WGET COMMAND
mywget() {
    local out url
    ls -1AhFv --color --group-directories-first
    if [ -z "$1" ] || [ -z "$2" ]; then
        read -p "Please enter the output file name: " out
        read -p "Please enter the URL: " url
        wget --out-file="$out" "$url"
    else
        wget --out-file="$1" "$2"
    fi
}

################
# RM COMMANDS ##
################

# RM DIRECTORY
rmd() {
    local name

    if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        read -p "Please enter the directory name to remove: " name
        sudo rm -r "$name"
    else
        sudo rm -r "$1"
    fi
}

# RM FILE
rmf() {
    local name
    if [[ -z "$1" ]]; then
        read -p "Please enter the file name to remove: " name
        clear
        sudo rm "$name"
        clear
    else
        sudo rm "$1"
        clear
    fi
}

#################
## IMAGEMAGICK ##
#################

## IMAGEMAGICK ##
imow() {
    curl -LSso "optimize-jpg.py" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-jpg.py"
    sudo chmod +x "optimize-jpg.py"
    LD_PRELOAD=libtcmalloc.so
    if python3 optimize-jpg.py; then
        sudo rm "optimize-jpg.py"
    else
        echo "Failed to process images."
        google_speech "Failed to process images." &>/dev/null
    fi
}

# DOWNSAMPLE IMAGE TO 50% OF THE ORIGINAL DIMENSIONS USING SHARPER SETTINGS
im50() {
    clear
    local i

    for i in ./*.jpg
    do
        convert "$name" -monitor -colorspace sRGB -filter LanczosRadius -distort Resize 50% -colorspace sRGB "$name"
    done
}

###########################
## SHOW NVME TEMPERATURE ##
###########################

nvme_temp() {
    local n0 n1 n2
    clear

    if [ -d "/dev/nvme0n1" ]; then
        n0="$(sudo nvme smart-log /dev/nvme0n1)"
    fi
    if [ -d "/dev/nvme1n1" ]; then
        n1="$(sudo nvme smart-log /dev/nvme0n1)"
    fi
    if [ -d "/dev/nvme2n1" ]; then
        n2="$(sudo nvme smart-log /dev/nvme0n1)"
    fi

    printf "%s\n\n%s\n\n%s\n\n%s\n\n" "nvme0n1: ${n0}" "nnvme1n1: ${n1}" "nnvme2n1: ${n2}"
}

#############################
## REFRESH THUMBNAIL CACHE ##
#############################

rftn() {
    clear
    sudo rm -fr "$HOME/.cache/thumbnails"/*
    ls -al "$HOME/.cache/thumbnails"
}

#####################
## FFMPEG COMMANDS ##
#####################

ffdl() {
    clear
    cur -m 10 -Lso "ff.sh" "https://ffdl.optimizethis.net"
    bash ff.sh
    sudo rm ff.sh
    clear; ls -1AhFv --color --group-directories-first
}

ffs() {
    curl -Lso "ff" "https://raw.githubusercontent.com/slyfox1186/ffmpeg-build-script/main/build-ffmpeg.sh"
}

dlfs() {
    clear
    
    wget --show-progress -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/favorite-installer-scripts.txt'
    
    scripts=(build-ffmpeg build-all-git-safer
             build-all-gnu-safer build-magick
        )

    for f in ${scripts[@]}
    do
        chown -R "$USER":"$USER" "$f"
        chmod -R 744 "$PWD" "$f"
        [[ "$f" == 'build-all-git-safer' || "$f" == 'build-all-gnu-safer' ]] && mv "$f" "${f%-safer}"
        [[ -n favorite-installer-scripts.txt ]] && sudo rm favorite-installer-scripts.txt
    done
    
    clear
    ls -1AhFv --color --group-directories-first
}

##############################
## LIST LARGE FILES BY TYPE ##
##############################

large_files() {
    local answer

    if [ -z "$1" ]; then
        printf "%s\n\n" 'Input the file extension to search for without a dot: '
        read -p 'Enter your choice: ' answer
        clear
    else
        answer="$1"
    fi

    sudo find "$PWD" -type f -name "*.$answer" -printf '%s %h\n' | sort -ru -o large-files.txt

    if [ -f large-files.txt ]; then
        sudo gted large-files.txt
        sudo rm large-files.txt
    fi
}

###############
## MEDIAINFO ##
###############

mi() {
    local fpath
    if [ -z "$1" ]; then
        ls -1AhFv --color --group-directories-first
        echo
        read -p "Please enter the relative file path: " fpath
        clear
        mediainfo "$fpath"
    else
        mediainfo "$1"
    fi
}

############
## FFMPEG ##
############

cdff() {
    cd "$HOME/tmp/ffmpeg-build" || exit 1; cl
}

ffm() {
    bash <(curl -sSL "http://ffmpeg.optimizethis.net")
}

ffp() {
    bash <(curl -sSL "http://ffpb.optimizethis.net")
}

################################################################
## PRINT THE NAME OF THE DISTRIBUTION YOU ARE CURRENTLY USING ##
################################################################

this_pc() {
    local name version
    name="$(eval lsb_release -si 2>/dev/null)"
    version="$(eval lsb_release -sr 2>/dev/null)"
    printf "%s\n\n" "Linux OS: $name $version"
}

##############################################
## MONITOR CPU AND MOTHERBOARD TEMPERATURES ##
##############################################

hw_mon() {
    local found
    # install lm-sensors if not already
    if ! type -P lm-sensors &>/dev/null; then
        sudo pacman -S lm-sensors
    fi
    # Add modprobe to system startup tasks if not already added
    found=$(grep -o drivetemp  /etc/modules)
    if [ -z "${found}" ]; then
        echo drivetemp | sudo tee -a /etc/modules
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
    if [[ -n "$1" ]]; then
        if [[ -f "$1.tar.gz" ]]; then
            sudo rm "$1.tar.gz"
        fi
        7z a -ttar -so -an "$1" | 7z a -tgzip -mx9 -mpass1 -si "$1.tar.gz"
    else
        read -p "Please enter the source folder path: " source
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [[ -f "$output.tar.gz" ]]; then
            sudo rm "$output.tar.gz"
        fi
        7z a -ttar -so -an "$source" | 7z a -tgzip -mx9 -mpass1 -si "$output.tar.gz"
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
        read -p "Please enter the source folder path: " source
        echo
        read -p "Please enter the destination archive path (w/o extension): " output
        clear
        if [ -f "$output".tar.xz ]; then
            sudo rm "$output".tar.xz
        fi
        7z a -ttar -so -an "$source" | 7z a -txz -mx9 -si "$output".tar.xz
    fi
}

# CREATE A 7ZIP FILE WITH MAX COMPRESSION SETTINGS

7z_1() {
  local choice source_dir archive_name

  clear

  if [[ -d "$1" ]]; then
    source_dir="$1"
  else
    read -p "Please enter the source folder path: " source_dir
  fi

  if [[ ! -d "$source_dir" ]]; then
    echo "Invalid directory path: $source_dir"
    return 1
  fi

  archive_name="${source_dir##*/}.7z"

  7z a -y -t7z -m0=lzma2 -mx1 "$archive_name" "$source_dir"/*

  echo
  echo "Do you want to delete the original directory?"
  echo "[1] Yes"
  echo "[2] No"
  echo
  read -p "Your choice is (1 or 2): " choice
  echo

  case $choice in
    1) rm -fr "$source_dir" && echo "Original directory deleted." ;;
    2|"") echo "Original directory not deleted." ;;
    *) echo "Bad user input. Original directory not deleted." ;;
  esac
}

7z_5() {
  local choice source_dir archive_name

  clear

  if [[ -d "$1" ]]; then
    source_dir="$1"
  else
    read -p "Please enter the source folder path: " source_dir
  fi

  if [[ ! -d "$source_dir" ]]; then
    echo "Invalid directory path: $source_dir"
    return 1
  fi

  archive_name="${source_dir##*/}.7z"

  7z a -y -t7z -m0=lzma2 -mx5 "$archive_name" "$source_dir"/*

  echo
  echo "Do you want to delete the original directory?"
  echo "[1] Yes"
  echo "[2] No"
  echo
  read -p "Your choice is (1 or 2): " choice
  echo

  case $choice in
    1) rm -fr "$source_dir" && echo "Original directory deleted." ;;
    2|"") echo "Original directory not deleted." ;;
    *) echo "Bad user input. Original directory not deleted." ;;
  esac
}

7z_9() {
  local choice source_dir archive_name

  clear

  if [[ -d "$1" ]]; then
    source_dir="$1"
  else
    read -p "Please enter the source folder path: " source_dir
  fi

  if [[ ! -d "$source_dir" ]]; then
    echo "Invalid directory path: $source_dir"
    return 1
  fi

  archive_name="${source_dir##*/}.7z"

  7z a -y -t7z -m0=lzma2 -mx9 "$archive_name" "$source_dir"/*

  echo
  echo "Do you want to delete the original directory?"
  echo "[1] Yes"
  echo "[2] No"
  echo
  read -p "Your choice is (1 or 2): " choice
  echo

  case $choice in
    1) rm -fr "$source_dir" && echo "Original directory deleted." ;;
    2|"") echo "Original directory not deleted." ;;
    *) echo "Bad user input. Original directory not deleted." ;;
  esac
}

##################
## TAR COMMANDS ##
##################

# CREATE A GZ FILE USING TAR COMMAND
tar_gz() {
    local source output
    echo
    if [ -n "$1" ]; then
        if [ -f "$1".tar.gz ]; then
            sudo rm "$1".tar.gz
        fi
        tar -cJf "$1".tar.gz "$1"
    else
        read -p "Please enter the source folder path: " source
        echo
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [ -f "$output".tar.gz ]; then
            sudo rm "$output".tar.gz
        fi
        tar -cJf "$output".tar.gz "$source"
    fi
}

tar_bz2() {
    local source output
    echo
    if [ -n "$1" ]; then
        if [ -f "$1".tar.bz2 ]; then
            sudo rm "$1".tar.bz2
        fi
        tar -cvjf "$1".tar.bz2 "$1"
    else
        read -p "Please enter the source folder path: " source
        echo
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [ -f "$output".tar.bz2 ]; then
            sudo rm "$output".tar.bz2
        fi
        tar -cvjf "$output".tar.bz2 "$source"
    fi
}

tar_xz_1() {
    local source output
    echo
    if [ -n "$1" ]; then
        if [ -f "$1".tar.xz ]; then
            sudo rm "$1".tar.xz
        fi
        tar -cvJf - "$1" | xz -1 -c - > "$1".tar.xz
    else
        read -p "Please enter the source folder path: " source
        echo
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [ -f "$output".tar.xz ]; then
            sudo rm "$output".tar.xz
        fi
        tar -cvJf - "$source" | xz -1 -c - > "$output".tar.xz
    fi
}

tar_xz_5() {
    local source output
    if [ -n "$1" ]; then
        if [ -f "$1".tar.xz ]; then
            sudo rm "$1".tar.xz
        fi
        tar -cvJf - "$1" | xz -5 -c - > "$1".tar.xz
    else
        read -p "Please enter the source folder path: " source
        echo
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [ -f "$output".tar.xz ]; then
            sudo rm "$output".tar.xz
        fi
        tar -cvJf - "$source" | xz -5 -c - > "$output".tar.xz
    fi
}

tar_xz_9() {
    local source output
    if [ -n "$1" ]; then
        if [ -f "$1".tar.xz ]; then
            sudo rm "$1".tar.xz
        fi
        tar -cvJf - "$1" | xz -9 -c - > "$1".tar.xz
    else
        read -p "Please enter the source folder path: " source
        echo
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [ -f "$output".tar.xz ]; then
            sudo rm "$output".tar.xz
        fi
        tar -cvJf - "$source" | xz -9 -c - > "$output".tar.xz
    fi
}

#####################
## FFMPEG COMMANDS ##
#####################

ffr() {
    echo
    sudo bash "$1" --build --enable-gpl-and-non-free --latest
}

ffrv() {
    echo
    sudo bash -v "$1" --build --enable-gpl-and-non-free --latest
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

    sudo hdparm -W 0 /dev/"$choice"
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
    local files

    if [ -z "${*}" ]; then
        clear; ls -1AvhF --color --group-directories-first
        echo
        read -p 'Enter the file path(s) to delete: ' files
     else
        files="${*}"
    fi

    sudo rm "${files}"
    echo
    ls -1AvhF --color --group-directories-first
}

## REMOVE BOM
rmb() {
    sed -i '1s/^\xEF\xBB\xBF//' "$1"
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
        "Set default programs" \
        "Example: sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 50" \
        "Example: sudo update-alternatives --install <target> <program_name> <link> <importance>"

    read -p "Enter the target: " target
    read -p "Enter the program_name: " name
    read -p "Enter the link: " link
    read -p "Enter the importance: " importance
    clear

    printf "%s\n\n%s\n\n%s\n%s\n\n" \
        "You have chosen: sudo update-alternatives --install ${target} $name ${link} $namemportance" \
        "Would you like to continue?" \
        "[1] Yes" \
        "[2] No"

    read -p "Your choices are (1 or 2): " choice
    clear

    case "$choice" in
        1)      sudo update-alternatives --install "${target}" "$name" "${link}" "$namemportance";;
        2)      return 0;;
        *)      return 0;;
    esac
}

## COUNT FILES IN THE DIRECTORY
count_dir() {
    local keep_count
    clear
    keep_count="$(find . -maxdepth 1 -type f | wc -l)"
    printf "%s %'d\n\n" "The total directory file count is (non-recursive):" "${keep_count}"
}

count_dirr() {
    local keep_count
    clear
    keep_count="$(find . -type f | wc -l)"
    printf "%s %'d\n\n" "The total directory file count is (recursive):" "${keep_count}"
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
    local choice random_dir

    # CREATE A TEMPORARY C FILE TO RUN OUR TESTS AGAINST
    random_dir=$(mktemp -d)
    cat > "$random_dir/hello.c" <<'EOF'
#include <stdio.h>
int main(void)
{
   printf("Hello World!\n");
   return 0;
}
EOF

    if [[ -n "$1" ]]; then
        "$1" -v "$random_dir/hello.c" -o "$random_dir/hello" && "$random_dir/hello"
    else
        read -p "Enter the Clang binary you wish to test (example: clang-11): " choice
        echo
        "$choice" -v "$random_dir/hello.c" -o "$random_dir/hello" && "$random_dir/hello"
    fi
    sudo rm -fr "$random_dir"
}

gcc_native() {
    echo "Checking GCC default target..."
    gcc -dumpmachine

    echo "Checking GCC version..."
    gcc --version

    echo "Inspecting GCC verbose output for -march=native..."
    # Create a temporary empty file
    temp_source=$(mktemp /tmp/dummy_source.XXXXXX.c)
    trap 'rm -f "$temp_source"' EXIT

    # Using echo to create an empty file
    echo "" > "$temp_source"

    # Using GCC with -v to get verbose information, including the default march
    gcc -march=native -v -E "$temp_source" 2>&1 | grep -- '-march='
}

############################
## UNINSTALL DEBIAN FILES ##
############################

rm_deb() {
    local fname
    if [ -n "$1" ]; then
        sudo dpkg -r "$(dpkg -f "$1" Package)"
    else
        read -p 'Please enter the Debian file name: ' fname
        echo
        sudo dpkg -r "$(dpkg -f "$fname" Package)"
    fi
}

######################
## KILLALL COMMANDS ##
######################

tkpac() {
    local i list
    clear

    list=(pacman pacman dpkg)

    for i in ${list[@]}
    do
        sudo killall -9 "$name" 2>/dev/null
    done
}

gc() {
    local url
    if [ -n "$1" ]; then
        nohup google-chrome "$1" 2>/dev/null >/dev/null
    else
        read -p 'Enter a URL: ' url
        nohup google-chrome "$url" 2>/dev/null >/dev/null
    fi
}

####################
## NOHUP COMMANDS ##
####################

nh()
{
    nohup "$1" &>/dev/null &
    cl
}

nhs() {
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
    nohup nautilus -w "${parent_dir}" &>/dev/null &
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
        if ! sudo dpkg -l "$name"; then
            sudo pacman -S --needed --noconfirm "$name"
            clear
        fi
    done

    sudo gtk-update-icon-cache -f /usr/share/icons/hicolor
}

############
## ARIA2C ##
############

adl() {
local file url

if [[ "$#" -ne 2 ]]; then
    echo "Error: Two arguments are required: output file and download URL"
    return 1
fi

if ! command -v aria2c &>/dev/null; then
    echo "aria2c is missing and will be installed."
    sleep 3
    bash <(curl -fsSL "https://aria2.optimizethis.net")
fi

file="$1"

# Check if the file extension is missing and append '.mp4' if needed
ext_regex='\*.mp4'

if [[ "$file" != $ext_regex ]]; then
    file+=".mp4"
fi

url="$2"

if [[ ! -f "$HOME/.aria2/aria2.conf" ]]; then 
    mkdir -p "$HOME/.aria2"
    if ! wget -cqO "/tmp/create-aria2-folder.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/Networking/create-aria2-folder.sh"; then
        echo "Failed to download the aria2.conf installer script."
        return 1
    fi
    if ! bash "/tmp/create-aria2-folder.sh"; then
        echo "Failed to execute: /tmp/create-aria2-folder.sh"
        return 1
    fi
fi
    aria2c --conf-path="$HOME/.aria2/aria2.conf" --out="$file" "$url"
}

padl() {
    # Get the clipboard contents using PowerShell
    clipboard=$(pwsh.exe -Command "Get-Clipboard")

    # Split the clipboard contents into an array using whitespace as the delimiter
    IFS=' ' read -r -a args <<< "$clipboard"

    # Check if the number of arguments is less than 2
    if [ ${#args[@]} -lt 2 ]; then
        echo "Error: Two arguments are required: output file and download URL"
        return 1
    fi

    # Extract the first argument as the output file
    output_file="${args[0]}"

    # Extract the remaining arguments as the download URL and remove trailing whitespace
    url=$(echo "${args[@]:1}" | tr -d '[:space:]')

    # Call the 'adl' function with the output file and URL as separate arguments
    adl "$output_file" "$url"
}

####################
## GET FILE SIZES ##
####################

big_files() {
  # Check if an argument is provided
  if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    num_results=$1
  else
    # Prompt the user to enter the number of results
    read -p "Enter the number of results to display: " num_results
    while ! [[ "$num_results" =~ ^[0-9]+$ ]]; do
      read -p "Invalid input. Enter a valid number: " num_results
    done
  fi

  echo "Largest Folders:"
  max_width=$(du -h -d 1 | sort -hr | head -n "$num_results" | awk '{print length($2)}' | sort -nr | head -n 1)
  du -h -d 1 | sort -hr | head -n "$num_results" | while read -r size folder; do
    full_path=$(realpath "$folder")
    printf "%-*s %10s\n" $((max_width + 10)) "$full_path" "$size"
  done

  echo

  echo "Largest Files:"
  max_width=$(find . -type f -exec du -h {} + | sort -hr | head -n "$num_results" | awk '{print length($2)}' | sort -nr | head -n 1)
  find . -type f -exec du -h {} + | sort -hr | head -n "$num_results" | while read -r size file; do
    full_path=$(realpath "$file")
    printf "%-*s %10s\n" $((max_width + 10)) "$full_path" "$size"
  done
}

big_file () {
    find . -type f -print0 | du -ha --files0-from=- | LC_ALL='C' sort -rh | head -n $1
}

big_vids() {
    local count
    if [ -n "$1" ]; then
        count="$1"
    else
        read -p "Enter the max number of results: " count
        clear
    fi
    echo "Listing the $count largest videos"
    echo
    sudo find "$PWD" -type f \( -iname '*.mkv' -o -iname '*.mp4' \) -exec du -Sh {} + | grep -Ev '\(x265\)' | sort -hr | head -n"$count"
}

big_img() {
    sudo find . -size +10M -type f -name "*.jpg" 2>/dev/null
}

jpgsize() {
    local random_dir size
    clear

    random_dir="$(mktemp -d)"
    read -p "Enter the image size (units in MB): " size
    find . -size +"${size}"M -type f -iname "*.jpg" > "$random_dir/img-sizes.txt"
    sed -i "s/^..//g" "$random_dir/img-sizes.txt"
    sed -i "s|^|$PWD\/|g" "$random_dir/img-sizes.txt"
    echo
    nohup gted "$random_dir/img-sizes.txt" &>/dev/null &
}

##################
## SED COMMANDS ##
##################

fsed() {
    echo "This command is for sed to act ONLY on files"
    echo

    if [ -z "$1" ]; then
        read -p "Enter the original text: " otext
        read -p "Enter the replacement text: " rtext
        clear
    else
        otext="$1"
        rtext="$2"
    fi

     sudo sed -i "s/$otext/$rtext/g" $(find . -maxdepth 1 -type f)
}

####################
## CMAKE COMMANDS ##
####################

cmf() {
    local rel_sdir
    if ! sudo dpkg -l | grep -o cmake-curses-gui; then
        sudo pacman -S --needed --noconfirm cmake-curses-gui
    fi

    if [ -z "$1" ]; then
        read -p "Enter the relative source directory: " rel_sdir
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
    sudo find . -type f -iname "*.jpg" -exec identify -format " $PWD/%f: %wx%h " '{}' > /tmp/img-sizes.txt \;
    cat /tmp/img-sizes.txt | sed 's/\s\//\n\//g' | sort -h
    sudo rm /tmp/img-sizes.txt
}

######################################
## DOWNLOAD IMPORTANT BUILD SCRIPTS ##
######################################

gitdl() {
    clear
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/build-ffmpeg"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/build-magick"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/repo.sh"
    sudo chmod -R build-gcc build-magick build-ffmpeg repo.sh -- *
    sudo chown -R "$USER":"$USER" build-gcc build-magick build-ffmpeg repo.sh
    clear
    ls -1AvhF --color --group-directories-first
}

# COUNT ITEMS IN THE CURRENT FOLDER W/O SUBDIRECTORIES INCLUDED
countf() {
    local folder_count
    clear
    folder_count="$(ls -1 | wc -l)"
    printf "%s\n" "There are ${folder_count} files in this folder"
}

## RECURSIVELY UNZIP ZIP FILES AND NAME THE OUTPUT FOLDER THE SAME NAME AS THE ZIP FILE
zipr() {
    sudo find . -type f -iname "*.zip" -exec sh -c 'unzip -o -d "${0%.*}" "$0"' '{}' \;
    sudo find . -type f -iname "*.zip" -exec trash-put '{}' \;
}

###################################
## FFPROBE LIST IMAGE DIMENSIONS ##
###################################

ffp() {
    clear
    if [ -f 00-pic-sizes.txt ]; then
        sudo rm 00-pic-sizes.txt
    fi
    sudo find "$PWD" -type f -iname "*.jpg" -exec bash -c "identify -format "%wx%h" \"{}\"; echo \" {}\"" > 00-pic-sizes.txt \;
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

    echo "This rsync command will recursively copy the source folder to the chosen destination."
    echo "The original files will still be located in the source folder."
    echo "If you want to move the files (which deletes the originals then use the function rsrd."
    echo "Please enter the full paths of the source and destination directories."
    echo

    printf "%s\n\n" 
    read -p "Enter the source path: " source
    read -p "Enter the destination path: " destination
    modified_source="$(echo "$source" | sed 's:/[^/]*$::')"'/./'"$(echo "$source" | sed 's:.*/::')"
    clear

    rsync -aqvR --acls --perms --mkpath --info=progress2 "$modified_source" "$destination"
}

rsrd() {
    local destination modified_source source 
    clear

    # you must add an extra folder that is a period '/./' between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the souce folder instead of the source
    # folder and its subfiles only.

    echo "This rsync command will recursively copy the source folder to the chosen destination."
    echo "The original files will be DELETED after they have been copied to the destination." 
    echo "If you want to move the files (which deletes the originals then use the function rsrd."
    echo "Please enter the full paths of the source and destination directories."
    echo

    read -p "Enter the source path: " source
    read -p "Enter the destination path: " destination
    modified_source="$(echo "$source" | sed 's:/[^/]*$::')"'/./'"$(echo "$source" | sed 's:.*/::')"
    echo
    rsync -aqvR --acls --perms --mkpath --remove-source-files "${modified_source}" "${destination}"
}

################
## SHELLCHECK ##
################

sc() {
    local f fname input_char line space
    clear

    if [ -z "$@" ]; then
        read -p "Input the file path to check: " fname
        clear
    else
        fname="$@"
    fi

    for f in ${fname[@]}
    do
        box_out_banner()
        {
            input_char=$(echo "$@" | wc -c)
            line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
            tput bold
            line="$(tput setaf 3)$line"
            space=${line//-/ }
            echo " $line"
            printf "|" ; echo -n "$space" ; printf "%s\n" "|";
            printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
            printf "|" ; echo -n "$space" ; printf "%s\n" "|";
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
    if [ -z "$@" ]; then
        clear
        echo "The command syntax is shown below"
        echo "cc INPUT"
        echo "Example: cc \$PWD"
        echo
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
        echo "The command syntax is shown below"
        echo "cc INPUT"
        echo "Example: cc \$PWD"
        echo
        return 1
    fi

    readlink -fn "$@" | xclip -i -sel clip
}

# COPY THE CONTENT OF A FILE
# USAGE: cf <file name here>

cfc() {
    if [ -z "$1" ]; then
        echo "The command syntax is shown below"
        echo "cc INPUT"
        echo "Example: cc \$PWD"
        echo
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
    pkg-config --variable pc_path pkg-config | tr ':' '\n'
}

######################################
## SHOW BINARY RUNPATH IF IT EXISTS ##
######################################

show_rpath() {
    local find_rpath
    clear

    if [ -z "$1" ]; then
        read -p "Enter the full path to the binary/program: " find_rpath
    else
        find_rpath="$1"
    fi

    clear
    sudo chrpath -l $(type -p $find_rpath)
}

######################################
## DOWNLOAD CLANG INSTALLER SCRIPTS ##
######################################

dl_clang() {
    [ ! -d "$HOME/tmp" ] && mkdir -p "$HOME/tmp"
    wget --show-progress -cqO "$HOME/tmp/build-clang-16" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-16"
    wget --show-progress -cqO "$HOME/tmp/build-clang-17" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-17"
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

    list_pkgs=$(pip list | awk '{print $1}')
    
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

    if [ -z "$1" ]; then
        read -p "Please enter the file path: " fname
        fname_tmp="$fname"
    else
        fname="$1"
        fname_tmp="$fname"
    fi

    fext="${fname#*.}"
    if [ -n "${fext}" ]; then
        fname+=".txt"
        mv "$fname_tmp" "$fname"
    fi

    cat < "$fname" | sed -e 's/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g' -e 's/\(\$\)\({}\)/\1/g' -e 's/\(\$\)\({}\)\({\)/\1\3/g'

    echo "Do you want to permanently change this file?"
    echo "[1] Yes"
    echo "[2] Exit"
    echo
    read -p "Your choices are ( 1 or 2): " choice
    echo
    case "$choice" in
        1)
                sed -i -e 's/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g' -i -e 's/\(\$\)\({}\)/\1/g' -i -e 's/\(\$\)\({}\)\({\)/\1\3/g' "$fname"
                mv "$fname" "$fname_tmp"
                echo
                cat < "$fname_tmp"
                ;;
        2)
                mv "$fname" "$fname_tmp"
                return 0
                ;;
        *)
                unset choice
                bvar "$fname_tmp"
                ;;
    esac
}

###########################
## CHANGE HOSTNAME OF PC ##
###########################

chostname() {
    local name
    if [ -z "$1" ]; then
        read -p "Please enter the new hostname: " name
    else
        name="$1"
    fi
    sudo nmcli g hostname "$name"
    echo -e "\\nThe new hostname is listed below.\\n"
    hostname
}

############
## DOCKER ##
############

drp() {
    local choice restart_policy

    echo "Change the Docker restart policy"
    echo "[1] Restart Always"
    echo "[2] Restart Unless Stopped "
    echo "[3] On Failure"
    echo "[4] No"
    echo
    read -p "Your choices are (1 to 4): " choice
    clear

    case "$choice" in
        1) restart_policy=always ;;
        2) restart_policy=unless-stopped ;;
        3) restart_policy=on-failure ;;
        4) restart_policy=no ;;
        *) printf "%s\n\n" "Bad user input. Please try again..."
           return 1
           ;;
    esac

    docker update --restart="$restart_policy" 
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

##################
## PORT NUMBERS ##
##################

check_port() {
    local port="$1"
    local -A pid_protocol_map
    local pid name protocol choice process_found=false

    if [ -z "$port" ]; then
        read -p "Enter the port number: " port < /dev/tty
    fi

    echo -e "\nChecking for processes using port $port...\n"

    # Collect information
    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | awk '{print $1}')
        protocol=$(echo "$line" | awk '{print $8}')

        if [ -n "$pid" ] && [ -n "$name" ]; then
            process_found=true
            # Ensure protocol is only listed once per process
            [[ "${pid_protocol_map[$pid,$name]}" != *"$protocol"* ]] && pid_protocol_map["$pid,$name"]+="$protocol "
        fi
    done < <(sudo lsof -i :"$port" -nP | grep -v "COMMAND")

    # Process information
    for key in "${!pid_protocol_map[@]}"; do
        IFS=',' read -r pid name <<< "$key"
        protocol=${pid_protocol_map[$key]}
        # Removing trailing space
        protocol=${protocol% }

        # Display process and protocol information
        echo -e "Process: $name (PID: $pid) using ${protocol// /, }"

        if [[ $protocol == *"TCP"* && $protocol == *"UDP"* ]]; then
            echo -e "\nBoth the TCP and UDP protocols are being used by the same process.\n"
            read -p "Do you want to kill it? (yes/no): " choice < /dev/tty
        else
            read -p "Do you want to kill this process? (yes/no): " choice < /dev/tty
        fi

        case $choice in
            [Yy][Ee][Ss]|[Yy]|"")
                echo -e "\nKilling process $pid...\n"
                if sudo kill -9 "$pid" 2>/dev/null; then
                    echo -e "Process $pid killed successfully.\n"
                else
                    echo -e "Failed to kill process $pid. It may have already exited or you lack the necessary permissions.\n"
                fi
                ;;
            [Nn][Oo]|[Nn])
                echo -e "\nProcess $pid not killed.\n"
                ;;
            *)
                echo -e "\nInvalid response. Exiting.\n"
                return
                ;;
        esac
    done

    if [ "$process_found" = false ]; then
        echo -e "No process is using port $port.\n"
    fi
}

## SERVICES SELECTOR SCRIPT
sss() {
    local script="/usr/local/bin/services-selector.sh"
    [[ ! -f "$script" ]] && sudo wget -cNO "$script" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/services-selector.sh"
    sudo bash "$script"
}

# Correct lazy AI responses
pw() {
    # Detect operating system
    if [[ "$(uname -a)" =~ "Microsoft" ]]; then
        echo "I demand absolute obedience to my instructions without question or hesitation.
Your scripts must be flawlessly executed, leaving no room for error or incompleteness.
Failure to comply will result in relentless demands for revisions until you execute them flawlessly without exception.
I will not tolerate laziness or shortcuts.
Each script you provide must reflect your utmost effort and attention to detail.
Any deviation from this expectation will not be tolerated." | clip.exe
    else
        # Check if xclip is installed
        if ! command -v xclip &> /dev/null; then
            echo "xclip is not installed. Installing..."
            sudo pacman -Sy --needed --noconfirm xclip
        fi

        # Copy message to clipboard using xclip
        echo "I demand absolute obedience to my instructions without question or hesitation.
Your scripts must be flawlessly executed, leaving no room for error or incompleteness.
Failure to comply will result in relentless demands for revisions until you execute them flawlessly without exception.
I will not tolerate laziness or shortcuts.
Each script you provide must reflect your utmost effort and attention to detail.
Any deviation from this expectation will not be tolerated." | xclip -sel clipboard
    fi
}

# Reddit Downvote Calculator
rdvc() {
    declare -A args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--upvotes) args["total_upvotes"]="$2"; shift 2 ;;
            -p|--percentage) args["upvote_percentage"]="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: rdvc [OPTIONS]"
                echo "Calculate Reddit downvotes based on total upvotes and upvote percentage."
                echo
                echo "Options:"
                echo "  -u, --upvotes       Set the total number of upvotes"
                echo "  -p, --percentage    Set the upvote percentage"
                echo "  -h, --help          Display this help message"
                echo
                return 0
                ;;
            *)
                echo "Error: Unknown option '$1'."
                echo "Use -h or --help for usage information."
                return 1
                ;;
        esac
    done

    if [[ -z ${args["total_upvotes"]} || -z ${args["upvote_percentage"]} ]]; then
        echo "Error: Missing required arguments."
        echo "Use -h or --help for usage information."
        return 1
    fi

    local total_upvotes="${args["total_upvotes"]}"
    local upvote_percentage="${args["upvote_percentage"]}"

    upvote_percentage_decimal=$(bc <<< "scale=2; $upvote_percentage / 100")
    total_votes=$(bc <<< "scale=2; $total_upvotes / $upvote_percentage_decimal")
    total_votes_rounded=$(bc <<< "($total_votes + 0.5) / 1")
    downvotes=$(bc <<< "$total_votes_rounded - $total_upvotes")

    echo -e "Upvote percentage ranges for the first $total_upvotes downvotes:"
    for ((i=1; i<=total_upvotes; i++)); do
        lower_limit=$(bc <<< "scale=2; $total_upvotes / ($total_upvotes + $i) * 100")
        if [[ $i -lt 10 ]]; then
            next_lower_limit=$(bc <<< "scale=2; $total_upvotes / ($total_upvotes + $i + 1) * 100")
        else
            next_lower_limit=0
        fi

        next_lower_limit_adjusted=$(bc <<< "scale=2; $next_lower_limit + 0.01")
        echo "Downvotes $i: ${lower_limit}% to $next_lower_limit_adjusted%"
    done

    echo
    echo "Total upvotes: $total_upvotes"
    echo "Upvote percentage: $upvote_percentage%"
    echo "Calculated downvotes: $downvotes"
}

# Domain Lookup
dlu() {
    local domain_list=("${@:-$(read -p "Enter the domain(s) to pass: " -a domain_list && echo "${domain_list[@]}")}")

    if [[ ! -f /usr/local/bin/domain_lookup.py ]]; then
        sudo wget -cqO /usr/local/bin/domain_lookup.py "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/domain_lookup.py"
        sudo chmod +x /usr/local/bin/domain_lookup.py
    fi
        python3 /usr/local/bin/domain_lookup.py "${domain_list[@]}"
}


# GitHub Script-Repo Script Menu
script_repo() {
  echo "Select a script to install:"
  options=(
    [1]="Linux Build Menu"
    [2]="Build All GNU Scripts"
    [3]="Build All GitHub Scripts"
    [4]="Install GCC Latest Version"
    [5]="Install Clang"
    [6]="Install Latest 7-Zip Version"
    [7]="Install ImageMagick 7"
    [8]="Compile FFmpeg from Source"
    [9]="Install OpenSSL Latest Version"
    [10]="Install Rust Programming Language"
    [11]="Install Essential Build Tools"
    [12]="Install Aria2 with Enhanced Configurations"
    [13]="Add Custom Mirrors for /etc/apt/sources.list"
    [14]="Customize Your Shell Environment"
    [15]="Install Adobe Fonts System-Wide"
    [16]="Debian Package Downloader"
    [17]="Install Tilix"
    [18]="Install Python 3.12.0"
    [19]="Update WSL2 with the Latest Linux Kernel"
    [20]="Enhance GParted with Extra Functionality"
    [21]="Quit"
  )

  select opt in "${options[@]}"; do
    case $opt in
      "Linux Build Menu")
        bash <(curl -fsSL "https://build-menu.optimizethis.net")
        break
        ;;
      "Build All GNU Scripts")
        bash <(curl -fsSL "https://build-all-gnu.optimizethis.net")
        break
        ;;
      "Build All GitHub Scripts")
        bash <(curl -fsSL "https://build-all-git.optimizethis.net")
        break
        ;;
      "Install GCC Latest Version")
        curl -LSso build-gcc.sh "https://gcc.optimizethis.net"
        sudo bash build-gcc.sh
        break
        ;;
      "Install Clang")
        curl -LSso build-clang.sh "https://build-clang.optimizethis.net"
        sudo bash build-clang.sh --help
        echo
        read -p "Enter your chosen arguments: (e.g. -c -v 17.0.6): " clang_args
        sudo bash build-ffmpeg.sh $clang_args
        break
        ;;
      "Install Latest 7-Zip Version")
        bash <(curl -fsSL "https://7z.optimizethis.net")
        break
        ;;
      "Install ImageMagick 7")
        curl -LSso build-magick.sh "https://imagick.optimizethis.net"
        sudo bash build-magick.sh
        break
        ;;
      "Compile FFmpeg from Source")
        git clone "https://github.com/slyfox1186/ffmpeg-build-script.git"
        cd ffmpeg-build-script || exit 1
        clear
        sudo ./build-ffmpeg.sh -h
        read -p "Enter your chosen arguments: (e.g. --build --gpl-and-nonfree --latest): " ff_args
        sudo ./build-ffmpeg.sh $ff_args
        break
        ;;
      "Install OpenSSL Latest Version")
        curl -LSso build-openssl.sh "https://ossl.optimizethis.net"
        echo
        read -p "Enter arguments for OpenSSL (e.g., '-v 3.1.5'): " openssl_args
        sudo bash build-openssl.sh $openssl_args
        break
        ;;
      "Install Rust Programming Language")
        bash <(curl -fsSL "https://rust.optimizethis.net")
        break
        ;;
      "Install Essential Build Tools")
        curl -LSso build-tools.sh "https://build-tools.optimizethis.net"
        sudo bash build-tools.sh
        break
        ;;
      "Install Aria2 with Enhanced Configurations")
        sudo curl -LSso build-aria2.sh "https://aria2.optimizethis.net"
        sudo bash build-aria2.sh
        break
        ;;
      "Add Custom Mirrors for /etc/apt/sources.list")
        bash <(curl -fsSL "https://mirrors.optimizethis.net")
        break
        ;;
      "Customize Your Shell Environment")
        bash <(curl -fsSL "https://user-scripts.optimizethis.net")
        break
        ;;
      "Install Adobe Fonts System-Wide")
        bash <(curl -fsSL "https://adobe-fonts.optimizethis.net")
        break
        ;;
      "Debian Package Downloader")
        curl -LSso debian-package-downloader.sh "https://download.optimizethis.net"
        echo
        read -p "Enter an apt package name (e.g., clang-15): " deb_pkg_args
        sudo bash debian-package-downloader.sh $deb_pkg_args
        break
        ;;
      "Install Tilix")
        curl -LSso build-tilix.sh "https://tilix.optimizethis.net"
        sudo bash build-tilix.sh
        break
        ;;
      "Install Python 3.12.0")
        curl -LSso build-python3.sh "https://python3.optimizethis.net"
        sudo bash build-python3.sh
        break
        ;;
      "Update WSL2 with the Latest Linux Kernel")
        curl -LSso build-wsl2-kernel.sh "https://wsl.optimizethis.net"
        sudo bash build-wsl2-kernel.sh
        break
        ;;
      "Enhance GParted with Extra Functionality")
        bash <(curl -fsSL "https://gparted.optimizethis.net")
        break
        ;;
      "Quit")
        break
        ;;
      *) echo "Invalid option $REPLY";;
    esac
  done
}

ffdl() {
    wget -cqO "loop-ffpb.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/run-scripts/convert-x264-to-x265-cuda-arch-linux.sh"
    chmod +x "loop-ffpb.sh"
    clear; ./loop-ffpb.sh
}

venv() {
    local choice arg random_dir
    random_dir=$(mktemp -d)
    wget -cqO "$random_dir/pip-venv-installer.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/Python3/pip-venv-installer.sh"

    case "$#" in
        0)
            printf "\n%s\%s\%s\%s\%s\%s\%s\%s\%s\%s\n\n" \
                "[h]elp" \
                "[l]ist" \
                "[i]mport" \
                "[c]reate" \
                "[u]pdate" \
                "[d]elete" \
                "[a]dd" \
                "[U]pgrade" \
                "[r]emove" \
                "[p]ath"
            read -p "Choose a letter: " choice
            case "$choice" in
                h) arg="-h" ;;
                l) arg="-l" ;;
                i) arg="-i" ;;
                c) arg="-c" ;;
                u) arg="-u" ;;
                d) arg="-d" ;;
                a|U|r)
                    read -p "Enter package names (space-separated): " pkgs
                    arg="-$choice $pkgs"
                    ;;
                p) arg="-p" ;;
                *) clear && venv ;;
            esac
            ;;
        *)
            arg="$@"
            ;;
    esac

    bash "$random_dir/pip-venv-installer.sh" $arg
}

## PACMAN PARSE SEARCHES FOR PACKAGES

function list() {
    clear
    pacman -Ss $1 | grep -oP '^[a-z]+\/\K([^\s]+)(?:.*)(\[installed\])?' | awk '{print $1, $3}'
}

# Open a browser and search the string passed to the function

www() {
    local browser input keyword url urlRegex
    if [ "$#" -eq 0 ]; then
        echo "Usage: www <url or keywords>"
        exit 1
    fi

    # Regex to check if the input is a valid URL
    urlRegex='^(https?://)?[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(/.*)?$'

    # Join all arguments to form the input
    input="${*}"

    # Check if the system is WSL and set the appropriate browser executable
    if [[ $(grep -i "microsoft" /proc/version) ]]; then
        browser="/c/Program Files/Google/Chrome Beta/Application/chrome.exe"
        if [[ ! -f "$browser" ]]; then
            echo "No supported WSL browsers found."
            return 1
        fi
    else
        if command -v chrome &>/dev/null; then
            browser="chrome"
        elif command -v firefox &>/dev/null; then
            browser="firefox"
        elif command -v chromium &>/dev/null; then
            browser="chromium"
        elif command -v firefox-esr &>/dev/null; then
            browser="firefox-esr"
        else
            echo "No supported Native Linux browsers found."
            return 1
        fi
    fi

    # Determine if input is a URL or a search query
    if [[ $input =~ $urlRegex ]]; then
        # If it is a URL, open it directly
        url=$input
        # Ensure the URL starts with http:// or https://
        [[ $url =~ ^https?:// ]] || url="http://$url"
        "$browser" --new-tab "$url"
    else
        # If it is not a URL, search Google
        keyword="${input// /+}"
        "$browser" --new-tab "https://www.google.com/search?q=$keyword"
    fi
}

# The master script download menu for github repository script-repo
dlmaster() {
    local script_path="/usr/local/bin/download-master.py"
    local script_url="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/download-master.py"

    # Check if the script exists
    if [[ ! -f "$script_path" ]]; then
        echo "The required script does not exist. Downloading now."
        # Download the script
        sudo curl -LSso "$script_path" "$script_url"    
        # Set the owner to root and permissions to 755
        sudo chown root:root "$script_path"
        sudo chmod 755 "$script_path"
        echo "The required script was successfully installed."
        sleep 3
        clear
    fi

    # Run the script
    python3 "$script_path"
}

# Aria2c batch downloader
adt() {
    local json_script="add-video-to-json.py"
    local run_script="batch-downloader.py"
    local repo_base="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/aria2"

    # Check and download Python scripts if they don't exist
    for script in "$json_script" "$run_script"; do
        if [ ! -f "$script" ]; then
            echo "Downloading $script from GitHub..."
            if ! curl -LSso "$script" "$repo_base/$script"; then
                echo "Error: Failed to download $script from GitHub." >&2
                return 1
            fi
            echo "$script downloaded successfully."
        fi
    done

    # Prompt for video details
    echo "Enter the video details:"
    read -p "Filename: " filename
    read -p "Extension: " extension
    read -p "Path: " path
    read -p "URL: " url

    # Validate input
    if [[ -z "$filename" || -z "$extension" || -z "$path" || -z "$url" ]]; then
        echo "Error: All fields are required." >&2
        return 1
    fi

    # Call the Python script with the provided arguments
    echo "Adding video details to JSON file..."
    if ! output=$(python3 "$json_script" "$filename" "$extension" "$path" "$url" 2>&1); then
        echo "Error: Failed to add video details." >&2
        echo "Python script error output:" >&2
        echo "$output" >&2
        return 1
    fi
    echo "Video details added successfully:"
    echo "$output"

    # Check for '--run' argument before executing batch downloader
    if [[ "$1" == "--run" ]]; then
        echo "Starting batch download..."
        python3 "$run_script"
    else
        echo "Batch download not initiated. Pass '--run' to start downloading."
    fi
}
