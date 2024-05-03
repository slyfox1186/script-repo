#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-git/
##  Purpose: Build git from source code
##  Script updated on: 05.02.24
##  Script version: 1.4

# Default values for arguments
compiler="gcc"
git_version=""
keep_build="false"
prefix="/usr/local/git-"
verbose="true"

# Colors for logging
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Function to display help menu
display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -v, --version      Set the Git version number for installation"
    echo "  -k, --keep         Keep build files post-execution (default: remove)"
    echo "  -c, --compiler     Set the compiler (default: gcc, alternative: clang)"
    echo "  -p, --prefix       Set the prefix used by configure (default: /usr/local/git-VERSION)"
    echo "  -n, --no-verbose   Suppress logging"
    echo "  -l, --list         List all available Git versions"
    echo "  -h, --help         Display this help menu"
}

# Function to parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                git_version="$2"
                shift 2
                ;;
            -k|--keep)
                keep_build=true
                shift
                ;;
            -c|--compiler)
                compiler="$2"
                shift 2
                ;;
            -p|--prefix)
                prefix="$2"
                shift 2
                ;;
            -n|--no-verbose)
                verbose=false
                shift
                ;;
            -l|--list)
                list_git_versions
                exit 0
                ;;
            -h|--help)
                display_help
                exit 0
                ;;
            *)
                echo -e "${RED}[fail]${NC} Invalid argument: $1"
                display_help
                exit 1
                ;;
        esac
    done
}

# Function to log messages
log() {
    if [[ "$verbose" == true ]]; then
        echo -e "${GREEN}[LOG]${NC} $1"
    fi
}

# Function to log warnings
warn() {
    if [[ "$verbose" == true ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

# Function to log errors
fail() {
    echo -e "${RED}[fail]${NC} $1"
    exit 1
}

# Function to retrieve the latest Git version number
get_latest_git_version() {
    if [[ -z "$git_version" ]]; then
        log "Retrieving the latest Git version number..."
        git_version=$(curl -fsSL "https://github.com/git/git/tags/" | grep -oP 'v\d+\.\d+\.\d+' | head -n1 | tr -d 'v')
        log "Latest Git version: $git_version"
    fi
}

# Function to list all available Git versions
list_git_versions() {
    log "Listing all available Git versions..."
    echo
    curl -fsSL "https://github.com/git/git/tags/" | grep -oP 'v\d+\.\d+\.\d+' | sort -ruV | sed 's/^v//'
}

# Function to install necessary dependencies for building Git
install_dependencies() {
    local missing_packages pkg pkgs
    log "Installing dependencies necessary for building Git from source..."
    echo
    pkgs=(cmake gettext libcurl4-gnutls-dev libexpat1-dev libssl-dev libz-dev "$compiler")
    for pkg in ${pkgs[@]}; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+="$pkg "
        fi
    done
    if [[ -n "$missing_packages" ]]; then
        sudo apt update
        sudo apt -y install $missing_packages
        log "Successfully installed build dependencies."
    fi
}

# Function to download, compile, and install Git from source
install_git() {
    log "Fetching Git source code (version: $git_version)..."
    cd /tmp || exit 1
    if [[ ! -f "git-$git_version.tar.gz" ]]; then
        sudo wget --show-progress -cqO "git-$git_version.tar.gz" "https://github.com/git/git/archive/refs/tags/v$git_version.tar.gz" || fail "Failed to download Git source code."
    else
        log "The source files have already been downloaded."
    fi

    log "Extracting Git source code..."
    if ! sudo tar -zxf "git-$git_version.tar.gz"; then
        sudo rm -f "git-$git_version.tar.gz"
        fail "Tar failed to extract the archive so it was deleted. Line: $LINENO"
    fi

    cd "git-$git_version" || exit 1
    
    log "Compiling Git from source. This may take a while..."
    prefix="$prefix$git_version"
    sudo make "-j$(nproc --all)" prefix="$prefix" all || fail "Compilation of Git failed. Line: $LINENO"
    
    log "Installing Git..."
    sudo make prefix="$prefix" install || fail "Failed to install Git. Line: $LINENO"
    echo
    log "Git has been successfully installed from source."
    echo
    log "Creating soft links from $prefix/bin to /usr/local/bin..."
    sudo ln -sf "$prefix/bin/git" /usr/local/bin/git
    sudo ln -sf "$prefix/bin/git-shell" /usr/local/bin/git-shell
    sudo ln -sf "$prefix/bin/git-upload-pack" /usr/local/bin/git-upload-pack
    sudo ln -sf "$prefix/bin/git-receive-pack" /usr/local/bin/git-receive-pack
}

# Function to clean up build files
clean_up() {
    if [[ $keep_build == false ]]; then
        log "Cleaning up build files..."
        sudo rm -rf "/tmp/git-$git_version" "/tmp/git-$git_version.tar.gz"
    else
        log "Keeping the build files as requested."
    fi
}

# Function to optimize the script
optimize_script() {
    CC="$compiler"
    CXX="$compiler++"
    CFLAGS="-O3 -pipe -fstack-protector-strong -fPIC -fPIE -D_FORTIFY_SOURCE=2 -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-z,relro,-z,now,-rpath,$prefix/lib"
    export CC CFLAGS CXX CXXFLAGS CPPFLAGS LDFLAGS
}

# Main function to control the flow of the script
main() {
    log "Starting the script to install Git from source."
    echo
    parse_arguments "$@"
    get_latest_git_version
    optimize_script
    install_dependencies
    install_git
    clean_up
}

# Calling the main function with command-line arguments
main "$@"

echo
log "Build completed successfully."
echo
log "Make sure to star this repository to show your support!"
log "https://github.com/slyfox1186/script-repo"
