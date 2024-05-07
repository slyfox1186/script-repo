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
    local version="$1"
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

# Function to find the appropriate gcc and g++ binaries, excluding any paths that contain 'ccache'
find_gcc_binaries() {
    local version="$1"
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

# Function to install and configure clang version if not already set
install_and_configure_clang() {
    local paths pkg_manager version
    version="$1"
    pkg_manager="$(detect_package_manager)"
    
    if [[ "$version" -eq 17 ]]; then
        paths=$(find_clang_binaries $version)
        if [[ -n "$paths" ]]; then
            configure_alternatives_clang "$paths"
        else
            echo "Clang version 17 binaries not found."
        fi
    else
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
        
        paths=$(find_clang_binaries $version)
        if [[ -n "$paths" ]]; then
            configure_alternatives_clang "$paths"
        else
            echo "No valid Clang or Clang++ binaries found for version $version."
        fi
    fi
    
    # Update ccache symlinks right after installation and configuration of Clang/Clang++
    if type -P ccache &>/dev/null; then
        /usr/sbin/update-ccache-symlinks
    fi
}

# Function to install and configure gcc version if not already set
install_and_configure_gcc() {
    local paths pkg_manager version
    version="$1"
    pkg_manager="$(detect_package_manager)"
    
    case "$pkg_manager" in
        apt)
            apt install -y "gcc-$version" "g++-$version"
            ;;
        yum)
            yum install -y "gcc-$version" "gcc-c++-$version"
            ;;
        pacman)
            pacman -Sy --noconfirm "gcc=$version"
            ;;
    esac
    
    paths=$(find_gcc_binaries $version)
    if [[ -n "$paths" ]]; then
        configure_alternatives_gcc "$paths"
    else
        echo "No valid GCC or G++ binaries found for version $version."
    fi
    
    # Update ccache symlinks right after installation and configuration of GCC/G++
    if type -P ccache &>/dev/null; then
        /usr/sbin/update-ccache-symlinks
    fi
}

# Function to configure alternatives for clang
configure_alternatives_clang() {
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

# Function to configure alternatives for gcc
configure_alternatives_gcc() {
    local gcc_path gpp_path
    read -r gcc_path gpp_path <<< "$1"
    if [[ -n $gcc_path && -n $gpp_path ]]; then
        update-alternatives --install /usr/bin/gcc gcc $gcc_path 50
        update-alternatives --install /usr/bin/g++ g++ $gpp_path 50
        update-alternatives --set gcc $gcc_path
        update-alternatives --set g++ $gpp_path
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
    # Handle removal of existing alternatives with care to avoid errors
    update-alternatives --remove-all clang 2>/dev/null || echo "No alternatives for clang to remove."
    update-alternatives --remove-all clang++ 2>/dev/null || echo "No alternatives for clang++ to remove."
    update-alternatives --remove-all gcc 2>/dev/null || echo "No alternatives for gcc to remove."
    update-alternatives --remove-all g++ 2>/dev/null || echo "No alternatives for g++ to remove."

    if [[ "$install_clang" == true ]]; then
        if [[ -n "$version_clang" ]]; then
            install_and_configure_clang "$version_clang"
        else
            for version in 17 16 15 14 13; do
                paths=$(find_clang_binaries $version)
                if [[ -n "$paths" ]]; then
                    install_and_configure_clang "$version"
                    break
                fi
            done
        fi
    fi

    if [[ "$install_gcc" == true ]]; then
        if [[ -n "$version_gcc" ]]; then
            install_and_configure_gcc "$version_gcc"
        else
            for version in 13 12 11 10; do
                paths=$(find_gcc_binaries $version)
                if [[ -n "$paths" ]]; then
                    install_and_configure_gcc "$version"
                    break
                fi
            done
        fi
    fi
}

main

echo
echo "Setup completed based on selected options."
