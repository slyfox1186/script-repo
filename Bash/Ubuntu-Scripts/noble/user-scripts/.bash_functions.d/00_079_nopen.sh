#!/usr/bin/env bash

## NAUTILUS COMMANDS
nopen() {
    nohup nautilus -w "$1" &>/dev/null &
    return 0
}
