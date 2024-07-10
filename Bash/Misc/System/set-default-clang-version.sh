#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

update() {
    echo -e "${CYAN}[UPDATE]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to find the highest version of a compiler
find_highest_version() {
    local compiler="$1"
    local highest_version=""
    local -a versions=()

    # Check APT versions
    versions+=($(apt-cache search "^${compiler}-[0-9]+$" | grep -oP "${compiler}-\K\d+" | sort -Vr))

    # Check manually installed versions in various locations
    local dirs=("/usr/local" "/usr/local/bin")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local manual_versions=($(find "$dir" -name "${compiler}-[0-9]*" \( -type f -executable -o -type l \) | grep -oP "${compiler}-\K[0-9]+(\.[0-9]+)*" | sort -Vr))
            versions+=("${manual_versions[@]}")
        fi
    done

    # Get the highest version
    highest_version=$(printf '%s\n' "${versions[@]}" | sort -Vr | head -n1)

    echo "$highest_version"
}

install_and_set_compiler() {
    local compiler="$1"
    local version="$2"
    local binary_base_path=""
    local cpp_binary_path=""
    local major_version="${version%%.*}"  # Extract major version number

    [[ -z "$version" ]] && version=$(find_highest_version "$compiler")
    major_version="${version%%.*}"

    log "Setting up $compiler version $version"

    if [[ "$compiler" == "gcc" ]]; then
        log "Searching for gcc-$major_version and g++-$major_version"
        
        # Prioritize /usr/bin directly
        if [[ -x "/usr/bin/gcc-$major_version" ]]; then
            binary_base_path="/usr/bin/gcc-$major_version"
        else
            # Exclude ccache directories
            binary_base_path=$(find /usr -type f -executable -name "gcc-$major_version" ! -path "*/ccache/*" -print -quit 2>/dev/null)
        fi
        
        if [[ -x "/usr/bin/g++-$major_version" ]]; then
            cpp_binary_path="/usr/bin/g++-$major_version"
        else
            cpp_binary_path=$(find /usr -type f -executable -name "g++-$major_version" ! -path "*/ccache/*" -print -quit 2>/dev/null)
        fi

        if [[ -z "$binary_base_path" ]]; then
            log "gcc-$major_version not found, searching for gcc"
            binary_base_path=$(find /usr -type f -executable -name "gcc" ! -path "*/ccache/*" -print -quit 2>/dev/null)
            cpp_binary_path=$(find /usr -type f -executable -name "g++" ! -path "*/ccache/*" -print -quit 2>/dev/null)
        fi
    else
        log "Searching for clang-$major_version and clang++-$major_version"
        
        # Use readlink to determine the correct paths and exclude ccache
        binary_base_path=$(readlink -f "$(which clang-$major_version 2>/dev/null)" | grep -v "ccache")
        cpp_binary_path=$(readlink -f "$(which clang++-$major_version 2>/dev/null)" | grep -v "ccache")

        if [[ -z "$binary_base_path" ]]; then
            log "clang-$major_version not found, searching for clang"
            binary_base_path=$(readlink -f "$(which clang 2>/dev/null)" | grep -v "ccache")
            cpp_binary_path=$(readlink -f "$(which clang++ 2>/dev/null)" | grep -v "ccache")
        fi
    fi

    if [[ -n "$binary_base_path" ]]; then
        log "Found $compiler-$major_version: $binary_base_path"
        [[ -x "$cpp_binary_path" ]] && log "Found ${compiler}++-$major_version: $cpp_binary_path"
    else
        error "Could not find $compiler-$major_version. Please ensure it is installed."
        error "Searched for executables excluding ccache directories."
        return 1
    fi

    # Verify that the binaries exist and are executable
    if [[ ! -x "$binary_base_path" ]]; then
        error "The $compiler binary $binary_base_path does not exist or is not executable."
        return 1
    fi

    if [[ ! -x "$cpp_binary_path" ]]; then
        error "The ${compiler}++ binary $cpp_binary_path does not exist or is not executable."
        return 1
    fi

    # Set alternatives for C compiler
    update-alternatives --remove-all "$compiler" 2>/dev/null || true
    update-alternatives --install "/usr/bin/$compiler" "$compiler" "$binary_base_path" 100
    update-alternatives --set "$compiler" "$binary_base_path"
    warn "Set $compiler-$major_version as default"

    # Set alternatives for C++ compiler
    local cpp_compiler="${compiler}++"
    update-alternatives --remove-all "$cpp_compiler" 2>/dev/null || true
    update-alternatives --install "/usr/bin/$cpp_compiler" "$cpp_compiler" "$cpp_binary_path" 100
    update-alternatives --set "$cpp_compiler" "$cpp_binary_path"
    warn "Set $cpp_compiler-$major_version as default"

    log "Successfully set $compiler-$major_version and ${compiler}++-$major_version as default"
    echo ""  # Add a blank line for spacing between compiler setups
}

install_and_set_compiler() {
    local compiler="$1"
    local version="$2"
    local binary_base_path=""
    local cpp_binary_path=""
    local major_version="${version%%.*}"  # Extract major version number

    [[ -z "$version" ]] && version=$(find_highest_version "$compiler")
    major_version="${version%%.*}"

    log "Setting up $compiler version $version"

    if [[ "$compiler" == "gcc" ]]; then
        log "Searching for gcc-$major_version and g++-$major_version"
        
        # Prioritize /usr/bin directly
        if [[ -x "/usr/bin/gcc-$major_version" ]]; then
            binary_base_path="/usr/bin/gcc-$major_version"
            log "Found gcc-$major_version in /usr/bin: $binary_base_path"
        else
            # Exclude ccache directories
            binary_base_path=$(find /usr -type f -executable -name "gcc-$major_version" ! -path "*/ccache/*" -print -quit 2>/dev/null)
            log "Searching for gcc-$major_version excluding ccache: $binary_base_path"
        fi
        
        if [[ -x "/usr/bin/g++-$major_version" ]]; then
            cpp_binary_path="/usr/bin/g++-$major_version"
            log "Found g++-$major_version in /usr/bin: $cpp_binary_path"
        else
            cpp_binary_path=$(find /usr -type f -executable -name "g++-$major_version" ! -path "*/ccache/*" -print -quit 2>/dev/null)
            log "Searching for g++-$major_version excluding ccache: $cpp_binary_path"
        fi

        if [[ -z "$binary_base_path" ]]; then
            log "gcc-$major_version not found, searching for gcc"
            binary_base_path=$(find /usr -type f -executable -name "gcc" ! -path "*/ccache/*" -print -quit 2>/dev/null)
            log "Searching for gcc excluding ccache: $binary_base_path"
            cpp_binary_path=$(find /usr -type f -executable -name "g++" ! -path "*/ccache/*" -print -quit 2>/dev/null)
            log "Searching for g++ excluding ccache: $cpp_binary_path"
        fi
    else
        log "Searching for clang-$major_version and clang++-$major_version"
        
        # Use readlink to determine the correct paths and exclude ccache
        binary_base_path=$(readlink -f "$(which clang-$major_version 2>/dev/null)" | grep -v "ccache")
        log "Searching for clang-$major_version excluding ccache: $binary_base_path"
        cpp_binary_path=$(readlink -f "$(which clang++-$major_version 2>/dev/null)" | grep -v "ccache")
        log "Searching for clang++-$major_version excluding ccache: $cpp_binary_path"

        if [[ -z "$binary_base_path" ]]; then
            log "clang-$major_version not found, searching for clang"
            binary_base_path=$(readlink -f "$(which clang 2>/dev/null)" | grep -v "ccache")
            log "Searching for clang excluding ccache: $binary_base_path"
            cpp_binary_path=$(readlink -f "$(which clang++ 2>/dev/null)" | grep -v "ccache")
            log "Searching for clang++ excluding ccache: $cpp_binary_path"
        fi
    fi

    if [[ -n "$binary_base_path" ]]; then
        log "Found $compiler-$major_version: $binary_base_path"
        [[ -x "$cpp_binary_path" ]] && log "Found ${compiler}++-$major_version: $cpp_binary_path"
    else
        error "Could not find $compiler-$major_version. Please ensure it is installed."
        error "Searched for executables excluding ccache directories."
        return 1
    fi

    # Verify that the binaries exist and are executable
    if [[ ! -x "$binary_base_path" ]]; then
        error "The $compiler binary $binary_base_path does not exist or is not executable."
        return 1
    fi

    if [[ ! -x "$cpp_binary_path" ]]; then
        error "The ${compiler}++ binary $cpp_binary_path does not exist or is not executable."
        return 1
    fi

    # Set alternatives for C compiler
    update-alternatives --remove-all "$compiler" 2>/dev/null || true
    update-alternatives --install "/usr/bin/$compiler" "$compiler" "$binary_base_path" 100
    update-alternatives --set "$compiler" "$binary_base_path"
    warn "Set $compiler-$major_version as default"

    # Set alternatives for C++ compiler
    local cpp_compiler="${compiler}++"
    update-alternatives --remove-all "$cpp_compiler" 2>/dev/null || true
    update-alternatives --install "/usr/bin/$cpp_compiler" "$cpp_compiler" "$cpp_binary_path" 100
    update-alternatives --set "$cpp_compiler" "$cpp_binary_path"
    warn "Set $cpp_compiler-$major_version as default"

    log "Successfully set $compiler-$major_version and ${compiler}++-$major_version as default"
    echo ""  # Add a blank line for spacing between compiler setups
}

# Main execution
main() {
    install_and_set_compiler "gcc" "12.4.0" || exit 1
    install_and_set_compiler "clang" "" || exit 1

    log "The script completed successfully."
}

main "$@"
