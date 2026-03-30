#!/usr/bin/env bash

set -euo pipefail

container_volume1="/share/<FOLDER HERE>/Container"
container_volume2="/share/<FOLDER HERE>/.qpkg"

usage() {
    echo "Usage: $0 <set|unset> <UID>"
    echo "  set   - Grant read/execute ACL permissions for the given UID"
    echo "  unset - Remove ACL permissions for the given UID"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

action="$1"
uid="$2"

if ! [[ "$uid" =~ ^[0-9]+$ ]]; then
    echo "Error: UID must be a numeric value, got '$uid'" >&2
    exit 1
fi

if [[ "$container_volume1" == *'<FOLDER HERE>'* ]]; then
    echo "Error: Edit this script and replace <FOLDER HERE> with your actual share folder name." >&2
    exit 1
fi

set_acls() {
    local paths=(
        "$container_volume1"
        "$container_volume1/container-station-data/lib"
        "$container_volume1/container-station-data/lib/lxd"
        "$container_volume2/container-station"
        "$container_volume2/container-station/lib"
        "$container_volume2/container-station/var"
        /var/lib/lxd
        /var/lib/lxd/containers
        /var/lib/lxd/devices
        /var/lib/lxd/shmounts
        /var/lib/lxd/snapshots
        /var/lib/lxd/storage-pools
        /var/lib/lxd/storage-pools/default/containers
    )

    for path in "${paths[@]}"; do
        if [[ -d "$path" ]]; then
            setfacl -m "user:$uid:rx" "$path"
        else
            echo "Warning: Skipping missing directory: $path" >&2
        fi
    done

    # Recursive ACL on usr directory
    if [[ -d "$container_volume2/container-station/usr" ]]; then
        setfacl -R -m "user:$uid:rx" "$container_volume2/container-station/usr"
    fi

    echo "ACL permissions set for UID $uid."
}

unset_acls() {
    setfacl -R -x "user:$uid" "$container_volume1" 2>/dev/null || true
    setfacl -R -x "user:$uid" "$container_volume2/container-station" 2>/dev/null || true
    setfacl -R -x "user:$uid" /var/lib/lxd/ 2>/dev/null || true
    setfacl -x "user:$uid" /var/lib/lxd 2>/dev/null || true

    echo "ACL permissions removed for UID $uid."
}

case "$action" in
    set)   set_acls ;;
    unset) unset_acls ;;
    *)     echo "Error: Invalid operation '$action'" >&2; usage ;;
esac
