#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Misc/Conda/install_conda.sh

# main creates the private workspace and log. Until then, log only to stderr so
# the functions can be sourced by tests without side effects.
TEMP_DIR=""
LOGFILE=/dev/null

# Log function for feedback
log() {
    echo -e "$1" | tee -a "$LOGFILE" >&2
}

# Fail function for errors
fail() {
    log "Error: $1"
    exit 1
}

# Create the private per-run workspace. mktemp creates it exclusively with
# mode 0700, so a directory or symlink planted by another user is never reused.
init_workspace() {
    local tmp_root
    tmp_root="${TMPDIR:-/tmp}"
    TEMP_DIR="$(mktemp -d "${tmp_root%/}/conda_installer.XXXXXX")" || {
        echo "Error: Failed to create a temporary directory." >&2
        exit 1
    }
    LOGFILE="$TEMP_DIR/miniconda_install.log"
    trap cleanup_workspace EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

# Remove the workspace on every exit. After a failure, copy the log to the home
# directory first so the reason stays available.
cleanup_workspace() {
    # Read the exit status before any other command replaces it.
    local status=$?
    local kept_log
    trap - EXIT
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        if (( status != 0 )) && [[ -s "$LOGFILE" ]]; then
            if kept_log="$(mktemp "$HOME/miniconda_install_log.XXXXXX")" && cat -- "$LOGFILE" > "$kept_log"; then
                echo "Installation log kept at: $kept_log" >&2
            fi
        fi
        rm -rf -- "${TEMP_DIR:?}"
    fi
    exit "$status"
}

# Function to detect the operating system and distribution
detect_os_distro() {
    local ID="" ID_LIKE=""

    log "Detecting operating system and distribution..."
    DISTRO_LIKE=""
    if [[ $(uname -s) == Darwin ]]; then
        OS=macos
        DISTRO=macos
    elif [[ $(uname -s) == Linux ]]; then
        OS=linux
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            DISTRO="${ID,,}"
            DISTRO_LIKE="${ID_LIKE,,}"
            if [[ -z "$DISTRO" ]]; then
                DISTRO=unknown
            fi
        elif command -v lsb_release &>/dev/null; then
            DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        elif [[ -f /etc/redhat-release ]]; then
            DISTRO=$(awk '{print tolower($1)}' /etc/redhat-release)
        else
            DISTRO=unknown
        fi
    else
        fail "Unsupported operating system: $(uname -s)"
    fi
    log "Operating System: $OS"
    log "Distribution: $DISTRO"
}

# Function to detect system architecture and set arch_suffix
detect_architecture() {
    log "Detecting system architecture..."
    arch="$(uname -m)"
    case $arch in
        x86_64|amd64) arch_suffix=x86_64 ;;
        i386|i686) arch_suffix=x86 ;;
        aarch64|arm64) arch_suffix=arm64 ;;
        armv7l|armv6l) arch_suffix=armv7l ;;
        *) fail "Unrecognized architecture: $arch" ;;
    esac
    log "Architecture detected: $arch_suffix"
}

# Print the package-manager family for the distribution. Derivatives such as
# Linux Mint or Pop!_OS are matched through the ID_LIKE list in os-release.
linux_package_family() {
    local candidate
    local -a candidates
    read -r -a candidates <<< "$DISTRO ${DISTRO_LIKE:-}"
    for candidate in ${candidates[@]+"${candidates[@]}"}; do
        case "$candidate" in
            ubuntu|debian|raspbian) echo apt; return 0 ;;
            centos|fedora|rhel) echo rpm; return 0 ;;
            arch|manjaro) echo pacman; return 0 ;;
            opensuse*|suse) echo zypper; return 0 ;;
        esac
    done
    return 1
}

# Succeed when a tool the installer needs is missing: a downloader (wget or
# curl) and tar.
missing_required_tools() {
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        return 0
    fi
    ! command -v tar &>/dev/null
}

# Install packages only when a required tool is missing, then verify the tools.
ensure_dependencies() {
    if missing_required_tools; then
        install_dependencies
    else
        log "Required download and archive tools are already installed."
    fi
    check_prerequisites
}

