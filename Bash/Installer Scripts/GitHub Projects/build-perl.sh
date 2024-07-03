#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-perl.sh
# Purpose: Install the latest PERL version from source code
# Updated: 06.21.24

# Variables
base_url="https://github.com/Perl/perl5"
tags_url="${base_url}/tags"
tarball_url="${base_url}/archive/refs/tags"
install_dir="/usr/local/programs/perl"
build_dir="/tmp/perl_build"
log_file="$build_dir/perl_install.log"
bin_dir="/usr/local/bin"

# Functions
function log_message {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$log_file"
}

function check_dependencies {
    local dependencies=("curl" "tar" "make" "gcc")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log_message "Error: $dep is not installed. Please install it first."
            exit 1
        fi
    done
}

function get_latest_even_version {
    latest_even_version=$(curl -fSs "$tags_url" | grep -oP '/Perl/perl5/releases/tag/v\K[0-9]+\.[0-9]*[02468]\.[0-9]+' | head -1)
    if [[ -z "$latest_even_version" ]]; then
        log_message "Error: Unable to fetch the latest even Perl version."
        exit 1
    fi
    echo "v$latest_even_version"
}

function download_and_extract {
    local version="$1"
    local tarball="${tarball_url}/${version}.tar.gz"
    mkdir -p "$build_dir"
    log_message "Downloading Perl $version..."
    if ! curl -Lso "$build_dir/${version}.tar.gz" "$tarball"; then
        log_message "Error: Failed to download $tarball"
        exit 1
    fi
    log_message "Verifying download integrity..."
    if ! tar -tzf "$build_dir/${version}.tar.gz" &>/dev/null; then
        log_message "Error: Downloaded tarball is corrupted"
        exit 1
    fi
    log_message "Extracting Perl $version..."
    if ! tar -xzf "$build_dir/${version}.tar.gz" -C "$build_dir"; then
        log_message "Error: Failed to extract $build_dir/${version}.tar.gz"
        exit 1
    fi
}

function build_and_install {
    local version="$1"
    cd "$build_dir/perl5-${version#v}" || { log_message "Error: Directory $build_dir/perl5-${version#v} does not exist"; exit 1; }
    log_message "Configuring Perl $version..."
    ./Configure -des -Dprefix="$install_dir"
    log_message "Building Perl $version..."
    if ! make -j"$(nproc)"; then
        log_message "Error: Build failed"
        exit 1
    fi
    log_message "Installing Perl $version..."
    if ! sudo make install; then
        log_message "Error: Installation failed"
        exit 1
    fi
}

function create_symlink {
    local binary_path="${install_dir}/bin/perl"
    if [[ -f "$binary_path" ]]; then
        sudo ln -sf "$binary_path" "$bin_dir/perl"
        log_message "Created symbolic link for Perl binary in $bin_dir."
    else
        log_message "Error: Perl binary not found in $binary_path."
        exit 1
    fi
}

# Main
log_message "Starting Perl installation..."
check_dependencies
latest_even_version=$(get_latest_even_version)
if [[ -z "$latest_even_version" ]]; then
    log_message "Error: No even version found. Exiting."
    exit 1
fi
download_and_extract "$latest_even_version"
build_and_install "$latest_even_version"
create_symlink
log_message "Perl installation completed successfully."
