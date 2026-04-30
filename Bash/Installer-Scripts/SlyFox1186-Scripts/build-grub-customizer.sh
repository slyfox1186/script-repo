#!/usr/bin/env bash

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Define logging functions
fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Define required packages
REQUIRED_PKGS=(cmake gettext hwinfo libarchive-dev libgtkmm-3.0-dev libssl-dev ninja-build)

# Define compiler flags
set_compiler_flags() {
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-O2 -fno-plt -pipe -march=native -mtune=native"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath=$INSTALL_PREFIX/lib"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS
}

# Check if the script is run with root or sudo
if [[ "$EUID" -eq 0 ]]; then
    fail "You must run this script without using root or sudo."
fi

# Display help menu
display_help() {
    echo "  Usage: $0 [OPTIONS]"
    echo
    echo "  Options:"
    echo
    echo "  -h, --help            Display this help menu"
    echo "  -c, --cleanup         Cleanup build files and temporary workspace"
    echo "  -g, --gui             Add customized settings before creating and saving the master grub.conf file"
    echo "  -i, --install         Install grub-customizer (default)"
    echo "  -u, --uninstall       Uninstall grub-customizer"
    echo
    echo "  Example: $0 --gui -c        # Installs grub-customizer, opens its GUI Window, and then cleans up the leftover build files"
    echo "  Example: $0 -u --cleanup    # Uninstalls grub-customizer, and then cleans up the leftover build files"
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -i|--install)
            INSTALL_MODE="install"
            shift
            ;;
        -u|--uninstall)
            INSTALL_MODE="uninstall"
            shift
            ;;
        -g|--gui)
            LAUNCH_GUI="true"
            shift
            ;;
        -c|--cleanup)
            CLEANUP="true"
            shift
            ;;
        -h|--help)
            display_help
            exit 0
            ;;
        *)
            warn "Unknown option: $1"
            display_help
            exit 1
            ;;
    esac
done

# Set default installation mode
INSTALL_MODE="${INSTALL_MODE:-install}"

# Check if the grub-customizer is already installed
if command -v grub-customizer &>/dev/null; then
    if [[ "$INSTALL_MODE" == "install" ]]; then
        warn "grub-customizer is already installed."
        if [[ "$LAUNCH_GUI" == "true" ]]; then
            log "Launching grub-customizer GUI..."
            sudo grub-customizer
            exit 0
        else
            exit 0
        fi
    fi
else
    if [[ "$INSTALL_MODE" == "uninstall" ]]; then
        warn "grub-customizer is not installed."
        exit 0
    fi
fi

# Check and install required packages
log "Checking required packages..."
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    log "Installing missing packages: ${MISSING_PKGS[*]}"
    sudo apt update
    sudo apt install -y "${MISSING_PKGS[@]}"
fi

# Build and install/uninstall grub-customizer
WORKSPACE="/tmp/grub-customizer"

if [[ "$INSTALL_MODE" == "install" ]]; then
    log "Building grub-customizer..."
    rm -fr "$WORKSPACE"
    git clone "https://git.launchpad.net/grub-customizer" "$WORKSPACE"
    cd "$WORKSPACE"

    # Get the version from the changelog file
    VERSION=$(cat changelog | head -n1 | awk '{print $2}')
    INSTALL_PREFIX="/usr/local/grub-customizer-$VERSION"

    set_compiler_flags

    cmake -B build \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -G Ninja -Wno-dev

    ninja "-j$(nproc --all)" -C build
    sudo hwinfo
    sudo ninja -C build install

    sudo ln -sf "$INSTALL_PREFIX/bin/grub-customizer" "/usr/local/bin/grub-customizer"
    log "grub-customizer has been installed successfully."

    # Launch grub-customizer GUI if --gui argument is provided
    if [[ "$LAUNCH_GUI" == "true" ]]; then
        log "Launching grub-customizer GUI..."
        sudo grub-customizer
    fi
else
    log "Uninstalling grub-customizer..."
    sudo ninja -C "$WORKSPACE/build" uninstall
    sudo rm -fr "$INSTALL_PREFIX"
    sudo rm -f "/usr/local/bin/grub-customizer"
    log "grub-customizer has been uninstalled successfully."
fi

# Update grub configuration
if [[ "$INSTALL_MODE" == "install" ]]; then
    log "Updating grub configuration..."
    if ! sudo update-grub; then
        warn "Failed to update grub configuration."
    fi
fi

# Cleanup
if [[ "$CLEANUP" == "true" ]]; then
    log "Cleaning up build files and temporary workspace..."
    rm -fr "$WORKSPACE"
fi

echo
log "The script has completed."
