#!/usr/bin/env bash

# Purpose: install the latest 7-zip package across multiple linux distributions and macos
# Updated: 03-26-2024
# Script version: 3.2
# Optimized code

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

random=$(mkdtemp -d)

# Set variables
readonly script_version="3.2"
readonly working="$random/7zip-install-script"
readonly install_dir="/usr/local/bin"

# Ansi escape codes for colors
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to handle errors and exit
fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "${YELLOW}[WARN]${NC} Please create a support ticket at: https://github.com/slyfox1186/script-repo/issues"
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
    wget --show-progress -cqO "$2" "$1" || fail "Failed to download the file. Please try again later."
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
        elif command -v lsb_release >/dev/null 2>&1; then
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
                    apt-get update
                    apt-get install -y tar wget
                    ;;
                centos|fedora|rhel)
                    yum install -y tar wget
                    ;;
                arch|manjaro)
                    pacman -Sy --needed --noconfirm tar wget
                    ;;
                opensuse*)
                    zypper install -y tar wget
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
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help      Display this help menu"
    echo "  -b, --beta      Download and install the beta version of 7-Zip"
    echo "  -r, --release   Download and install the release version of 7-Zip (default)"
    echo "  -v, --version   Display the script version"
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)    display_help; exit 0 ;;
        -b|--beta)    version="7z2403" ;;
        -r|--release) version="7z2301" ;;
        -v|--version) log "Script version: $script_version"; exit 0 ;;
        *)            warn "Unknown option: $1"; display_help ;;
    esac
    shift
done

[[ -z "$version" ]] && version="7z2301"

box_out_banner "7-Zip Install Script"
detect_os_distro

# Check if wget and tar are installed and install them if missing
command -v wget &>/dev/null || command -v tar &>/dev/null || install_dependencies

# Clean up existing installation directory
[[ -d "$working" ]] && { log "Deleting existing 7zip-install-script directory..."; rm -fr "$working"; }

# Create the installation directory
mkdir -p "$working"

# Detect architecture and set download url based on the operating system
case "$OS" in
    linux)
        case "$(uname -m)" in
            x86_64)          url="https://www.7-zip.org/a/${version}-linux-x64.tar.xz" ;;
            i386|i686)       url="https://www.7-zip.org/a/${version}-linux-x86.tar.xz" ;;
            aarch64*|armv8*) url="https://www.7-zip.org/a/${version}-linux-arm64.tar.xz" ;;
            arm|armv7*)      url="https://www.7-zip.org/a/${version}-linux-arm.tar.xz" ;;
            *)               fail "Unrecognized architecture: $(uname -m)" ;;
        esac
        ;;
    macos) url="https://www.7-zip.org/a/${version}-mac.tar.xz" ;;
esac

tar_file="$version.tar.xz"
output_dir="$working/$version"
mkdir -p "$output_dir"

[[ ! -f "$working/$tar_file" ]] && download "$url" "$working/$tar_file"

if ! tar -xf "$working/$tar_file" -C "$output_dir"; then
    fail "The script was unable to extract the archive: '$working/$tar_file'"
fi

case "$OS" in
    linux)
        cp -f "$output_dir/7zzs" "$install_dir/7z" || fail "The script was unable to copy the static file '7zzs' to '$install_dir/7z'"
        chmod 755 "$install_dir/7z"
        ;;
    macos)
        cp -f "$output_dir/7zz" "$install_dir/7z" || fail "The script was unable to copy the static file '7zz' to '$install_dir/7z'"
        chmod 755 "$install_dir/7z"
        ;;
esac

echo
log_update "7-Zip installation completed successfully."
print_version

rm -fr "$working"
