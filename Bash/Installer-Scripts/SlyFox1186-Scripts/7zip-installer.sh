#!/usr/bin/env bash
# shellcheck disable=SC2000,SC2034,SC2086 source=/dev/null

# Set variables
readonly script_version="4.3"
readonly working="$PWD/7zip-install-script"
readonly install_dir="/usr/local/bin"
no_cleanup=false
use_beta=false

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

# Function to get the installed 7-Zip version
get_installed_version() {
    [[ -x "$install_dir/7z" ]] || return 1

    "$install_dir/7z" -version 2>&1 | awk '
        /^7-Zip/ {
            for (field = 1; field <= NF; field++) {
                if ($field ~ /^[0-9]+(\.[0-9]+)+$/) {
                    print $field
                    exit
                }
            }
        }'
}

# Function to print the installed 7-Zip version banner
print_version() {
    if [[ -x "$install_dir/7z" ]]; then
        "$install_dir/7z" -version 2>&1 | awk '/^7-Zip/ { print; exit }'
    else
        echo "7-Zip not found in $install_dir"
    fi
}

# Function to print script banner
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(printf '%*s' "$input_char" '' | tr ' ' '-')
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    printf "\n %s\n|%s|\n| %s |\n|%s|\n %s\n\n" "$line" "$space" "$(tput setaf 4)$*$(tput setaf 3)" "$space" "$line"
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
    cat <<EOF
7-Zip Install Script $script_version

Install the latest stable 7-Zip release on Linux or macOS. Use --beta to prefer
the latest beta release published on the official 7-Zip download page.

