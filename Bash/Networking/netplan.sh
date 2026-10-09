#!/usr/bin/env bash

set -Eeuo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=Bash/Networking/networking-common.sh
source "$script_dir/networking-common.sh"

config_dir=/etc/netplan
backup_dir=
candidate_root=
restore_needed=0

install_yaml() {
    local temporary
    temporary=$(mktemp "$config_dir/.network-new.XXXXXX") || return 1
    if cp -a -- "$1" "$temporary" && mv -f -- "$temporary" "$2"; then
        return 0
    fi
    rm -f -- "$temporary"
    return 1
}

restore_netplan() {
    local status=$? file restore_failed=0
    trap - EXIT
    trap '' INT TERM HUP
    if (( restore_needed )); then
        for file in "$config_dir"/*.yaml; do
            [[ -e $file ]] || continue
            [[ -e $backup_dir/${file##*/} ]] || rm -- "$file" || restore_failed=1
        done
        for file in "$backup_dir"/*.yaml; do
            [[ -e $file ]] || continue
            install_yaml "$file" "$config_dir/${file##*/}" || restore_failed=1
        done
        if (( restore_failed )); then
            printf 'Configuration restoration failed. Restore YAML files from %s before rebooting.\n' "$backup_dir" >&2
        else
            printf 'Previous YAML configuration restored. Backup: %s\n' "$backup_dir" >&2
            network_run netplan generate || printf 'Regenerating the previous backend configuration failed.\n' >&2
        fi
        printf 'Verify the running network from a local console; runtime rollback is handled by netplan try.\n' >&2
        status=1
    fi
    [[ -z $candidate_root ]] || rm -rf -- "$candidate_root"
    exit "$status"
}

