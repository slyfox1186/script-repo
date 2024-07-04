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

find_gcc_installation() {
    local version="$1"
    local major_version="${version%%.*}"  # Extract major version number
    local gcc_path=""

    # Search in common directories and their subdirectories
    local dirs=("/usr/local" "/usr/local/bin" "/usr/local/programs" "/opt")
    
    # First, search for symbolic links
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # Try to find exact major version symlink
            gcc_path=$(find "$dir" -name "gcc-$major_version" -type l -print -quit 2>/dev/null)
            [[ -n "$gcc_path" ]] && break

            # If exact version not found, try to find the closest match symlink
            if [[ -z "$gcc_path" ]]; then
                gcc_path=$(find "$dir" -name "gcc-$major_version*" -type l -print -quit 2>/dev/null)
                [[ -n "$gcc_path" ]] && break
            fi

            # If still not found, search for 'gcc' symlink in version-specific directories
            if [[ -z "$gcc_path" ]]; then
                gcc_path=$(find "$dir" -path "*/$major_version*/bin/gcc" -type l -print -quit 2>/dev/null)
                [[ -n "$gcc_path" ]] && break
            fi
        fi
    done

    # If no symlink found, search for real files
    if [[ -z "$gcc_path" ]]; then
        for dir in "${dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                # Try to find exact major version file
                gcc_path=$(find "$dir" -name "gcc-$major_version" -type f -executable -print -quit 2>/dev/null)
                [[ -n "$gcc_path" ]] && break

                # If exact version not found, try to find the closest match file
                if [[ -z "$gcc_path" ]]; then
                    gcc_path=$(find "$dir" -name "gcc-$major_version*" -type f -executable -print -quit 2>/dev/null)
                    [[ -n "$gcc_path" ]] && break
                fi

                # If still not found, search for 'gcc' file in version-specific directories
                if [[ -z "$gcc_path" ]]; then
                    gcc_path=$(find "$dir" -path "*/$major_version*/bin/gcc" -type f -executable -print -quit 2>/dev/null)
                    [[ -n "$gcc_path" ]] && break
                fi
            fi
        done
    fi

    # If still not found, try a system-wide search for symlinks first, then files
    if [[ -z "$gcc_path" ]]; then
        gcc_path=$(find / -name "gcc-$major_version" -type l -print -quit 2>/dev/null)
        if [[ -z "$gcc_path" ]]; then
            gcc_path=$(find / -name "gcc-$major_version" -type f -executable -print -quit 2>/dev/null)
        fi
    fi

    echo "$gcc_path"
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
        binary_base_path=$(find_gcc_installation "$version")
        cpp_binary_path="${binary_base_path/gcc/g++}"
    else
        # For clang, search in bin directories
        local search_dirs=("/usr/local" "/usr" "/opt")
        for dir in "${search_dirs[@]}"; do
            binary_base_path=$(find "$dir" -path "*/bin/${compiler}-${major_version}*" -type l -print -quit 2>/dev/null)
            [[ -n "$binary_base_path" ]] && break
        done

        if [[ -z "$binary_base_path" ]]; then
            for dir in "${search_dirs[@]}"; do
                binary_base_path=$(find "$dir" -path "*/bin/${compiler}-${major_version}*" -type f -executable -print -quit 2>/dev/null)
                [[ -n "$binary_base_path" ]] && break
            done
        fi
        cpp_binary_path="${binary_base_path/clang/clang++}"
    fi

    if [[ -n "$binary_base_path" ]]; then
        log "Found $compiler-$major_version: $binary_base_path"
        [[ -x "$cpp_binary_path" ]] && log "Found ${compiler}++-$major_version: $cpp_binary_path"
    elif [[ -x "/usr/bin/$compiler-$major_version" ]]; then
        log "Found APT installed $compiler-$major_version in /usr/bin"
        binary_base_path="/usr/bin/$compiler-$major_version"
        cpp_binary_path="/usr/bin/${compiler}++-$major_version"
        [[ -x "$cpp_binary_path" ]] && log "Found APT installed ${compiler}++-$major_version in /usr/bin"
    else
        error "Could not find $compiler-$major_version. Please ensure it is installed."
        error "Searched for symlinks and executables in /usr/local/bin, /usr/bin, and /opt/*/bin."
        error "If installed in a non-standard location, please specify the full path."
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
    update-alternatives --set "$cpp_compiler" "$cpp_compiler_path"
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
