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
    echo "  -cv, --clang-version VERSION  Set a specific version of Clang as the default."
    echo "  -gv, --gcc-version VERSION    Set a specific version of GCC as the default."
    echo "  -b,  --both                   Install and set both Clang and GCC (default if no -cv or -gv specified)."
    echo "  -h,  --help                   Display this help and exit."
    echo ""
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
            echo "Unknown option: $1"
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
    local available_versions=()

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
    local compiler="$1"
    local version="$2"
    local pkg_manager="$3"
    local binary_base_path="/usr/bin/$compiler"

    [[ -z "$version" ]] && version=$(find_highest_version "$compiler" "$pkg_manager")

    apt install -y "$compiler-$version" && [[ "$compiler" == "gcc" ]] && apt install -y "g++-$version"

    # Set alternatives
    update-alternatives --install "$binary_base_path" "$compiler" "$binary_base_path-$version" 50
    update-alternatives --set "$compiler" "$binary_base_path-$version"

    # Set alternatives for the compiler++
    [[ "$compiler" == "gcc" ]] && update-alternatives --install "/usr/bin/g++" "g++" "/usr/bin/g++-$version" 50 && update-alternatives --set "g++" "/usr/bin/g++-$version"
    [[ "$compiler" == "clang" ]] && update-alternatives --install "$binary_base_path++" "clang++" "$binary_base_path++-$version" 50 && update-alternatives --set "clang++" "$binary_base_path++-$version"
}

# Main execution
main() {
    local pkg_manager=$(detect_package_manager)

    if [[ "$pkg_manager" == "Unsupported package manager" ]]; then
        echo "The script does not support your package manager."
        exit 1
    fi

    [[ "$install_gcc" == true ]] && install_and_set_compiler "gcc" "$version_gcc" "$pkg_manager"
    [[ "$install_clang" == true ]] && install_and_set_compiler "clang" "$version_clang" "$pkg_manager"

    if [[ "$?" -eq 0 ]]; then
        echo "Setup completed based on selected options."
    else
        echo "The setup failed based on the selected options"
    fi
}

main "$@"
