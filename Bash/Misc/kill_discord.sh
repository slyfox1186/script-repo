#!/usr/bin/env bash

# Match only this user's Discord process name, never script paths or Vesktop.
# The kdc alias uses sudo, so retain the invoking user's process ownership.
target_uid=${SUDO_UID:-$UID}
mapfile -t pids < <(pgrep -u "$target_uid" -ix discord)
if (( ${#pids[@]} )); then
    echo "Killing Discord (PID: ${pids[*]})"
    kill "${pids[@]}"
    sleep 2
    mapfile -t remaining < <(pgrep -u "$target_uid" -ix discord)
    if (( ${#remaining[@]} )); then
        echo "Force killing Discord (PID: ${remaining[*]})"
        kill -9 "${remaining[@]}"
    fi
else
    echo "Discord is not running"
fi
