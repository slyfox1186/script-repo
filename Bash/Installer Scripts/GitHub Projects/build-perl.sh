#!/usr/bin/env bash

# Variables
base_url="https://github.com/Perl/perl5"
tags_url="${base_url}/tags"
tarball_url="${base_url}/archive/refs/tags"
install_dir="/usr/local/perl"
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
    latest_even_version=$(curl -sL "$tags_url" | grep -oP '/Perl/perl5/releases/tag/v\K[0-9]+\.[0-9]*[02468]\.[0-9]+' | head -1)
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
    curl -fsSo "$build_dir/${version}.tar.gz" "$tarball"
    log_message "Extracting Perl $version..."
    tar -xzf "$build_dir/${version}.tar.gz" -C "$build_dir"
}

function build_and_install {
    local version="$1"
    cd "$build_dir/perl5-${version#v}" || exit
    log_message "Configuring Perl $version..."
    ./Configure -des -Dprefix="$install_dir"
    log_message "Building Perl $version..."
    make -j"$(nproc)"
    log_message "Installing Perl $version..."
    sudo make install
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
