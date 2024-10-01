#!/usr/bin/env bash

set -euo pipefail

# Variables
LOGFILE="miniconda_install.log"

# Log function for feedback
log() {
    echo -e "$1" | tee -a "$LOGFILE" >&2
}

# Fail function for errors
fail() {
    log "Error: $1"
    exit 1
}

# Function to detect the operating system and distribution
detect_os_distro() {
    log "Detecting operating system and distribution..."
    if [[ "$(uname -s)" == "Darwin" ]]; then
        OS="macos"
        DISTRO="macos"
    elif [[ "$(uname -s)" == "Linux" ]]; then
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
    else
        fail "Unsupported operating system: $(uname -s)"
    fi
    log "Operating System: $OS"
    log "Distribution: $DISTRO"
}

# Function to install dependencies
install_dependencies() {
    log "Installing dependencies..."
    case "$OS" in
        linux)
            case "$DISTRO" in
                ubuntu|debian|raspbian)
                    sudo apt update && \
                    sudo apt -y install tar wget xz-utils curl
                    ;;
                centos|fedora|rhel)
                    sudo yum install -y tar wget xz curl
                    ;;
                arch|manjaro)
                    sudo pacman -Syu --needed --noconfirm tar wget xz curl
                    ;;
                opensuse*|suse)
                    sudo zypper install -y tar wget xz curl
                    ;;
                *)
                    fail "Unsupported Linux distribution: $DISTRO"
                    ;;
            esac
            ;;
        macos)
            if ! command -v brew &>/dev/null; then
                fail "Homebrew is not installed. Please install Homebrew from https://brew.sh/ and try again."
            fi
            brew update
            brew install tar wget xz
            ;;
        *)
            fail "Unsupported operating system: $OS"
            ;;
    esac
    log "Dependencies installed successfully."
}

# Function to detect architecture and set download URL
set_download_url() {
    log "Detecting system architecture..."
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch_suffix="x86_64" ;;
        i386|i686) arch_suffix="x86" ;;
        aarch64|arm64) arch_suffix="arm64" ;;
        armv7l|armv6l) arch_suffix="armv7l" ;;
        *) fail "Unrecognized architecture: $arch" ;;
    esac
    log "Architecture detected: $arch_suffix"

    # Example: Setting URL for 7-Zip based on OS and architecture
    # Adjust the URLs based on actual available downloads
    if [[ "$OS" == "linux" ]]; then
        url="https://www.7-zip.org/a/7z2107-linux-$arch_suffix.tar.xz"
    elif [[ "$OS" == "macos" ]]; then
        url="https://www.7-zip.org/a/7z2107-mac.tar.xz"
    else
        fail "Unsupported operating system for 7-Zip download: $OS"
    fi
    log "Download URL set to: $url"
}

# Function to download and extract 7-Zip
download_and_extract_7zip() {
    local seven_zip_tar="7z.tar.xz"
    log "Downloading 7-Zip from $url..."
    if command -v wget &> /dev/null; then
        wget "$url" -O "$seven_zip_tar" 2>&1 | tee -a "$LOGFILE"
    elif command -v curl &> /dev/null; then
        curl -L "$url" -o "$seven_zip_tar" 2>&1 | tee -a "$LOGFILE"
    else
        fail "Neither wget nor curl is available for downloading 7-Zip."
    fi

    log "Extracting 7-Zip..."
    tar -xf "$seven_zip_tar" || fail "Failed to extract 7-Zip archive."
    rm "$seven_zip_tar"
    log "7-Zip downloaded and extracted successfully."
}

# Set the Miniconda installer URL based on OS and architecture
set_miniconda_url() {
    log "Setting Miniconda installer URL..."
    if [[ "$OS" == "linux" ]]; then
        case "$arch_suffix" in
            x86_64)
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
                INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
                ;;
            arm64)
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh"
                INSTALLER="Miniconda3-latest-Linux-aarch64.sh"
                ;;
            armv7l)
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-armv7l.sh"
                INSTALLER="Miniconda3-latest-Linux-armv7l.sh"
                ;;
            x86)
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86.sh"
                INSTALLER="Miniconda3-latest-Linux-x86.sh"
                ;;
            *)
                fail "Unsupported architecture for Miniconda: $arch_suffix"
                ;;
        esac
    elif [[ "$OS" == "macos" ]]; then
        if [[ "$arch_suffix" == "arm64" ]]; then
            MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh"
            INSTALLER="Miniconda3-latest-MacOSX-arm64.sh"
        else
            MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh"
            INSTALLER="Miniconda3-latest-MacOSX-x86_64.sh"
        fi
    else
        fail "Unsupported operating system for Miniconda download: $OS"
    fi
    log "Miniconda installer URL set to: $MINICONDA_URL"
}

