#!/usr/bin/env bash

# Clean OS
clean() {
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt -y purge
}
