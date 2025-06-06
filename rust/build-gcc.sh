#!/usr/bin/env bash
# shellcheck disable=SC2162 source=/dev/null

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc.sh
# Purpose: Build GNU GCC
# GCC versions available: 10-15
# Features: Automatically sources the latest release of each version.
# Updated: 06.02.2025
# Script version: 1.8

build_dir="/tmp/gcc-build-script"
packages="$build_dir/packages"
workspace="$build_dir/workspace"
default_target_arch="x86_64-linux-gnu" # Default, can be overridden by detected pc_type
target_arch="" # Will be set by pc_type
debug_mode=0
declare -a selected_versions=()
dry_run=0
enable_multilib_flag=0 # Renamed to avoid conflict with --enable-multilib configure option
keep_build_dir=0
log_file=""
optimization_level="-O3"
save_binaries=0
static_build=0
verbose=0
generic_build=0
user_prefix=""
pc_type="" # Will be auto-detected or use default_target_arch
cuda_check=""

# Available major GCC versions
versions=(10 11 12 13 14 15)

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color

# Logging function - defined early since it's used in variable initialization
log() {
    local level=$1
    shift
    local message=$*
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color_prefix=""
    local nc_suffix=""

    # Determine if we are writing to a tty for console output
    if [[ -t 3 || (-n "$log_file" && "$verbose" -eq 1) ]]; then # Check original stdout or if logging to file but verbose
        case "$level" in
            DEBUG) color_prefix="$CYAN" ;;
            INFO) color_prefix="$GREEN" ;;
            WARNING) color_prefix="$YELLOW" ;;
            ERROR) color_prefix="$RED" ;;
        esac
        nc_suffix="$NC"
    fi

    local log_line="[$level $timestamp] $message"
    
    # Log to file if specified
    if [[ -n "$log_file" ]]; then
        echo "$log_line" >> "$log_file"
    fi

    # Log to original stdout/stderr based on level and verbosity
    case "$level" in
        DEBUG)
            if [[ "$debug_mode" -eq 1 ]]; then
                echo -e "${color_prefix}${log_line}${nc_suffix}" >&3
            fi
            ;;
        INFO)
            if [[ "$verbose" -eq 1 || "$debug_mode" -eq 1 ]]; then
                echo -e "${color_prefix}${log_line}${nc_suffix}" >&3
            fi
            ;;
        WARNING)
            echo -e "${color_prefix}${log_line}${nc_suffix}" >&4 # Warnings always to stderr
            ;;
        ERROR)
            echo -e "${color_prefix}${log_line}${nc_suffix}" >&4 # Errors always to stderr
            ;;
    esac
}

# Utility functions for efficiency
create_directory() {
    local dir="$1" description="${2:-directory}" use_sudo="${3:-false}"
    [[ "$dry_run" -eq 1 ]] && { log "INFO" "Dry run: would create $description: $dir"; return 0; }
    local cmd="mkdir -p"; [[ "$use_sudo" == "true" ]] && cmd="sudo $cmd"
    $cmd "$dir" || fail "Failed to create $description: $dir"
}

create_directories() {
    local failed_dirs=()
    for dir in "$@"; do mkdir -p "$dir" 2>/dev/null || failed_dirs+=("$dir"); done
    [[ ${#failed_dirs[@]} -gt 0 ]] && fail "Failed to create directories: ${failed_dirs[*]}"
}

# GCC configure options data (eliminates massive duplication)
get_gcc_configure_options() {
    local major_version="$1" install_prefix="$2"
    
    # Base options for all versions
    local base_options=(
        "--prefix=$install_prefix"
        "--build=$target_arch" "--host=$target_arch" "--target=$target_arch"
        "--enable-languages=all" "--disable-bootstrap" "--enable-checking=release"
        "--disable-nls" "--enable-shared" "--enable-threads=posix"
        "--with-system-zlib" "--with-isl=/usr"
        "--program-suffix=-$major_version" "--with-gcc-major-version-only"
    )
    
    # Multilib option
    if [[ "$enable_multilib_flag" -eq 1 ]]; then
        base_options+=("--enable-multilib")
    else
        base_options+=("--disable-multilib")
    fi
    
    # Version-specific features (data-driven)
    case "$major_version" in
        9|10|11) base_options+=("--enable-default-pie" "--enable-gnu-unique-object") ;;
        12) base_options+=("--enable-default-pie" "--enable-gnu-unique-object" "--with-link-serialization=2") ;;
        13|14|15) base_options+=("--enable-default-pie" "--enable-gnu-unique-object" "--with-link-serialization=2" "--enable-cet") ;;
    esac
    
    # CUDA support
    [[ -n "$cuda_check" ]] && base_options+=("$cuda_check")
    
    printf '%s\n' "${base_options[@]}"
}

# Ensure pc_type and target_arch are set early
# Try to determine the system's architecture triplet
pc_type=$(gcc -dumpmachine 2>/dev/null)
if [[ -z "$pc_type" ]]; then
    # Fallback if gcc is not available or fails to report
    log "WARNING" "Could not auto-detect machine type using 'gcc -dumpmachine'."
    # Attempt to get it from 'cc'
    pc_type=$(cc -dumpmachine 2>/dev/null)
    if [[ -z "$pc_type" ]]; then
        log "WARNING" "Could not auto-detect machine type using 'cc -dumpmachine'. Using default: $default_target_arch"
        pc_type="$default_target_arch"
    else
        log "INFO" "Auto-detected machine type using 'cc -dumpmachine': $pc_type"
    fi
else
    log "INFO" "Auto-detected machine type using 'gcc -dumpmachine': $pc_type"
fi
target_arch="$pc_type" # Use detected pc_type as the target architecture

echo "Initial dry_run value: $dry_run" >&2
log "INFO" "Machine type (pc_type/target_arch) set to: $target_arch"

setup_logging() {
    if [[ -n "$log_file" ]]; then
        # Create log directory if it doesn't exist
        mkdir -p "$(dirname "$log_file")" || fail "Failed to create log directory: $(dirname "$log_file")"
        # Clear existing log file
        : > "$log_file" || fail "Failed to create log file: $log_file"
        # Redirect stderr to log file as well
        exec 3>&1 4>&2 # Save original stdout and stderr
        exec 1>> "$log_file"
        exec 2>> "$log_file"
        log "INFO" "Logging started to $log_file. Original stdout/stderr saved."
    fi
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  --debug                    Enable debug mode (set -x, logs every executed command)"
    echo "  --dry-run                  Perform a dry run without making any changes"
    echo "  --enable-multilib          Enable multilib support for GCC (passed to GCC's configure)"
    echo "  --static                   Build static GCC executables"
    echo "  -g, --generic              Use generic tuning instead of native for GCC build"
    echo "  -k, --keep-build-dir       Keep the temporary build directory after completion"
    echo "  -l, --log-file FILE        Specify a log file for output (redirects stdout & stderr)"
    echo "  -O LEVEL                   Set optimization level for building GCC (0, 1, 2, 3, fast, g, s). Default: 2"
    echo "  -p, --prefix DIR           Set the installation prefix (default: /usr/local/programs/gcc-<version>)"
    echo "  -s, --save                 Save static binaries (only works with --static)"
    echo "  -v, --verbose              Enable verbose logging to stdout/stderr (if not logging to file)"
    echo
    exit 0
}



fail() {
    log "ERROR" "$1"
    log "ERROR" "To report a bug, create an issue at: ${CYAN}https://github.com/slyfox1186/script-repo/issues${NC}"
    # If logging to file, also print error to original stderr
    if [[ -n "$log_file" ]]; then
        echo -e "${RED}[ERROR $(date +"%Y-%m-%d %H:%M:%S")] $1${NC}" >&4
        echo -e "${RED}View $log_file for more details.${NC}" >&4
    fi
    # Perform cleanup if keep_build_dir is not set, to avoid leaving partial builds
    if [[ "$keep_build_dir" -ne 1 && -d "$build_dir" ]]; then
        log "INFO" "Attempting to cleanup $build_dir due to failure..."
        sudo rm -rf "$build_dir"
    fi
    exit 1
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --debug)
                debug_mode=1
                set -x # Enable shell debug mode
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --enable-multilib)
                enable_multilib_flag=1 # This is for the GCC configure script
                shift
                ;;
            -g|--generic)
                generic_build=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            -k|--keep-build-dir)
                keep_build_dir=1
                shift
                ;;
            -l|--log-file)
                if [[ -z "$2" ]]; then
                    fail "Log file path is missing for -l option."
                fi
                # Check if directory is writable, or can be created
                local log_dir
                log_dir=$(dirname "$2")
                if [[ ! -d "$log_dir" ]]; then
                    if mkdir -p "$log_dir"; then
                        log "INFO" "Created log directory: $log_dir"
                    else
                        fail "Log file directory does not exist and cannot be created: $log_dir"
                    fi
                elif [[ ! -w "$log_dir" ]]; then
                     fail "Log file directory is not writable: $log_dir"
                fi

                if [[ -f "$2" && ! -w "$2" ]]; then
                     fail "Log file exists but is not writable: $2"
                elif [[ -f "$2" ]]; then
                    # This warning will go to console before redirection if log_file is not yet set
                    echo -e "${YELLOW}[WARNING] Log file already exists and will be overwritten: $2${NC}"
                fi
                log_file="$2"
                shift 2
                ;;
            -O)
                if [[ -z "$2" ]]; then
                    fail "Optimization level is missing for -O option."
                fi
                case "$2" in
                    0|1|2|3|fast|g|s)
                        optimization_level="-O$2"
                        ;;
                    *)
                        fail "Invalid optimization level: $2. Valid values are: 0, 1, 2, 3, fast, g, s"
                        ;;
                esac
                shift 2
                ;;
            -p|--prefix)
                if [[ -z "$2" ]]; then
                    fail "Prefix directory is missing for -p option."
                fi
                if [[ ! "$2" =~ ^/ ]]; then
                    fail "Prefix must be an absolute path starting with '/'. Value: $2"
                fi
                # Check if parent of prefix is writable, or if prefix itself is writable if it exists
                local prefix_path="$2"
                local prefix_parent
                prefix_parent=$(dirname "$prefix_path")
                if [[ -d "$prefix_path" ]]; then
                    if [[ ! -w "$prefix_path" ]]; then
                        fail "Prefix directory exists but is not writable: $prefix_path. Check permissions or run with sudo for 'make install' if needed (script itself should not be sudo)."
                    fi
                elif [[ ! -w "$prefix_parent" ]]; then
                    fail "Parent directory of prefix is not writable: $prefix_parent. Cannot create $prefix_path."
                fi
                user_prefix="$2"
                shift 2
                ;;
            -s|--save)
                save_binaries=1
                shift
                ;;
            --static)
                static_build=1
                shift
                ;;
            -v|--verbose)
                verbose=1
                shift
                ;;
            *)
                fail "Unknown option: $1. Use -h or --help for usage information."
                ;;
        esac
    done
    if [[ "$save_binaries" -eq 1 && "$static_build" -eq 0 ]]; then
        fail "The --save option can only be used with --static."
    fi
}

