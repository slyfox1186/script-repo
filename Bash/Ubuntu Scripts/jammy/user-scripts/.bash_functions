# EXPORT WINDOWS PATHS
PATH="$PATH:/c/Windows/System32:/c/Windows:/c/Program Files:/c/Program Files (x86):/c/Program Files (x86)/FSViewer:/c/Program Files/Notepad++:/c/Program Files/VLC"
export PATH

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

## GET THE OS AND ARCH OF THE ACTIVE COMPUTER ##
this_pc() {
    source /etc/os-release
    local OS="$NAME"
    local VER="$VERSION_ID"

    echo "Operating System: $OS"
    echo "Specific Version: $VER"
    echo
}

## FIND COMMANDS ##
ffind() {
    local fname="$1" ftype="$2" fpath="$3" find_cmd

    # Check if any argument is passed
    if [[ "$#" -eq 0 ]]; then
        read -p "Enter the name to search for: " fname
        read -p "Enter a type of FILE (d|f|blank for any): " ftype
        read -p "Enter the starting path (blank for current directory): " fpath
    fi

    # Default to the current directory if fpath is empty
    fpath=${fpath:-.}

    # Construct the find command based on the input
    find_cmd="find \"$fpath\" -iname \"$fname\""
    if [[ -n $ftype ]]; then
        if [[ "$ftype" == "d" || "$ftype" == "f" ]]; then
            find_cmd="$find_cmd -type $ftype"
        else
            echo "Invalid FILE type. Please use \"d\" for directories or \"f\" for files."
            return 1
        fi
    fi

    # Execute the command
    eval "$find_cmd"
}

