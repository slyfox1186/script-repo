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
            pacman -Sy --noconfirm gcc clang
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

if type -P apt-get &>/dev/null; then
    find_clang_binaries
    find_gcc_binaries
    configure_alternatives_clang
    configure_alternatives_gcc
fi

echo "Setup completed based on selected options."
