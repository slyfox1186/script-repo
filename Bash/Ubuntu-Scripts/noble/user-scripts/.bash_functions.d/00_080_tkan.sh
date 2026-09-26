#!/usr/bin/env bash

tkan() {
    local parent_dir=$PWD
    sudo killall -9 nautilus
    sleep 1
    nohup nautilus -w "$parent_dir" &>/dev/null &
    return 0
}