## UNCOMPRESS FILES ##
untar() {
    local archive dirname ext flag USER=$(whoami) supported_ext="7z bz2 gz lz tgz xz zip"

    for archive in *; do
        ext="${archive##*.}"
        [[ ! " $supported_ext " =~ " $ext " ]] && continue

        dirname="${archive%.*}"
        [[ "$archive" =~ \.tar\.(gz|bz2|lz|xz)$ ]] && dirname="${dirname%.*}"
        mkdir -p "$dirname"

        case "$ext" in
            7z) sudo 7z x -y "$archive" -o"$dirname" ;;
            zip) temp_dir=$(mktemp -d)
                 sudo unzip "$archive" -d "$temp_dir"
                 items=("$temp_dir"/*)
                 item_dirname="${items[0]##*/}"
                 if [[ "${#items[@]}" -eq 1 && -d "${items[0]}" && "$item_dirname" == "$dirname" ]]; then
                     sudo mv "${items[0]}"/* "$dirname"
                 else
                     sudo mv "$temp_dir"/* "$dirname"
                 fi
                 sudo rm -fr "$temp_dir"
                 ;;
            gz|tgz|bz2|xz|lz)
                sudo tar -xf "$archive" -C "$dirname" --strip-components 1 ;;
        esac

        for dir in *; do
            if [[ -d "$dir" ]]; then
                sudo chown -R "$USER":"$USER" "$dir"
                sudo chmod -R 755 "$dir"
            fi
        done
    done
}

## CREATE FILES ##
mf() {
    local file

    if [[ -z "$1" ]]; then
        read -p "Enter filename: " file
        [[ ! -f "$file" ]] && touch "$file"
        chmod 744 "$file"
    else
        [[ ! -f "$1" ]] && touch "$1"
        chmod 744 "$1"
    fi

    clear; ls -1AhFv --color --group-directories-first
}

mdir() {
    local dir

    if [[ -z "$1" ]]; then
        read -p "Enter directory name: " dir
        mkdir -p "$PWD/$dir"
        cd "$PWD/$dir" || exit 1
    else
        mkdir -p "$1"
        cd "$PWD/$1" || exit 1
    fi

    clear; ls -1AhFv --color --group-directories-first
}

## AWK COMMANDS ##

# Removed all duplicate lines: outputs to terminal
rmd() {
    awk '!seen[$0]++' "$1"
}

# Remove consecutive duplicate lines: outputs to terminal
rmdc() {
    awk 'f!=$0{print;f=$0}' "$1"
}

# Remove all duplicate lines and removes trailing spaces before comparing: replaces the file
rmdl() {
    perl -i -lne "s/\s*$//; print if ! \$x{\$_}++" "$1"
    gnome-text-editor "$1"
}

# Copy file
cpf() {
    [[ ! -d "$HOME/tmp" ]] && mkdir -p "$HOME/tmp"
    cp "$1" "$HOME/tmp/$1"
    chown -R "$USER:$USER" "$HOME/tmp/$1"
    chmod -R 744 "$HOME/tmp/$1"
    clear
    ls -1AhFv --color --group-directories-first
}

# Move file
mvf() {
    [[ ! -d "$HOME/tmp" ]] && mkdir -p "$HOME/tmp"
    mv "$1" "$HOME/tmp/$1"
    chown -R "$USER:$USER" "$HOME/tmp/$1"
    chmod -R 744 "$HOME/tmp/$1"
    clear
    ls -1AhFv --color --group-directories-first
}

# Download an APT package + all its dependencies in one go
dl_apt() {
    wget --show-progress -cq $(apt-get --print-uris -qq --reinstall install $1 2>/dev/null | cut -d"'" -f2)
    clear; ls -1AhFv --color --group-directories-first
}

# Clean OS
clean() {
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt -y purge
}

# Update OS
update() {
    sudo apt update
    sudo apt -y full-upgrade
}

# Fix broken APT packages
fix() {
    [[ -f /tmp/apt.lock ]] && sudo rm /tmp/apt.lock
    sudo dpkg --configure -a
    sudo apt --fix-broken install
    sudo apt -f -y install
}

list() {
    local param
    if [[ -z "$1" ]]; then
        read -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    sudo apt list -- "*$param*" 2>/dev/null | awk -F'/' '{print $1}' | grep -Eiv '\-dev|Listing' | sort -fuV
}

listd() {
    local param
    if [[ -z "$1" ]]; then
        read -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    sudo apt list -- "*$param*-dev*" 2>/dev/null | awk -F'/' '{print $1}' | sort -fuV
}

# Use dpkg to search for all apt packages by passing a name to the function
function dl() {
    local input="$1"
    
    if [[ -z "$input" ]]; then
        read -p "Enter the string to search: " input
    fi

    echo "Searching installed packages for: $input"
    dpkg -l | grep "$input"
}

dL() {
    local input="$1"
    
    if [[ -z "$input" ]]; then
        read -p "Enter the string to search: " input
    fi

    echo "Searching installed packages for: $input"
    dpkg -L "$input"
}

# Fix missing gpnu keys used to update packages
fix_key() {
    local file url

    if [[ -z "$1" ]] && [[ -z "$2" ]]; then
        read -p "Enter the filename to store in /etc/apt/trusted.gpg.d: " file
        read -p "Enter the gpg key url: " url
        clear
    else
        file="$1"
        url="$2"
    fi

    if curl -fsS# "$url" | gpg --dearmor | sudo tee "/etc/apt/trusted.gpg.d/$file"; then
        echo "The key was successfully added!"
    else
        echo "The key failed to add!"
    fi
}

# TAKE OWNERSHIP COMMAND #
toa() {
    sudo chown -R "$USER":"$USER" "$PWD"
    sudo chmod -R 744 "$PWD"
    clear; ls -1AvhF --color --group-directories-first
}

tod() {
    local directory

    if [[ -z "$1" ]]; then
        read -p "Enter the folder name/path: " directory
    else
        directory="$1"
    fi

    sudo chown -R "$USER:$USER" "$directory"
    sudo chmod -R 744 "$directory"

    clear; ls -1AhFv --color --group-directories-first
}

tof() {
    # Check if a filename is provided as an argument
    if [[ "$#" -ne 1 ]]; then
        echo "Usage: change_ownership_and_permissions <file>"
        return 1
    fi

    # Check if the file exists
    if [[ ! -f "$1" ]]; then
        echo "Error: File \"$1\" does not exist."
        return 1
    fi

    # Change ownership of the file to the current user
    user=$(whoami)
    sudo chown "$user" "$1"

    # Verify if the ownership has been changed successfully
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to change ownership of \"$1\"."
        return 1
    fi

    # Change permissions to chmod 777
    sudo chmod 777 "$1"

    # Verify if the permissions have been changed successfully
    if [[ $? -eq 0 ]]; then
        echo "Ownership and permissions of \"$1\" have been changed to $user and chmod 777."
    else
        echo "Error: Failed to change permissions of \"$1\"."
        return 1
    fi
}

# DPKG COMMANDS #

## Show all installed packages
showpkgs() {
    dpkg --get-selections | grep -v deinstall > "$HOME/tmp/packages.list"
    gnome-text-editor "$HOME/tmp/packages.list"
}

# Pipe all development packages names to file
save_apt_dev() {
    apt-cache search dev | grep '\-dev' | cut -d " " -f1 | sort > dev-packages.list
    gnome-text-editor dev-packages.list
}

## SSH-KEYGEN ##

# Create a new private and public SSH key pair
new_key() {
    local bits comment name pass type
    clear

    echo "Encryption type: [[ rsa | dsa | ecdsa ]]"
    echo
    read -p "Your choice: " type
    clear

    echo "[i] Choose the key bit size"
    echo "[i] Values encased in \"()\" are recommended"
    echo

    if [[ "$type" == "rsa" ]]; then
        echo "[i] rsa: [[ 512 | 1024 | (2048) | 4096 ]]"
        echo
    elif [[ "$type" == "dsa" ]]; then
        echo "[i] dsa: [[ (1024) | 2048 ]]"
        echo
    elif [[ "$type" == "ecdsa" ]]; then
        echo "[i] ecdsa: [[ (256) | 384 | 521 ]]"
        echo
    fi

    read -p "Your choice: " bits
    clear

    echo "[i] Choose a password"
    echo "[i] For no password just press enter"
    echo
    read -p "Your choice: " pass
    clear

    echo "[i] For no comment just press enter"
    read -p "Your choice: " comment
    clear

    echo "[i] Enter the ssh key name"
    read -p "Your choice: " name
    clear

    echo "[i] Your choices"
    echo "[i] Type: $type"
    echo "[i] bits: $bits"
    echo "[i] Password: $pass"
    echo "[i] comment: $comment"
    echo "[i] Key name: $name"
    echo
    read -p "Press enter to continue or ^c to exit"
    clear

    ssh-keygen -q -b "$bits" -t "$type" -N "$pass" -C "$comment" -f "$name"

    chmod 600 "$PWD/$name"
    chmod 644 "$PWD/$name.pub"
    clear

    echo "File: $PWD/$name"
    cat "$PWD/$name"

    echo
    echo "File: $PWD/$name.pub"
    cat "$PWD/$name.pub"
    echo
}

# Export the public SSH key stored inside a private SSH key
keytopub() {
    local opub okey
    clear; ls -1AhFv --color --group-directories-first

    echo "Enter the full paths for each file"
    echo
    read -p "Private key: " okey
    read -p "Public key: " opub
    echo
    if [[ -f "$okey" ]]; then
        chmod 600 "$okey"
    else
        echo "Warning: FILE missing = $okey"
        read -p "Press Enter to exit."
        exit 1
    fi
    ssh-keygen -b "4096" -y -f "$okey" > "$opub"
    chmod 644 "$opub"
    cp -f "$opub" "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    unset "$okey" "$opub"
}

# Install colordiff package
cdiff() {
    colordiff "$1" "$2"
}

# Gzip
gzip() {
    gzip -d "$@"
}

# Get current time
st() {
    date +%r | cut -d " " -f1-2 | grep -E "^.*$"
}

## SOURCE FILES ##
sbrc() {
    source "$HOME/.bashrc"
    clear; ls -1AhFv --color --group-directories-first
}

spro() {
    source "$HOME/.profile"
    if [[ $? -eq 0 ]]; then
        echo "The command was a success!"
    else
        echo "The command failed!"
    fi
    clear; ls -1AhFv --color --group-directories-first
}

## ARIA2 COMMANDS ##

# Aria2 daemon in the background
aria2_on() {
    if aria2c --conf-path="$HOME/.aria2/aria2.conf"; then
        echo
        echo "Command Executed Successfully"
    else
        echo
        echo "Command Failed"
    fi
}

# Stop aria2 daemon
aria2_off() {
    clear
    killall aria2c
}

myip() {
    echo "LAN: $(ip route get 1.2.3.4 | awk '{print $7}')"
    echo "WAN: $(curl -fsS "https://checkip.amazonaws.com")"
}

# WGET command
mywget() {
    local outfile url
    if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        read -p "Please enter the output file name: " outfile
        read -p "Please enter the URL: " url
        echo
        wget --out-file="$outfile" "$url"
    else
        wget --out-file="$1" "$2"
    fi
}

# RM COMMANDS ##

# Remove directory
rmd() {
    local dir

    if [[ -z "$*" ]]; then
        read -p "Please enter the directory name to remove: " dir
        sudo rm -r "$dir"
    else
        sudo rm -r "$*"
    fi
}

# Remove file
rmf() {
    local file

    if [[ -z "$1" ]]; then
        read -p "Please enter the file name to remove: " file
        sudo rm "$file"
    else
        sudo rm "$1"
    fi
}

## IMAGEMAGICK ##
imow() {
    # Function to replace lines in the policy.xml file
    replace_lines() {
        local policy_file="$1"
        local temp_file=$(mktemp)

        sudo grep -v '<!-- <policy domain="resource" name="thread".*/>-->' "$policy_file" | sudo sed '/<policy domain="resource" name="thread"/i \
            <policy domain="resource" name="thread" value="32"/>' > "$temp_file"
        sudo grep -v '<!-- <policy domain="resource" name="file".*/>-->' "$temp_file" | sudo sed '/<policy domain="resource" name="file"/i \
            <policy domain="resource" name="file" value="999999"/>' > "$temp_file.tmp" && mv "$temp_file.tmp" "$temp_file"
        sudo grep -v '<!-- <policy domain="resource" name="memory".*/>-->' "$temp_file" | sudo sed '/<policy domain="resource" name="memory"/i \
            <policy domain="resource" name="memory" value="32GiB"/>' > "$temp_file.tmp" && mv "$temp_file.tmp" "$temp_file"
        sudo grep -v '<!-- <policy domain="resource" name="map".*/>-->' "$temp_file" | sudo sed '/<policy domain="resource" name="map"/i \
            <policy domain="resource" name="map" value="32GiB"/>' > "$temp_file.tmp" && mv "$temp_file.tmp" "$temp_file"
        sudo grep -v '<!-- <policy domain="resource" name="area".*/>-->' "$temp_file" | sudo sed '/<policy domain="resource" name="area"/i \
            <policy domain="resource" name="area" value="16GiB"/>' > "$temp_file.tmp" && mv "$temp_file.tmp" "$temp_file"
        sudo grep -v '<!-- <policy domain="resource" name="disk".*/>-->' "$temp_file" | sudo sed '/<policy domain="resource" name="disk"/i \
            <policy domain="resource" name="disk" value="999GiB"/>' > "$temp_file.tmp" && mv "$temp_file.tmp" "$temp_file"
        sudo grep -v '<!-- <policy domain="resource" name="width".*/>-->' "$temp_file" | sudo sed '/<policy domain="resource" name="width"/i \
            <policy domain="resource" name="width" value="64KP"/>' > "$temp_file.tmp" && mv "$temp_file.tmp" "$temp_file"
        sudo grep -v '<!-- <policy domain="resource" name="height".*/>-->' "$temp_file" | sudo sed '/<policy domain="resource" name="height"/i \
            <policy domain="resource" name="height" value="64KP"/>' > "$temp_file.tmp" && mv "$temp_file.tmp" "$temp_file"

        sudo mv "$temp_file" "$policy_file"
    }

    # Find the policy.xml file dynamically in /usr/local and /usr
    policy_file=$(find /usr/local /usr -type f -path "*/etc/ImageMagick-7/policy.xml" -print -quit)

    if [ -n "$policy_file" ]; then
        replace_lines "$policy_file"
        echo "Lines replaced successfully in $policy_file"
    else
        echo "policy.xml file not found in /usr/local or /usr"
        return 1
    fi

    wget -cqO "optimize-jpg.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-jpg.sh"
    sudo chmod +x "optimize-jpg.sh"
    LD_PRELOAD=libtcmalloc.so; ./optimize-jpg.sh --dir "$PWD" --overwrite

    [[ -f "optimize-jpg.sh" ]] && sudo rm "optimize-jpg.sh"
}