# This debug function is for BASH_COMMAND trap
bash_debug_trap() {
    # Log to file if specified, otherwise to original stderr
    local log_target="$log_file"
    [[ -z "$log_target" ]] && log_target="/dev/stderr"
    echo "[SHELL_DEBUG $(date +"%I:%M:%S %p")] Executing: ${BASH_COMMAND}" >> "$log_target"
}


verbose_logging_cmd() { # Renamed to avoid conflict
    local retval output
    local cmd_string="$*"

    log "DEBUG" "Executing command: $cmd_string"

    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Dry run: would execute: $cmd_string"
        return 0
    fi

    # For actual execution, redirect command's own stdout/stderr to main log (if active) or pass through
    if [[ "$debug_mode" -eq 1 ]]; then
        # Debug mode: Show command, let output go to current stdout/stderr (which might be log file)
        echo "+ $cmd_string" # Mimic set -x
        if ! "$@"; then
            retval=$?
            fail "Command failed with exit code $retval: $cmd_string"
        fi
    elif [[ "$verbose" -eq 1 && -z "$log_file" ]]; then # Verbose to console, not to file
        # Verbose mode: Show command, show output only on error
        echo "+ $cmd_string" >&3 # Show command on original stdout
        if ! output=$("$@" 2>&1); then
            retval=$?
            echo "$output" >&4 # Show output on original stderr
            fail "Command failed with exit code $retval: $cmd_string"
        fi
    else # Normal mode or verbose with log file (output already going to log)
        if ! output=$("$@" 2>&1); then
            retval=$?
            # Output is already in $output variable, log it before failing
            log "ERROR" "Command output on failure:\n$output"
            fail "Command failed with exit code $retval: $cmd_string"
        else
            # Log command output if verbose and logging to file
            [[ "$verbose" -eq 1 && -n "$log_file" ]] && log "DEBUG" "Command output:\n$output"
        fi
    fi
    return 0
}


set_path() {
    log "INFO" "Setting PATH and optimizing ccache..."
    # Prepend ccache and workspace bin to PATH
    PATH="/usr/lib/ccache:$workspace/bin:$PATH"
    export PATH
    
    # Optimize ccache for GCC builds
    export CCACHE_MAXSIZE="10G"
    export CCACHE_COMPRESS=1
    export CCACHE_SLOPPINESS="time_macros,include_file_mtime"
    ccache -M 10G >/dev/null 2>&1 || true  # Don't fail if ccache not available
    
    log "DEBUG" "Updated PATH: $PATH"
    log "DEBUG" "ccache configured: 10GB max, compression enabled"
}

set_pkg_config_path() {
    log "INFO" "Setting PKG_CONFIG_PATH..."
    local new_pkg_config_path
    # Common paths
    new_pkg_config_path="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    # CUDA paths (if relevant)
    new_pkg_config_path+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    # Arch-specific paths
    new_pkg_config_path+=":/usr/lib/$target_arch/pkgconfig" # Use detected target_arch
    if [[ "$target_arch" == "x86_64-linux-gnu" ]]; then # Add common cross-compile/multiarch paths if primary is x86_64
        new_pkg_config_path+=":/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    fi
    
    export PKG_CONFIG_PATH="$new_pkg_config_path${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" # Prepend new paths
    log "DEBUG" "Updated PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
}

set_environment() {
    log "INFO" "Setting build environment variables..."
    
    # Base CFLAGS
    CFLAGS="$optimization_level -pipe"
    CXXFLAGS="$optimization_level -pipe"
    
    # Add architecture-specific flags
    if [[ "$generic_build" -eq 0 ]]; then
        # Check if march=native is supported by the current compiler
        if gcc -v --help 2>&1 | grep -q 'march=native'; then
            CFLAGS+=" -march=native"
            CXXFLAGS+=" -march=native"
        else
            log "WARNING" "-march=native not supported by current GCC, using generic tuning."
        fi
        # mtune=native is often implied by march=native or can be omitted if causing issues.
        # For simplicity, let's rely on march=native or generic.
    fi
    
    CFLAGS+=" -fstack-protector-strong"
    CXXFLAGS+=" -fstack-protector-strong"
    
    CPPFLAGS="-D_FORTIFY_SOURCE=2"

    # Base LDFLAGS, common for static and dynamic
    LDFLAGS="-Wl,-z,relro -Wl,-z,now"
    # Add library path for the target architecture if it's standard
    if [[ -d "/usr/lib/$target_arch" ]]; then
         LDFLAGS+=" -L/usr/lib/$target_arch"
    elif [[ -d "/usr/lib64" && "$target_arch" == *64* ]]; then # Fallback for systems like Fedora
         LDFLAGS+=" -L/usr/lib64"
    elif [[ -d "/usr/lib" ]]; then
         LDFLAGS+=" -L/usr/lib"
    fi

    if [[ "$static_build" -eq 1 ]]; then
        LDFLAGS="-static $LDFLAGS" # Prepend -static
    fi

    CC="gcc" # Use system gcc for bootstrapping if needed, or the one being built
    CXX="g++"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS

    log "DEBUG" "CC=$CC, CXX=$CXX"
    log "DEBUG" "CFLAGS=$CFLAGS"
    log "DEBUG" "CXXFLAGS=$CXXFLAGS"
    log "DEBUG" "CPPFLAGS=$CPPFLAGS"
    log "DEBUG" "LDFLAGS=$LDFLAGS"

    # CUDA check for offload targets
    # Prefer command -v for checking nvcc
    if command -v nvcc &>/dev/null; then
        local nvcc_path
        nvcc_path=$(command -v nvcc)
        cuda_check="--enable-offload-targets=nvptx-none" # Generic, specific target might need nvcc path
        # cuda_check="--enable-offload-targets=nvptx-none=$(dirname "$(dirname "$nvcc_path")")" # Example if path needed
        log "INFO" "CUDA (nvcc) found at $nvcc_path. Enabling nvptx offload target."
    else
        cuda_check=""
        log "INFO" "CUDA (nvcc) not found. nvptx offload target will not be configured."
    fi
}

verify_checksum() {
    local file version expected_checksum actual_checksum sig_url
    file=$1
    version=$2 # Full version string e.g., 13.2.0
    local major_version="${version%%.*}" # e.g. 13

    # GCC 15+ uses GPG signatures, not plaintext checksums
    if [[ "$major_version" -ge "15" ]]; then
        log "INFO" "GCC $version uses GPG signature verification instead of plaintext checksums."
        return 2  # Return 2 for "skipped" instead of 0
    elif [[ "$major_version" == "14" ]]; then
        log "INFO" "Checksum verification for GCC $version (major version $major_version) might use a different signature format or not be available in the old format."
        log "INFO" "Attempting to find a .sha512 file first."
        local sha512_url="https://ftp.gnu.org/gnu/gcc/gcc-${version}/sha512.sum"
        if expected_checksum=$(curl -fsSL "$sha512_url" | grep "gcc-${version}.tar.xz" | awk '{print $1}'); then
             if [[ -n "$expected_checksum" ]]; then
                log "INFO" "Found SHA512 checksum for $file from $sha512_url"
             else
                log "WARNING" "Could not retrieve SHA512 checksum from $sha512_url for GCC $version."
                log "WARNING" "Skipping checksum verification for GCC $version due to potentially new/different signature format."
                return 2  # Return 2 for "skipped" instead of 0
             fi
        else
            log "WARNING" "Could not retrieve SHA512 checksum from $sha512_url for GCC $version."
            log "WARNING" "Skipping checksum verification for GCC $version due to potentially new/different signature format."
            return 2  # Return 2 for "skipped" instead of 0
        fi
    else
        # Traditional .sig file for SHA512
        sig_url="https://ftp.gnu.org/gnu/gcc/gcc-${version}/gcc-${version}.tar.xz.sig"
        log "INFO" "Attempting to retrieve SHA512 checksum from signature file: $sig_url"
        if ! expected_checksum_line=$(curl -fsSL "$sig_url"); then
            log "WARNING" "Could not retrieve signature file from $sig_url for GCC $version."
            log "WARNING" "Proceeding without checksum verification."
            return 2  # Return 2 for "skipped" instead of 0
        fi

        # Try to parse the SHA512 sum from the .sig file (format can vary slightly)
        expected_checksum=$(echo "$expected_checksum_line" | grep -oP '(?<=SHA512 CHECKSUM: )[a-f0-9]+' || echo "$expected_checksum_line" | grep -oP '^[a-f0-9]{128}')
        
        if [[ -z "$expected_checksum" ]]; then
            log "WARNING" "No SHA512 checksum found in the signature file: $sig_url"
            log "WARNING" "Content of sig file:\n$expected_checksum_line"
            log "WARNING" "Proceeding without checksum verification for GCC $version."
            return 2  # Return 2 for "skipped" instead of 0
        fi
        log "INFO" "Found expected SHA512 checksum for $file: $expected_checksum"
    fi

    log "INFO" "Calculating SHA512 checksum for local file: $file"
    actual_checksum=$(sha512sum "$file" | awk '{print $1}')
    log "INFO" "Actual SHA512 checksum: $actual_checksum"

    if [[ "$expected_checksum" != "$actual_checksum" ]]; then
        fail "Checksum mismatch for $file. Expected: $expected_checksum, Actual: $actual_checksum"
    else
        log "INFO" "Checksum verified successfully for $file."
    fi
    return 0
}


