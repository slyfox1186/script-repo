#!/usr/bin/env bash
# Process Management Functions

# Succeeds while PID exists and is not a zombie awaiting collection by its parent.
_pid_alive() {
    local state
    state=$(ps -o stat= -p "$1" 2>/dev/null) || return 1
    [[ -n $state && $state != Z* ]]
}

# Usage: _terminate_pids [--sudo] PID...
# Lists the targets, asks before SIGTERM, waits up to 5 seconds, then asks before SIGKILL for
# survivors. Enter or end of input declines. --sudo permits sudo for processes owned by other
# users. Returns 0 only when every target has exited.
_terminate_pids() {
    local allow_sudo=false answer pid owner signal tries
    local -a pids=() survivors=()

    if [[ ${1-} == --sudo ]]; then
        allow_sudo=true
        shift
    fi
    for pid in "$@"; do
        if [[ ! $pid =~ ^[1-9][0-9]*$ ]]; then
            printf 'Invalid PID: %s\n' "$pid" >&2
            return 2
        fi
        _pid_alive "$pid" && pids+=("$pid")
    done
    if ((${#pids[@]} == 0)); then
        printf 'No running processes to terminate.\n'
        return 0
    fi

    for signal in TERM KILL; do
        ps -o pid=,user=,args= -p "$(IFS=,; printf '%s' "${pids[*]}")"
        read -r -p "Send SIG$signal to ${#pids[@]} process(es)? [y/N] " answer || answer=
        if [[ $answer != [yY] && $answer != [yY][eE][sS] ]]; then
            printf 'Not sent. %d process(es) still running.\n' "${#pids[@]}"
            return 1
        fi
        for pid in "${pids[@]}"; do
            owner=$(ps -o uid= -p "$pid" 2>/dev/null) || continue
            if ((owner != EUID)) && [[ $allow_sudo == true ]]; then
                sudo kill "-$signal" -- "$pid" || printf 'Failed to signal PID %s.\n' "$pid" >&2
            else
                kill "-$signal" -- "$pid" || printf 'Failed to signal PID %s.\n' "$pid" >&2
            fi
        done
        for ((tries = 0; tries < 50; tries++)); do
            survivors=()
            for pid in "${pids[@]}"; do
                _pid_alive "$pid" && survivors+=("$pid")
            done
            ((${#survivors[@]} == 0)) && break
            sleep 0.1
        done
        if ((${#survivors[@]} == 0)); then
            printf 'All %d process(es) exited after SIG%s.\n' "${#pids[@]}" "$signal"
            return 0
        fi
        pids=("${survivors[@]}")
        printf '%d process(es) survived SIG%s.\n' "${#pids[@]}" "$signal"
    done
    return 1
}

# Prints "PID<TAB>COMMAND<TAB>PROTOCOL" for each process listening on TCP or bound to UDP PORT.
# Connections to a remote PORT are not listeners and are excluded.
_port_listeners() {
    sudo ss -Hlnptu "sport = :$1" |
        gawk '{
            protocol = toupper($1)
            while (match($0, /\("([^"]+)",pid=([0-9]+)/, found)) {
                print found[2] "\t" found[1] "\t" protocol
                $0 = substr($0, RSTART + RLENGTH)
            }
        }' | sort -u
}

# Usage: kill_process [-f] NAME
# Matches the exact process name; -f matches NAME anywhere in the full command line.
kill_process() {
    local pid
    local -a pgrep_args=(-x) protected=() targets=()

    if [[ ${1-} == -f ]]; then
        pgrep_args=(-f)
        shift
    fi
    if (($# != 1)) || [[ -z $1 ]]; then
        printf 'Usage: kill_process [-f] NAME\n' >&2
        return 1
    fi

    # Never offer this shell or its ancestors, such as the terminal that is running it.
    pid=$$
    while [[ $pid =~ ^[0-9]+$ ]] && ((pid > 1)); do
        protected+=("$pid")
        pid=$(ps -o ppid= -p "$pid" | tr -d '[:space:]')
    done
    while IFS= read -r pid; do
        [[ " ${protected[*]} " == *" $pid "* ]] || targets+=("$pid")
    done < <(pgrep "${pgrep_args[@]}" -- "$1")

    if ((${#targets[@]} == 0)); then
        printf "No running process matches '%s'.\n" "$1"
        return 0
    fi
    _terminate_pids --sudo "${targets[@]}"
}

## nohup commands
nh() {
    nhe "$@" || return
    echo
    ls -1AvhF --color --group-directories-first
}

nhs() {
    nhse "$@" || return
    echo
    ls -1AvhF --color --group-directories-first
}

nhe() {
    if (($# == 0)); then
        printf 'Usage: nhe COMMAND [ARGUMENTS...]\n' >&2
        return 1
    fi
    nohup "$@" &>/dev/null &
    return 0
}

nhse() {
    if (($# == 0)); then
        printf 'Usage: nhse COMMAND [ARGUMENTS...]\n' >&2
        return 1
    fi
    # Authenticate in the foreground before the detached command suppresses output.
    sudo -v || return
    nhe sudo -n -- "$@"
}

# Usage: taskkill_pid PORT...
taskkill_pid() {
    local port status=0
    local -a pids

    if (($# == 0)); then
        printf 'Usage: tkpid PORT...\nExample: tkpid 3000 8080\n' >&2
        return 1
    fi

    for port in "$@"; do
        if [[ ! $port =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
            printf 'Invalid port: %s\n' "$port" >&2
            status=1
            continue
        fi
        mapfile -t pids < <(_port_listeners "$port" | cut -f1 | sort -un)
        if ((${#pids[@]} == 0)); then
            printf 'No process is listening on port %s.\n' "$port"
            continue
        fi
        printf 'Port %s:\n' "$port"
        _terminate_pids --sudo "${pids[@]}" || status=1
    done
    return "$status"
}

alias tkpid='taskkill_pid'
