#!/usr/bin/env bash

set -Eeuo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=Bash/Networking/networking-common.sh
source "$script_dir/networking-common.sh"

fname=/etc/network/interfaces
candidate=
probe=
backup=
restore_needed=0
activation_started=0

cleanup_interfaces() {
    local status=$? restored=1
    trap - EXIT
    trap '' INT TERM HUP
    if (( activation_started && restore_needed )); then
        network_run ifdown "$interface" || printf 'Could not fully deconfigure the failed activation.\n' >&2
    fi
    if (( restore_needed )); then
        if cp -a -- "$backup" "$candidate" && mv -f -- "$candidate" "$fname"; then
            printf 'Previous interfaces file restored. Backup: %s\n' "$backup" >&2
        else
            printf 'Restoration failed. Restore %s to %s from a local console.\n' "$backup" "$fname" >&2
            restored=0
        fi
        status=1
    fi
    if (( activation_started && restored )); then
        network_run ifup --force "$interface" || printf 'Could not reactivate the previous configuration; use a local console.\n' >&2
        status=1
    fi
    [[ -z $candidate ]] || rm -f -- "$candidate"
    [[ -z $probe ]] || rm -f -- "$probe"
    exit "$status"
}

main() {
    local choice address='' netmask='' broadcast='' gateway='' dns_list='' activation
    local address_number mask_number broadcast_number gateway_number
    network_require_root
    printf 'This tool changes ifupdown IPv4 settings. Keep a local console available.\n'
    network_confirm 'Continue?' || return 0
    network_require_commands ip ifquery ifup ifdown flock awk mktemp cp mv cmp
    network_lock
    [[ -f $fname && ! -L $fname ]] || network_fail "Expected a regular file: $fname"
    printf 'Choose a configuration\n[1] DHCP\n[2] Static IPv4\n'
    network_read choice 'Choice (1 or 2): '
    [[ $choice == 1 || $choice == 2 ]] || network_fail 'Choose 1 or 2.'
    network_read_interface
    if [[ $choice == 2 ]]; then
        network_read address 'IPv4 address (example: 192.168.1.20): '
        network_ipv4 "$address" || network_fail 'Invalid IPv4 address.'
        network_read netmask 'Netmask (example: 255.255.255.0): '
        network_netmask "$netmask" || network_fail 'The netmask must have contiguous bits.'
        network_read broadcast 'Broadcast (example: 192.168.1.255): '
        network_ipv4 "$broadcast" || network_fail 'Invalid IPv4 broadcast.'
        network_read gateway 'IPv4 gateway: '
        network_ipv4 "$gateway" || network_fail 'Invalid IPv4 gateway.'
        address_number=$(network_ipv4_number "$address")
        mask_number=$(network_ipv4_number "$netmask")
        broadcast_number=$(network_ipv4_number "$broadcast")
        gateway_number=$(network_ipv4_number "$gateway")
        (( broadcast_number == (address_number | ((~mask_number) & 0xffffffff)) )) || network_fail 'Broadcast does not match the address and netmask.'
        (( (address_number & mask_number) == (gateway_number & mask_number) )) || network_fail 'Gateway is outside the configured subnet.'
        network_dns 4
        dns_list=${dns_servers[*]}
    fi

    candidate=$(mktemp "$fname.new.XXXXXX")
    trap cleanup_interfaces EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    probe=$(mktemp "$fname.probe.XXXXXX")
    # Query a copy without this interface to detect definitions in included files.
    awk -v target="$interface" '
        $1 ~ /^(iface|auto|allow-|source|source-directory|mapping)/ { skip = 0 }
        $1 == "iface" && $2 == target { skip = 1 }
        !skip { print }
    ' "$fname" > "$probe"
    network_run ifquery --list --interfaces="$probe" >/dev/null || network_fail 'Cannot parse the interfaces configuration.'
    if network_run ifquery --no-mappings --interfaces="$probe" "$interface" >/dev/null 2>&1; then
        network_fail 'This interface is also defined in an included file. Edit that file directly.'
    fi
    cp -a -- "$fname" "$candidate" || network_fail 'Cannot preserve interfaces file metadata.'
    cp -a -- "$fname" "$probe"
    awk -v target="$interface" -v method="$choice" -v address="$address" \
        -v netmask="$netmask" -v broadcast="$broadcast" -v gateway="$gateway" -v dns="$dns_list" '
        function stanza() {
            print "iface " target " inet " (method == 1 ? "dhcp" : "static")
            if (method == 2) {
                print "    address " address
                print "    netmask " netmask
                print "    broadcast " broadcast
                print "    gateway " gateway
                if (dns != "") print "    dns-nameservers " dns
            }
        }
        $1 ~ /^(iface|auto|allow-|source|source-directory|mapping)/ { replacing = 0 }
        $1 == "auto" || $1 ~ /^allow-/ {
            for (i = 2; i <= NF; i++) if ($i == target) activated = 1
        }
        $1 == "mapping" { print "Mapping stanzas require manual editing." > "/dev/stderr"; bad = 1 }
        $1 == "iface" && $2 == target && $3 == "inet" {
            if (++found > 1) { bad = 1; next }
            replacing = 1; stanza(); next
        }
        replacing && $1 ~ /^(address|netmask|broadcast|gateway|dns-nameservers)$/ { next }
        { print }
        END {
            if (bad) exit 1
            if (!found) {
                print ""
                if (!activated) print "auto " target
                stanza()
            }
        }
    ' "$fname" > "$candidate" || network_fail 'Ambiguous or unsupported interfaces configuration.'
    network_run ifquery --no-mappings --interfaces="$candidate" "$interface" >/dev/null || network_fail 'ifquery rejected the candidate configuration.'
    printf '\nProposed IPv4 settings (other stanzas and options are preserved):\n'
    awk -v target="$interface" '
        $1 ~ /^(iface|auto|allow-|source|source-directory|mapping)/ { selected = 0 }
        $1 == "iface" && $2 == target && $3 == "inet" { selected = 1; print; next }
        selected && $1 ~ /^(address|netmask|broadcast|gateway|dns-nameservers)$/ { print }
    ' "$candidate"
    network_confirm 'Save this configuration?' || return 0
    network_read activation 'Activate now? [1] Yes [2] Save only: '
    [[ $activation == 1 || $activation == 2 ]] || network_fail 'Choose 1 or 2.'
    if [[ $activation == 1 && -n ${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-} ]]; then
        network_fail 'Activation over SSH can disconnect you. Choose save only, then activate from a local console.'
    fi
    cmp -s -- "$fname" "$probe" || network_fail 'The interfaces file changed during the preview. Run the script again.'
    backup=$(mktemp "$fname.backup.$(date +%Y-%m-%d_%H%M%S).XXXXXX")
    cp -a -- "$fname" "$backup" || network_fail 'Cannot back up the interfaces file.'
    printf 'Backup: %s\n' "$backup"
    if [[ $activation == 1 ]]; then
        # Deconfigure using the OLD settings, before replacing the file.
        activation_started=1
        network_run ifdown --interfaces="$backup" "$interface" || network_fail 'ifdown failed; configuration was not changed. Check the interface from a local console.'
    fi
    restore_needed=1
    mv -f -- "$candidate" "$fname" || network_fail 'Cannot install the interfaces configuration.'
    if [[ $activation == 1 ]]; then
        if ! network_run ifup "$interface"; then
            network_fail "Activation failed. Attempting recovery from backup: $backup"
        fi
        printf 'Interface activation completed.\n'
    else
        printf 'Configuration saved. The running interface was not changed.\n'
    fi
    restore_needed=0
    activation_started=0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