check_system_resources() {
    log "INFO" "Checking system resources..."
    # Overall basic check (can be run early)
    local required_ram_mb=2000 # Minimum RAM in MB
    local available_ram_mb
    available_ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ "$available_ram_mb" -lt "$required_ram_mb" ]]; then
        fail "Insufficient RAM. Required: ${required_ram_mb}MB, Available: ${available_ram_mb}MB"
    fi
    log "INFO" "Available RAM: ${available_ram_mb}MB (Required: ${required_ram_mb}MB)"

    # Disk space check specifically for the build directory partition
    # This is a more general check; a more specific one is done per GCC version later.
    local required_disk_gb_general=10 # Minimum free space in GB for /tmp or build_dir parent
    local build_dir_parent
    build_dir_parent=$(dirname "$build_dir")
    local available_disk_gb
    available_disk_gb=$(df -BG "$build_dir_parent" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ "$available_disk_gb" -lt "$required_disk_gb_general" ]]; then
        fail "Insufficient disk space in $build_dir_parent. Required: ${required_disk_gb_general}G, Available: ${available_disk_gb}G"
    fi
    log "INFO" "Available disk space in $build_dir_parent: ${available_disk_gb}G (General minimum: ${required_disk_gb_general}G)"
}

check_disk_space_for_selected_versions() {
    [[ "${#selected_versions[@]}" -eq 0 ]] && { log "WARNING" "No versions selected, skipping disk space check."; return; }

    log "INFO" "Checking disk space for selected GCC versions..."
    local required_per_version=25 safety_margin=5 total_required available_space
    total_required=$((required_per_version * ${#selected_versions[@]} + safety_margin))
    available_space=$(df -BG "$build_dir" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    log "INFO" "Required: ${total_required}GB, Available: ${available_space}GB for ${#selected_versions[@]} version(s)"
    
    # Early failure if insufficient space
    [[ $available_space -lt $total_required ]] && fail "Insufficient disk space: need ${total_required}GB, have ${available_space}GB"
    
    # Warning if tight on space
    local recommended=$((total_required + total_required / 10))
    [[ $available_space -lt $recommended ]] && log "WARNING" "Tight on disk space. Recommended: ${recommended}GB"
    
    log "INFO" "Disk space check passed."
}


trim_binaries() {
    local bin_dir install_dir version
    version=$1 # Full version string
    if [[ -z "$user_prefix" ]]; then
        install_dir="/usr/local/programs/gcc-$version"
    else
        install_dir="${user_prefix%/}/gcc-$version" # Remove trailing slash from user_prefix if any
    fi

    bin_dir="$install_dir/bin"
    log "INFO" "Trimming binary filenames in $bin_dir (removing $target_arch- prefix)"

    if [[ ! -d "$bin_dir" ]]; then
        log "WARNING" "Binary directory $bin_dir not found. Skipping trimming."
        return
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Dry run: would rename $target_arch-* binaries in $bin_dir"
        # Example of what would be logged for one file
        local example_file
        example_file=$(find "$bin_dir" -name "$target_arch-*" -print -quit)
        if [[ -n "$example_file" ]]; then
            local new_name_example="${example_file##*/}"
            new_name_example="${new_name_example#$target_arch-}"
            log "INFO" "Dry run example: would rename $example_file to $bin_dir/$new_name_example"
        fi
        return
    fi

    # Ensure target_arch is not empty to prevent accidentally renaming all files
    if [[ -z "$target_arch" ]]; then
        log "ERROR" "target_arch is not set. Cannot trim binaries safely. Skipping."
        return
    fi

    pushd "$bin_dir" >/dev/null || { log "ERROR" "Failed to cd into $bin_dir"; return; }
    for file in "$target_arch"-*; do
        if [[ -f "$file" || -L "$file" ]]; then # Handle files and symlinks
            local new_name="${file#$target_arch-}"
            # Check if a file with the new name already exists and is not a symlink to the current file
            if [[ -e "$new_name" && "$file" != "$(readlink -f "$new_name")" ]]; then
                log "WARNING" "File $new_name already exists and is not the target of $file. Skipping rename of $file."
            else
                log "INFO" "Renaming $file to $new_name"
                if sudo mv "$file" "$new_name"; then
                    log "INFO" "Renamed $file to $new_name successfully."
                else
                    log "ERROR" "Failed to rename $file to $new_name."
                fi
            fi
        fi
    done
    popd >/dev/null
}

save_static_binaries() {
    local install_dir save_dir version
    version=$1 # Full version string
    local short_version="${version%%.*}" # e.g. 13

    if [[ -z "$user_prefix" ]]; then
        install_dir="/usr/local/programs/gcc-$version"
    else
        install_dir="${user_prefix%/}/gcc-$version"
    fi

    save_dir="$PWD/gcc-${version}-static-binaries"

    if [[ "$static_build" -eq 1 && "$save_binaries" -eq 1 ]]; then
        log "INFO" "Saving static binaries from $install_dir/bin to $save_dir"
        if [[ "$dry_run" -eq 1 ]]; then
            log "INFO" "Dry run: would create $save_dir and copy static binaries into it."
            return
        fi
        
        create_directory "$save_dir" "save directory"

        # Define core programs to save, ensure they use the program-suffix if applicable
        # The program-suffix is -$short_version. The program-prefix is $target_arch-
        # After trimming, the prefix is gone.
        local programs_to_save=(
            "cpp-$short_version" "g++-$short_version" "gcc-$short_version"
            "gcc-ar-$short_version" "gcc-nm-$short_version" "gcc-ranlib-$short_version"
            "gcov-$short_version" "gcov-dump-$short_version" "gcov-tool-$short_version"
            # Add other language compilers if built and static
            # These might not all be present or relevant depending on --enable-languages
            "gfortran-$short_version"
            # "gnat-$short_version" # Ada related, often not built by default or needs specific setup
            # "go-$short_version" "gccgo-$short_version" # Go related
            # "lto-dump-$short_version" # LTO related
        )
        # Add target-prefixed versions IF they exist and before trimming was done or if suffix only applied
        # However, save_static_binaries runs AFTER trim_binaries, so we look for trimmed names + suffix

        local copied_count=0
        local not_found_count=0
        for program_base_name in "${programs_to_save[@]}"; do
            local source_file="$install_dir/bin/$program_base_name"
            if [[ -f "$source_file" ]]; then
                if verbose_logging_cmd sudo cp -f "$source_file" "$save_dir/"; then
                    log "INFO" "Copied $program_base_name to $save_dir"
                    ((copied_count++))
                else
                    log "WARNING" "Failed to copy $source_file to $save_dir"
                fi
            else
                log "WARNING" "Static binary not found (or not expected): $source_file"
                ((not_found_count++))
            fi
        done

        if [[ "$copied_count" -gt 0 ]]; then
            log "INFO" "Successfully saved $copied_count static binaries to $save_dir"
        else
            log "WARNING" "No static binaries were copied. Searched for $not_found_count files."
        fi
        [[ "$not_found_count" -gt 0 ]] && log "INFO" "$not_found_count expected binaries were not found (this may be normal depending on enabled languages)."
    fi
}

download_source_file() {
    local url file version
    url=$1
    file=$(basename "$url")
    # version=$(echo "$file" | grep -oP 'gcc-\K[0-9.]+(?=\.tar\.[a-z]+)') # version is passed directly now
    version=$2 # Expect full version string e.g. 13.2.0
    local max_attempts=3
    local attempt=1
    local download_path="$build_dir/$file"

    log "INFO" "Preparing to download $file for GCC $version."

    while [[ $attempt -le $max_attempts ]]; do
        log "INFO" "Download attempt $attempt of $max_attempts for $file."
        # Check if file exists and is valid (simple tar -tf check)
        if [[ -f "$download_path" ]]; then
            log "INFO" "File $download_path already exists. Verifying integrity..."
            if tar -tf "$download_path" &>/dev/null; then
                log "INFO" "Existing file $download_path seems valid. Skipping download."
                # Optional: Add checksum verification here too for existing files
                if [[ "$dry_run" -eq 0 ]]; then
                    local checksum_result
                    verify_checksum "$download_path" "$version"
                    checksum_result=$?
                    
                    case $checksum_result in
                        0) log "INFO" "Checksum for existing file $download_path verified successfully."
                           return 0 ;;
                        1) log "WARNING" "Checksum verification failed for existing file $download_path. Will attempt re-download."
                           rm -f "$download_path" || { log "ERROR" "Failed to remove corrupted existing file: $download_path"; return 1; } ;;
                        2) return 0 ;;  # Accept file when verification is unavailable
                        *) log "ERROR" "Unknown checksum verification result: $checksum_result"
                           return 1 ;;
                    esac
                else
                    log "INFO" "Dry run: Would verify checksum for existing file $download_path"
                    return 0
                fi
            else
                log "WARNING" "Existing file $download_path appears to be corrupted. Removing and retrying download..."
                if [[ "$keep_build_dir" -eq 0 || "$dry_run" -eq 0 ]]; then # Remove if not keeping or not dry run
                    rm -f "$download_path" || { log "ERROR" "Failed to remove corrupted existing file: $download_path"; return 1; }
                else
                    log "WARNING" "Keeping corrupted file $download_path due to -k flag. Please remove manually and try again."
                    return 1
                fi
            fi
        fi # End of existing file check

        # File does not exist or was removed, proceed to download
        if [[ ! -f "$download_path" ]]; then
            log "INFO" "Downloading $file from $url ..."
            if [[ "$dry_run" -eq 1 ]]; then
                log "INFO" "Dry run: would download $url to $download_path"
                return 0 # Simulate successful download for dry run
            fi
            # Use wget with progress, timeout, and continue options
            # -T for timeout, -c for continue
            if ! wget --progress=bar:force:noscroll -T 60 -c -O "$download_path" "$url"; then
                log "WARNING" "Download attempt $attempt for $file failed (wget exit code: $?)."
                if [[ "$keep_build_dir" -eq 0 ]]; then
                    # Remove partial download if not keeping build dir
                    log "INFO" "Removing potentially partial download: $download_path"
                    rm -f "$download_path"
                else
                    log "WARNING" "Keeping potentially partial download $download_path due to -k flag."
                fi
                
                if [[ $attempt -eq $max_attempts ]]; then
                    fail "Failed to download $file after $max_attempts attempts. Please check network or URL: $url"
                fi
                log "INFO" "Retrying download in 5 seconds..."
                sleep 5
                ((attempt++))
                continue # Retry download
            else
                log "INFO" "Successfully downloaded $file."
                # Verify integrity of newly downloaded file
                if ! tar -tf "$download_path" &>/dev/null; then
                    log "WARNING" "Downloaded file $download_path is corrupted after successful wget."
                     if [[ "$keep_build_dir" -eq 0 ]]; then
                        log "INFO" "Removing corrupted download: $download_path"
                        rm -f "$download_path"
                    else
                        log "WARNING" "Keeping corrupted download $download_path due to -k flag."
                    fi
                    if [[ $attempt -eq $max_attempts ]]; then
                         fail "Failed to download a valid $file after $max_attempts attempts (corrupted after download)."
                    fi
                    log "INFO" "Retrying download for corrupted file..."
                    sleep 2
                    ((attempt++))
                    continue # Retry download
                else
                    log "INFO" "Downloaded file $download_path integrity verified (tar -tf)."
                    # Perform checksum verification
                    local checksum_result
                    verify_checksum "$download_path" "$version"
                    checksum_result=$?
                    
                    case $checksum_result in
                        0) log "INFO" "Checksum verification passed for downloaded file $download_path"
                           return 0 ;;
                        1) fail "Checksum verification failed for downloaded file $download_path" ;;
                        2) return 0 ;;  # Accept download when verification is unavailable  
                        *) fail "Unknown checksum verification result: $checksum_result" ;;
                    esac
                fi
            fi
        fi # End of ! -f download_path
    done # End of while loop

    # Should not be reached if download succeeds or fails definitively
    fail "Failed to download $file after $max_attempts attempts (unexpected state)."
}


