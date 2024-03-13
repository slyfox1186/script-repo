#!/usr/bin/env bash

# Purpose: Install the latest 7-Zip package across multiple Linux distributions and macOS
# Updated: 03-13-2024
# Script version: 3.0
# Added macOS: If errors occur create an issue at: https://github.com/slyfox1186/script-repo/issues

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

# Set variables
readonly script_version="3.0"
readonly WORKDIR="/tmp/7zip-install-script"
readonly install_dir="/usr/local/bin"

# ANSI escape codes for colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

# Function to log messages
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_update() {
    echo -e "${GREEN}[UPDATE]${NC} $1"
}

# Function to log warnings
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to handle errors and exit
fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "${YELLOW}[WARN]${NC} Please create a support ticket at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Function to print 7-Zip version
print_version() {
    local version_info
    version_info=$("$install_dir/7z" | awk -F ' |\\(' '/7-Zip/{print $4; exit}')
    echo

    # Capture the output of the '7z -version' command directly.
    command_output=$("$install_dir/7z" -version 2>/dev/null)

    # Initialize variables to hold version, architecture, and date information.
    version=""
    architecture=""
    date=""

    # Extract version, architecture, and date from the command output.
    while read -r line; do
        if [[ "$line" =~ 7-Zip\ \(z\)\ ([0-9]+\.[0-9]+)\ \((x64|x86|arm64)\) ]]; then
            version="${BASH_REMATCH[1]}"
            architecture="${BASH_REMATCH[2]}"
        fi
        if [[ "$line" =~ ([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
            date="${BASH_REMATCH[2]}-${BASH_REMATCH[3]}-${BASH_REMATCH[1]}"
        fi
    done <<< "$command_output"

    # Format and print the output.
    formatted_output="7-Zip $version ($architecture) Igor Pavlov $date"
    echo "$formatted_output"
}

# Function to print script banner
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo -e "\n $line"
    printf "|" ; echo -n "${space}" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "${space}" ; printf "%s\n" "|";
    echo -e " $line\n"
    tput sgr 0
}

# Function to download the file with retries
download() {
    local url="$1"
    local dest="$2"

    if ! wget --show-progress -cqO "$dest" "$url"; then
        fail "Failed to download the file. Please try again later."
    fi
}

# Function to detect the operating system
detect_os() {
    case $(uname -s) in
        Linux*)  OS="linux";;
        Darwin*) OS="macos";;
        *)       fail "Unsupported operating system: $(uname -s)";;
    esac
}

# Function to detect the Linux distribution
detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO="$ID"
    elif type lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si | tr '[[:upper:]]' '[[:lower:]]')
    elif [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release
        DISTRO="$DISTRIB_ID"
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO=$(awk '{print $1}' /etc/redhat-release | tr '[[:upper:]]' '[[:lower:]]')
    else
        DISTRO="unknown"
    fi
}

# Function to install dependencies based on the operating system and distribution
install_dependencies() {
    log "Installing dependencies..."

    case "$OS" in
        linux)
           case "$DISTRO" in
               ubuntu|debian|raspbian)
                  apt-get update
                  apt-get install -y tar wget
                  ;;
               centos|fedora|rhel)
                  yum install -y tar wget ;;
               arch|manjaro)
                  pacman -Sy tar wget ;;
               opensuse*)
                  zypper install -y tar wget ;;
               *) fail "Unsupported Linux distribution: $DISTRO" ;;
           esac
           ;;
        macos)
           if ! command -v brew &>/dev/null; then
               fail "Homebrew is not installed. Please install Homebrew and try again."
           fi
           brew install tar wget
           ;;
        *) fail "Unsupported operating system: $OS" ;;
    esac

    log_update "Dependencies installed successfully."
}

# Display the help menu
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "\nOptions:"
    echo "  -h, --help                  Display this help menu"
    echo "  -b, --beta                  Download and install the beta version of 7-Zip"
    echo "  -o, --output <DIR>          Specify a custom output directory"
    echo "  -u, --url <URL>             Specify a custom download URL"
    echo "  -v, --version               Display the script version"
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
           display_help
           exit 0
           ;;
        -b|--beta)
           beta=1
           ;;
        -v|--version)
           log "Script version: $script_version"
           exit 0
           ;;
        -u|--url)
           custom_url=$2
           shift
           ;;
        -o|--output)
           custom_output_dir=$2
           shift
           ;;
        *) warn "Unknown option: $1"
           echo
           display_help
           ;;
    esac
    shift
done

# Main script execution starts here
box_out_banner "7-Zip Install Script"
detect_os
detect_distribution

# Check if wget and tar are installed and install them if missing
if ! command -v wget &>/dev/null || ! command -v tar &>/dev/null; then
    install_dependencies
fi

# Check if the 7zip-install-script directory exists and delete it
if [[ -d "$WORKDIR" ]]; then
    log "Deleting existing 7zip-install-script directory..."
    rm -fr "$WORKDIR"
fi

# Create the 7zip-install-script directory
mkdir -p "$WORKDIR"

# Detect architecture and set download URL based on the operating system
case $OS in
    linux)
        case "$(uname -m)" in
            x86_64)          url="linux-x64" ;;
            i386|i686)       url="linux-x86" ;;
            aarch64*|armv8*) url="linux-arm64" ;;
            arm|armv7*)      url="linux-arm" ;;
            *)               fail "Unrecognized architecture: $(uname -m)" ;;
        esac
        ;;
    macos) url="mac" ;;
esac

# Set the download URL based on the beta flag
if [[ "$beta" -eq 1 ]]; then
    version="7z2400"
else
    version="7z2301"
fi

# Set the download URL
url="https://www.7-zip.org/a/$version-$url.tar.xz"
# Use a custom download URL if provided by the user
[[ -n $custom_url ]] && url="$custom_url"

# Set the tar file and output directory names
tar_file="$version.tar.xz"
output_dir="$WORKDIR/$version"

# Create the output directory
mkdir -p "$output_dir"

# Download the tar file with retries if missing
if [[ ! -f "$WORKDIR/$tar_file" ]]; then
    download "$url" "$WORKDIR/$tar_file" || fail "Failed to download the file."
fi

# Extract files into directory '7z'
if ! tar -xf "$WORKDIR/$tar_file" -C "$output_dir"; then
    fail "The script was unable to extract the archive: '$WORKDIR/$tar_file'"
fi

# Use custom output directory if provided
[[ -n $custom_output_dir ]] && install_dir="$custom_output_dir"

# Copy the file to its destination or throw an error if the copying of the file fails
case "$OS" in
    linux) if ! cp -f "$output_dir/7zzs" "$install_dir/7z"; then
               fail "The script was unable to copy the static file '7zzs' to '$install_dir/7z'"
           else
               chmod 755 "$install_dir/7z"
           fi
           ;;
    macos) if ! cp -f "$output_dir/7zz" "$install_dir/7z"; then
               fail "The script was unable to copy the static file '7zz' to '$install_dir/7z'"
           else
               chmod 755 "$install_dir/7z"
           fi
           ;;
esac

# Show the newly installed 7-Zip version
echo
log_update "7-Zip installation completed successfully."
print_version

# Clean up the install files
rm -fr "$WORKDIR"