# Function to install dependencies
install_dependencies() {
    local family
    log "Installing dependencies..."
    case "$OS" in
        linux)
            family="$(linux_package_family)" || fail "Unsupported Linux distribution: $DISTRO. Install curl or wget, and tar, then run this script again."
            case "$family" in
                apt)
                    { sudo apt-get update && sudo apt-get install -y curl sudo tar wget xz-utils; } || fail "Failed to install dependencies with apt-get."
                    ;;
                rpm)
                    if command -v dnf &>/dev/null; then
                        sudo dnf install -y curl sudo tar wget xz || fail "Failed to install dependencies with dnf."
                    else
                        sudo yum install -y curl sudo tar wget xz || fail "Failed to install dependencies with yum."
                    fi
                    ;;
                pacman)
                    # Installing without -Sy avoids a partial upgrade and does not
                    # upgrade the whole system. If the package database is stale,
                    # pacman fails and the user should run 'pacman -Syu' first.
                    sudo pacman -S --needed --noconfirm curl sudo tar wget xz || fail "Failed to install dependencies with pacman. If the package database is out of date, run 'sudo pacman -Syu' and try again."
                    ;;
                zypper)
                    sudo zypper install -y curl sudo tar wget xz || fail "Failed to install dependencies with zypper."
                    ;;
            esac
            ;;
        macos)
            if ! command -v brew &>/dev/null; then
                fail "Homebrew is not installed. Please install Homebrew from https://brew.sh/ and try again."
            fi
            brew install tar wget xz || fail "Failed to install dependencies with Homebrew."
            ;;
        *)
            fail "Unsupported operating system: $OS"
            ;;
    esac
    log "Dependencies installed successfully."
}

# Function to install 7-Zip using the provided GitHub script
install_7zip() {
    log "Installing 7-Zip using the provided installer script..."
    local installer_script installer_url
    installer_url="https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Installer-Scripts/SlyFox1186-Scripts/7zip_installer.sh"
    installer_script="$TEMP_DIR/7zip_installer.sh"

    log "Downloading 7-Zip installer from $installer_url..."
    if command -v wget &> /dev/null; then
        wget "$installer_url" -O "$installer_script" 2>>"$LOGFILE" || fail "Failed to download 7-Zip installer using wget."
    elif command -v curl &> /dev/null; then
        curl -fsSL "$installer_url" -o "$installer_script" 2>>"$LOGFILE" || fail "Failed to download 7-Zip installer using curl."
    else
        fail "Neither wget nor curl is available for downloading the 7-Zip installer."
    fi

    if [[ ! -f "$installer_script" ]]; then
        fail "7-Zip installer script was not downloaded successfully."
    fi

    log "Executing 7-Zip installer script with sudo privileges..."
    sudo bash "$installer_script" 2>>"$LOGFILE" || fail "Failed to execute the 7-Zip installer script."

    log "7-Zip installed successfully."
}

# Function to check and install 7-Zip if necessary
handle_7zip_installation() {
    if ! command -v 7z &>/dev/null; then
        install_7zip
    else
        log "7-Zip is already installed."
    fi
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
        wget "$MINICONDA_URL" -O "$TEMP_DIR/$INSTALLER" 2>>"$LOGFILE" || fail "Failed to download Miniconda installer using wget."
    elif command -v curl &> /dev/null; then
        curl -fL "$MINICONDA_URL" -o "$TEMP_DIR/$INSTALLER" 2>>"$LOGFILE" || fail "Failed to download Miniconda installer using curl."
    fi

    if [[ ! -f "$TEMP_DIR/$INSTALLER" ]]; then
        fail "Miniconda installer was not downloaded successfully."
    fi
    log "Miniconda installer downloaded successfully."
}

# Check for disk space (at least 1 GB free required) on the filesystem that
# will hold the installation. The directory may not exist yet, so measure its
# nearest existing parent. 'df -Pk' is POSIX output that Linux and macOS share.
check_disk_space() {
    local available_space_kb location required_space_kb
    location="$1"
    required_space_kb=1048576 # 1 GB in KB

    while [[ ! -d "$location" ]]; do
        location="${location%/*}"
        [[ -n "$location" ]] || location=/
    done
    log "Checking available disk space for '$location'..."

    if ! command -v df &>/dev/null; then
        fail "'df' command not found to check disk space."
    fi
    available_space_kb="$(df -Pk "$location" | awk 'NR == 2 {print $4}')" || fail "Failed to check the disk space for '$location'."
    if [[ ! "$available_space_kb" =~ ^[0-9]+$ ]]; then
        fail "Could not determine the free disk space for '$location'."
    fi

    if (( available_space_kb < required_space_kb )); then
        fail "Not enough disk space. At least 1 GB is required."
    fi
    log "Sufficient disk space available."
}