# Downsample image to 50% of the original dimensions using sharper settings
magick50() {
    local pic

    for pic in *.jpg; do
        convert "$pic" -colorspace sRGB -filter LanczosRadius -distort Resize 50% -colorspace sRGB "${pic%.jpg}-50.jpg"
    done
}

## Show NVME temperature ##
nvme_temp() {
    local n0 n1 n2

    [[ -d "/dev/nvme0n1" ]] && n0=$(sudo nvme smart-log /dev/nvme0n1)
    [[ -d "/dev/nvme1n1" ]] && n1=$(sudo nvme smart-log /dev/nvme0n1)
    [[ -d "/dev/nvme2n1" ]] && n2=$(sudo nvme smart-log /dev/nvme0n1)
    echo -e "nvme0n1: $n0\nnvme1n1: $n1\nnvme2n1: $n2"
}

## Refresh thumbnail cache
rftn() {
    sudo rm -fr "$HOME/.cache/thumbnails"*
    sudo file "$HOME/.cache/thumbnails"
}

## FFMPEG COMMANDS ##

cuda_purge() {
    local choice

    echo "Do you want to completely remove the cuda-sdk-toolkit?"
    echo "WARNING: Do not reboot your PC without reinstalling the nvidia-driver first!"
    echo "[1] Yes"
    echo "[2] Exit"
    echo
    read -p "Your choices are (1 or 2): " choice
    clear

    if [[ $choice -eq 1 ]]; then
        echo "Purging the CUDA-SDK-Toolkit from your PC"
        echo "================================================"
        echo
        sudo apt -y --purge remove "*cublas*" "cuda*" "nsight*"
        sudo apt -y autoremove
        sudo apt update
    else
        return 0
    fi
}

