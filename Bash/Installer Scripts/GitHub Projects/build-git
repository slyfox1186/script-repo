#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-git/
##  Purpose: Build git from source code
##  Script updated on: 11.24.23
##  Git version: 2.43.0
##  Script version: 1.3

CC=gcc
CXX=g++
CFLAGS="-g -O3 -pipe -fno-plt -march=native"
CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CC CFLAGS CXX CXXFLAGS

# Function to log messages
log() {
    echo "[LOG] $(date '+%Y-%m-%d %H:%M:%S'): $1"
}

# Installing necessary dependencies for building git
install_dependencies() {
    log "Installing dependencies necessary for building Git from source..."
    sudo apt update
    sudo apt install libz-dev libssl-dev libcurl4-gnutls-dev libexpat1-dev gettext cmake gcc -y
    if [ $? -eq 0 ]; then
        log "Successfully installed build dependencies."
    else
        log "Failed to install build dependencies."
        exit 1
    fi
}

# Download, compile, and install git from source
install_git() {
    log "Fetching the latest Git source code..."
    cd /usr/src
    sudo wget https://github.com/git/git/archive/refs/tags/v2.43.2.tar.gz -O git.tar.gz
    if [ $? -ne 0 ]; then
        log "Failed to download Git source code."
        exit 1
    fi
    
    log "Extracting Git source code..."
    sudo tar -zxf git.tar.gz
    cd git-*
    
    log "Compiling Git from source. This may take a while..."
    sudo make "-j$(nproc --all)" prefix=/usr/local all
    if [ $? -ne 0 ]; then
        log "Compilation of Git failed."
        exit 1
    fi
    
    log "Installing Git..."
    sudo make install
    if [ $? -eq 0 ]; then
        log "Git has been successfully installed from source."
    else
        log "Failed to install Git."
        exit 1
    fi
}

# Main function to control the flow of the script
main() {
    log "Starting the script to install Git from source."
    install_dependencies
    install_git
    log "Script completed."
}

# Calling the main function
main