# Expand common home-directory shortcuts in interactive path input.
normalize_install_directory() {
    local install_dir
    install_dir="$1"
    case "$install_dir" in
        \~|\~/*) install_dir="$HOME${install_dir:1}" ;;
    esac
    install_dir="${install_dir//\$\{HOME\}/$HOME}"
    install_dir="${install_dir//\$HOME/$HOME}"

    if [[ "$install_dir" != /* ]]; then
        install_dir="$(pwd)/$install_dir"
    fi

    echo "$install_dir"
}

# Print the physical absolute path, resolving symlinks and '..' in the part that
# exists. Components that do not exist yet cannot be symlinks, so they are
# normalized textually.
canonicalize_path() {
    local component existing resolved tail
    local -a parts
    existing="$1"
    [[ "$existing" == /* ]] || existing="$PWD/$existing"
    tail=""

    while [[ ! -d "$existing" ]]; do
        tail="${existing##*/}/$tail"
        existing="${existing%/*}"
        [[ -n "$existing" ]] || existing=/
    done
    resolved="$(cd -P -- "$existing" && pwd -P)" || return 1

    IFS=/ read -r -a parts <<< "$tail"
    for component in ${parts[@]+"${parts[@]}"}; do
        case "$component" in
            ''|.) ;;
            ..)
                resolved="${resolved%/*}"
                [[ -n "$resolved" ]] || resolved=/
                ;;
            *)
                if [[ "$resolved" == / ]]; then
                    resolved="/$component"
                else
                    resolved="$resolved/$component"
                fi
                ;;
        esac
    done
    printf '%s\n' "$resolved"
}