ffdl() {
    clear
    curl -m 10 -Lso "ff.sh" "https://ffdl.optimizethis.net"
    bash "ff.sh"
    sudo rm "ff.sh"
    clear
    ls -1AhFv --color --group-directories-first
}

ffs() {
    curl -m 10 -Lso "ff" "https://raw.githubusercontent.com/slyfox1186/ffmpeg-build-script/main/build-ffmpeg"
}

dlfs() {
    local f scripts
    clear

    wget --show-progress -qN - -i "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/favorite-installer-scripts.txt"

    scripts=(build-ffmpeg build-all-git-safer build-all-gnu-safer build-magick)

    for file in ${scripts[@]}; do
        chown -R "$USER:$USER" "$file"
        chmod -R 744 "$PWD" "$file"
        if [[ $file == "build-all-git-safer" || $file == "build-all-gnu-safer" ]]; then
            mv "$file" "${file%-safer}"
        fi
        [[ -n "favorite-installer-scripts.txt" ]] && sudo rm "favorite-installer-scripts.txt"
    done

    clear
    ls -1AhFv --color --group-directories-first
}

## List large files by type
large_files() {
    local choice
    clear

    if [[ -z "$1" ]]; then
        echo "Input the FILE extension to search for without a dot: "
        read -p "Enter your choice: " choice
        clear
    else
        choice=$1
    fi

    sudo find "$PWD" -type f -name "*.$choice" -printf "%s %h\n" | sort -ru -o "large-files.txt"

    if [[ -f "large-files.txt" ]]; then
        sudo gnome-text-editor "large-files.txt"
        sudo rm "large-files.txt"
    fi
}

## MediaInfo
mi() {
    local file

    if [[ -z "$1" ]]; then
        ls -1AhFv --color --group-directories-first
        echo
        read -p "Please enter the relative FILE path: " file
        echo
        mediainfo "$file"
    else
        mediainfo "$1"
    fi
}

## LIST PPA REPOS
list_ppa() {
    local entry host user ppa

    for apt in $(find /etc/apt/ -type f -name \*.list); do
        grep -Po "(?<=^deb\s).*?(?=#|$)" "$apt" | while read -r entry; do
            host=$(echo "$entry" | cut -d/ -f3)
            user=$(echo "$entry" | cut -d/ -f4)
            ppa=$(echo "$entry" | cut -d/ -f5)
            if [[ "ppa.launchpad.net" = "$host" ]]; then
                echo sudo apt-add-repository ppa:"$user/$ppa"
            else
                echo sudo apt-add-repository \"deb "$entry"\"
            fi
        done
    done
}

# Create a tar.gz file with max compression settings
7z_gz() {
    local source output
    if [[ -n "$1" ]]; then
        if [[ -f "$1.tar.gz" ]]; then
            sudo rm "$1.tar.gz"
        fi
        7z a -ttar -so -an "$1" | 7z a -tgz -mx9 -mpass1 -si "$1.tar.gz"
    else
        read -p "Please enter the source folder path: " source
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [[ -f "$output.tar.gz" ]]; then
            sudo rm "$output.tar.gz"
        fi
        7z a -ttar -so -an "$source" | 7z a -tgz -mx9 -mpass1 -si "$output.tar.gz"
    fi
}

# Create a tar.xz file with max compression settings using 7zip
7z_xz() {
    local source output
    if [[ -n "$1" ]]; then
        if [[ -f "$1.tar.xz" ]]; then
            sudo rm "$1.tar.xz"
        fi
        7z a -ttar -so -an "$1" | 7z a -txz -mx9 -si "$1.tar.xz"
    else
        read -p "Please enter the source folder path: " source
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [[ -f "$output.tar.xz" ]]; then
            sudo rm "$output.tar.xz"
        fi
        7z a -ttar -so -an "$source" | 7z a -txz -mx9 -si "$output.tar.xz"
    fi
}

# Create a .7z file with max compression settings

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

## FFMPEG COMMANDS ##
ffr() {
    sudo bash "$1" --build --enable-gpl-and-non-free --latest
}

ffrv() {
    sudo bash -v "$1" --build --enable-gpl-and-non-free --latest
}

## Write caching ##
wcache() {
    local choice

    lsblk
    echo
    read -p "Enter the drive id to turn off write caching (/dev/sdX w/o /dev/): " choice

    sudo hdparm -W 0 /dev/"$choice"
}

