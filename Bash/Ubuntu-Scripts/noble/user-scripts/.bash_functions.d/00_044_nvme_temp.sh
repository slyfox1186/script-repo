#!/usr/bin/env bash

## Show NVME temperature ##
nvme_temp() {
    local n0 n1 n2

    [[ -d "/dev/nvme0n1" ]] && n0=$(sudo nvme smart-log /dev/nvme0n1)
    [[ -d "/dev/nvme1n1" ]] && n1=$(sudo nvme smart-log /dev/nvme0n1)
    [[ -d "/dev/nvme2n1" ]] && n2=$(sudo nvme smart-log /dev/nvme0n1)
    echo -e "nvme0n1: $n0\nnvme1n1: $n1\nnvme2n1: $n2"
}
