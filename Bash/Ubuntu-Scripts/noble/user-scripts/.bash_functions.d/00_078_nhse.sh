#!/usr/bin/env bash

nhse() {
    nohup sudo "$1" &>/dev/null &
    return 0
}