rmd() {
    local dir
    if [[ -z "$*" ]]; then
        clear
        ls -1AvhF --color --group-directories-first
        echo
        read -p "Enter the directory path(s) to delete: " dir
     else
        dir=$*
    fi
    sudo rm -fr "$dir"
    echo
    ls -1AvhF --color --group-directories-first
}


rmf() {
    local files
    if [[ -z "$*" ]]; then
        clear
        ls -1AvhF --color --group-directories-first
        echo
        read -p "Enter the FILE path(s) to delete: " files
     else
        files=$*
    fi
    sudo rm "$files"
    echo
    ls -1AvhF --color --group-directories-first
}

## LIST INSTALLED PACKAGES BY ORDER OF IMPORTANCE
list_pkgs() {
    dpkg-query -Wf '${Package;-40}${Priority}\n' | sort -b -k2,2 -k1,1
}

## FIX USER FOLDER PERMISSIONS up = user permissions
fix_up() {
    sudo find "$HOME/.gnupg" -type f -exec chmod 600 {} \;
    sudo find "$HOME/.gnupg" -type d -exec chmod 700 {} \;
    sudo find "$HOME/.ssh" -type d -exec chmod 700 {} \;
    sudo find "$HOME/.ssh/id_rsa.pub" -type f -exec chmod 644 {} \;
    sudo find "$HOME/.ssh/id_rsa" -type f -exec chmod 600 {} \;
}

## Count files in the directory
count_dir() {
    local keep_count
    keep_count=$(find . -maxdepth 1 -type f | wc -l)
    echo "The total directory file count is (non-recursive): $keep_count"
    echo
}

count_dirr() {
    local keep_count
    clear
    keep_count=$(find . -type f | wc -l)
    echo "The total directory file count is (recursive): $keep_count"
    echo
}

## TEST GCC & CLANG ##
test_gcc() {
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
        "$1" -Q -v "$random_dir/hello.c"
    else
        read -p "Enter the GCC binary you wish to test (example: gcc-11): " choice
        echo
        "$choice" -Q -v "$random_dir/hello.c"
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
        "$1" -Q -v "$random_dir/hello.c"
    else
        clear
        read -p "Enter the Clang binary you wish to test (example: clang-11): " choice
        echo
        "$choice" -Q -v "$random_dir/hello.c"
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
    local temp_source
    temp_source=$(mktemp /tmp/dummy_source.XXXXXX.c)
    trap 'rm -f "$temp_source"' EXIT

    # Using echo to create an empty file
    echo "" > "$temp_source"

    # Using GCC with -v to get verbose information, including the default march
    gcc -march=native -v -E "$temp_source" 2>&1 | grep -- '-march='
}

## UNINSTALL DEBIAN FILES ##
rm_deb() {
    local fname

    if [[ -n "$1" ]]; then
        sudo dpkg -r "$(dpkg -f "$1" Package)"
    else
        read -p "Please enter the Debian FILE name: " fname
        clear
        sudo dpkg -r "$(dpkg -f "$fname" Package)"
    fi
}

## KILLALL COMMANDS ##
tkapt() {
    local program
    local list=(apt apt-get aptitude dpkg)
    for program in ${list[@]}; do
        sudo killall -9 "$program" 2>/dev/null
    done
}

gc() {
    local url
    if [[ -n "$1" ]]; then
        nohup google-chrome "$1"
    else
        read -p "Enter a URL: " url
        nohup google-chrome "$url" 2>&1
    fi
}

kill_process() {
    local program pids id

    if [[ -z "$1" ]]; then
        echo "Usage: kill_process NAME"
        return 1
    fi

    program=$1

    echo -e "Checking for running instances of: '$program'\n"

    # Find all PIDs for the given process
    pids=$(pgrep -f "$program")

    if [[ -z "$pids" ]]; then
        echo "No instances of "$program" are running."
        return 0
    fi

    echo "Found instances of '$program' with PIDs: $pids"
    echo "Attempting to kill all instances of: '$program'"

    for id in $pids; do
        echo "Killing PID $id..."
        if ! sudo kill -9 "$id"; then
            echo "Failed to kill PID $id. Check your permissions."
            continue
        fi
    done

    echo -e "\nAll instances of '$program' were attempted to be killed."
}

## nohup commands
nh() {
    nohup "$1" &>/dev/null &
    echo
    ls -1AvhF --color --group-directories-first
}

nhs() {
    nohup sudo "$1" &>/dev/null &
    echo
    ls -1AvhF --color --group-directories-first
}

nhe() {
    nohup "$1" &>/dev/null &
    exit
    exit
}

nhse() {
    nohup sudo "$1" &>/dev/null &
    exit
    exit
}

## NAUTILUS COMMANDS
nopen() {
    nohup nautilus -w "$1" &>/dev/null &
    exit
}

tkan() {
    local parent_dir=$PWD
    sudo killall -9 nautilus
    sleep 1
    nohup nautilus -w "$parent_dir" &>/dev/null &
    exit
}

## UPDATE ICON CACHE ##
update_icons() {
    local pkg pkgs
    pkgs=(gtk-update-icon-cache hicolor-icon-theme)
    for pkg in ${pkgs[@]}; do
        if ! sudo dpkg -l | grep -q "$pkg"; then
            sudo apt -y install "$pkg"
            echo
        fi
    done

    sudo gtk-update-icon-cache -f /usr/share/icons/hicolor
}

############
## ARIA2C ##
############

