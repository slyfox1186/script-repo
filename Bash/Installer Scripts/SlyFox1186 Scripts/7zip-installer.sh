#!/usr/bin/env bash
# shellcheck disable=SC2000,SC2034,SC2086 source=/dev/null

# Set variables
readonly script_version="4.0"
readonly working="$PWD/7zip-install-script"
readonly install_dir="/usr/local/bin"
no_cleanup=false

# Ansi escape codes for colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Functions to log messages

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_update() {
    echo -e "${GREEN}[UPDATE]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

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
    line=$(printf '%*s' "$input_char" | tr ' ' '-')
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    printf "\n %s\n|%s|\n| %s |\n|%s|\n %s\n\n" "$line" "$space" "$(tput setaf 4)$@$(tput setaf 3)" "$space" "$line"
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

# Function to install dependencies
install_dependencies() {
    log "Installing dependencies..."
    case "$OS" in
        linux)
            case "$DISTRO" in
                ubuntu|debian|raspbian)
                    sudo apt update && \
                    sudo apt -y install tar wget xz-utils
                    ;;
                centos|fedora|rhel)
                    sudo yum install -y tar wget
                    ;;
                arch|manjaro)
                    sudo pacman -Syu --needed --noconfirm tar wget xz
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
            command -v brew &>/dev/null || fail "Homebrew is not installed. Please install Homebrew and try again."
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
while [[ "$#" -gt 0 ]]; then
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
        *)
            warn "Unknown option: $1"; display_help
            exit 1
            ;;
    esac
    shift
done

# Main script execution
box_out_banner "7-Zip Install Script"
detect_os_distro

# Check if wget and tar are installed and install them if missing
command -v wget &>/dev/null && command -v tar &>/dev/null || install_dependencies

# Fetch and parse the 7-zip download page
download_page=$(wget -qO- "https://www.7-zip.org/download.html")
release_version=$(echo "$download_page" | grep -oP '(?<=Download 7-Zip )[0-9.]+(?= \()' | head -n1)
beta_version=$(echo "$download_page" | grep -oP '(?<=Download 7-Zip )[0-9.]+ beta(?= \()' | head -n1)

if [[ -n "$beta_version" ]]; then
    version="${release_version}-beta"
else
    version="$release_version"
fi

# Detect architecture and set download url based on the operating system
case "$OS" in
    linux)
        arch=$(uname -m)
        case "$arch" in
            x86_64) arch_suffix="x64" ;;
            i386|i686) arch_suffix="x86" ;;
            aarch64*|armv8*) arch_suffix="arm64" ;;
            arm|armv7*) arch_suffix="arm" ;;
            *) fail "Unrecognized architecture: $arch" ;;
        esac
        url="https://www.7-zip.org/a/7z${version//./}-linux-$arch_suffix.tar.xz"
        ;;
    macos) url="https://www.7-zip.org/a/7z${version//./}-mac.tar.xz" ;;
    *) fail "Unsupported operating system: $OS" ;;
esac

# Create variables to make the script easier to read
tar_file="7zip-$version.tar.xz"
download_files_dir="$working/7zip-$version"

# Clean up any found existing installation directory (use sudo in case it was root-owned)
[[ -d "$working" ]] && { log "Deleting existing 7zip-install-script directory..."; sudo rm -fr "$working"; }

# Create the installation directory and the output folder to store the sourced files
mkdir -p "$download_files_dir"

# Download the source files if not already downloaded
[[ ! -f "$working/$tar_file" ]] && download "$url" "$working/$tar_file"

# Extract the downloaded files
tar -xf "$working/$tar_file" -C "$download_files_dir" || fail "The script was unable to extract the archive: '$working/$tar_file'"

# Copy the 7z binary file to the /usr/local/bin folder
case "$OS" in
    linux) sudo cp -f "$download_files_dir/7zzs" "$install_dir/7z" || fail "The script was unable to copy the static file '7zzs' to '$install_dir/7z'" ;;
    macos) sudo cp -f "$download_files_dir/7zz" "$install_dir/7z" || fail "The script was unable to copy the static file '7zz' to '$install_dir/7z'" ;;
esac
sudo chmod 755 "$install_dir/7z"

log_update "7-Zip installation completed successfully."

# Display the installed version
print_version

# Cleanup the leftover install files if specified by an argument
if [[ "$no_cleanup" == false ]]; then
    sudo rm -fr "$working" "$0"
else
    log "Skipped the cleanup of install files as specified."
fi
