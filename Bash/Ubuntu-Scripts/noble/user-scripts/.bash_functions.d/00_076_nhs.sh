#!/usr/bin/env bash

nhs() {
    nohup sudo "$1" &>/dev/null &
    echo
    ls -1AvhF --color --group-directories-first
}