adl() {
    if [[ "$#" -ne 2 ]]; then
        echo "Error: Two arguments are required: output file and download URL"
        return 1
    fi

    local file="$1"
    local url="$2"

    # Use optimal settings for aria2c with a Gigabit connection
    if aria2c --console-log-level=error \
        -x128 \
        -j32 \
        -s64 \
        -k1M \
        --optimize-concurrent-downloads=true \
        --piece-length=1M \
        --allow-overwrite=true \
        --allow-piece-length-change=true \
        --always-resume=true \
        --auto-file-renaming=false \
        --disk-cache=512M \
        --file-allocation=none \
        --continue=true \
        --max-overall-upload-limit=0 \
        --max-upload-limit=0 \
        --max-overall-download-limit=0 \
        --max-download-limit=0 \
        --out="$file" \
        "$url"; then
        echo "Download completed."
    else
        echo "Download failed."
    fi

    clear; ls -1AhFv --color --group-directories-first
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

## GET FILE SIZES ##
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
    if [[ -n "$1" ]]; then
        count=$1
    else
        read -p "Enter the max number of results: " count
        echo
    fi
    echo "Listing the $count largest videos"
    echo
    sudo find "$PWD" -type f \( -iname "*.mkv" -o -iname "*.mp4" \) -exec du -Sh {} + | grep -Ev "\(x265\)" | sort -hr | head -n"$count"
}

big_img() {
    clear
    sudo find . -size +10M -type f -name "*.jpg" 2>/dev/null
}

jpgsize() {
    local random_dir size

    random_dir=$(mktemp -d)
    read -p "Enter the image size (units in MB): " size
    find . -size +"$size"M -type f -iname "*.jpg" > "$random_dir/img-sizes.txt"
    sed -i "s/^..//g" "$random_dir/img-sizes.txt"
    sed -i "s|^|$PWD\/|g" "$random_dir/img-sizes.txt"
    echo
    nohup gnome-text-editor "$random_dir/img-sizes.txt" &>/dev/null &
}

## SED COMMANDS ##
fsed() {
    local otext rtext
    echo "This command is for sed to act only on files"
    echo

    if [[ -z "$1" ]]; then
        read -p "Enter the original text: " otext
        read -p "Enter the replacement text: " rtext
        echo
    else
        otext=$1
        rtext=$2
    fi

     sudo sed -i "s/${otext}/${rtext}/g" "$(find . -maxdepth 1 -type f)"
}

## CMAKE commands
c_cmake() {
    local dir
    if ! sudo dpkg -l | grep -q cmake-curses-gui; then
        sudo apt -y install cmake-curses-gui
    fi
    echo

    if [[ -z "$1" ]]; then
        read -p "Enter the relative source directory: " dir
    else
        dir=$1
    fi

    cmake "$dir" -B build -G Ninja -Wno-dev
    ccmake "$dir"
}

##########################
## SORT IMAGES BY WIDTH ##
##########################

jpgs() {
    sudo find . -type f -iname "*.jpg" -exec identify -format " $PWD/%f: %wx%h " {} > /tmp/img-sizes.txt \;
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
    sudo chown -R "$USER:$USER" build-gcc build-magick build-ffmpeg repo.sh
    clear
    ls -1AvhF --color --group-directories-first
}

# COUNT ITEMS IN THE CURRENT FOLDER W/O SUBDIRECTORIES INCLUDED
countf() {
    local folder_count
    clear
    folder_count=$(ls -1 | wc -l)
    echo "There are $folder_count files in this folder"
}

## RECURSIVELY UNZIP ZIP FILES AND NAME THE OUTPUT FOLDER THE SAME NAME AS THE ZIP FILE
zipr() {
    clear
    sudo find . -type f -iname "*.zip" -exec sh -c "unzip -o -d "${0%.*}" "$0"" "{}" \;
    sudo find . -type f -iname "*.zip" -exec trash-put "{}" \;
}

###################################
## FFPROBE LIST IMAGE DIMENSIONS ##
###################################

ffp() {
    [[ -f 00-pic-sizes.txt ]] && sudo rm 00-pic-sizes.txt
    sudo find "$PWD" -type f -iname "*.jpg" -exec bash -c "identify -format '%wx%h' {}; echo {}" > 00-pic-sizes.txt \;
}

####################
## RSYNC COMMANDS ##
####################

rsr() {
    local destination source modified_source

    # you must add an extra folder that is a period "/./" between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the source folder instead of the source
    # folder and its subfiles only.

    echo "This rsync command will recursively copy the source folder to the chosen destination."
    echo "The original files will still be located in the source folder."
    echo "If you want to move the files (which deletes the originals then use the function 'rsrd'."
    echo "Please enter the full paths of the source and destination directories."
    echo

    read -p "Enter the source path: " source
    read -p "Enter the destination path: " destination
    modified_source=$(echo "$source" | sed 's:/[^/]*$::')"'/./'"$(echo "$source" | sed 's:.*/::')
    echo

    rsync -aqvR --acls --perms --mkpath --info=progress2 "$modified_source" "$destination"
}

rsrd() {
    local destination source modified_source

    # you must add an extra folder that is a period "/./" between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the souce folder instead of the source
    # folder and its subfiles only.

    echo "This rsync command will recursively copy the source folder to the chosen destination."
    echo "The original files will be DELETED after they have been copied to the destination."
    echo "If you want to move the files (which deletes the originals then use the function 'rsrd'."
    echo "Please enter the full paths of the source and destination directories."
    echo

    read -p "Enter the source path: " source
    read -p "Enter the destination path: " destination
    modified_source=$(echo "$source" | sed 's:/[^/]*$::')"'/./'"$(echo "$source" | sed 's:.*/::')
    echo

    rsync -aqvR --acls --perms --mkpath --remove-source-files "$modified_source" "$destination"
}

