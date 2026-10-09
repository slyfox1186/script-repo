#!/usr/bin/env bash
# Shared input checks for the two interactive networking tools. Source this file.

network_fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

network_read() {
    IFS= read -r -p "$2" "$1" || network_fail 'Input ended. No further changes will be made.'
}

network_require_root() {
    (( EUID == 0 )) || network_fail 'Run this script with sudo or as root.'
}

network_require_commands() {
    local command_name
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 || network_fail "Required command is missing: $command_name"
    done
}

network_lock() {
    local lock_file=/run/script-repo-networking.lock
    [[ ! -L $lock_file ]] || network_fail 'The lock file must not be a symbolic link.'
    exec {network_lock_fd}>"$lock_file" || network_fail 'Cannot open the networking lock.'
    flock -n "$network_lock_fd" || network_fail 'Another networking script is running.'
}

network_run() (
    # Daemonized DHCP clients and hooks must not keep the parent script's lock.
    exec {network_lock_fd}>&-
    exec "$@"
)

network_ipv4() {
    local value=$1 octet
    local -a octets
    [[ $value =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$value"
    for octet in "${octets[@]}"; do
        # Reject ambiguous leading zeros rather than reinterpret them as octal.
        [[ $octet == 0 || $octet != 0* ]] || return 1
        (( 10#$octet <= 255 )) || return 1
    done
}

network_ipv4_number() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    printf '%s\n' "$(( (10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d ))"
}

network_netmask() {
    local mask inverse
    network_ipv4 "$1" || return 1
    mask=$(network_ipv4_number "$1")
    inverse=$(( (~mask) & 0xffffffff ))
    (( (inverse & (inverse + 1)) == 0 ))
}

network_cidr() {
    local prefix=${1#*/}
    [[ $1 == */* && $prefix =~ ^([0-9]|[12][0-9]|3[0-2])$ ]] || return 1
    network_ipv4 "${1%/*}"
}

network_interface() {
    [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,14}$ && $1 != lo ]] || return 1
    ip link show dev "$1" >/dev/null 2>&1
}

network_read_interface() {
    interface=''
    network_read interface 'Network interface (example: eth0): '
    network_interface "$interface" || network_fail 'Enter an existing interface name other than lo.'
}

network_dns() {
    local count=$1 dns index
    dns_servers=()
    for ((index = 1; index <= count; index++)); do
        network_read dns "DNS server $index (IPv4, blank to finish): "
        [[ -n $dns && $dns != 0 ]] || break
        network_ipv4 "$dns" || network_fail "Invalid DNS server: $dns"
        dns_servers+=("$dns")
    done
}

network_confirm() {
    local answer
    network_read answer "$1 [1] Yes [2] No: "
    case $answer in
        1) return 0 ;;
        2) return 1 ;;
        *) network_fail 'Choose 1 or 2.' ;;
    esac
}
