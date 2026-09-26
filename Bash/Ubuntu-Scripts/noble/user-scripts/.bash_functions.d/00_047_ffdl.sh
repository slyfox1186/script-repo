#!/usr/bin/env bash

ffdl() {
    clear
    wget --show-progress -cqO "ff.sh" "https://ffdl.optimizethis.net"
    ./ff.sh
    sudo rm ff.sh
    clear; ls -1AhFv --color --group-directories-first
}
