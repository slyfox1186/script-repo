#!/usr/bin/env bash

# This script finds and installs the highest available versions of GCC and Clang and sets them as default compilers.

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

# Function to print the help menu
print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "This script identifies, installs, and sets the highest or a specific version of Clang or GCC as the default."
    echo ""
    echo "Options:"
    echo "  -vc, --version-clang VERSION  Set a specific version of Clang as the default."
    echo "  -vg, --version-gcc VERSION    Set a specific version of GCC as the default."
    echo "  -c                            Only install and set Clang."
    echo "  -g                            Only install and set GCC."
    echo "  -b                            Install and set both Clang and GCC (default if no -c or -g specified)."
    echo "  -h, --help                    Display this help and exit."
    echo ""
    echo "Examples:"
    echo "  $0 -vg 11 -g                 Install (if necessary) and set GCC 11 as the default version."
    echo "  $0 -vc 10 -c                 Install (if necessary) and set Clang 10 as the default version."
    echo "  $0 -vg 11 -vc 10 -b          Install and set both GCC 11 and Clang 10 as the default versions."
}

# Default settings
install_clang=false
install_gcc=false
version_clang=""
version_gcc=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -vc|--version-clang) version_clang="$2"; shift ;;
        -vg|--version-gcc) version_gcc="$2"; shift ;;
        -c) install_clang=true ;;
        -g) install_gcc=true ;;
        -b) install_clang=true; install_gcc=true ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown option: $1"; print_help; exit 1 ;;
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
    local pkg_manager="$2"
    local highest_version=""
    local available_versions=()

    case "$pkg_manager" in
        apt)
            available_versions=($(apt-cache search "^${compiler}-[0-9]+$" | grep -oP "${compiler}-\K\d+" | sort -nr))
            ;;
        yum)
            available_versions=($(yum search "${compiler}" | grep -oP "${compiler}-\K\d+" | sort -nr))
            ;;
    esac

    if [ ${#available_versions[@]} -gt 0 ]; then
        highest_version="${available_versions[0]}"
    fi

    echo "$highest_version"
}

# Detect package manager
detect_package_manager() {
    if command -v apt-get >/dev/null; then
        echo "apt"
    elif command -v yum >/dev/null; then
        echo "yum"
    else
        echo "Unsupported package manager"
        exit 1
    fi
}

# Function to install and configure GCC or Clang
install_and_set_compiler() {
    local compiler="$1"
    local version="$2"
    local pkg_manager="$3"
    local binary_base_path="/usr/bin/$compiler"

    [[ -z "$version" ]] && version=$(find_highest_version "$compiler" "$pkg_manager")

    case "$pkg_manager" in
        apt)
            if [[ "$compiler" == "gcc" ]]; then
                apt install -y "$compiler-$version" "g++-$version"
            else
                apt install -y "$compiler-$version"
            fi
            ;;
        yum)
            if [[ "$compiler" == "gcc" ]]; then
                yum install -y "$compiler-$version" "g++-$version"
            else
                yum install -y "$compiler-$version"
            fi
            ;;
    esac

    # Set alternatives
    update-alternatives --install "$binary_base_path" "$compiler" "$binary_base_path-$version" 50
    update-alternatives --set "$compiler" "$binary_base_path-$version"

    # Set alternatives for the compiler++
    if [[ "$compiler" == "gcc" ]]; then
        update-alternatives --install "$binary_base_path++" "g++" "$binary_base_path++-$version" 50
        update-alternatives --set "g++" "$binary_base_path++-$version"
    elif [[ "$compiler" == "clang" ]]; then
        update-alternatives --install "$binary_base_path++" "clang++" "$binary_base_path++-$version" 50
        update-alternatives --set "clang++" "$binary_base_path++-$version"
    fi
}

# Main execution
main() {
    local pkg_manager=$(detect_package_manager)

    if [[ "$pkg_manager" == "Unsupported package manager" ]]; then
        echo "The script does not support your package manager."
        exit 1
    fi

    if [[ "$install_gcc" == true ]]; then
        install_and_set_compiler "gcc" "$version_gcc" "$pkg_manager"
    fi
    if [[ "$install_clang" == true ]]; then
        install_and_set_compiler "clang" "$version_clang" "$pkg_manager"
    fi

    echo "Setup completed based on selected options."
}

main "$@"