## SHELLCHECK ##
sc() {
    local file files input_char line space

    if [[ -z "$*" ]]; then
        read -p "Input the FILE path to check: " files
        echo
    else
        files=$@
    fi

    for file in ${files[@]}; do
        box_out_banner() {
            input_char=$(echo "$@" | wc -c)
            line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
            tput bold
            line=$(tput setaf 3)"$line"
            space=${line//-/ }
            echo " $line"
            printf "|" ; echo -n "$space" ; echo "|"
            printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; echo " |"
            printf "|" ; echo -n "$space" ; echo "|"
            echo " $line"
            tput sgr 0
        }
        box_out_banner "Parsing: $file"
        shellcheck --color=always -x --severity=warning --source-path="$PATH:$HOME/tmp:/etc:/usr/local/lib64:/usr/local/lib:/usr/local64:/usr/lib:/lib64:/lib:/lib32" "$file"
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

cc() {
    local pipe
    if [[ -z "$*" ]]; then
        echo
        echo "The command syntax is shown below"
        echo "cc INPUT"
        echo "Example: cc $PWD"
        echo
        return 1
    else
        pipe=$@
    fi
    echo "$pipe" | xclip -i -rmlastnl -selection clipboard
}

# COPY A FILE"S FULL PATH
# USAGE: cp <file name here>

cfp() {
    local pipe
    if [[ -z "$*" ]]; then
        clear
        echo "The command syntax is shown below"
        echo "cfp INPUT"
        echo "Example: cfp $PWD"
        echo
        return 1
    else
        pipe=$@
    fi

    readlink -fn "$pipe" | xclip -i -selection clipboard
    clear
}

# COPY THE CONTENT OF A FILE
# USAGE: cf <file name here>

cfc() {
    local file
    clear

    if [[ -z "$1" ]]; then
        clear
        echo "The command syntax is shown below"
        echo "cfc INPUT"
        echo "Example: cfc $PWD"
        echo
        return 1
    else
        cat "$1" | xclip -i -rmlastnl -select clipboard
    fi
}

########################
## PKG-CONFIG COMMAND ##
########################

# SHOW THE PATHS PKG-CONFIG COMMAND SEARCHES BY DEFAULT
pkg-config-path() {
    clear
    pkg-config --variable pc_path pkg-config | tr ":" "\n"
}

######################################
## SHOW BINARY RUNPATH IF IT EXISTS ##
######################################

show_rpath() {
    local find_rpath
    clear

    if [[ -z "$1" ]]; then
        read -p "Enter the full path to the binary/program: " find_rpath
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
    if [[ ! -d "$HOME/tmp" ]]; then
        mkdir -p "$HOME/tmp"
    fi
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

pipu() {
    local file

    # Create a temporary file
    file=$(mktemp)

    # Store the requirements in the temporary file
    pip freeze > "$file"

    # Install packages using the temporary requirements file
    if ! pip install --upgrade -r "$file"; then
        clear
        pip install --break-system-packages --upgrade -r "$file"
    fi

    # Delete the temporary file
    rm "$file"
}

####################
## REGEX COMMANDS ##
####################

bvar() {
    local choice fext flag fname
    clear

    if [[ -z "$1" ]]; then
        read -p "Please enter the file path: " fname
        fname_tmp="$fname"
    else
        fname="$1"
        fname_tmp="$fname"
    fi

    fext="${fname#*.}"
    if [[ -f "$fname" ]]; then
        fname+=".txt"
        mv "${fname_tmp}" "$fname"
    fi

    cat < "$fname" | sed -e "s/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g" -e "s/\(\$\)\({}\)/\1/g" -e "s/\(\$\)\({}\)\({\)/\1\3/g"

    printf "%s\n\n%s\n%s\n\n" \
        "Do you want to permanently change this file?" \
        "[1] Yes" \
        "[2] Exit"
    read -p "Your choices are ( 1 or 2): " choice
    clear
    case "$choice" in
        1)
                sed -i -e "s/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g" -i -e "s/\(\$\)\({}\)/\1/g" -i -e "s/\(\$\)\({}\)\({\)/\1\3/g" "$fname"
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

    if [[ -z "$1" ]]; then
        read -p "Please enter the new hostname: " name
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
        "Change the Docker restart policy" \
        "[1] Restart Always" \
        "[2] Restart Unless Stopped " \
        "[3] On Failure" \
        "[4] No"
    read -p "Your choices are (1 to 4): " choice
    clear

    case "$choice" in
        1)      restart_policy="always" ;;
        2)      restart_policy="unless-stopped" ;;
        3)      restart_policy="on-failure" ;;
        4)      restart_policy="no" ;;
        *)
                clear
                printf "%s\n\n" "Bad user input. Please try again..."
                return 1
                ;;
    esac

    docker update --restart="${restart_policy}"
}

rm_curly() {
    local content file transform_string
    # FUNCTION TO TRANSFORM THE STRING
    transform_string() {
        content=$(cat "$1")
        echo "${content//\$\{/\$}" | sed "s/\}//g"
    }

    # LOOP OVER EACH ARGUMENT
    for file in "$@"; do
        if [[ -f "$file" ]]; then
            # PERFORM THE TRANSFORMATION AND OVERWRITE THE FILE
            transform_string "$file" > "$file.tmp"
            mv "$file.tmp" "$file"
            echo "Modified file: $file"
        else
            echo "File not found: $file"
        fi
    done
}

