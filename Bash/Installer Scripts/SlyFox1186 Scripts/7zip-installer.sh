#!/usr/bin/env bash
# shellcheck disable=SC2000,SC2034,SC2086 source=/dev/null

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/7zip-installer.sh
# Purpose: install the latest 7-zip package across multiple linux distributions and macos
# Updated: 06-03-2024
# Script version: 3.4

# Set variables
readonly script_version="3.4"
readonly working="$PWD/7zip-install-script"
readonly install_dir="/usr/local/bin"
readonly download_files_dir="$working/7zip-$version"
no_cleanup=false

# Ansi escape codes for colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Function to log messages
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_update() {
    echo -e "${GREEN}[UPDATE]${NC} $1"
}

# Function to log warnings
warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to handle errors and exit
fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "${YELLOW}[WARNING]${NC} Please create a support ticket at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Function to print 7-zip version
print_version() {
    "$install_dir/7z" -version 2>/dev/null | awk '
        /7-Zip \(z\)/ {
            version = $3
            architecture = $4
            gsub(/[()]/, "", architecture)
        }
        /[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
            date = $0
            sub(/^[^-]*-/, "", date)
        }
        END {
            print "7-Zip", version, "(" architecture ")", "Igor Pavlov", date
        }'
}

# Function to print script banner
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo -e "\n $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo -e " $line\n"
    tput sgr 0
}

# Function to download the file with retries
download() {
    wget --show-progress --timeout=60 --connect-timeout=5 --tries=3 -cqO "$2" "$1" || fail "Failed to download the file. Please try again later."
}

# Function to detect the operating system and distribution
detect_os_distro() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        OS="macos"
    else
        OS="linux"
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            DISTRO="$ID"
        elif command -v lsb_release &>/dev/null; then
            DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        elif [[ -f /etc/redhat-release ]]; then
            DISTRO=$(awk '{print tolower($1)}' /etc/redhat-release)
        else
            DISTRO="unknown"
        fi
    fi
}

# Function to install dependencies based on the operating system and distribution
install_dependencies() {
    log "Installing dependencies..."

    case "$OS" in
        linux)
            case "$DISTRO" in
                ubuntu|debian|raspbian)
                    sudo apt update
                    sudo apt -y install tar wget xz-utils
                    ;;
                centos|fedora|rhel)
                    sudo yum install -y tar wget
                    ;;
                arch|manjaro)
                    sudo pacman -Syu
                    sudo pacman -Sy --needed --noconfirm tar wget xz
                    ;;
                opensuse*)
                    sudo zypper install -y tar wget
                    ;;
                *)
                    fail "Unsupported Linux distribution: $DISTRO"
                    ;;
            esac
            ;;
        macos)
            if ! command -v brew &>/dev/null; then
                fail "Homebrew is not installed. Please install Homebrew and try again."
            fi
            brew install tar wget
            ;;
        *)
            fail "Unsupported operating system: $OS"
            ;;
    esac

    log_update "Dependencies installed successfully."
}

# Function to display the help menu
display_help() {
    echo "Script: 7-Zip Install Script"
    echo "Version: $script_version"
    echo "Purpose: This script installs the latest 7-Zip package across multiple Linux distributions and macOS."
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help         Display this help menu"
    echo "  -n, --no-cleanup   Do not clean up the install files after the script has finished"
    echo "  -v, --version      Display the script version"
    echo
    echo "Examples:"
    echo "  Install 7-Zip (stable version) and clean up install files:"
    echo "    $0"
    echo
    echo "  Install 7-Zip (beta version) and keep install files:"
    echo "    $0 -nc"
    echo
    echo "  Display the script version:"
    echo "    $0 -v"
    echo
    echo "  Display this help menu:"
    echo "    $0 -h"
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            display_help
            exit 0
            ;;
        -n|--no-cleanup)
            no_cleanup=true
            ;;
        -v|--version)
            log "Script version: $script_version"
            exit 0
            ;;
        *)  warn "Unknown option: $1"
            display_help
            exit 1
            ;;
    esac
    shift
done

# Display the script banner
box_out_banner "7-Zip Install Script"
detect_os_distro

# Check if wget and tar are installed and install them if missing
if ! command -v wget &>/dev/null || ! command -v tar &>/dev/null; then
    install_dependencies
fi

# Set current version
version="7z2406"

# Detect architecture and set download url based on the operating system
case "$OS" in
    linux)
        case "$(uname -m)" in
            x86_64)
                url="https://www.7-zip.org/a/${version}-linux-x64.tar.xz"
                ;;
            i386|i686)
                url="https://www.7-zip.org/a/${version}-linux-x86.tar.xz"
                ;;
            aarch64*|armv8*)
                url="https://www.7-zip.org/a/${version}-linux-arm64.tar.xz"
                ;;
            arm|armv7*)
                url="https://www.7-zip.org/a/${version}-linux-arm.tar.xz"
                ;;
            *)
                fail "Unrecognized architecture: $(uname -m)"
                ;;
        esac
        ;;
    macos) url="https://www.7-zip.org/a/${version}-mac.tar.xz" ;;
esac

# Create variables to make the script easier to read
tar_file="7zip-$version.tar.xz"

# Clean up any found existing installation directory
if [[ -d "$working" ]]; then
    log "Deleting existing 7zip-install-script directory..."
    echo
    rm -fr "$working"
fi

# Create the installation directory and the output folder to store the sourced files
mkdir -p "$download_files_dir"

# Download the source files if not already downloaded
[[ ! -f "$working/$tar_file" ]] && download "$url" "$working/$tar_file"

# Extract the downloaded files
if ! tar -xf "$working/$tar_file" -C "$download_files_dir"; then
    fail "The script was unable to extract the archive: '$working/$tar_file'"
fi

# Copy the 7z binary file to the /usr/local/bin folder
case "$OS" in
    linux)
        sudo cp -f "$download_files_dir/7zzs" "$install_dir/7z" || fail "The script was unable to copy the static file '7zzs' to '$install_dir/7z'"
        sudo chmod 755 "$install_dir/7z"
        ;;
    macos)
        sudo cp -f "$download_files_dir/7zz" "$install_dir/7z" || fail "The script was unable to copy the static file '7zz' to '$install_dir/7z'"
        sudo chmod 755 "$install_dir/7z"
        ;;
esac

echo
log_update "7-Zip installation completed successfully."

# Display the installed version
print_version

# Cleanup the leftover install files if specified by an argument
if [[ "$no_cleanup" == false ]]; then
    sudo rm -fr "$working" "$0"
else
    log "Skipped the cleanup of install files as specified."
fi