create_symlinks() {
    local version=$1 # Full version string
    local short_version="${version%%.*}"
    local install_dir symlink_target_dir
    
    if [[ -z "$user_prefix" ]]; then
        install_dir="/usr/local/programs/gcc-$version"
    else
        install_dir="${user_prefix%/}/gcc-$version"
    fi

    symlink_target_dir="/usr/local/bin" # Standard location for user-installed symlinks

    if [[ ! -d "$install_dir/bin" ]]; then
        log "WARNING" "Installation binary directory $install_dir/bin not found for GCC $version. Cannot create symlinks."
        return
    fi

    log "INFO" "Creating symlinks in $symlink_target_dir for GCC $version executables from $install_dir/bin..."
    log "INFO" "Note: Symlinks will be like 'gcc' (pointing to gcc-$short_version if suffix was used and trimmed) or 'gcc-$short_version'."

    # Ensure symlink target directory exists and is writable by current user (or sudo will handle it)
    if [[ ! -d "$symlink_target_dir" ]]; then
        log "WARNING" "$symlink_target_dir does not exist. Attempting to create."
        # Try creating with sudo, as /usr/local/bin often requires it
        if ! verbose_logging_cmd sudo mkdir -p "$symlink_target_dir"; then
            log "ERROR" "Failed to create symlink target directory $symlink_target_dir. Check permissions."
            return
        fi
    fi
     if [[ ! -w "$symlink_target_dir" ]]; then
        log "INFO" "$symlink_target_dir is not writable by current user. Sudo will be used for symlinks."
    fi


    local symlink_count=0
    local created_symlinks=()
    local skipped_symlinks=0

    # Iterate over executables in the installation's bin directory
    # We expect binaries to be named e.g. gcc-13, g++-13 after --program-suffix and trimming
    pushd "$install_dir/bin" >/dev/null || { log "ERROR" "Failed to cd to $install_dir/bin"; return; }
    for executable_in_path in * ; do
        if [[ -f "$executable_in_path" && -x "$executable_in_path" ]]; then
            # Determine the base name for the symlink
            # e.g., if file is "gcc-13", symlink could be "gcc" or "gcc-13"
            # If file is "gcov-tool-13", symlink could be "gcov-tool" or "gcov-tool-13"
            local base_symlink_name="${executable_in_path%-$short_version}" # try removing suffix "gcc-13" -> "gcc"
            
            # If removing suffix results in empty name or same name (no suffix), use original name
            if [[ -z "$base_symlink_name" || "$base_symlink_name" == "$executable_in_path" ]]; then
                 base_symlink_name="$executable_in_path" # e.g. for 'gfortran' if it was an unsuffixed binary
            fi

            # Create symlink without version suffix if it makes sense (e.g. gcc, g++)
            # Also create versioned symlink (e.g. gcc-13)
            local symlinks_to_try=()
            symlinks_to_try+=("$base_symlink_name") # e.g., gcc
            if [[ "$base_symlink_name" != "$executable_in_path" ]]; then # if "gcc" is different from "gcc-13"
                symlinks_to_try+=("$executable_in_path") # e.g., gcc-13
            fi
            
            # Deduplicate
            symlinks_to_try=($(printf "%s\n" "${symlinks_to_try[@]}" | sort -u))

            for symlink_name in "${symlinks_to_try[@]}"; do
                local symlink_path="$symlink_target_dir/$symlink_name"
                # Check if a conflicting file/symlink already exists
                if [[ -e "$symlink_path" && ! -L "$symlink_path" ]]; then
                    log "WARNING" "A non-symlink file already exists at $symlink_path. Skipping symlink creation for $symlink_name."
                    ((skipped_symlinks++))
                    continue
                fi
                # If it's a symlink, check if it already points to the correct executable
                if [[ -L "$symlink_path" && "$(readlink -f "$symlink_path")" == "$(readlink -f "$executable_in_path")" ]]; then
                    log "INFO" "Symlink $symlink_path already exists and points to the correct executable. Skipping."
                    ((skipped_symlinks++))
                    continue
                fi

                if [[ "$dry_run" -eq 1 ]]; then
                    log "INFO" "Dry run: would create/update symlink: sudo ln -sf $install_dir/bin/$executable_in_path $symlink_path"
                    ((symlink_count++))
                else
                    log "INFO" "Creating symlink: $symlink_path -> $install_dir/bin/$executable_in_path"
                    if verbose_logging_cmd sudo ln -sf "$install_dir/bin/$executable_in_path" "$symlink_path"; then
                        created_symlinks+=("$symlink_path")
                        ((symlink_count++))
                    else
                        log "ERROR" "Failed to create symlink $symlink_path"
                    fi
                fi
            done
        fi
    done
    popd >/dev/null

    if [[ "$symlink_count" -gt 0 ]]; then
        log "INFO" "Created/updated $symlink_count symlinks for GCC $version in $symlink_target_dir."
        [[ "$verbose" -eq 1 && ${#created_symlinks[@]} -gt 0 ]] && log "DEBUG" "Symlinks: ${created_symlinks[*]}"
    else
        log "INFO" "No new symlinks were created for GCC $version."
    fi
    [[ "$skipped_symlinks" -gt 0 ]] && log "INFO" "$skipped_symlinks symlinks were skipped (e.g. already exist or conflict)."
}


install_dependencies() {
    log "INFO" "Checking and installing system dependencies..."
    
    # Optimized package list (data-driven)
    local base_pkgs="build-essential binutils gawk m4 flex bison texinfo patch curl wget ca-certificates ccache libtool libtool-bin autoconf automake zlib1g-dev libisl-dev libzstd-dev"
    local multilib_pkgs=""
    [[ "$enable_multilib_flag" -eq 1 && "$target_arch" == "x86_64-linux-gnu" ]] && multilib_pkgs="libc6-dev-i386"
    
    local required_pkgs="$base_pkgs $multilib_pkgs"
    read -ra pkg_array <<< "$required_pkgs"
    
    # Batch package check (much faster than individual checks)
    local installed_output missing_pkgs=()
    installed_output=$(dpkg-query -W -f='${Package} ${Status}\n' "${pkg_array[@]}" 2>/dev/null || true)
    
    for pkg in "${pkg_array[@]}"; do
        if ! echo "$installed_output" | grep -q "^$pkg.*ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ "${#missing_pkgs[@]}" -gt 0 ]]; then
        log "INFO" "Missing packages: ${missing_pkgs[*]}"
        if [[ "$dry_run" -eq 1 ]]; then
            log "INFO" "Dry run: would install ${missing_pkgs[*]}"
        else
            log "INFO" "Installing missing packages..."
            verbose_logging_cmd sudo apt-get update || fail "Failed to update package lists"
            verbose_logging_cmd sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing_pkgs[@]}" || fail "Failed to install packages: ${missing_pkgs[*]}"
            log "INFO" "Successfully installed missing packages."
        fi
    else
        log "INFO" "All required dependencies are installed."
    fi
}

get_latest_gcc_release_version() {
    local major_version=$1 # e.g., 13
    local cache_file="$build_dir/.gcc_version_cache"
    local cache_age_seconds=3600  # Cache for 1 hour

    # Create cache directory if it doesn't exist
    mkdir -p "$build_dir" || { log "ERROR" "Failed to create cache directory $build_dir"; return 1; }

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_timestamp current_time age
        cache_timestamp=$(stat -c %Y "$cache_file" 2>/dev/null || date +%s) # Get mod time or current if error
        current_time=$(date +%s)
        age=$((current_time - cache_timestamp))

        if [[ $age -lt $cache_age_seconds ]]; then
            # Use cached version if available for this major version
            local cached_release_version
            cached_release_version=$(grep "^gcc-${major_version}:" "$cache_file" | cut -d: -f2)
            if [[ -n "$cached_release_version" ]]; then
                log "INFO" "Using cached latest release for GCC $major_version: $cached_release_version (cache age: $age seconds)"
                echo "$cached_release_version"
                return 0
            fi
        else
            log "INFO" "Cache file $cache_file is stale (age: $age seconds). Refreshing."
        fi
    fi

    log "INFO" "Fetching latest release version for GCC $major_version from ftp.gnu.org..."
    local ftp_url="https://ftp.gnu.org/gnu/gcc/"
    local latest_release_version
    
    # Fetch directory listing, filter for gcc-MAJOR.MINOR.PATCH/, sort, and get the last one.
    # Regex matches gcc-MAJOR. (any digits for minor/patch) /
    # Example: gcc-13.2.0/
    # For GCC 15, which is not yet released, this might return nothing or an early dev snapshot.
    # The sed commands strip "gcc-" and the trailing "/"
    if ! listing=$(curl -fsSL "$ftp_url"); then
        log "ERROR" "Failed to fetch directory listing from $ftp_url"
        return 1
    fi

    latest_release_version=$(echo "$listing" | \
                            grep -oP "gcc-${major_version}[0-9.]+\/" | \
                            sed -e 's/gcc-//' -e 's/\///' | \
                            sort -V | \
                            tail -n1)

    if [[ -n "$latest_release_version" ]]; then
        log "INFO" "Latest release found for GCC $major_version: $latest_release_version"
        # Update cache: Remove old entry for this major version and add new one
        if [[ -f "$cache_file" ]]; then
            sed -i "/^gcc-${major_version}:/d" "$cache_file" # Remove old entry
        fi
        echo "gcc-${major_version}:$latest_release_version" >> "$cache_file"
        echo "$latest_release_version"
        return 0
    else
        log "ERROR" "Failed to determine the latest release for GCC $major_version from $ftp_url."
        # Specific warning for unreleased versions
        if [[ "$major_version" -ge 15 ]]; then # Assuming 15+ might not be out
            log "WARNING" "GCC $major_version may not be officially released yet, or the naming convention on the FTP site might have changed."
        fi
        return 1
    fi
}


post_build_cleanup_and_config() {
    local version_string=$1 # Full version e.g. 13.2.0
    local short_version="${version_string%%.*}" # e.g. 13
    local install_prefix
    if [[ -z "$user_prefix" ]]; then
        install_prefix="/usr/local/programs/gcc-$version_string"
    else
        install_prefix="${user_prefix%/}/gcc-$version_string"
    fi

    log "INFO" "Performing post-build tasks for GCC $version_string installed at $install_prefix..."

    # Run libtool --finish
    # Path for libexec varies: $install_prefix/libexec/gcc/$target_arch/$version_string or $install_prefix/libexec/gcc/$pc_type/$short_version
    # The actual path for libtool --finish is often where cc1, cc1plus etc. are.
    local libexec_subdir="$install_prefix/libexec/gcc/$target_arch/$version_string" # Common pattern
     if [[ ! -d "$libexec_subdir" ]]; then
        # Fallback to using short_version if full version_string dir doesn't exist
        libexec_subdir="$install_prefix/libexec/gcc/$target_arch/$short_version"
        if [[ ! -d "$libexec_subdir" ]]; then
            log "WARNING" "Could not find standard libexec directory for libtool --finish at $libexec_subdir or with full version string. Probing..."
            # More robustly find a likely candidate directory
            local candidate_dir
            candidate_dir=$(find "$install_prefix/libexec/gcc/" -mindepth 2 -maxdepth 2 -type d -name "$short_version" -print -quit || find "$install_prefix/libexec/gcc/" -mindepth 2 -maxdepth 2 -type d -name "$version_string" -print -quit)
            if [[ -n "$candidate_dir" && -d "$candidate_dir" ]]; then
                libexec_subdir="$candidate_dir"
                log "INFO" "Found candidate libexec dir: $libexec_subdir"
            else
                log "ERROR" "Failed to find a suitable directory for libtool --finish under $install_prefix/libexec/gcc/. Skipping libtool --finish."
                libexec_subdir="" # Ensure it's empty so we don't proceed
            fi
        fi
    fi

    if [[ -n "$libexec_subdir" && -d "$libexec_subdir" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            log "INFO" "Dry run: would run sudo libtool --finish $libexec_subdir"
        else
            log "INFO" "Running libtool --finish in $libexec_subdir"
            if ! verbose_logging_cmd sudo libtool --finish "$libexec_subdir"; then
                log "WARNING" "libtool --finish command failed for $libexec_subdir. This might or might not be critical."
            else
                log "INFO" "libtool --finish completed successfully for $libexec_subdir."
            fi
        fi
    else
        log "WARNING" "Skipped libtool --finish as a suitable directory was not found for GCC $version_string."
    fi

    # Update dynamic linker cache
    log "INFO" "Updating dynamic linker cache for GCC $version_string libraries..."
    local ld_conf_file="/etc/ld.so.conf.d/custom-gcc-$version_string.conf"
    local lib_path="$install_prefix/lib"
    local lib64_path="$install_prefix/lib64" # Common for 64-bit systems

    if [[ "$dry_run" -eq 1 ]]; then
        [[ -d "$lib_path" ]] && log "INFO" "Dry run: would add $lib_path to $ld_conf_file"
        [[ -d "$lib64_path" ]] && log "INFO" "Dry run: would add $lib64_path to $ld_conf_file"
        log "INFO" "Dry run: would run sudo ldconfig"
    else
        # Create/update ld.so.conf.d file
        # Ensure we have permissions to write to /etc/ld.so.conf.d/
        # Check if directory exists and is writable (usually requires sudo)
        if [[ ! -w "$(dirname "$ld_conf_file")" ]]; then
            log "INFO" "$(dirname "$ld_conf_file") is not writable by current user. Sudo will be used."
        fi
        
        # Clear existing conf file for this version to avoid duplicates if script re-run
        verbose_logging_cmd sudo rm -f "$ld_conf_file"

        local ld_paths_added=0
        if [[ -d "$lib_path" ]]; then
            if echo "$lib_path" | verbose_logging_cmd sudo tee -a "$ld_conf_file" >/dev/null; then
                log "INFO" "Added $lib_path to $ld_conf_file"
                ((ld_paths_added++))
            else
                log "ERROR" "Failed to add $lib_path to $ld_conf_file"
            fi
        fi
        if [[ -d "$lib64_path" ]]; then
             if echo "$lib64_path" | verbose_logging_cmd sudo tee -a "$ld_conf_file" >/dev/null; then
                log "INFO" "Added $lib64_path to $ld_conf_file"
                ((ld_paths_added++))
            else
                log "ERROR" "Failed to add $lib64_path to $ld_conf_file"
            fi
        fi

        if [[ "$ld_paths_added" -gt 0 ]]; then
            log "INFO" "Running ldconfig to update linker cache..."
            if ! verbose_logging_cmd sudo ldconfig; then
                log "ERROR" "sudo ldconfig failed. Dynamic linker cache might not be up-to-date."
            else
                log "INFO" "ldconfig completed successfully."
            fi
        else
            log "INFO" "No library paths found in $install_prefix/lib or $install_prefix/lib64. ld.so.conf.d file not created/updated."
        fi
    fi

    # Create symlinks for executables
    create_symlinks "$version_string"
    
    # Create additional soft links for pkgconfig files
    create_additional_pkgconfig_links "$install_prefix"
}

create_additional_pkgconfig_links() {
    local install_prefix="$1"
    local pkgconfig_source_dir="$install_prefix/lib/pkgconfig"
    local pkgconfig_target_dir="/usr/local/lib/pkgconfig" # A common place

    log "INFO" "Checking for pkg-config files in $pkgconfig_source_dir to link to $pkgconfig_target_dir."

    if [[ ! -d "$pkgconfig_source_dir" ]]; then
        log "INFO" "No pkgconfig directory found at $pkgconfig_source_dir. Skipping linking of .pc files."
        return
    fi
    
    if [[ "$dry_run" -eq 1 ]]; then
        # Count potential files for dry run log
        local pc_files_count
        pc_files_count=$(find "$pkgconfig_source_dir" -type f -name '*.pc' 2>/dev/null | wc -l)
        if [[ "$pc_files_count" -gt 0 ]]; then
            log "INFO" "Dry run: would find $pc_files_count .pc files in $pkgconfig_source_dir and attempt to symlink them to $pkgconfig_target_dir."
        else
            log "INFO" "Dry run: no .pc files found in $pkgconfig_source_dir."
        fi
        return
    fi

    # Ensure target directory exists
    if [[ ! -d "$pkgconfig_target_dir" ]]; then
        log "INFO" "Pkgconfig target directory $pkgconfig_target_dir does not exist. Attempting to create with sudo."
        verbose_logging_cmd sudo mkdir -p "$pkgconfig_target_dir" || {
            log "ERROR" "Failed to create pkgconfig target directory $pkgconfig_target_dir. Skipping .pc file linking."
            return
        }
    fi
    
    local linked_count=0
    find "$pkgconfig_source_dir" -type f -name '*.pc' | while IFS= read -r pc_file; do
        local base_name
        base_name=$(basename "$pc_file")
        local target_link="$pkgconfig_target_dir/$base_name"
        
        # Check if a conflicting file/symlink already exists
        if [[ -e "$target_link" && ! -L "$target_link" ]]; then
            log "WARNING" "A non-symlink file already exists at $target_link. Skipping symlink for $pc_file."
            continue
        fi
        if [[ -L "$target_link" && "$(readlink -f "$target_link")" == "$(readlink -f "$pc_file")" ]]; then
            log "INFO" "Pkgconfig symlink $target_link already exists and is correct. Skipping."
            continue
        fi

        log "INFO" "Linking $pc_file to $target_link"
        if verbose_logging_cmd sudo ln -sf "$pc_file" "$target_link"; then
            ((linked_count++))
        else
            log "ERROR" "Failed to link $pc_file to $target_link."
        fi
    done

    if [[ "$linked_count" -gt 0 ]]; then
        log "INFO" "Successfully linked $linked_count pkg-config (.pc) files to $pkgconfig_target_dir."
    else
        log "INFO" "No new pkg-config files were linked from $pkgconfig_source_dir."
    fi
}


build_status_log() {
    local package version status
    package=$1
    version=$2
    status=$3 # e.g., "SUCCESS", "FAILURE", "CONFIG_START", "BUILD_START", "INSTALL_START"
    log "INFO" "STATUS: Package: $package, Version: $version, Stage: $status"
}


# Simplified build function, mainly for autoconf if needed by a specific GCC version.
# The main GCC build is handled by build_gcc_version directly.
build_generic_package() {
    local package version
    package=$1
    version=$2
    # shift 2; local configure_opts=("$@") # If opts needed

    log "INFO" "Building generic package: $package $version (if required by GCC build)..."
    local package_build_dir="$workspace/$package-$version"
    local source_tarball="$package-$version.tar.xz" # Assuming .tar.xz
    local download_url="https_ftp_gnu_org_gnu_$package/$source_tarball" # Placeholder, adjust URL

    cd "$build_dir" || fail "Failed to change directory to $build_dir"

    # Example for autoconf (if needed)
    if [[ "$package" == "autoconf" ]]; then
        download_url="https://ftp.gnu.org/gnu/autoconf/autoconf-$version.tar.xz"
        if ! download_source_file "$download_url" "$version" ; then
             fail "Failed to download $package-$version.tar.xz"
        fi

        if [[ "$dry_run" -eq 1 ]]; then
            log "INFO" "Dry run: would extract $source_tarball and build $package"
            return 0
        fi
        
        # Clean up any previous build attempts for this package
        log "INFO" "Cleaning up previous build directory: $package_build_dir"
        rm -rf "$package_build_dir"
        verbose_logging_cmd tar -Jxf "$build_dir/$source_tarball" -C "$workspace" || fail "Failed to extract $source_tarball"
        
        cd "$package_build_dir" || fail "Failed to change directory to $package_build_dir"
        
        log "INFO" "Configuring $package $version..."
        # Configure to install into the workspace/bin, so it's in PATH for GCC build
        if ! verbose_logging_cmd ./configure --prefix="$workspace"; then
             fail "$package configure failed."
        fi
        
        log "INFO" "Making $package $version..."
        local workers
        workers=$(nproc --all 2>/dev/null || echo 2)
        if ! verbose_logging_cmd make "-j$workers"; then
            log "WARNING" "Parallel make for $package failed, trying single-threaded build..."
            if ! verbose_logging_cmd make; then
                fail "$package make failed."
            fi
        fi
        
        log "INFO" "Installing $package $version to $workspace..."
        if ! verbose_logging_cmd make install; then
            fail "$package make install failed."
        fi
        build_status_log "$package" "$version" "SUCCESS"
        log "INFO" "$package $version built and installed to $workspace successfully."
    else
        log "WARNING" "Generic build for package '$package' is not specifically implemented."
        return 1
    fi
    cd "$build_dir" # Return to base build dir
}


cleanup_temporary_folders() {
    if [[ "$keep_build_dir" -eq 1 ]]; then
        log "INFO" "Keeping temporary build folders in $build_dir as requested via -k or --keep-build-dir."
        return 0
    fi
    
    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Dry run: would remove temporary build directory $build_dir (except for logs if separate, and saved binaries)."
        return
    fi

    if [[ -d "$build_dir" ]]; then
        log "INFO" "Cleaning up temporary build directory: $build_dir..."
        # Be careful not to delete log file if it's inside build_dir (it shouldn't be by default)
        # or saved binaries if they were put there.
        # This removes the entire $build_dir. User should save binaries elsewhere or use -k.
        if sudo rm -rf "$build_dir"; then
            log "INFO" "Successfully removed temporary build directory $build_dir."
        else
            # Attempt to remove contents first if rm -rf on directory fails (e.g. due to busy sub-mount)
            log "WARNING" "Failed to remove $build_dir directly. Attempting to remove its contents..."
            if sudo find "$build_dir" -mindepth 1 -delete; then
                 sudo rm -rf "$build_dir" # Try removing the empty dir again
                 log "INFO" "Successfully removed contents of $build_dir."
            else
                fail "Failed to clean up temporary build directory $build_dir or its contents. Please remove it manually."
            fi
        fi
    else
        log "INFO" "Temporary build directory $build_dir not found. No cleanup needed or already cleaned."
    fi
}

install_required_autoconf() {
    # Some GCC versions might need a specific autoconf.
    # For modern GCC, system autoconf is usually fine.
    # This function can be expanded if a specific autoconf version needs to be built.
    if ! command -v autoconf &>/dev/null; then
        log "INFO" "autoconf command not found. Attempting to build a version (e.g., 2.69)."
        # build_generic_package "autoconf" "2.69" # Example, if needed.
        # For now, rely on install_dependencies to get it via apt.
        log "WARNING" "autoconf not found. It should have been installed by install_dependencies. Check system."
    else
        local autoconf_version
        autoconf_version=$(autoconf --version | head -n1)
        log "INFO" "Found autoconf: $autoconf_version. Assuming it's sufficient."
    fi
}

select_gcc_versions_to_build() {
    # selected_versions is a global array
    selected_versions=() # Clear previous selections if any

    echo -e "\n${GREEN}Select the GCC major version(s) to install (available: ${versions[*]}):${NC}" >&3
    echo -e "${CYAN}1. A single major version${NC}" >&3
    echo -e "${CYAN}2. Multiple major versions (comma-separated or ranges, e.g., 12,14 or 11-13)${NC}" >&3
    echo -e "${CYAN}3. All available major versions${NC}" >&3
    echo >&3 # Newline for readability

    local choice
    while true; do
        read -r -p "Enter your choice (1-3): " choice <&1 # Read from original stdin
        if [[ "$choice" =~ ^[1-3]$ ]]; then
            break
        fi
        echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}" >&3
    done

    case "$choice" in
        1)
            echo -e "\n${GREEN}Available GCC major versions:${NC}" >&3
            for ((i=0; i<${#versions[@]}; i++)); do
                echo -e "${CYAN}$((i+1)). GCC ${versions[i]}${NC}" >&3
            done
            echo >&3
            local single_choice_idx
            while true; do
                read -r -p "Enter the number for the GCC version you want (1-${#versions[@]}): " single_choice_idx <&1
                if [[ "$single_choice_idx" =~ ^[1-9][0-9]*$ ]] && \
                   ((single_choice_idx >= 1 && single_choice_idx <= ${#versions[@]})); then
                    selected_versions+=("${versions[$((single_choice_idx-1))]}")
                    break
                fi
                echo -e "${RED}Invalid selection. Please enter a number between 1 and ${#versions[@]}.${NC}" >&3
            done
            ;;
        2)
            local custom_input
            while true; do
                read -r -p "Enter comma-separated versions or ranges (e.g., 11,14 or 10-12): " custom_input <&1
                if [[ -z "$custom_input" ]]; then
                    echo -e "${RED}Input cannot be empty.${NC}" >&3
                    continue
                fi
                # Basic validation for allowed characters
                if [[ "$custom_input" =~ ^[0-9,\ -]+$ ]]; then # Allow digits, commas, hyphens, spaces
                    # Remove spaces for easier parsing
                    custom_input_no_spaces=${custom_input// /}
                    break
                fi
                echo -e "${RED}Invalid input format. Please use only numbers, commas, hyphens, and spaces (e.g., 11, 14 or 10-12).${NC}" >&3
            done
            
            IFS=',' read -ra raw_entries <<< "$custom_input_no_spaces"
            for entry in "${raw_entries[@]}"; do
                if [[ $entry =~ ^([0-9]+)-([0-9]+)$ ]]; then # Range: X-Y
                    local start=${BASH_REMATCH[1]}
                    local end=${BASH_REMATCH[2]}
                    if ! [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]]; then # Ensure start/end are numbers
                        log "WARNING" "Invalid range format in '$entry'. Skipping."
                        continue
                    fi
                    if ((start > end)); then
                        log "WARNING" "Invalid range $start-$end (start > end). Skipping."
                        continue
                    fi
                    for ((v=start; v<=end; v++)); do
                        if [[ " ${versions[*]} " =~ " $v " ]]; then # Check if version v is in available list
                            selected_versions+=("$v")
                        else
                            log "WARNING" "Major version $v from range $entry is not available and will be skipped."
                        fi
                    done
                elif [[ $entry =~ ^[0-9]+$ ]]; then # Single number
                    if [[ " ${versions[*]} " =~ " $entry " ]]; then
                        selected_versions+=("$entry")
                    else
                        log "WARNING" "Major version $entry is not available and will be skipped."
                    fi
                else
                    log "WARNING" "Invalid entry '$entry'. Skipping."
                fi
            done
            ;;
        3)
            log "INFO" "Selected all available GCC major versions."
            selected_versions=("${versions[@]}")
            ;;
    esac

    # Deduplicate selected_versions and sort them
    if [[ "${#selected_versions[@]}" -gt 0 ]]; then
        mapfile -t sorted_unique_versions < <(printf "%s\n" "${selected_versions[@]}" | sort -un)
        selected_versions=("${sorted_unique_versions[@]}")
        log "INFO" "Final selected GCC major versions to build: ${selected_versions[*]}"
    else
        fail "No valid GCC major versions were selected. Exiting."
    fi

    if [[ "${#selected_versions[@]}" -eq 0 ]]; then # Should be caught by above, but as a safeguard
        fail "No GCC versions selected to build. Exiting."
    fi
}

# Placeholder for build state tracking if resume functionality is enhanced later
# build_state_manager() {
#     local action=$1
#     local stage=$2
#     local state_file="$build_dir/.build_state"
    
#     case "$action" in
#         save)
#             echo "$stage" > "$state_file"
#             ;;
#         load)
#             [[ -f "$state_file" ]] && cat "$state_file"
#             ;;
#         clear)
#             rm -f "$state_file"
#             ;;
#     esac
# }

build_gcc_version() {
    local full_version_string=$1 # e.g., 13.2.0
    local major_version="${full_version_string%%.*}" # e.g., 13
    local install_prefix # Determined based on user_prefix or default
    local gcc_source_dir="$workspace/gcc-$full_version_string"
    local gcc_build_dir="$gcc_source_dir/build-gcc" # Separate build dir inside source tree

    build_status_log "GCC" "$full_version_string" "BUILD_PROCESS_START"

    if [[ -z "$user_prefix" ]]; then
        install_prefix="/usr/local/programs/gcc-$full_version_string"
    else
        install_prefix="${user_prefix%/}/gcc-$full_version_string" # Ensure no double slashes
    fi
    log "INFO" "Installation prefix for GCC $full_version_string will be: $install_prefix"

    # Create the custom programs directory if it's the default and doesn't exist
    if [[ -z "$user_prefix" && ! -d "/usr/local/programs" ]]; then
        log "INFO" "Default programs directory /usr/local/programs does not exist."
        if [[ "$dry_run" -eq 1 ]]; then
            log "INFO" "Dry run: would create directory /usr/local/programs and chown to $USER."
        else
            verbose_logging_cmd sudo mkdir -p "/usr/local/programs" || fail "Failed to create /usr/local/programs"
            # Chown to current user so subsequent operations within it (like creating gcc-version dir) don't need sudo yet
            verbose_logging_cmd sudo chown "$USER:$USER" "/usr/local/programs" || fail "Failed to chown /usr/local/programs"
        fi
    fi
    # Create the specific version install directory (parent must be writable by user now or sudo used for make install)
    # If user_prefix is used, its parent's writability was checked in parse_args.
    # If default prefix, /usr/local/programs was chowned to user.
    if [[ "$dry_run" -eq 0 ]]; then # Only create if not dry run
        mkdir -p "$install_prefix" || fail "Failed to create installation directory: $install_prefix. Check permissions."
    else
        log "INFO" "Dry run: would ensure creation of installation directory: $install_prefix"
    fi


    # --- Download GCC Source ---
    local gcc_tarball="gcc-$full_version_string.tar.xz"
    local gcc_download_url="https://ftp.gnu.org/gnu/gcc/gcc-$full_version_string/$gcc_tarball"
    if ! download_source_file "$gcc_download_url" "$full_version_string"; then
        fail "Failed to download or verify GCC $full_version_string source."
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Dry run: Would proceed to extract, configure, build, and install GCC $full_version_string."
        build_status_log "GCC" "$full_version_string" "DRY_RUN_COMPLETE"
        return 0 # End of dry run for this version
    fi

    # --- Extract Source ---
    build_status_log "GCC" "$full_version_string" "EXTRACT_START"
    log "INFO" "Extracting $gcc_tarball to $workspace..."
    # Clean up old source dir first to ensure fresh extraction
    if [[ -d "$gcc_source_dir" ]]; then
        log "INFO" "Removing existing source directory: $gcc_source_dir"
        rm -rf "$gcc_source_dir" || fail "Failed to remove existing source directory: $gcc_source_dir"
    fi
    if ! verbose_logging_cmd tar -Jxf "$build_dir/$gcc_tarball" -C "$workspace"; then
        fail "Failed to extract $gcc_tarball."
    fi
    log "INFO" "Successfully extracted GCC $full_version_string to $gcc_source_dir"
    build_status_log "GCC" "$full_version_string" "EXTRACT_SUCCESS"

    cd "$gcc_source_dir" || fail "Failed to change directory to $gcc_source_dir"

    # --- Download Prerequisites ---
    build_status_log "GCC" "$full_version_string" "PREREQUISITES_DOWNLOAD_START"
    log "INFO" "Downloading GCC prerequisites using ./contrib/download_prerequisites..."
    if [[ -f "./contrib/download_prerequisites" ]]; then
        # Some older GCC versions might not have this script or might have issues with it.
        # Modify environment for the script if necessary (e.g., proxy)
        # HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy" FTP_PROXY="$ftp_proxy" 
        if ! verbose_logging_cmd ./contrib/download_prerequisites; then
             # Allow continuing if prerequisites fail, as system libs might be used or some are optional.
            log "WARNING" "Failed to download all prerequisites using ./contrib/download_prerequisites. Build might still succeed if system libraries are found or some prerequisites are optional."
            build_status_log "GCC" "$full_version_string" "PREREQUISITES_DOWNLOAD_PARTIAL_FAILURE"
        else
            log "INFO" "Successfully downloaded prerequisites."
            build_status_log "GCC" "$full_version_string" "PREREQUISITES_DOWNLOAD_SUCCESS"
        fi
    else
        log "WARNING" "./contrib/download_prerequisites script not found in $gcc_source_dir. Assuming prerequisites will be met by system libraries or are not needed."
    fi
    
    # --- Configure GCC ---
    build_status_log "GCC" "$full_version_string" "CONFIGURE_START"
    log "INFO" "Configuring GCC $full_version_string..."
    # Create a separate build directory (out-of-source build is recommended)
    rm -rf "$gcc_build_dir" # Clean previous attempt
    mkdir -p "$gcc_build_dir" || fail "Failed to create build directory: $gcc_build_dir"
    cd "$gcc_build_dir" || fail "Failed to change directory to $gcc_build_dir"

    # Generate configure options efficiently (replaces 90+ lines of duplication)
    mapfile -t configure_options < <(get_gcc_configure_options "$major_version" "$install_prefix")
    
    # Add tuning options
    [[ "$generic_build" -eq 1 ]] && configure_options+=(--with-tune=generic)
    
    # Log multilib status  
    if [[ "$enable_multilib_flag" -eq 1 ]]; then
        log "INFO" "Multilib support enabled for GCC configure."
    else
        log "INFO" "Multilib support disabled for GCC configure."
    fi
    
    # Static build info
    [[ "$static_build" -eq 1 ]] && log "INFO" "Static build requested - using LDFLAGS for static linking."
    
    # Log the final configure command
    log "INFO" "Running configure with options:"
    # Print each option on a new line for readability in logs
    printf " ../configure \\\n" # Relative path to configure from build dir
    for opt in "${configure_options[@]}"; do
        printf "   %s \\\n" "$opt"
    done
    printf "\n" # End of command

    # Execute configure
    if ! ../configure "${configure_options[@]}"; then
        # If configure fails, config.log in the build directory ($gcc_build_dir/config.log) is key
        log "ERROR" "GCC configure script failed. Check $gcc_build_dir/config.log for details."
        # Offer to keep build dir for inspection
        [[ "$keep_build_dir" -eq 0 ]] && log "ERROR" "To preserve build files for debugging, re-run with -k or --keep-build-dir."
        build_status_log "GCC" "$full_version_string" "CONFIGURE_FAILURE"
        fail "GCC $full_version_string configure failed." # fail exits
    fi
    log "INFO" "GCC $full_version_string configuration completed successfully."
    build_status_log "GCC" "$full_version_string" "CONFIGURE_SUCCESS"

    # --- Build GCC (make) ---
    build_status_log "GCC" "$full_version_string" "MAKE_START"
    log "INFO" "Building GCC $full_version_string (make). This will take a significant amount of time..."
    
    # Simple thread calculation - use all available cores
    local workers
    workers=$(nproc --all 2>/dev/null || echo 2)
    log "INFO" "Using $workers threads (all available CPU cores)."

    local make_start_time make_end_time make_duration
    make_start_time=$(date +%s)

    # The 'make_gcc' function from original script is refactored here
    # Simpler make call; verbose_logging_cmd handles detailed output/errors
    if ! verbose_logging_cmd make "-j$workers"; then
        log "WARNING" "Parallel make (-j$workers) failed for GCC $full_version_string."
        log "INFO" "Attempting single-threaded make (make). This will be slower."
        build_status_log "GCC" "$full_version_string" "MAKE_PARALLEL_FAILURE_RETRYING_SINGLE"
        if ! verbose_logging_cmd make; then
            make_end_time=$(date +%s)
            make_duration=$((make_end_time - make_start_time))
            log "ERROR" "Single-threaded make also failed for GCC $full_version_string after $make_duration seconds."
            log "ERROR" "Check the output above or the log file for detailed error messages from make."
            [[ "$keep_build_dir" -eq 0 ]] && log "ERROR" "To preserve build files for debugging, re-run with -k or --keep-build-dir."
            build_status_log "GCC" "$full_version_string" "MAKE_FAILURE"
            fail "GCC $full_version_string build (make) failed."
        fi
    fi
    make_end_time=$(date +%s)
    make_duration=$((make_end_time - make_start_time))
    local duration_human_readable
    duration_human_readable=$(printf "%02d:%02d:%02d" $((make_duration/3600)) $(( (make_duration/60)%60)) $((make_duration%60)) )
    log "INFO" "GCC $full_version_string build (make) completed successfully in $duration_human_readable (Total $make_duration seconds)."
    build_status_log "GCC" "$full_version_string" "MAKE_SUCCESS"

    # --- Install GCC (make install) ---
    build_status_log "GCC" "$full_version_string" "INSTALL_START"
    log "INFO" "Installing GCC $full_version_string to $install_prefix (sudo make install-strip)..."
    # Using install-strip to reduce installed size by stripping debug symbols from binaries
    if ! verbose_logging_cmd sudo make install-strip; then
        log "ERROR" "GCC $full_version_string installation (sudo make install-strip) failed."
        log "ERROR" "Check output above for errors. Ensure $install_prefix (or its parent) is writable by sudo or user if prefix is in home dir."
        build_status_log "GCC" "$full_version_string" "INSTALL_FAILURE"
        fail "GCC $full_version_string installation failed."
    fi
    log "INFO" "GCC $full_version_string installation completed successfully to $install_prefix."
    build_status_log "GCC" "$full_version_string" "INSTALL_SUCCESS"
    
    # --- Post-installation tasks ---
    build_status_log "GCC" "$full_version_string" "POST_BUILD_TASKS_START"
    post_build_cleanup_and_config "$full_version_string" # Handles libtool, ldconfig, symlinks
    trim_binaries "$full_version_string" # Trim $target_arch- prefix from installed binaries
    save_static_binaries "$full_version_string" # Save static binaries if requested
    build_status_log "GCC" "$full_version_string" "POST_BUILD_TASKS_SUCCESS"

    log "INFO" "Successfully built and installed GCC $full_version_string."
    build_status_log "GCC" "$full_version_string" "BUILD_PROCESS_SUCCESS"
    cd "$build_dir" # Return to base build dir
}

# Trap for errors, call cleanup
trap_and_exit_on_error() {
    local exit_code=$?
    local line_no=$1
    local command=${BASH_COMMAND}
    
    if [[ $exit_code -ne 0 ]]; then
        # Avoid re-trapping inside fail or cleanup
        trap - ERR
        log "ERROR" "Script execution failed!"
        log "ERROR" "Error on or near line $line_no: Command '$command' exited with status $exit_code."
        # build_state_manager load # If resume logic were implemented
        # No automatic cleanup here, fail() handles it based on keep_build_dir
        fail "Exiting due to error (see logs)." # fail will exit
    fi
}


# --- Main Script Execution ---
main() {
    # Ensure original std descriptors are saved if logging is enabled later
    exec 3>&1 4>&2 

    # Parse arguments first, as they might enable debug/verbose or set log file
    parse_args "$@"

    # Setup logging if -l option was used
    # This must happen after parse_args and before extensive logging
    if [[ -n "$log_file" ]]; then
        setup_logging # This will redirect stdout/stderr
    fi

    log "INFO" "Starting GCC Build Script v$SCRIPT_VERSION"
    log "INFO" "Script PID: $$"
    log "INFO" "Dry run mode: $dry_run"
    log "INFO" "Debug mode: $debug_mode"
    log "INFO" "Verbose mode: $verbose"
    log "INFO" "Keep build directory: $keep_build_dir"
    log "INFO" "Installation prefix (if set): $user_prefix"
    log "INFO" "Static build: $static_build"
    log "INFO" "Save static binaries: $save_binaries"
    log "INFO" "Optimization level for GCC build: $optimization_level"
    log "INFO" "Target architecture (pc_type/target_arch): $target_arch"

    # Note: ERR trap disabled to avoid issues with conditional expressions
    # Error handling is done manually where needed using || fail
    # Setup debug trap if debug_mode is on
    # The previous `trap 'debug' DEBUG` was for a function named 'debug'.
    # This script uses `set -x` for general debug, and `bash_debug_trap` for BASH_COMMAND.
    case "$debug_mode" in
        1) trap 'bash_debug_trap' DEBUG ;; # Log each command before execution via BASH_COMMAND
        *) ;; # No debug trap
    esac

    if [[ "$EUID" -eq 0 ]]; then
        fail "This script must NOT be run as root or with sudo directly. Sudo is used internally for specific commands like 'make install' or 'apt install'."
    fi
    
    # Create base temporary build directory
    # check_and_create_dir from original script
    if [[ ! -d "$build_dir" ]]; then
        log "INFO" "Creating base build directory: $build_dir"
        mkdir -p "$build_dir" || fail "Failed to create base build directory: $build_dir"
        # Permissions should be fine as it's in /tmp or user-owned if $build_dir is elsewhere
    fi
    # Create subdirectories (packages, workspace)
    create_directories "$packages" "$workspace"
    
    check_system_resources # Basic RAM and general disk check

    # Setup environment variables (PATH, PKG_CONFIG_PATH, CFLAGS, etc.)
    set_path
    set_pkg_config_path
    set_environment # Sets CFLAGS, LDFLAGS etc. for building GCC itself

    install_dependencies # Install build-essential, autoconf, etc.
    install_required_autoconf # Check/install specific autoconf if ever needed

    select_gcc_versions_to_build # Populates `selected_versions` array

    # Check disk space AFTER versions are selected
    check_disk_space_for_selected_versions

    if [[ "${#selected_versions[@]}" -eq 0 ]]; then
        log "INFO" "No GCC versions to build. Exiting."
        exit 0
    fi

    log "INFO" "Starting build process for selected GCC major versions: ${selected_versions[*]}"
    local overall_start_time overall_end_time overall_duration
    overall_start_time=$(date +%s)

    for major_ver in "${selected_versions[@]}"; do
        log "INFO" "--- Processing GCC major version: $major_ver ---"
        local full_release_ver
        full_release_ver=$(get_latest_gcc_release_version "$major_ver")
        
        if [[ -z "$full_release_ver" ]]; then
            log "ERROR" "Could not determine the latest release for GCC $major_ver. Skipping this version."
            build_status_log "GCC" "$major_ver (Major)" "VERSION_LOOKUP_FAILURE"
            continue
        fi
        log "INFO" "Latest release for GCC $major_ver is $full_release_ver."
        
        build_gcc_version "$full_release_ver" # This function contains the full build logic per version
    done
    
    overall_end_time=$(date +%s)
    overall_duration=$((overall_end_time - overall_start_time))
    local overall_duration_human
    overall_duration_human=$(printf "%02d:%02d:%02d" $((overall_duration/3600)) $(( (overall_duration/60)%60)) $((overall_duration%60)) )

    log "INFO" "All selected GCC versions have been processed."
    log "INFO" "Total script execution time: $overall_duration_human (Total $overall_duration seconds)."

    # Final cleanup of temporary build directory (if not keeping)
    cleanup_temporary_folders
    
    log "INFO" "--- GCC Build Script Finished ---"
    # Summary of what was built could be added here if build_status_log is used to track successes.
    local successful_builds=0
    # This is a simple check, could be more robust by tracking build_status_log "BUILD_PROCESS_SUCCESS"
    for major_ver in "${selected_versions[@]}"; do
        # Check if install dir exists as a proxy for success
        # Needs full_release_ver again, or better status tracking
        # For now, just a generic message
        : # Placeholder for more detailed summary
    done
    log "INFO" "Check logs and install prefixes for build status of each version."


    # Restore original stdout/stderr if they were redirected
    if [[ -n "$log_file" ]]; then
        exec 1>&3 2>&4
        exec 3>&- 4>&-
        echo "Script finished. Logging was directed to $log_file"
    fi
    
    trap - ERR DEBUG EXIT # Clear traps
    exit 0
}

# Global SCRIPT_VERSION, used in main's log
SCRIPT_VERSION="1.8"

# Call main function with all script arguments
main "$@"