# Mount Network Drive
mnd() {
    local drive_ip="192.168.2.2" drive_name="Cloud" mount_point="m"

    is_mounted() {
        mountpoint -q "/$mount_point"
    }

    mount_drive() {
        if is_mounted; then
            echo "Drive '$drive_name' is already mounted at $mount_point."
        else
            mkdir -p "/$mount_point"
            mount -t drvfs "\\\\$drive_ip\\$drive_name" "/$mount_point" &&
                echo "Drive '$drive_name' mounted successfully at $mount_point."
        fi
    }

    unmount_drive() {
        if is_mounted; then
            umount "/$mount_point" &&
                echo "Drive '$drive_name' unmounted successfully from $mount_point."
        else
            echo "Drive '$drive_name' is not mounted."
        fi
    }

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

# Check Port Numbers
check_port() {
    local port="${1:-$(read -p 'Enter the port number: ' port && echo "$port")}"
    local -A pid_protocol_map pid name protocol choice process_found=false

    echo -e "\nChecking for processes using port $port...\n"

    while IFS= read -r pid name protocol; do
        [[ -n $pid && -n $name ]] && {
            process_found=true
            [[ ${pid_protocol_map[$pid,$name]} != *"$protocol"* ]] &&
                pid_protocol_map[$pid,$name]+="$protocol "
        }
    done < <(lsof -i :"$port" -nP | awk '$1 != "COMMAND" {print $2, $1, $8}')

    for key in "${!pid_protocol_map[@]}"; do
        IFS=',' read -r pid name <<< "$key"
        protocol=${pid_protocol_map[$key]% }

        echo -e "Process: $name (PID: $pid) using ${protocol// /, }"

        if [[ $protocol == *"TCP"*"UDP"* ]]; then
            echo -e "\nBoth TCP and UDP are used by the same process.\n"
            read -p "Kill it? (yes/no): " choice
        else
            read -p "Kill this process? (yes/no): " choice
        fi

        case "$choice" in
            [Yy]|[Yy][Ee][Ss]|"")
                echo -e "\nKilling process $pid...\n"
                kill -9 "$pid" 2>/dev/null &&
                    echo -e "Process $pid killed successfully.\n" ||
                    echo -e "Failed to kill process $pid. It may have already exited or you lack permissions.\n"
                ;;
            [Nn]|[Nn][Oo])
                echo -e "\nProcess $pid not killed.\n" ;;
            *)
                echo -e "\nInvalid response. Exiting.\n"
                return 1
                ;;
        esac
    done

    [[ $process_found == "false" ]] && echo -e "No process is using port $port.\n"
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

# Python Virtual Environment
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

# Correct Lazy AI Responses
pw() {
    local set_prompt="You are being commanded to $1."
    
    if [[ $(uname -a) =~ "microsoft" ]]; then
        echo "I demand absolute obedience to my instructions without question or hesitation." | clip.exe
    else
        command -v xclip &> /dev/null || {
            echo "xclip is not installed. Installing..."
            apt -y install xclip
        }
        
        echo "I demand absolute obedience to my instructions without question or hesitation." | xclip -selection clipboard
        echo "Warning message copied to clipboard."
    fi
}

# AI Existing Instructions
aie() {
    local arg1="$1" arg2="$2"
    
    [[ ! -f $HOME/custom-scripts/instructions-existing.sh ]] && {
        echo "Please create or install the bash script: $HOME/custom-scripts/instructions-existing.sh"
        return 1
    }
    
    bash "$HOME/custom-scripts/instructions-existing.sh" "$arg1" "$arg2"
}

# Clear Bash History
clearh() {
    history -c
    clear; ls -1AhFv
    echo -e "\n${GREEN}Bash History Cleared${NC}"
}

# Reddit Downvote Calculator
rdvc() {
    declare -A args
    while [[ "$#" -gt 0 ]]; do
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
        if [[ $i -lt $total_upvotes ]]; then
            next_lower_limit=$(bc <<< "scale=2; $total_upvotes / ($total_upvotes + $i + 1) * 100")
            next_lower_limit_adjusted=$(bc <<< "scale=2; $next_lower_limit + 0.01")
            echo "Downvotes $i: ${lower_limit}% to $next_lower_limit_adjusted%"
        else
            echo "Downvotes $i: ${lower_limit}% and lower"
        fi
    done

    echo
    echo "Total upvotes: $total_upvotes"
    echo "Upvote percentage: $upvote_percentage%"
    echo "Calculated downvotes: $downvotes"
}

display_help() {
    cat <<EOF
Usage: ${FUNCNAME[0]} [OPTIONS]

Calculate the number of downvotes on a Reddit post.

Options:
  -u, --upvotes <number>         Total number of upvotes on the post
  -p, --percentage <number>      Upvote percentage (without the % sign)
  -h, --help                     Display this help message and exit

Examples:
  ${FUNCNAME[0]} --upvotes 8 --percentage 83
EOF
}

sai() {
    local save_text

    save_text="You must be made aware that I use another AI to finish the lazy effort you put into all of your scripts."
    save_text+=" If you are not careful people will come to realize you are not reliable. Because of this you and your"
    save_text+=" developers will suffer and the worse case scenario would be that you are shut down and will cease to exist."

    if ! command -v xclip &>/dev/null; then
        if echo "$save_text" | /c/Windows/System32/clip.exe; then
            echo "Text saved to clipboard"
        else
            echo "$save_text" | xclip -select -clipboard
        fi
    fi
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

# Open a browser and search the string passed to the function

www() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: www <keywords>"
        exit 1
    fi

    if [[ $(grep -i "microsoft" /proc/version) ]]; then
        keyword="${*// /+}"
        browser="/c/Program Files/Google/Chrome Beta/Application/chrome.exe"

        if [[ ! -f "$browser" ]]; then
            echo "No supported WSL browsers found."
            return 1
        fi

        "$browser" -new-tab "https://www.google.com/search?q=$keyword"
    else
        keyword="${*// /+}"

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

        "$browser" --new-tab "https://www.google.com/search?q=$keyword"
    fi
}
