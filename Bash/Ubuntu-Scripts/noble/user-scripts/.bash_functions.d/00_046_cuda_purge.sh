#!/usr/bin/env bash

## FFMPEG COMMANDS ##

cuda_purge() {
    local choice

    echo "Do you want to completely remove the cuda-sdk-toolkit?"
    echo "WARNING: Do not reboot your PC without reinstalling the nvidia-driver first!"
    echo "[1] Yes"
    echo "[2] Exit"
    echo
    read -r -p "Your choices are (1 or 2): " choice
    clear

    if [[ $choice -eq 1 ]]; then
        echo "Purging the CUDA-SDK-Toolkit from your PC"
        echo "================================================"
        echo
        sudo apt -y --purge remove "*cublas*" "cuda*" "nsight*"
        sudo apt -y autoremove
        sudo apt update
    else
        return 0
    fi
}
