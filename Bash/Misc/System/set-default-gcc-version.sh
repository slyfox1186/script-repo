#!/usr/bin/env bash

# Function to print the help menu
print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "This script identifies, installs, and sets the highest or a specific version of GCC as the default."
    echo ""
    echo "Options:"
    echo "  -v, --version VERSION  Set a specific version of GCC as the default."
    echo "  -h, --help             Display this help and exit."
    echo ""
    echo "Example:"
    echo "  $0 --version 11        Install (if necessary) and set GCC 11 as the default version."
}

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

# Function to find the appropriate gcc and g++ binaries, excluding any paths that contain 'ccache'
find_gcc_binaries() {
    local version=$1
    local search_paths=("/usr/bin" "/usr/local/bin" "/opt/bin")
    local gcc_path=""
    local gpp_path=""
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path/gcc-$version" ]]; then
            gcc_path="$path/gcc-$version"
        fi
        if [[ -f "$path/g++-$version" ]]; then
            gpp_path="$path/g++-$version"
        fi
    done
    
    if [[ -n "$gcc_path" && -n "$gpp_path" ]]; then
        echo "$gcc_path $gpp_path"
    else
        echo ""
    fi
}

# Function to install and configure gcc version if not already set
install_and_configure_gcc() {
    local version=$1
    local pkg_manager=$(detect_package_manager)
    case "$pkg_manager" in
        apt)
            sudo apt install -y "gcc-$version" "g++-$version"
            ;;
        yum)
            sudo yum install -y "gcc-$version" "gcc-c++-$version"
            ;;
        pacman)
            sudo pacman -Sy --noconfirm "gcc-$version"
            ;;
    esac
    local paths=$(find_gcc_binaries $version)
    if [[ -n "$paths" ]]; then
        configure_alternatives "$paths"
    else
        echo "No valid GCC or G++ binaries found for version $version."
    fi
    # Update ccache symlinks right after installation and configuration of GCC/G++
    if type -P ccache &>/dev/null; then
        sudo /usr/sbin/update-ccache-symlinks
    fi
}

# Function to configure alternatives for gcc
configure_alternatives() {
    local gcc_path gpp_path
    read -r gcc_path gpp_path <<< "$1"
    if [[ -n $gcc_path && -n $gpp_path ]]; then
        sudo update-alternatives --install /usr/bin/gcc gcc $gcc_path 50
        sudo update-alternatives --install /usr/bin/g++ g++ $gpp_path 50
        sudo update-alternatives --set gcc $gcc_path
        sudo update-alternatives --set g++ $gpp_path
    else
        if [[ -z $gcc_path ]]; then
            echo "Error: Missing path for GCC binary."
        fi
        if [[ -z $gpp_path ]]; then
            echo "Error: Missing path for G++ binary."
        fi
    fi
}

# Main script function
main() {
    local specific_version=""

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -v|--version)
                specific_version="$2"
                shift
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

    # Clear existing gcc and g++ alternatives
    sudo update-alternatives --remove-all gcc
    sudo update-alternatives --remove-all g++

    if [[ -n "$specific_version" ]]; then
        install_and_configure_gcc "$specific_version"
    else
        # Fallback to install and set the highest version available
        local available_versions=$(apt-cache search "^gcc-[0-9]+$" | cut -d' ' -f1 | grep -oP "gcc-\K[0-9]+")
        local highest_version=$(echo "$available_versions" | sort -nr | head -n1)
        install_and_configure_gcc "$highest_version"
    fi

    echo "GCC setup completed."
}

main "$@"
