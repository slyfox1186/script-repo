#!/usr/bin/env bash
# APT and DPKG Package Management Functions

# Usage: dl_apt PACKAGE
# Downloads PACKAGE and its complete dependency closure into ./PACKAGE-debs, for installing on
# a machine without network access. Resolving against an empty dpkg status makes APT include
# dependencies that are already installed here.
dl_apt() {
    local package="${1-}" empty_status target
    local -a urls

    if [[ -z "$package" ]]; then
        printf 'Usage: dl_apt PACKAGE\n' >&2
        return 1
    fi

    empty_status=$(mktemp) || return
    mapfile -t urls < <(apt-get -o Dir::State::status="$empty_status" --print-uris -qq install -- "$package" | cut -d"'" -f2)
    rm -f -- "$empty_status"
    if ((${#urls[@]} == 0)); then
        printf 'APT found nothing to download for: %s\n' "$package" >&2
        return 1
    fi

    target="$PWD/$package-debs"
    mkdir -p -- "$target" || return
    wget --show-progress -cq -P "$target" -- "${urls[@]}" || return
    printf '%d package files saved in %s\n' "${#urls[@]}" "$target"
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

    # A glob lists kernel directories without depending on `ls` formatting.
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
        # DKMS builds land in updates/dkms; Ubuntu's prebuilt signed modules live under kernel/.
        if [[ -z $(find "/lib/modules/$newest" -name 'nvidia.ko*' -print -quit 2>/dev/null) ]]; then
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
    local retry_configuration=false

    # Missing dependencies can prevent configuration until APT repairs them.
    if ! sudo dpkg --configure -a; then
        retry_configuration=true
        printf 'Package configuration failed; attempting dependency repair.\n' >&2
    fi
    sudo apt --fix-broken -y install || return
    if [[ "$retry_configuration" == true ]]; then
        sudo dpkg --configure -a || return
    fi
}

list() {
    local param
    if [[ -z "$1" ]]; then
        read -r -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    apt list -- "*$param*" 2>/dev/null | awk -F'/' '{print $1}' | grep -Eiv '\-dev|Listing' | sort -fuV
}

listd() {
    local param
    if [[ -z "$1" ]]; then
        read -r -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    apt list -- "*$param*-dev*" 2>/dev/null | awk -F'/' '{print $1}' | sort -fuV
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

# Usage: fix_key NAME.gpg URL
# Installs a repository signing key as /etc/apt/keyrings/NAME.gpg. Reference it from that
# repository's entry with signed-by, so APT trusts the key for that repository only.
fix_key() {
    local file="${1-}" url="${2-}" downloaded key

    if (($# == 0)); then
        read -r -p "Enter the key file name (ending in .gpg): " file || return 1
        read -r -p "Enter the gpg key url: " url || return 1
        echo
    fi
    if [[ ! "$file" =~ ^[A-Za-z0-9._-]+\.gpg$ ]]; then
        printf 'The key file name must be a plain name ending in .gpg: %s\n' "$file" >&2
        return 1
    fi
    if [[ ! "$url" =~ ^https?:// ]]; then
        printf 'The key URL must start with http:// or https://: %s\n' "$url" >&2
        return 1
    fi

    downloaded=$(mktemp) || return
    key=$(mktemp) || { rm -f -- "$downloaded"; return 1; }
    if ! curl -fsSL "$url" -o "$downloaded" || [[ ! -s "$downloaded" ]]; then
        printf 'The key download failed or was empty: %s\n' "$url" >&2
        rm -f -- "$downloaded" "$key"
        return 1
    fi
    if grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$downloaded"; then
        gpg --dearmor < "$downloaded" > "$key"
    else
        cp -- "$downloaded" "$key"
    fi
    if ! gpg --show-keys -- "$key" > /dev/null 2>&1; then
        printf 'The download is not a valid OpenPGP key: %s\n' "$url" >&2
        rm -f -- "$downloaded" "$key"
        return 1
    fi
    if ! sudo install -D -m 644 -o root -g root -- "$key" "/etc/apt/keyrings/$file"; then
        rm -f -- "$downloaded" "$key"
        return 1
    fi
    rm -f -- "$downloaded" "$key"
    printf 'Installed /etc/apt/keyrings/%s\n' "$file"
    printf 'Add signed-by=/etc/apt/keyrings/%s to the matching repository entry.\n' "$file"
}

# DPKG COMMANDS #

## Show all installed packages
showpkgs() {
    mkdir -p -- "$HOME/tmp" || return
    dpkg --get-selections | grep -v deinstall > "$HOME/tmp/packages.list"
    gnome-text-editor "$HOME/tmp/packages.list"
}

# Pipe all development packages names to file
save_apt_dev() {
    apt-cache search dev | grep '\-dev' | cut -d " " -f1 | sort > dev-packages.list
    gnome-text-editor dev-packages.list
}

## LIST PPA REPOS
# Prints an add-apt-repository command for every enabled binary repository, read from both
# one-line .list files and deb822 .sources files.
list_ppa() {
    local comps file host ppa suite uri user

    {
        for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
            [[ -f "$file" ]] || continue
            sed -nE 's/^[[:space:]]*deb[[:space:]]+(\[[^]]*\][[:space:]]+)?([^#]*[^#[:space:]]).*/\2/p' -- "$file"
        done
        for file in /etc/apt/sources.list.d/*.sources; do
            [[ -f "$file" ]] || continue
            gawk 'BEGIN { RS = "" }
            {
                types = uris = suites = comps = ""
                enabled = 1
                count = split($0, lines, "\n")
                for (i = 1; i <= count; i++) {
                    line = lines[i]
                    if (line ~ /^[ \t#]/ || index(line, ":") == 0) continue
                    key = tolower(substr(line, 1, index(line, ":") - 1))
                    value = substr(line, index(line, ":") + 1)
                    gsub(/^[ \t]+|[ \t]+$/, "", value)
                    if (key == "types") types = value
                    else if (key == "uris") uris = value
                    else if (key == "suites") suites = value
                    else if (key == "components") comps = value
                    else if (key == "enabled" && tolower(value) == "no") enabled = 0
                }
                if (!enabled || (" " types " ") !~ / deb /) next
                uri_count = split(uris, uri_list, /[ \t]+/)
                suite_count = split(suites, suite_list, /[ \t]+/)
                for (i = 1; i <= uri_count; i++)
                    for (j = 1; j <= suite_count; j++)
                        print uri_list[i] " " suite_list[j] (comps == "" ? "" : " " comps)
            }' "$file"
        done
    } | while read -r uri suite comps; do
        IFS=/ read -r _ _ host user ppa _ <<< "$uri"
        if [[ "$host" == ppa.launchpad.net || "$host" == ppa.launchpadcontent.net ]]; then
            printf 'sudo add-apt-repository ppa:%s/%s\n' "$user" "$ppa"
        else
            printf 'sudo add-apt-repository "deb %s %s%s"\n' "$uri" "$suite" "${comps:+ $comps}"
        fi
    done
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

## APT LOCK HOLDERS ##
# Shows which processes hold the APT and dpkg locks and offers to stop the APT front ends.
# dpkg itself is never signalled: interrupting it mid-write leaves packages half-installed.
tkapt() {
    local pid
    local -a dpkg_pids=() frontends=() holders=() others=()
    local -a locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock)

    mapfile -t holders < <(sudo fuser -- "${locks[@]}" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -un)
    if ((${#holders[@]} == 0)); then
        printf 'No process holds the APT or dpkg locks.\n'
        return 0
    fi

    for pid in "${holders[@]}"; do
        case "$(ps -o comm= -p "$pid")" in
            dpkg*) dpkg_pids+=("$pid") ;;
            apt|apt-get|aptitude|unattended-upgr*|packagekitd) frontends+=("$pid") ;;
            *) others+=("$pid") ;;
        esac
    done

    if ((${#dpkg_pids[@]})); then
        printf 'dpkg is running and must be left to finish:\n'
        ps -o pid=,user=,args= -p "$(IFS=,; printf '%s' "${dpkg_pids[*]}")"
    fi
    if ((${#others[@]})); then
        printf 'Other lock holders, left untouched:\n'
        ps -o pid=,user=,args= -p "$(IFS=,; printf '%s' "${others[*]}")"
    fi
    if ((${#frontends[@]})); then
        printf 'APT front ends holding the locks:\n'
        _terminate_pids --sudo "${frontends[@]}" || return
        printf "Run 'fix' to finish any interrupted package configuration.\n"
    fi
    ((${#dpkg_pids[@]} == 0))
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

    if [[ $choice == 1 ]]; then
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
