#!/usr/bin/env bash

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

    [[ -z "$version" ]] && version=$(find_highest_version "$compiler")

    echo

    # Check for manually installed version first
    local manual_install_path=$(find /usr/local /usr/local/bin -name "${compiler}-${version}*" \( -type f -executable -o -type l \) | head -n1)
    if [[ -n "$manual_install_path" ]]; then
        log "Found manually installed $compiler-$version: $manual_install_path"
        binary_base_path="$manual_install_path"
    elif [[ -x "/usr/bin/$compiler-$version" ]]; then
        log "Found APT installed $compiler-$version in /usr/bin"
        binary_base_path="/usr/bin/$compiler-$version"
    else
        if run_command "apt install -y $compiler-$version"; then
            if [[ "$compiler" == "gcc" ]]; then
                echo
                run_command "apt install -y g++-$version"
            fi
            binary_base_path="/usr/bin/$compiler-$version"
        fi
    fi

    # Set alternatives
    echo
    run_command "update-alternatives --install /usr/bin/$compiler $compiler $binary_base_path 50"
    run_command "update-alternatives --set $compiler $binary_base_path"
    echo

    # Set alternatives for the compiler++
    if [[ "$compiler" == "gcc" ]]; then
        local gpp_path="${binary_base_path/gcc/g++}"
        if [[ ! -x "$gpp_path" ]]; then
            gpp_path="$(dirname "$binary_base_path")/g++-$version"
        fi
        if [[ ! -x "$gpp_path" ]]; then
            gpp_path=$(find /usr/local /usr/local/bin /usr/bin -name "g++-${version}*" \( -type f -executable -o -type l \) | head -n1)
        fi
        if [[ -x "$gpp_path" ]]; then
            run_command "update-alternatives --install /usr/bin/g++ g++ $gpp_path 50"
            run_command "update-alternatives --set g++ $gpp_path"
        else
            error "g++ not found. Please ensure g++-$version is installed."
        fi
    elif [[ "$compiler" == "clang" ]]; then
        local clangpp_path="${binary_base_path%%-*}++-${binary_base_path##*-}"
        if [[ -x "$clangpp_path" ]]; then
            run_command "update-alternatives --install /usr/bin/clang++ clang++ $clangpp_path 50"
            run_command "update-alternatives --set clang++ $clangpp_path"
        else
            error "clang++ not found at $clangpp_path"
        fi
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