Usage:
  ${0##*/} [OPTIONS]

Options:
  -b, --beta        Prefer the latest beta; use stable if no beta is published.
  -n, --no-cleanup  Keep downloaded and extracted installation files.
  -h, --help        Display this help menu and exit.
  -v, --version     Display the script version and exit.

Behavior:
  The selected release is compared with /usr/local/bin/7z when it is installed.
  Matching versions exit without reinstalling. Different versions require y/Y
  confirmation before the release archive is downloaded or installed. When no
  beta is published, --beta automatically selects the latest stable release.

Examples:
  ${0##*/}                 Install or update to the latest stable release.
  ${0##*/} --beta          Prefer beta, falling back to stable when necessary.
  ${0##*/} --beta -n       Prefer beta and keep the installation files.
  ${0##*/} --help          Show this help menu.
EOF
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
        -b|--beta)
            use_beta=true
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

# wget is required to determine the latest release before checking the installed version.
command -v wget &>/dev/null || install_dependencies

# Fetch and parse the 7-zip download page
log "Fetching 7-Zip download page..."
download_page=$(wget -qO- "https://www.7-zip.org/download.html") || fail "Failed to fetch 7-Zip download page"

# Extract the stable release once because it is both the default and the safe
# fallback when --beta is requested but no beta is currently published.
stable_version=$(printf '%s\n' "$download_page" | sed -n 's/.*Download 7-Zip \([0-9][0-9.]*\) (.*for Windows.*/\1/p' | head -n1)

# Select the requested release channel. Stable is the default. --beta prefers
# a published beta but falls back to stable so the command remains useful while
# 7-Zip has no active beta release.
if [[ "$use_beta" == true ]]; then
    beta_version=$(printf '%s\n' "$download_page" | sed -n 's/.*Download 7-Zip \([0-9][0-9.]*\) beta (.*for Windows.*/\1/p' | head -n1)
    if [[ -n "$beta_version" ]]; then
        version="$beta_version"
        release_channel="beta"
        version_suffix="beta"
        log "Found latest beta release: $version"
    else
        [[ -n "$stable_version" ]] || fail "Could not find a beta release or determine the latest stable 7-Zip release."

        version="$stable_version"
        release_channel="stable"
        version_suffix=""
        log "No beta release is currently published; using latest stable release: $version"
    fi
else
    [[ -n "$stable_version" ]] || fail "Could not determine the latest stable 7-Zip release from the download page."

    version="$stable_version"
    release_channel="stable"
    version_suffix=""
    log "Found latest stable release: $version"
fi

[[ "$version" =~ ^[0-9]+([.][0-9]+)+$ ]] || fail "Invalid 7-Zip version found on download page: $version"

version_label="$version"
if [[ "$release_channel" == "beta" ]]; then
    version_label="$version beta"
fi

# Only report that 7-Zip is already installed when it matches the latest release.
if [[ -x "$install_dir/7z" ]]; then
    installed_version=$(get_installed_version)

    if [[ -n "$installed_version" && "$installed_version" == "$version" ]]; then
        log "7-Zip $version_label is already installed and is the latest $release_channel release:"
        print_version
        exit 0
    fi

    if [[ -n "$installed_version" ]]; then
        log_update "A 7-Zip $release_channel update is available: $installed_version -> $version_label"
    else
        warn "7-Zip is installed, but its version could not be determined. The latest $release_channel release is $version_label."
    fi

    read -p "Do you want to download and install 7-Zip $version_label? (y/N): " -n 1 -r reply
    echo
    if [[ ! $reply =~ ^[Yy]$ ]]; then
        log "Installation cancelled by user."
        exit 0
    fi
fi

# tar is only needed after installation has been confirmed.
command -v tar &>/dev/null || install_dependencies

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
        # Construct the URL by removing dots and adding the beta suffix when needed.
        version_for_url="${version//./}"
        if [[ -n "$version_suffix" ]]; then
            version_for_url="${version_for_url}${version_suffix}"
        fi
        url="https://www.7-zip.org/a/7z${version_for_url}-linux-$arch_suffix.tar.xz"
        ;;
    macos)
        version_for_url="${version//./}"
        if [[ -n "$version_suffix" ]]; then
            version_for_url="${version_for_url}${version_suffix}"
        fi
        url="https://www.7-zip.org/a/7z${version_for_url}-mac.tar.xz"
        ;;
    *) fail "Unsupported operating system: $OS" ;;
esac

log "Download URL: $url"

# Create variables to make the script easier to read
tar_file="7zip-$version.tar.xz"
download_files_dir="$working/7zip-$version"

# Clean up any found existing installation directory (use sudo in case it was root-owned)
[[ -d "$working" ]] && { log "Deleting existing 7zip-install-script directory..."; sudo rm -fr "$working"; }

# Create the installation directory and the output folder to store the sourced files
mkdir -p "$download_files_dir"

# Download the source files if not already downloaded
log "Downloading 7-Zip $version_label..."
[[ ! -f "$working/$tar_file" ]] && download "$url" "$working/$tar_file"

# Extract the downloaded files
log "Extracting archive..."
tar -xf "$working/$tar_file" -C "$download_files_dir" || fail "The script was unable to extract the archive: '$working/$tar_file'"

# Copy the 7z binary file to the /usr/local/bin folder
log "Installing 7-Zip binary..."
case "$OS" in
    linux) 
        [[ -f "$download_files_dir/7zzs" ]] || fail "7zzs binary not found in extracted files"
        sudo cp -f "$download_files_dir/7zzs" "$install_dir/7z" || fail "The script was unable to copy the static file '7zzs' to '$install_dir/7z'" 
        ;;
    macos) 
        [[ -f "$download_files_dir/7zz" ]] || fail "7zz binary not found in extracted files"
        sudo cp -f "$download_files_dir/7zz" "$install_dir/7z" || fail "The script was unable to copy the static file '7zz' to '$install_dir/7z'" 
        ;;
esac
sudo chmod 755 "$install_dir/7z"

log_update "7-Zip installation completed successfully."

# Display the installed version
print_version

# Cleanup the leftover install files if specified by an argument
if [[ "$no_cleanup" == false ]]; then
    log "Cleaning up installation files..."
    sudo rm -fr "$working"
else
    log "Skipped the cleanup of install files as specified."
fi

log "Installation complete! You can now use 7-Zip with the '7z' command."
