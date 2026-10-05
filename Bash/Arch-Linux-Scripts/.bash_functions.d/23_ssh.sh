#!/usr/bin/env bash

# JSERVERPC's address, port, user and key live in the `Host jserverpc` entry in
# ~/.ssh/config. Password auth is disabled server-side, so sss and cssh rely on it.
JSERVER_HOST="jserverpc"

sss() {
    # Helper function for displaying usage instructions.
    _sss_help() {
        local key
        echo "Usage: sss [OPTION] | [DESTINATION_PATH] | delall"
        echo ""
        echo "Syncs screenshots to a remote server using rsync over SSH."
        echo "Swap the leading - for + (e.g. +t) to instead delete the png, jpg and"
        echo "webp files sitting directly in that same remote folder. Subfolders are"
        echo "left alone. Pass delall to do that for every folder listed below."
        echo ""
        echo "Options:"
        if declare -p SSS_DESTINATIONS &>/dev/null; then
            while IFS= read -r key; do
                printf '  -%-14s Set destination to %s\n' "$key" "${SSS_DESTINATIONS[$key]}"
            done < <(printf '%s\n' "${!SSS_DESTINATIONS[@]}" | LC_ALL=C sort)
        else
            echo "  (no lettered flags: define SSS_DESTINATIONS in ~/.bash_private.sh)"
        fi
        echo "  delall          Delete those images from every folder above."
        echo "  -h, --help      Display this help message and exit."
        echo ""
        echo "If no option flag is used, a custom DESTINATION_PATH can be provided."
        echo "If no arguments are provided, this help menu is displayed."
    }

    # Lettered flags and their remote folders come from SSS_DESTINATIONS in
    # ~/.bash_private.sh: -x fills the folder, +x cleans it, delall cleans all of them.
    local -A destinations=()
    if declare -p SSS_DESTINATIONS &>/dev/null; then
        local key
        for key in "${!SSS_DESTINATIONS[@]}"; do
            destinations[$key]="${SSS_DESTINATIONS[$key]}"
        done
    fi

    local destination=""
    local show_help=0
    local delete_images=0
    local delete_all=0
    local flag

    # Parse command-line arguments.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help=1
                shift
                ;;
            delall)
                if [[ -n "$destination" || "$delete_all" -eq 1 ]]; then
                    echo "Error: Only one destination can be specified." >&2
                    return 1
                fi
                if [[ ${#destinations[@]} -eq 0 ]]; then
                    echo "Error: delall needs SSS_DESTINATIONS in ~/.bash_private.sh" >&2
                    return 1
                fi
                delete_all=1
                shift
                ;;
            -*|+*)
                flag="${1:1}"
                if [[ -z "$flag" || -z "${destinations[$flag]+set}" ]]; then
                    echo "Error: Unknown option '$1'" >&2
                    _sss_help
                    return 1
                fi
                if [[ -n "$destination" || "$delete_all" -eq 1 ]]; then
                    echo "Error: Only one destination can be specified." >&2
                    return 1
                fi
                destination="${destinations[$flag]}"
                [[ "$1" == +* ]] && delete_images=1
                shift
                ;;
            *) # Handle a positional argument for the destination.
                if [[ -n "$destination" || "$delete_all" -eq 1 ]]; then
                    echo "Error: Cannot specify a path when a destination flag is already used." >&2
                    return 1
                fi
                destination="$1"
                shift
                ;;
        esac
    done

    # Display help if requested or if no destination was provided.
    if [[ "$show_help" -eq 1 || ( -z "$destination" && "$delete_all" -eq 0 ) ]]; then
        # Clear screen only if called with no arguments.
        if [[ "$show_help" -eq 0 ]]; then
            clear
        fi
        _sss_help
        return 0
    fi

    if [[ "$delete_images" -eq 1 || "$delete_all" -eq 1 ]]; then
        # -maxdepth 1 keeps the delete out of subfolders: +t points at ~/tmp, which
        # holds every project. %q quotes the paths for the remote shell.
        local find_images="-maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.webp' \\) -print -delete"
        local remote_dirs remote_cmd summary deleted count=0
        if [[ "$delete_all" -eq 1 ]]; then
            # Folders that do not exist on the server are skipped, since most
            # of the list is usually absent.
            local -a folders
            mapfile -t folders < <(printf '%s\n' "${destinations[@]%/}" | LC_ALL=C sort)
            printf -v remote_dirs '%q ' "${folders[@]}"
            remote_cmd="rc=0; for d in $remote_dirs; do [ -d \"\$d\" ] || continue; find \"\$d/\" $find_images || rc=1; done; exit \$rc"
            summary="every sss folder"
        else
            printf -v remote_dirs '%q' "${destination%/}/"
            remote_cmd="find $remote_dirs $find_images"
            summary="$destination"
        fi
        deleted=$(ssh "$JSERVER_HOST" "$remote_cmd") || return
        if [[ -n "$deleted" ]]; then
            printf '%s\n' "$deleted"
            count=$(wc -l <<< "$deleted")
        fi
        echo "Deleted $count image(s) from $summary"
        return 0
    fi

    rsync -avz "$HOME/Pictures/Screenshots/" "$JSERVER_HOST:$destination"
}

# Print the address ~/.ssh/config resolves for JSERVERPC.
_jserver_address() {
    command ssh -G "$JSERVER_HOST" 2>/dev/null </dev/null | awk '$1 == "hostname" { print $2; exit }'
}

_cssh_check_route() {
    local server_ip route=""
    server_ip=$(_jserver_address)

    if [[ -z "$server_ip" ]] || ! route=$(ip route get "$server_ip" 2>&1); then
        printf 'cssh: unable to determine route to %s: %s\n' "${server_ip:-$JSERVER_HOST}" "$route" >&2
        return 1
    fi
    if [[ " $route " == *" dev nordlynx "* ]]; then
        printf 'cssh: NordVPN is routing %s through nordlynx; SSH cannot reach the LAN server.\n' "$server_ip" >&2
        printf 'Fix: nordvpn allowlist add subnet %s/32\n' "$server_ip" >&2
        return 1
    fi
}

cssh() {
    _cssh_check_route || return
    clear
    if [[ $# -eq 0 ]]; then
        # No arguments - interactive SSH session
        ssh "$JSERVER_HOST"
    else
        # Arguments provided - run command then stay in interactive shell.
        # printf '%q' shell-quotes each arg, preventing injection via '$' or quotes.
        # sshd runs remote commands via a non-interactive 'bash -c' that never
        # sources ~/.bashrc, so aliases like cdg don't exist in it. Wrapping the
        # command in 'bash -ic' forces an interactive shell that sources
        # ~/.bashrc and expands aliases; 'exec bash' then keeps the session
        # open in whatever directory the command landed in.
        local quoted_cmd remote_cmd
        printf -v quoted_cmd '%q ' "$@"
        printf -v remote_cmd '%q' "${quoted_cmd% }; exec bash"
        ssh -t "$JSERVER_HOST" "bash -ic ${remote_cmd}"
    fi
}
