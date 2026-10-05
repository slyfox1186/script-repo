#!/usr/bin/env bash
# Networking Functions

my_ip() {
    # Efficiently retrieve WAN (public) and LAN (local) IP addresses in Bash.
    # Prioritizes DNS-based methods for WAN to reduce dependencies (e.g., no curl/wget needed if dig is available).
    # Falls back to HTTP if DNS fails, with timeouts for reliability.
    # Uses 'ip' for LAN to target the active outbound interface, avoiding deprecated 'ifconfig'.
    # Handles errors and edge cases like no connectivity or multiple interfaces.
    
    local wan_ip
    # Try DNS query first (faster, no HTTP overhead; uses OpenDNS for reliability).
    wan_ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    if [[ -z "$wan_ip" ]]; then
        # Fallback to HTTP with curl (common alternative service).
        wan_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    fi
    if [[ -z "$wan_ip" ]]; then
        wan_ip="Unavailable (no internet connectivity or resolution failure)"
    fi
    
    local lan_ip
    # Get LAN IP from the source address of the default route (efficient for primary interface).
    lan_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
    if [[ -z "$lan_ip" ]]; then
        # Fallback: First global-scope IPv4 address (excludes loopback).
        lan_ip=$(ip -4 addr show scope global 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
        if [[ -z "$lan_ip" ]]; then
            lan_ip="Unavailable (no active interfaces found)"
        fi
    fi
    
    # Structured output for easy parsing (e.g., by scripts) while remaining human-readable.
    printf "WAN IP: %s\n" "$wan_ip"
    printf "LAN IP: %s\n" "$lan_ip"
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

# WGET command
mywget() {
    local outfile url
    if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        read -rp "Please enter the output file name: " outfile
        read -rp "Please enter the URL: " url
        echo
        wget --output-document="$outfile" "$url"
    else
        wget --output-document="$1" "$2"
    fi
}

# High-throughput aria2c download tuned for ~1 Gbps fiber on Linux.
# Usage: aria2_download -o <output_path> <URL>
#   -o <path>   Output file (relative or absolute). Required.
#   <URL>       Source URL (http/https/ftp/sftp/magnet/metalink). Required.
# Existing output files are overwritten from scratch, including partial downloads.
aria2_download() {
    local output_path="" url="" user_agent="" rc=""
    
    user_agent="Mozilla/5.0 (X11; Linux x86_64; rv:155.0) Gecko/20100101 Firefox/155.0"

    while (( $# > 0 )); do
        case "$1" in
            -o)
                if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
                    printf 'Error: -o requires a path argument\n' >&2
                    printf 'Usage: aria2_download -o <output_path> <URL>\n' >&2
                    return 1
                fi
                output_path="$2"
                shift 2
                ;;
            -o*)
                output_path="${1#-o}"
                shift
                ;;
            -h|--help)
                printf 'Usage: aria2_download -o <output_path> <URL>\n'
                printf '  -o <path>   Output file (relative or absolute). Required.\n'
                printf '  <URL>       Source URL. Required.\n'
                printf '  Existing output files are overwritten; partial downloads restart.\n'
                return 0
                ;;
            --)
                shift
                if [[ -z "$url" && $# -gt 0 ]]; then
                    url="$1"
                    shift
                fi
                ;;
            -*)
                printf 'Error: unknown option: %s\n' "$1" >&2
                printf 'Usage: aria2_download -o <output_path> <URL>\n' >&2
                return 1
                ;;
            *)
                if [[ -z "$url" ]]; then
                    url="$1"
                else
                    printf 'Error: unexpected extra argument: %s\n' "$1" >&2
                    printf 'Usage: aria2_download -o <output_path> <URL>\n' >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$output_path" ]]; then
        printf 'Error: missing required argument -o <output_path>\n' >&2
        printf 'Usage: aria2_download -o <output_path> <URL>\n' >&2
        return 1
    fi

    if [[ -z "$url" ]]; then
        if [[ -t 0 ]]; then
            # Paste-safe: input read here is never shell-parsed, so '&' in URLs is harmless
            read -rep "Enter the URL: " url
        fi
        if [[ -z "$url" ]]; then
            printf 'Error: missing required URL argument\n' >&2
            printf 'Usage: aria2_download -o <output_path> <URL>\n' >&2
            return 1
        fi
    fi

    # Detect being launched as a background job: an unquoted URL containing '&'
    # makes bash split the command there, backgrounding adl with a truncated URL.
    local bg_job=0
    if [[ -t 2 ]]; then
        local self_pgid fg_pgid
        self_pgid=$(ps -o pgid= -p "$BASHPID" 2>/dev/null | tr -d ' ')
        fg_pgid=$(ps -o tpgid= -p "$BASHPID" 2>/dev/null | tr -d ' ')
        if [[ -n "$self_pgid" && -n "$fg_pgid" && "$self_pgid" != "$fg_pgid" ]]; then
            bg_job=1
            printf '\nWARNING: adl is running as a BACKGROUND job.\n' >&2
            printf 'Your URL likely contained an unquoted "&" and bash split the command there.\n' >&2
            printf 'URL as received (possibly truncated): %s\n' "$url" >&2
            printf 'Tip: wrap the URL in single quotes, or run plain "adl -o <file>" and paste the URL at the prompt.\n\n' >&2
        fi
    fi

    if ! command -v aria2c >/dev/null 2>&1; then
        printf 'Error: aria2c is not installed or not in PATH\n' >&2
        return 1
    fi

    local out_dir out_file
    if [[ "$output_path" == */* ]]; then
        out_dir="$(dirname -- "$output_path")"
        out_file="$(basename -- "$output_path")"
    else
        out_dir="."
        out_file="$output_path"
    fi

    if [[ ! -d "$out_dir" ]]; then
        if ! mkdir -p -- "$out_dir"; then
            printf 'Error: failed to create output directory: %s\n' "$out_dir" >&2
            return 1
        fi
    fi

    local -a cookie_args=()
    if [[ -f "$HOME/.aria2/cookies.txt" ]]; then
        cookie_args=(--load-cookies="$HOME/.aria2/cookies.txt")
    fi

    clear

    # Keep the original aggressive splitting settings for large single-file downloads.
    # Removing the control file prevents aria2 from resuming despite allow-overwrite.
    aria2c \
        --no-conf=true \
        "${cookie_args[@]}" \
        --dir="$out_dir" \
        --out="$out_file" \
        --max-connection-per-server=16 \
        --split=16 \
        --min-split-size=1M \
        --file-allocation=falloc \
        --enable-mmap=true \
        --disk-cache=64M \
        --continue=false \
        --max-tries=3 \
        --retry-wait=10 \
        --connect-timeout=30 \
        --timeout=60 \
        --max-file-not-found=3 \
        --auto-file-renaming=false \
        --allow-overwrite=true \
        --remove-control-file=true \
        --check-certificate=true \
        --remote-time=true \
        --summary-interval=0 \
        --show-console-readout=true \
        --console-log-level=warn \
        --user-agent="$user_agent" \
        -- "$url"

    rc=$?

    if (( bg_job )); then
        printf '\n[adl] Background download finished (exit %d). Your prompt is free - press Enter.\n' "$rc" >&2
    fi
    return "$rc"
}
alias adl='aria2_download'

padl() {
    local clipboard output_file url
    local -a args

    # Get the clipboard contents (clipboard text is never shell-parsed, so URLs
    # containing '&' or '?' are safe here - no quoting needed)
    if [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-paste >/dev/null 2>&1; then
        clipboard=$(wl-paste --no-newline 2>/dev/null)
    elif command -v xclip >/dev/null 2>&1; then
        clipboard=$(xclip -o -selection clipboard 2>/dev/null)
    elif command -v pwsh.exe >/dev/null 2>&1; then
        clipboard=$(pwsh.exe -Command "Get-Clipboard")
    else
        echo "Error: no clipboard tool found (need wl-paste, xclip, or pwsh.exe)"
        return 1
    fi

    # Split the clipboard contents into an array using whitespace as the delimiter
    IFS=' ' read -r -a args <<< "$clipboard"

    # Check if the number of arguments is less than 2
    if [[ ${#args[@]} -lt 2 ]]; then
        echo "Error: Two arguments are required: output file and download URL"
        echo "Clipboard should contain: <output_file> <url>"
        return 1
    fi

    # Extract the first argument as the output file
    output_file="${args[0]}"

    # Extract the remaining arguments as the download URL and remove trailing whitespace
    url=$(echo "${args[@]:1}" | tr -d '[:space:]')

    # Call aria2_download with the output file and URL as separate arguments
    aria2_download -o "$output_file" "$url"
}

# Aria2c batch downloader
adt() {
    local json_script="add-video-to-json.py"
    local run_script="batch-downloader.py"
    local repo_base="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/aria2"
    local script filename extension path url output

    # Check and download Python scripts if they don't exist
    for script in "$json_script" "$run_script"; do
        if [[ ! -f "$script" ]]; then
            echo "Downloading $script from GitHub..."
            if ! wget --show-progress -cqO "$script" "$repo_base/$script"; then
                echo "Error: Failed to download $script from GitHub." >&2
                return 1
            fi
            echo "$script downloaded successfully."
        fi
    done

    # Prompt for video details
    echo "Enter the video details:"
    read -rp "Filename: " filename
    read -rp "Extension: " extension
    read -rp "Path: " path
    read -rp "URL: " url

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

    read -rp "Enter the source path: " source
    read -rp "Enter the destination path: " destination
    # Trailing slash is stripped, then split into parent + basename joined by /./
    source="${source%/}"
    modified_source="${source%/*}/./${source##*/}"
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
    echo "If you want to KEEP the originals (copy only) then use the function 'rsr'."
    echo "Please enter the full paths of the source and destination directories."
    echo

    read -rp "Enter the source path: " source
    read -rp "Enter the destination path: " destination
    source="${source%/}"
    modified_source="${source%/*}/./${source##*/}"
    echo

    rsync -aqvR --acls --perms --mkpath --remove-source-files "$modified_source" "$destination"
}

# The master script download menu for github repository script-repo
dlmaster() {
    local script_path="/usr/local/bin/download-master.py"
    local script_url="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/download-master.py"

    # Check if the script exists
    if [[ ! -f "$script_path" ]]; then
        echo "The required script does not exist. Downloading now."
        # Download the script
        sudo wget --show-progress -cqO "$script_path" "$script_url"    
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

kill_ports() {
    local port pid
    # Check if at least one port number is provided.
    if [[ ${#} -eq 0 ]]; then
        echo "Usage: kill_ports <port1> [port2] [port3] ..."
        return 1
    fi

    # Loop through all the port numbers provided as arguments.
    for port in "${@}"; do
        echo "--> Checking for process on port: ${port}"

        # Find the PID of the process using the specified port.
        # The '-t' option for lsof outputs only the PID.
        pid=$(lsof -t -i:"${port}" 2>/dev/null)

        # Check if a PID was found.
        if [[ -n "$pid" ]]; then
            echo "    Process with PID ${pid} found on port ${port}. Terminating..."
            kill -9 "$pid"
            echo "    Process ${pid} terminated."
        else
            echo "    No process found running on port ${port}."
        fi
    done
}
