#!/usr/bin/env bash
# APT and DPKG Package Management Functions

# Download an APT package + all its dependencies in one go
dl_apt() {
    local -a urls

    if [[ -z "${1-}" ]]; then
        printf 'Usage: dl_apt PACKAGE\n' >&2
        return 1
    fi

    mapfile -t urls < <(apt-get --print-uris -qq --reinstall install "$1" 2>/dev/null | cut -d"'" -f2)
    ((${#urls[@]} > 0)) || return 1
    wget --show-progress -cq -- "${urls[@]}"
    clear; ls -1AhFv --color --group-directories-first
}

# Clean OS
clean() {
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt -y purge
}

# Update OS, then confirm the upgrade did not leave the box in a state that only
# breaks at the next boot. apt exits 0 for both failures that `health` guards.
update() {
    if ! sudo apt update; then
        echo
        echo -e "${YELLOW}Note: 'apt update' reported an error above (usually one unreachable repo).${NC}"
        echo -e "${YELLOW}Package lists may be stale, so a new version could be missed.${NC}"
        echo -e "${YELLOW}Upgrading anyway from the lists already on disk.${NC}"
        echo
    fi
    sudo apt -y full-upgrade
    echo
    health
}

# Post-upgrade sanity check. Safe to run on its own at any time. Catches:
#   - new kernels that get installed but never actually booted
#   - an NVIDIA userspace upgrade that leaves no matching kernel module behind,
#     which kills the GPU at the next boot without apt reporting anything
health() {
    local running newest rc=0
    local -a kernels
    running=$(uname -r)

    # Glob instead of `ls`: the interactive `ls` alias carries -F, which appends
    # a trailing slash to the directory name so it never matches `uname -r`.
    # `command` for the same reason - aliases expand inside function bodies.
    kernels=(/lib/modules/*/)
    kernels=("${kernels[@]%/}")
    kernels=("${kernels[@]##*/}")
    if [[ ${kernels[0]} == "*" ]]; then
        newest=$running
    else
        newest=$(printf '%s\n' "${kernels[@]}" | sort -V | tail -n1)
    fi

    if ! command dpkg -s linux-generic &>/dev/null; then
        echo -e "${RED}Kernel: linux-generic is not installed - no new kernels will arrive.${NC}"
        echo "  Fix: sudo apt -y install linux-generic"
        rc=1
    elif [[ $running != "$newest" ]]; then
        echo -e "${YELLOW}Kernel: running $running but $newest is installed. Reboot to use it.${NC}"
        rc=1
    fi

    if command grep -qs 0x10de /sys/bus/pci/devices/*/vendor; then
        if ! compgen -G "/lib/modules/$newest/updates/dkms/nvidia.ko*" > /dev/null; then
            echo -e "${RED}GPU: no NVIDIA kernel module built for $newest.${NC}"
            echo "  Fix: sudo apt -y install nvidia-open && sudo reboot"
            rc=1
        elif ! nvidia-smi &> /dev/null; then
            echo -e "${YELLOW}GPU: NVIDIA module built but not loaded. Reboot to activate it.${NC}"
            rc=1
        fi
    fi

    ((rc)) || echo -e "${GREEN}OK: running newest kernel ($running); nothing needs attention.${NC}"
    return $rc
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
        read -r -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    sudo apt list -- "*$param*" 2>/dev/null | awk -F'/' '{print $1}' | grep -Eiv '\-dev|Listing' | sort -fuV
}

listd() {
    local param
    if [[ -z "$1" ]]; then
        read -r -p "Enter the string to search: " param
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
        read -r -p "Enter the string to search: " input
    fi

    echo "Searching installed packages for: $input"
    dpkg -l | grep "$input"
}

dL() {
    local input="$1"

    if [[ -z "$input" ]]; then
        read -r -p "Enter the string to search: " input
    fi

    echo "Searching installed packages for: $input"
    dpkg -L "$input"
}

# Fix missing gpnu keys used to update packages
fix_key() {
    local file url

    if [[ -z "$1" ]] && [[ -z "$2" ]]; then
        read -r -p "Enter the filename to store in /etc/apt/trusted.gpg.d: " file
        read -r -p "Enter the gpg key url: " url
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

## LIST PPA REPOS
list_ppa() {
    local apt entry host user ppa

    while IFS= read -r -d '' apt; do
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
    done < <(find /etc/apt/ -type f -name '*.list' -print0)
}

## LIST INSTALLED PACKAGES BY ORDER OF IMPORTANCE
list_pkgs() {
    dpkg-query -Wf '${Package;-40}${Priority}\n' | sort -b -k2,2 -k1,1
}

## UNINSTALL DEBIAN FILES ##
rm_deb() {
    local fname

    if [[ -n "$1" ]]; then
        sudo dpkg -r "$(dpkg -f "$1" Package)"
    else
        read -r -p "Please enter the Debian FILE name: " fname
        clear
        sudo dpkg -r "$(dpkg -f "$fname" Package)"
    fi
}

## KILLALL COMMANDS ##
tkapt() {
    local program
    local list=(apt apt-get aptitude dpkg)
    for program in "${list[@]}"; do
        sudo killall -9 "$program" 2>/dev/null
    done
}

## CUDA TOOLKIT ##
cuda_purge() {
    local choice

    echo "Do you want to completely remove the cuda-sdk-toolkit?"
    echo "WARNING: Do not reboot your PC without reinstalling the nvidia-driver first!"
    echo "[1] Yes"
    echo "[2] Exit"
    echo
    read -r -p "Your choices are (1 or 2): " choice
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
