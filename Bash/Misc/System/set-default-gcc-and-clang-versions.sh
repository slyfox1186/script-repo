#!/usr/bin/env bash

# This script finds and installs the highest available versions of GCC and Clang and sets them as default compilers.

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[32m'
RED='\033[31m'
NC='\033[0m' # No color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

update() {
    echo -e "${CYAN}[INFO]${NC} $1"
}
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to print the help menu
print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "This script identifies, installs, and sets the highest or a specific version of Clang or GCC as the default."
    echo
    echo "Options:"
    echo "  -cv, --clang-version VERSION  Set a specific version of Clang as the default."
    echo "  -gv, --gcc-version VERSION    Set a specific version of GCC as the default."
    echo "  -b,  --both                   Install and set both Clang and GCC (default if no -cv or -gv specified)."
    echo "  -h,  --help                   Display this help and exit."
    echo
    echo "Examples:"
    echo "  $0 -gv 11                    Install (if necessary) and set GCC 11 as the default version."
    echo "  $0 -cv 10                    Install (if necessary) and set Clang 10 as the default version."
    echo "  $0 -gv 11 -cv 10 -b          Install and set both GCC 11 and Clang 10 as the default versions."
}

# Default settings
install_clang=false
install_gcc=false
version_clang=""
version_gcc=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -cv|--clang-version)
            version_clang="$2"
            install_clang=true
            shift
            ;;
        -gv|--gcc-version)
            version_gcc="$2"
            install_gcc=true
            shift
            ;;
        -b|--both)
            install_clang=true
            install_gcc=true
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
    shift
done

# Determine default behavior based on provided arguments
if [[ "$install_clang" == false && "$install_gcc" == false ]]; then
    install_clang=true
    install_gcc=true
fi

# Function to detect available compiler versions and return the highest
find_highest_version() {
    local compiler highest_version
    local -a available_versions=()
    compiler="$1"
    highest_version=""

    available_versions=($(apt-cache search "^${compiler}-[0-9]+$" | grep -oP "${compiler}-\K\d+" | sort -nr))

    [[ ${#available_versions[@]} -gt 0 ]] && highest_version="${available_versions[0]}"

    echo "$highest_version"
}

# Detect package manager
detect_package_manager() {
    if command -v apt-get >/dev/null; then
        echo "apt"
    else
        echo "Unsupported package manager"
        exit 1
    fi
}

# Function to install and configure GCC or Clang
install_and_set_compiler() {
    local binary_base_path compiler pkg_manager version
    compiler="$1"
    version="$2"
    pkg_manager="$3"
    binary_base_path="/usr/bin/$compiler"

    [[ -z "$version" ]] && version=$(find_highest_version "$compiler" "$pkg_manager")

    echo
    if run_command "apt install -y $compiler-$version"; then
        if [[ "$compiler" == "gcc" ]]; then
            echo
            run_command "apt install -y g++-$version"
        fi
    fi

    # Set alternatives
    echo
    run_command "update-alternatives --install $binary_base_path $compiler $binary_base_path-$version 50"
    run_command "update-alternatives --set $compiler $binary_base_path-$version"
    echo

    # Set alternatives for the compiler++
    if [[ "$compiler" == "gcc" ]]; then
        run_command "update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-$version 50"
        run_command "update-alternatives --set g++ /usr/bin/g++-$version"
    elif [[ "$compiler" == "clang" ]]; then
        run_command "update-alternatives --install $binary_base_path++ clang++ $binary_base_path++-$version 50"
        run_command "update-alternatives --set clang++ $binary_base_path++-$version"
    fi
}

# Function to run commands and echo them
run_command() {
    local cmd
    cmd="$1"
    update "Running: $cmd"
    if ! eval "$cmd"; then
        error "Command failed: $cmd"
        exit 1
    fi
}

# Main execution
main() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)

    if [[ "$pkg_manager" == "Unsupported package manager" ]]; then
        error "The script does not support your package manager."
        exit 1
    fi

    [[ "$install_gcc" == true ]] && install_and_set_compiler "gcc" "$version_gcc" "$pkg_manager"
    [[ "$install_clang" == true ]] && install_and_set_compiler "clang" "$version_clang" "$pkg_manager"

    echo
    if [[ "$?" -eq 0 ]]; then
        log "The script completed successfully."
    else
        error "The script failed!"
    fi
}

main "$@"