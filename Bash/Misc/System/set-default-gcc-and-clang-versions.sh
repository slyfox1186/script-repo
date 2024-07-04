#!/usr/bin/env bash
set -x

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to print the help menu
print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "This script identifies, installs, and sets the highest or a specific version of Clang or GCC as the default."
    echo "gcc-14 is only considered if the -e or --enable-gcc14 option is passed."
    echo
    echo "Options:"
    echo "  -cv, --clang-version VERSION  Set a specific version of Clang as the default."
    echo "  -gv, --gcc-version VERSION    Set a specific version of GCC as the default."
    echo "  -b,  --both                   Install and set both Clang and GCC (default if no -cv or -gv specified)."
    echo "  -e,  --enable-gcc14           Enable gcc-14 as a valid option for GCC version."
    echo "  -h,  --help                   Display this help and exit."
    echo
    echo "Examples:"
    echo "  $0 -gv 11                    Install (if necessary) and set GCC 11 as the default version."
    echo "  $0 -cv 10                    Install (if necessary) and set Clang 10 as the default version."
    echo "  $0 -gv 14 -e                 Install and set GCC 14 as the default version (requires -e option)."
}

# Ensure required packages are installed
ensure_packages() {
    log "Updating package lists..."
    if ! apt-get update; then
        error "Failed to update package lists. Please check your internet connection and try again."
        exit 1
    fi

    local packages=("software-properties-common" "wget" "gnupg")
    for package in "${packages[@]}"; do
        if ! dpkg -s "$package" >/dev/null 2>&1; then
            log "Installing required package: $package"
            if ! apt-get install -y "$package"; then
                error "Failed to install $package. Please check your internet connection and try again."
                exit 1
            fi
        fi
    done
}

# Default settings
install_clang=false
install_gcc=false
version_clang=""
version_gcc=""
enable_gcc14=false

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
            if [[ "$version_gcc" -eq 14 && "$enable_gcc14" == false ]]; then
                error "gcc-14 is not a valid option unless -e or --enable-gcc14 is specified."
                exit 1
            fi
            install_gcc=true
            shift
            ;;
        -b|--both)
            install_clang=true
            install_gcc=true
            ;;
        -e|--enable-gcc14)
            enable_gcc14=true
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
    local compiler="$1"
    local highest_version=""
    local -a versions=()

    # Check APT versions
    if [[ "$compiler" == "gcc" && "$enable_gcc14" == false ]]; then
        versions+=($(apt-cache search "^${compiler}-[0-9]+$" | grep -oP "${compiler}-\K\d+" | grep -v "^14$" | sort -Vr))
    else
        versions+=($(apt-cache search "^${compiler}-[0-9]+$" | grep -oP "${compiler}-\K\d+" | sort -Vr))
    fi

    # Check manually installed versions in /usr/local and /usr/local/bin
    local manual_versions=($(find /usr/local /usr/local/bin -name "${compiler}-[0-9]*" \( -type f -executable -o -type l \) | grep -oP "${compiler}-\K[0-9]+(\.[0-9]+)*" | sort -Vr))
    versions+=("${manual_versions[@]}")

    # Get the highest version
    highest_version=$(printf '%s\n' "${versions[@]}" | sort -Vr | head -n1)

    echo "$highest_version"
}

# Function to install and configure GCC or Clang
install_and_set_compiler() {
    local binary_base_path compiler version
    compiler="$1"
    version="$2"
    binary_base_path="/usr/bin/$compiler"

    [[ -z "$version" ]] && version=$(find_highest_version "$compiler")

    log "Setting up $compiler version $version"

    # Check for manually installed version first
    local manual_install_path=$(find /usr/local /usr/local/bin -name "${compiler}-${version}*" \( -type f -executable -o -type l \) | head -n1)
    if [[ -n "$manual_install_path" ]]; then
        log "Found manually installed $compiler-$version: $manual_install_path"
        binary_base_path="$manual_install_path"
    elif [[ -x "/usr/bin/$compiler-$version" ]]; then
        log "Found APT installed $compiler-$version in /usr/bin"
        binary_base_path="/usr/bin/$compiler-$version"
    else
        log "Installing $compiler-$version"
        if ! apt-get install -y "$compiler-$version"; then
            error "Failed to install $compiler-$version. This version may not be available in the current repositories."
            return 1
        fi
        binary_base_path="/usr/bin/$compiler-$version"
    fi

    # Verify that the binary exists
    if [[ ! -x "$binary_base_path" ]]; then
        error "The $compiler binary $binary_base_path does not exist or is not executable."
        return 1
    fi

    # Set alternatives
    update-alternatives --remove-all "$compiler" 2>/dev/null || true
    update-alternatives --install "/usr/bin/$compiler" "$compiler" "$binary_base_path" 50
    update-alternatives --set "$compiler" "$binary_base_path"

    # Set alternatives for the compiler++
    if [[ "$compiler" == "gcc" ]]; then
        local gpp_path="$(dirname "$binary_base_path")/g++-$version"
        if [[ -x "$gpp_path" ]]; then
            update-alternatives --remove-all g++ 2>/dev/null || true
            update-alternatives --install /usr/bin/g++ g++ "$gpp_path" 50
            update-alternatives --set g++ "$gpp_path"
        else
            error "g++ not found. Please ensure g++-$version is installed."
            return 1
        fi
    elif [[ "$compiler" == "clang" ]]; then
        local clangpp_path="$(dirname "$binary_base_path")/clang++-$version"
        if [[ -x "$clangpp_path" ]]; then
            update-alternatives --remove-all clang++ 2>/dev/null || true
            update-alternatives --install /usr/bin/clang++ clang++ "$clangpp_path" 50
            update-alternatives --set clang++ "$clangpp_path"
        else
            error "clang++ not found. This version of clang may not include clang++."
            return 1
        fi
    fi

    log "Successfully set $compiler-$version as default"
}

# Main execution
main() {
    ensure_packages

    if [[ "$install_gcc" == true ]]; then
        install_and_set_compiler "gcc" "$version_gcc" || exit 1
    fi
    if [[ "$install_clang" == true ]]; then
        install_and_set_compiler "clang" "$version_clang" || exit 1
    fi

    log "The script completed successfully."
}

main "$@"
