#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

# Function to print the help menu
print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "This script identifies, installs, and sets the highest or a specific version of Clang as the default."
    echo ""
    echo "Options:"
    echo "  -v, --version VERSION  Set a specific version of Clang as the default."
    echo "  -h, --help             Display this help and exit."
    echo ""
    echo "Example:"
    echo "  $0 --version 11        Install (if necessary) and set Clang 11 as the default version."
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

# Function to find the appropriate clang and clang++ binaries, excluding any paths that contain 'ccache'
find_clang_binaries() {
    local version=$1
    local search_paths=("/usr/bin" "/usr/local/bin" "/opt/bin")
    local clang_path=""
    local clangpp_path=""
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path/clang-$version" ]]; then
            clang_path="$path/clang-$version"
        fi
        if [[ -f "$path/clang++-$version" ]]; then
            clangpp_path="$path/clang++-$version"
        fi
    done
    
    if [[ -n "$clang_path" && -n "$clangpp_path" ]]; then
        echo "$clang_path $clangpp_path"
    else
        echo ""
    fi
}

# Function to install and configure clang version if not already set
install_and_configure_clang() {
    local version=$1
    local pkg_manager=$(detect_package_manager)
    case "$pkg_manager" in
        apt)
            apt install -y "clang-$version"
            if apt-cache search "clang-$version-tools" | grep -q "clang-$version-tools"; then
                apt install -y "clang-$version-tools"
            elif apt-cache search "clang-tools-$version" | grep -q "clang-tools-$version"; then
                apt install -y "clang-tools-$version"
            fi
            ;;
        yum)
            yum install -y "clang-$version"
            if yum search "clang-tools-extra" | grep -q "clang-tools-extra"; then
                yum install -y "clang-tools-extra"
            fi
            ;;
        pacman)
            pacman -Sy --noconfirm "clang=$version"
            if pacman -Ss "clang-tools-extra" | grep -q "clang-tools-extra"; then
                pacman -Sy "clang-tools-extra"
            fi
            ;;
    esac
    local paths=$(find_clang_binaries $version)
    if [[ -n "$paths" ]]; then
        configure_alternatives "$paths"
    else
        echo "No valid Clang or Clang++ binaries found for version $version."
    fi
    # Update ccache symlinks right after installation and configuration of Clang/Clang++
    if type -P ccache &>/dev/null; then
        /usr/sbin/update-ccache-symlinks
    fi
}

# Function to configure alternatives for clang
configure_alternatives() {
    local clang_path clangpp_path
    read -r clang_path clangpp_path <<< "$1"
    if [[ -n $clang_path && -n $clangpp_path ]]; then
        update-alternatives --install /usr/bin/clang clang $clang_path 50
        update-alternatives --install /usr/bin/clang++ clang++ $clangpp_path 50
        update-alternatives --set clang $clang_path
        update-alternatives --set clang++ $clangpp_path
    else
        if [[ -z $clang_path ]]; then
            echo "Error: Missing path for Clang binary."
        fi
        if [[ -z $clangpp_path ]]; then
            echo "Error: Missing path for Clang++ binary."
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

    # Handle removal of existing alternatives with care to avoid errors
    update-alternatives --remove-all clang 2>/dev/null || echo "No alternatives for clang to remove."
    update-alternatives --remove-all clang++ 2>/dev/null || echo "No alternatives for clang++ to remove."

    if [[ -n "$specific_version" ]]; then
        install_and_configure_clang "$specific_version"
    else
        # Fallback to install and set the highest version available
        local available_versions=$(apt-cache search "^clang-[0-9]+$" | cut -d' ' -f1 | grep -oP "clang-\K[0-9]+")
        local highest_version=$(echo "$available_versions" | sort -nr | head -n1)
        install_and_configure_clang "$highest_version"
    fi

    echo "Clang setup completed."
}

main "$@"