# Check if the necessary tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        fail "Neither 'wget' nor 'curl' is installed. Please install one to proceed."
    fi
    if ! command -v tar &>/dev/null; then
        fail "'tar' is not installed. Please install it to proceed."
    fi
    log "All prerequisites are met."
}

# Download the Miniconda installer using wget or curl
download_installer() {
    log "Downloading Miniconda installer from $MINICONDA_URL..."
    if command -v wget &> /dev/null; then
        wget "$MINICONDA_URL" -O "$INSTALLER" 2>&1 | tee -a "$LOGFILE"
    elif command -v curl &> /dev/null; then
        curl -L "$MINICONDA_URL" -o "$INSTALLER" 2>&1 | tee -a "$LOGFILE"
    fi

    if [[ ! -f "$INSTALLER" ]]; then
        fail "Failed to download Miniconda installer."
    fi
    log "Miniconda installer downloaded successfully."
}

# Check for disk space (at least 1 GB free required)
check_disk_space() {
    log "Checking available disk space..."
    local required_space_kb=1048576 # 1 GB in KB
    local available_space_kb
    if command -v df &>/dev/null; then
        available_space_kb=$(df --output=avail "$HOME" | tail -1 | tr -d ' ')
    else
        fail "'df' command not found to check disk space."
    fi

    if [[ "$available_space_kb" -lt "$required_space_kb" ]]; then
        fail "Not enough disk space. At least 1 GB is required."
    fi
    log "Sufficient disk space available."
}

# Prompt the user for installation directory and handle existing installation
get_install_directory() {
    local default_dir="$HOME/miniconda"
    local install_dir
    local first_prompt=true

    while true; do
        if $first_prompt; then
            read -rp "Enter the installation directory (default: \$HOME/miniconda): " install_dir
            install_dir=${install_dir:-"$default_dir"}
            first_prompt=false
        else
            read -rp "Enter a different installation directory: " install_dir
        fi

        # Check for spaces in the path
        if [[ "$install_dir" =~ \  ]]; then
            log "ERROR: Installation directory path cannot contain spaces. Please enter a valid path."
            continue
        fi

        if [[ -d "$install_dir" ]]; then
            read -rp "The directory '$install_dir' already exists. Do you want to overwrite it? (y/n): " overwrite_choice
            case "$overwrite_choice" in
                y|Y)
                    log "Overwriting existing Miniconda installation at '$install_dir'..."
                    rm -rf "$install_dir"
                    log "Existing installation removed."
                    echo "$install_dir"
                    break
                    ;;
                n|N)
                    log "Please choose a different installation directory."
                    ;;
                *)
                    log "Invalid choice. Please enter 'y' or 'n'."
                    ;;
            esac
        else
            echo "$install_dir"
            break
        fi
    done
}

# Install Miniconda
install_miniconda() {
    local install_dir=$1
    log "Installing Miniconda to '$install_dir'..."

    bash "$INSTALLER" -b -p "$install_dir" 2>&1 | tee -a "$LOGFILE"

    if [[ ! -d "$install_dir" ]]; then
        fail "Miniconda installation failed."
    fi
    log "Miniconda installed successfully to '$install_dir'."
}

# Clean up the installer
cleanup_installer() {
    read -rp "Do you want to remove the Miniconda installer after installation? (y/n): " cleanup_choice
    case "$cleanup_choice" in
        y|Y)
            rm -f "$INSTALLER"
            log "Installer removed."
            ;;
        *)
            log "Installer kept for future use."
            ;;
    esac
}

# Initialize Conda
initialize_conda() {
    local install_dir=$1
    install_dir=$1
    log "Initializing Conda..."
    "$install_dir/bin/conda" init bash 2>&1 | tee -a "$LOGFILE"

    # Source the conda.sh to make conda available in the current shell
    if [[ -f "$install_dir/etc/profile.d/conda.sh" ]]; then
        source "$install_dir/etc/profile.d/conda.sh"
        log "Sourced '$install_dir/etc/profile.d/conda.sh'."
    else
        log "Could not find conda.sh to source."
    fi

    # Attempt to source bashrc or bash_profile if conda is still not available
    if ! command -v conda &> /dev/null; then
        if [[ -f "$HOME/.bashrc" ]]; then
            source "$HOME/.bashrc"
            log "Sourced '$HOME/.bashrc'."
        elif [[ -f "$HOME/.bash_profile" ]]; then
            source "$HOME/.bash_profile"
            log "Sourced '$HOME/.bash_profile'."
        fi
    fi

    if ! command -v conda &> /dev/null; then
        fail "Conda command not found after installation."
    fi
    log "Conda initialized successfully."
}

