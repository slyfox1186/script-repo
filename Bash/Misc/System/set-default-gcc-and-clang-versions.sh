#!/usr/bin/env bash

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
    echo "  -c                           Only install and set Clang."
    echo "  -g                           Only install and set GCC."
    echo "  -b                           Install and set both Clang and GCC (default if no -c or -g specified)."
    echo "  -h, --help                   Display this help and exit."
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

# Function to determine the package manager
detect_package_manager() {
    if command -v apt-get >/dev/null; then
        echo "apt"
    elif command -v yum >/dev/null; then
        echo "yum"
    elif command -v pacman >/dev/null; then
        echo "pacman"
    fi
}

# Function to get the highest available version of a compiler from the package manager
get_highest_version() {
    local compiler="$1"
    local pkg_manager=$(detect_package_manager)
    local highest_version=""
    case "$pkg_manager" in
        apt)
            highest_version=$(apt-cache search "^${compiler}-[0-9]+$" | cut -d' ' -f1 | grep -oP "${compiler}-\K[0-9]+" | sort -nr | head -n1)
            ;;
        yum)
            highest_version=$(yum list available | grep -oP "${compiler}[0-9]+" | cut -d'.' -f1 | sort -nr | head -n1)
            ;;
        pacman)
            highest_version=$(pacman -Ss "^${compiler}[0-9]+$" | grep -oP "${compiler}\K[0-9]+" | sort -nr | head -n1)
            ;;
    esac
    echo "$highest_version"
}

# Function to install and configure a specific compiler
install_and_configure_compiler() {
    local compiler="$1"
    local version="$2"
    if [[ -z "$version" ]]; then
        version=$(get_highest_version "$compiler")
        echo "No version specified for $compiler. Using highest available version: $version"
    fi
    local pkg_manager=$(detect_package_manager)
    local package_name="${compiler}-${version}"
    local gcc_package=""

    if [[ "$compiler" == "gcc" ]]; then
        gcc_package="g++-${version}"
    fi

    # Install compiler and possibly extra tools
    case "$pkg_manager" in
        apt)
            apt install -y "$package_name"
            [[ -n "$gcc_package" ]] && apt install -y "$gcc_package"
            ;;
        yum)
            yum install -y "$package_name"
            [[ -n "$gcc_package" ]] && yum install -y "$gcc_package"
            ;;
        pacman)
            pacman -Sy --noconfirm "$package_name"
            [[ -n "$gcc_package" ]] && pacman -Sy "$gcc_package"
            ;;
    esac

    # Update ccache symlinks after installation
    if type -P ccache &>/dev/null; then
        $(type -P update-ccache-symlinks)
    fi

    echo "${compiler} setup completed for version ${version}."
}

# Install and configure Clang if requested
if [[ "$install_clang" == true ]]; then
    install_and_configure_compiler "clang" "$version_clang"
fi

# Install and configure GCC if requested
if [[ "$install_gcc" == true ]]; then
    install_and_configure_compiler "gcc" "$version_gcc"
fi

echo "Setup completed based on selected options."
