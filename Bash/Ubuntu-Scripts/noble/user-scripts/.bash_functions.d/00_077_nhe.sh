#!/usr/bin/env bash

nhe() {
    nohup "$1" &>/dev/null &
    return 0
}