main() {
    local choice address gateway dns_list key file directory field current_list
    printf 'Choose a configuration\n[1] DHCP\n[2] Static IPv4\n[3] Exit\n'
    network_read choice 'Choice (1 to 3): '
    case $choice in
        1|2) ;;
        3) return 0 ;;
        *) network_fail 'Choose 1, 2, or 3.' ;;
    esac
    network_require_root
    network_require_commands netplan ip flock mktemp cp rm mv mkdir tee grep cmp chmod
    network_lock
    [[ -d $config_dir && ! -L $config_dir ]] || network_fail "Expected a real directory: $config_dir"
    for file in "$config_dir"/*.yaml; do
        [[ ! -L $file && ( ! -e $file || -f $file ) ]] || network_fail "Not a regular YAML file: $file"
    done
    network_read_interface
    key="network.ethernets.${interface//./\\.}"
    printf '\nCurrent IPv4 settings for %s:\n' "$interface"
    for field in dhcp4 addresses routes nameservers.addresses; do
        printf '%s:\n' "$field"
        current_list=$(network_run netplan get "$key.$field") || network_fail 'Cannot read Netplan configuration. This script requires netplan get and set.'
        printf '%s\n' "$current_list"
        if [[ $field == addresses || $field == nameservers.addresses ]]; then
            [[ $current_list != *:* ]] || network_fail 'The address or DNS list contains IPv6. Edit this interface manually to preserve it.'
        elif [[ $field == routes ]]; then
            if grep -Eq '(to|via):[[:space:]]*[^[:space:]]*:' <<< "$current_list"; then
                network_fail 'The route list contains IPv6. Edit this interface manually to preserve it.'
            fi
        fi
    done
    if [[ $choice == 2 ]]; then
        network_read address 'IPv4 address/prefix (example: 192.168.1.20/24): '
        network_cidr "$address" || network_fail 'Invalid IPv4 address or prefix.'
        network_read gateway 'IPv4 gateway: '
        network_ipv4 "$gateway" || network_fail 'Invalid IPv4 gateway.'
        network_dns 3
        printf '\nStatic address: %s\nGateway: %s\nDNS: %s\n' "$address" "$gateway" "${dns_servers[*]:-(none)}"
    else
        printf '\nUse DHCP for %s.\n' "$interface"
    fi
    printf 'This replaces the selected interface address list, static routes, gateway4, and DNS address list.\n'
    printf 'If those lists contain IPv6 or custom routes, cancel and edit them manually.\n'
    printf 'Keep a local console available while testing the connection.\n'
    candidate_root=$(mktemp -d)
    trap restore_netplan EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    mkdir -p -- "$candidate_root/etc/netplan" "$candidate_root/original"
    for file in "$config_dir"/*.yaml; do
        [[ -e $file ]] || continue
        cp -a -- "$file" "$candidate_root/etc/netplan/"
        cp -a -- "$file" "$candidate_root/original/"
    done
    # Validate against the full hierarchy without changing generated live files.
    for directory in /lib/netplan /run/netplan; do
        [[ -d $directory ]] || continue
        mkdir -p -- "$candidate_root$directory"
        for file in "$directory"/*.yaml; do
            [[ -e $file ]] || continue
            cp -a -- "$file" "$candidate_root$directory/"
        done
    done
    # Clear lists before setting them: Netplan merges address and route sequences.
    network_run netplan set --root-dir="$candidate_root" "$key={addresses: null, routes: null, gateway4: null, nameservers: {addresses: null}}" || network_fail 'Cannot clear the previous static settings.'
    if [[ $choice == 1 ]]; then
        network_run netplan set --root-dir="$candidate_root" "$key.dhcp4=true" || network_fail 'Cannot set DHCP configuration.'
    else
        dns_list=$(IFS=,; printf '%s' "${dns_servers[*]}")
        network_run netplan set --root-dir="$candidate_root" "$key={dhcp4: false, addresses: [$address], routes: [{to: default, via: $gateway}], nameservers: {addresses: [$dns_list]}}" || network_fail 'Cannot set static configuration.'
    fi
    network_run netplan generate --root-dir="$candidate_root" || network_fail 'Netplan rejected the configuration.'
    printf '\nProposed IPv4 settings:\n'
    for field in dhcp4 addresses routes nameservers.addresses; do
        printf '%s:\n' "$field"
        network_run netplan get --root-dir="$candidate_root" "$key.$field" || network_fail 'Cannot preview the candidate configuration.'
    done
    network_confirm 'Save and test this configuration?' || return 0
    for file in "$config_dir"/*.yaml; do
        [[ -e $file ]] || continue
        if [[ -L $file ]] || ! cmp -s -- "$file" "$candidate_root/original/${file##*/}"; then
            network_fail 'Netplan files changed during the preview. Run the script again.'
        fi
    done
    for file in "$candidate_root/original"/*.yaml; do
        [[ -e $file ]] || continue
        cmp -s -- "$file" "$config_dir/${file##*/}" || network_fail 'Netplan files changed during the preview. Run the script again.'
    done
    backup_dir=$(mktemp -d "$config_dir/.network-backup.$(date +%Y-%m-%d_%H%M%S).XXXXXX")
    for file in "$config_dir"/*.yaml; do
        [[ -e $file ]] || continue
        cp -a -- "$file" "$backup_dir/" || network_fail 'Cannot back up Netplan configuration.'
    done
    printf 'Backup: %s\n' "$backup_dir"
    restore_needed=1
    for file in "$config_dir"/*.yaml; do
        [[ -e $file ]] || continue
        [[ -e $candidate_root/etc/netplan/${file##*/} ]] || rm -- "$file"
    done
    for file in "$candidate_root/etc/netplan"/*.yaml; do
        [[ -e $file ]] || continue
        if ! cmp -s -- "$file" "$config_dir/${file##*/}"; then
            chmod 600 -- "$file"
            install_yaml "$file" "$config_dir/${file##*/}" || network_fail 'Cannot install the candidate YAML configuration.'
        fi
    done
    printf '\nConfirm the connection in the Netplan prompt within 120 seconds.\n'
    LC_ALL=C network_run netplan try --timeout 120 | tee "$candidate_root/try.log" || network_fail 'Netplan test failed.'
    # Some releases also return zero after a successful rejection/rollback.
    grep -qx 'Configuration accepted\.' "$candidate_root/try.log" || network_fail 'Netplan configuration was not accepted.'
    restore_needed=0
    printf 'Netplan accepted the configuration. Backup: %s\n' "$backup_dir"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