# Add Conda channels
add_channels() {
    log "Adding Conda channels..."
    conda config --add channels defaults
    conda config --add channels nvidia
    conda config --add channels pytorch
    conda config --add channels conda-forge
    conda config --add channels fastai
    conda config --add channels bioconda
    conda config --add channels anaconda

    log "Conda channels added successfully:"
    conda config --show channels | tee -a "$LOGFILE"
}

# List available Python versions
list_python_versions() {
    echo
    log "Fetching available Python versions from Conda..."
    # Fetch the list of Python versions available in the default channels
    # Limiting to unique versions and sorting them
    available_versions=$(conda search python | grep -E "^python.*" | grep -v 'rc' | awk '{print $2}' | sort -uV)

    if [[ -z "$available_versions" ]]; then
        fail "Failed to retrieve Python versions from Conda."
    fi

    log "Available Python versions:"
    echo "$available_versions" | tee -a "$LOGFILE"
}

# Prompt user to enter Python version
get_python_version() {
    local selected_version
    echo
    while true; do
        read -rp "Enter the Python version you want to install (e.g., 3.8, 3.9, 3.10): " selected_version
        if [[ -z "$selected_version" ]]; then
            log "Python version cannot be empty. Please enter a valid version."
            continue
        fi
        # Check if the entered version is available
        if echo "$available_versions" | grep -qx "$selected_version"; then
            echo "$selected_version"
            break
        else
            log "Invalid Python version entered. Please choose from the available versions listed above."
        fi
    done
}

# Prompt user to enter Conda environment name
get_env_name() {
    local env_name
    while true; do
        read -rp "Enter the name for the new Conda environment: " env_name
        if [[ -z "$env_name" ]]; then
            log "Environment name cannot be empty. Please enter a valid name."
            continue
        fi
        # Check for valid Conda environment naming
        if [[ "$env_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "$env_name"
            break
        else
            log "Invalid environment name. Use only letters, numbers, underscores, or hyphens."
        fi
    done
}

# Check if Conda environment exists
check_env_exists() {
    local env_name=$1
    if conda env list | awk '{print $1}' | grep -qx "$env_name"; then
        return 0
    else
        return 1
    fi
}

# Create Conda environment
create_conda_env() {
    local env_name
    local python_version
    env_name=$1
    python_version=$2

    log "Creating Conda environment '$env_name' with Python $python_version..."
    if ! conda create -y -n "$env_name" python="$python_version" 2>&1 | tee -a "$LOGFILE"; then
        fail "Failed to create Conda environment '$env_name'."
    fi
    log "Conda environment '$env_name' created successfully."
}

# Main execution
main() {
    log "==== Starting Miniconda Installation ===="

    detect_os_distro
    check_prerequisites
    install_dependencies
    set_download_url
    download_and_extract_7zip
    set_miniconda_url
    check_disk_space
    download_installer

    # Get installation directory and install
    install_dir=$(get_install_directory)
    install_miniconda "$install_dir"

    # Initialize Conda
    initialize_conda "$install_dir"

    # Add the channels
    add_channels

    # List available Python versions
    list_python_versions

    # Prompt user for Python version
    python_version=$(get_python_version)

    # Prompt user for Conda environment name
    env_name=$(get_env_name)

    # Check if environment exists
    if check_env_exists "$env_name"; then
        read -rp "Conda environment '$env_name' already exists. Do you want to overwrite it? (y/n): " overwrite_choice
        case "$overwrite_choice" in
            y|Y)
                log "Removing existing Conda environment '$env_name'..."
                conda env remove -y -n "$env_name" 2>&1 | tee -a "$LOGFILE"
                log "Existing environment '$env_name' removed."
                ;;
            *)
                log "Exiting without creating a new environment."
                exit 0
                ;;
        esac
    fi

    # Create Conda environment
    create_conda_env "$env_name" "$python_version"

    # Clean up the installer if requested
    cleanup_installer

    log "==== Miniconda Installation Complete ===="
    log "Please restart your terminal or run 'source ~/.bashrc' to start using Conda."
    log "Activating your new environment: conda activate $env_name"
    conda activate $env_name

    # Optional: If the script is being sourced, source ~/.bashrc to update the current shell
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        log "Sourcing '~/.bashrc' to update the current shell session."
        source ~/.bashrc
    fi
    
}

# Run the script
main "$@"