# Classify a canonical installation path as "new" (absent), "empty", or "conda"
# (an existing conda installation). Any other path is refused with a message,
# because replacing it could delete unrelated data.
classify_install_directory() {
    local home_dir install_dir
    install_dir="$1"
    home_dir="$(canonicalize_path "$HOME")" || home_dir="$HOME"

    if [[ "$install_dir" == / ]]; then
        log "ERROR: Refusing to use the filesystem root as the installation directory."
        return 1
    fi
    if [[ "$install_dir" == "$home_dir" || "$home_dir" == "$install_dir"/* ]]; then
        log "ERROR: Refusing to use '$install_dir' because it is your home directory or contains it."
        return 1
    fi
    if [[ -L "$install_dir" ]]; then
        log "ERROR: '$install_dir' is a symbolic link. Enter the real directory path instead."
        return 1
    fi
    if [[ ! -e "$install_dir" ]]; then
        echo new
        return 0
    fi
    if [[ ! -d "$install_dir" ]]; then
        log "ERROR: '$install_dir' exists and is not a directory."
        return 1
    fi
    if [[ -z "$(ls -A -- "$install_dir" 2>/dev/null)" ]]; then
        echo empty
        return 0
    fi
    if [[ -d "$install_dir/conda-meta" && -x "$install_dir/bin/conda" ]]; then
        echo conda
        return 0
    fi
    log "ERROR: '$install_dir' is not empty and is not a conda installation. Choose another path."
    return 1
}

# Prompt the user for the installation directory. An existing conda
# installation is replaced only after explicit confirmation; the removal itself
# happens in prepare_install_directory, after the installer has downloaded.
get_install_directory() {
    local default_dir first_prompt install_dir kind overwrite_choice requested
    default_dir="$HOME/miniconda3"
    first_prompt=true

    while true; do
        if $first_prompt; then
            read -rp "Enter the installation directory (default: \$HOME/miniconda3): " requested || fail "No installation directory was entered."
            requested=${requested:-"$default_dir"}
            first_prompt=false
        else
            read -rp "Enter a different installation directory: " requested || fail "No installation directory was entered."
        fi

        requested="$(normalize_install_directory "$requested")"
        if [[ "$requested" != / && -L "${requested%/}" ]]; then
            log "ERROR: '$requested' is a symbolic link. Enter the real directory path instead."
            continue
        fi
        if ! install_dir="$(canonicalize_path "$requested")"; then
            log "ERROR: Could not resolve '$requested'. Please enter a valid path."
            continue
        fi

        # Miniconda's installer rejects prefixes that contain spaces.
        if [[ "$install_dir" =~ \  ]]; then
            log "ERROR: Installation directory path cannot contain spaces. Please enter a valid path."
            continue
        fi

        kind="$(classify_install_directory "$install_dir")" || continue
        if [[ "$kind" == conda ]]; then
            read -rp "'$install_dir' is an existing conda installation. Replacing it permanently deletes it and every environment inside it. Replace it? (y/n): " overwrite_choice || fail "No answer was entered."
            case "$overwrite_choice" in
                y|Y) ;;
                n|N)
                    log "Please choose a different installation directory."
                    continue
                    ;;
                *)
                    log "Invalid choice. Please enter 'y' or 'n'."
                    continue
                    ;;
            esac
        fi
        echo "$install_dir"
        return 0
    done
}

# Make the chosen directory ready for the Miniconda installer, which refuses an
# existing prefix. The path is classified again so that only a conda
# installation is removed recursively; an empty directory is removed with rmdir,
# which cannot delete contents.
prepare_install_directory() {
    local install_dir kind
    install_dir="$1"
    kind="$(classify_install_directory "$install_dir")" || fail "Refusing to install to '$install_dir'."

    case "$kind" in
        conda)
            log "Removing the existing conda installation at '$install_dir'..."
            rm -fr -- "${install_dir:?}" || fail "Failed to remove the existing conda installation at '$install_dir'."
            log "Existing installation removed."
            ;;
        empty)
            rmdir -- "$install_dir" || fail "Failed to prepare the empty directory '$install_dir'."
            ;;
    esac
}

# Install Miniconda
install_miniconda() {
    local install_dir=$1
    log "Installing Miniconda to '$install_dir'..."

    bash "$TEMP_DIR/$INSTALLER" -b -p "$install_dir" 2>>"$LOGFILE" || fail "Miniconda installation failed."

    if [[ ! -d "$install_dir" ]]; then
        fail "Miniconda installation directory does not exist after installation."
    fi
    log "Miniconda installed successfully to '$install_dir'."
}

# The workspace, including the installer, is removed on exit. A kept installer
# is moved to the home directory without replacing an existing file.
cleanup_installer() {
    local cleanup_choice kept_installer
    read -rp "Do you want to remove the Miniconda installer after installation? (y/n): " cleanup_choice || cleanup_choice=y
    case "$cleanup_choice" in
        y|Y)
            log "Installer removed."
            ;;
        *)
            kept_installer="$HOME/$INSTALLER"
            if [[ ! -e "$kept_installer" && ! -L "$kept_installer" ]]; then
                mv -n -- "$TEMP_DIR/$INSTALLER" "$kept_installer" || true
            fi
            if [[ -e "$TEMP_DIR/$INSTALLER" ]]; then
                kept_installer="$(mktemp "$HOME/$INSTALLER.XXXXXX")" || fail "Failed to create a file for the kept installer."
                mv -f -- "$TEMP_DIR/$INSTALLER" "$kept_installer" || fail "Failed to keep the installer."
            fi
            log "Installer kept at: $kept_installer"
            ;;
    esac
}

# Initialize Conda
initialize_conda() {
    local install_dir=$1
    log "Initializing Conda..."
    "$install_dir/bin/conda" init bash 2>>"$LOGFILE" || fail "Failed to initialize Conda."

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
    available_versions=$(conda search python | grep -E '^python[[:space:]]+' | grep -v 'rc' | awk '{print $2}' | sort -uV)

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
        local regex_pattern
        regex_pattern='^[a-zA-Z0-9_-]+$'
        if [[ "$env_name" =~ $regex_pattern ]]; then
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
    local env_name python_version
    env_name="$1"
    python_version="$2"

    log "Creating Conda environment '$env_name' with Python $python_version..."
    if ! conda create -y -n "$env_name" python="$python_version" 2>>"$LOGFILE" | tee -a "$LOGFILE"; then
        fail "Failed to create Conda environment '$env_name'."
    fi
    log "Conda environment '$env_name' created successfully."
}

# Main execution
main() {
    set -euo pipefail
    init_workspace

    log "==== Starting Miniconda Installation ===="

    detect_os_distro
    detect_architecture
    ensure_dependencies
    handle_7zip_installation
    set_miniconda_url

    # Choose the directory before downloading, but replace an existing
    # installation only once the new installer is ready.
    install_dir="$(get_install_directory)"
    check_disk_space "$install_dir"
    download_installer
    prepare_install_directory "$install_dir"
    install_miniconda "$install_dir"

    # Initialize Conda
    initialize_conda "$install_dir"

    # Add the channels
    add_channels

    # List available Python versions
    list_python_versions

    # Prompt user for Python version
    python_version="$(get_python_version)"

    # Prompt user for Conda environment name
    env_name=$(get_env_name)

    # Check if environment exists
    if check_env_exists "$env_name"; then
        read -rp "Conda environment '$env_name' already exists. Do you want to overwrite it? (y/n): " overwrite_choice
        case "$overwrite_choice" in
            y|Y)
                log "Removing existing Conda environment '$env_name'..."
                conda env remove -y -n "$env_name" 2>>"$LOGFILE" | tee -a "$LOGFILE" || fail "Failed to remove existing Conda environment '$env_name'."
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
    log "Activate your new environment with: conda activate $env_name"
    echo
    log "Full command: source ~/.bashrc; conda activate $env_name"
}

# Run the script only when executed, so tests can source its functions.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
