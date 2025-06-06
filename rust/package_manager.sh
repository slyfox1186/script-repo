# Package management utilities - ADD TO SCRIPT

# Define package collections
declare -A PACKAGE_GROUPS=(
    [build_essential]="build-essential binutils make dpkg-dev"
    [gnu_tools]="gawk m4 flex bison texinfo patch"
    [download_tools]="curl wget ca-certificates"
    [build_optimization]="ccache"
    [autotools]="libtool libtool-bin autoconf automake"
    [dev_libraries]="zlib1g-dev libisl-dev libzstd-dev"
    [multilib_i386]="libc6-dev-i386"
)

# Get required packages based on configuration
get_required_packages() {
    local -a packages=()
    
    # Always required groups
    local required_groups=(
        "build_essential" "gnu_tools" "download_tools" 
        "build_optimization" "autotools" "dev_libraries"
    )
    
    # Add conditional groups
    if [[ "$enable_multilib_flag" -eq 1 && "$target_arch" == "x86_64-linux-gnu" ]]; then
        required_groups+=("multilib_i386")
    fi
    
    # Expand groups to individual packages
    for group in "${required_groups[@]}"; do
        if [[ -n "${PACKAGE_GROUPS[$group]}" ]]; then
            read -ra group_packages <<< "${PACKAGE_GROUPS[$group]}"
            packages+=("${group_packages[@]}")
        fi
    done
    
    printf '%s\n' "${packages[@]}" | sort -u
}

# Check package installation status efficiently
check_packages_installed() {
    local -a packages=("$@")
    local -a missing=()
    local -a installed=()
    
    # Single dpkg call for all packages
    local dpkg_output
    dpkg_output=$(dpkg-query -W -f='${Package} ${Status}\n' "${packages[@]}" 2>/dev/null || true)
    
    for package in "${packages[@]}"; do
        if echo "$dpkg_output" | grep -q "^$package.*ok installed"; then
            installed+=("$package")
        else
            missing+=("$package")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "INFO" "Missing packages: ${missing[*]}"
        echo "missing:${missing[*]}"
    fi
    
    if [[ ${#installed[@]} -gt 0 ]]; then
        log "DEBUG" "Installed packages: ${installed[*]}"
        echo "installed:${installed[*]}"
    fi
}

# Install packages with error handling
install_packages() {
    local -a packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log "INFO" "No packages to install"
        return 0
    fi
    
    log "INFO" "Installing packages: ${packages[*]}"
    
    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Dry run: would install ${packages[*]}"
        return 0
    fi
    
    # Update package list first
    execute_with_retry 2 5 sudo apt-get update
    
    # Install packages
    local apt_options=(
        "-y"
        "--no-install-recommends"
        "install"
    )
    
    DEBIAN_FRONTEND=noninteractive execute_with_retry 2 10 \
        sudo apt-get "${apt_options[@]}" "${packages[@]}"
}