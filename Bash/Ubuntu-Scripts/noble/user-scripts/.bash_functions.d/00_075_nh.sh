#!/usr/bin/env bash

## nohup commands
nh() {
    nohup "$1" &>/dev/null &
    echo
    ls -1AvhF --color --group-directories-first
}
