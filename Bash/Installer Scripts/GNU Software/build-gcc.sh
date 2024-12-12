#!/usr/bin/env bash
# shellcheck disable=SC2162 source=/dev/null

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc.sh
# Purpose: Build GNU GCC
# GCC versions available: 10-14
# Features: Automatically sources the latest release of each version.
# Updated: 12.17.24
# Script version: 1.7

build_dir="/tmp/gcc-build-script"
packages="$build_dir/packages"
workspace="$build_dir/workspace"
target_arch="x86_64-linux-gnu"
debug_mode=0
declare -a selected_versions=()
dry_run=0
enable_multilib=0
keep_build_dir=0
log_file=""
optimization_level="-O2"
save_binaries=0
static_build=0
verbose=0
generic_build=0
user_prefix=""
pc_type=""
cuda_check=""

versions=(10 11 12 13 14)

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color

echo "Initial dry_run value: $dry_run" >&2

setup_logging() {
    if [[ -n "$log_file" ]]; then
        # Create log directory if it doesn't exist
        mkdir -p "$(dirname "$log_file")" || fail "Failed to create log directory"
        # Clear existing log file
        : > "$log_file" || fail "Failed to create log file"
        # Redirect stderr to log file as well
        exec 2>> "$log_file"
        log "INFO" "Logging started to $log_file"
    fi
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  --debug                    Enable debug mode (custom logging of every executed command)"
    echo "  --dry-run                  Perform a dry run without making any changes"
    echo "  --enable-multilib          Enable multilib support (disabled by default)"
    echo "  --static                   Build static GCC executables"
    echo "  -g, --generic              Use generic tuning instead of native"
    echo "  -k, --keep-build-dir       Keep the temporary build directory after completion"
    echo "  -l, --log-file FILE        Specify a log file for output"
    echo "  -O LEVEL                   Set optimization level (0, 1, 2, 3, fast, g, s)"
    echo "  -p, --prefix DIR           Set the installation prefix (default: /usr/local/programs/gcc-<version>)"
    echo "  -s, --save                 Save static binaries (only works with --static)"
    echo "  -v, --verbose              Enable verbose logging"
    echo
    exit 0
}

log() {
    local level=$1
    shift
    local message=$*
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    case "$level" in
        DEBUG)
            [[ "$debug_mode" -eq 1 ]] && echo -e "${CYAN}[DEBUG $timestamp]${NC} $message"
            ;;
        INFO)
            [[ "$verbose" -eq 1 || "$debug_mode" -eq 1 ]] && echo -e "${GREEN}[INFO $timestamp]${NC} $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING $timestamp]${NC} $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR $timestamp]${NC} $message"
            ;;
    esac
    
    if [[ -n "$log_file" ]]; then
        echo "[$level $timestamp] $message" >> "$log_file"
    fi
}

warn() {
    [[ "$verbose" -eq 1 ]] && echo -e "\\n${YELLOW}[WARNING $(date +"%I:%M:%S %p")]${NC} $1\\n"
    [[ -n "$log_file" ]] && echo "[WARNING $(date +"%I:%M:%S %p")] $1" >> "$log_file"
}

fail() {
    [[ "$verbose" -eq 1 ]] && echo -e "\\n${RED}[ERROR $(date +"%I:%M:%S %p")]${NC} $1\\n"
    [[ -n "$log_file" ]] && echo "[ERROR $(date +"%I:%M:%S %p")] $1" >> "$log_file"
    echo -e "\\nTo report a bug, create an issue at: ${CYAN}https://github.com/slyfox1186/script-repo/issues${NC}"
    exit 1
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --debug)
                debug_mode=1
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --enable-multilib)
                enable_multilib=1
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
                if [[ ! -d "$(dirname "$2")" ]]; then
                    fail "Log file directory does not exist: $(dirname "$2")"
                fi
                if [[ -f "$2" ]]; then
                    warn "Log file already exists and will be overwritten: $2"
                fi
                log_file="$2"
                shift 2
                ;;
            -O)
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
                if [[ ! "$2" =~ ^/ ]]; then
                    fail "Prefix must be an absolute path starting with '/'"
                fi
                if [[ -e "$2" && ! -d "$2" ]]; then
                    fail "Prefix path exists but is not a directory: $2"
                fi
                if [[ ! -w "$(dirname "$2")" ]]; then
                    fail "Prefix directory is not writable: $(dirname "$2")"
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

debug() {
    echo -e "${YELLOW}[DEBUG $(date +"%I:%M:%S %p")]${NC} Executing: ${CYAN}${BASH_COMMAND}${NC}"
    [[ -n "$log_file" ]] && echo "[DEBUG $(date +"%I:%M:%S %p")] Executing: ${BASH_COMMAND}" >> "$log_file"
}

if [[ "$debug_mode" -eq 1 ]]; then
    debug="ON"
else
    debug="OFF"
fi

verbose_logging() {
    local retval output

    if [[ "$debug_mode" -eq 1 ]]; then
        # Debug mode: Show command and full output
        echo "$ $*"
        if ! "$@"; then
            retval=$?
            fail "Command failed with exit code $retval: $*"
        fi
    elif [[ "$verbose" -eq 1 ]]; then
        # Verbose mode: Show command and output only on error
        echo "$ $*"
        if ! output=$("$@" 2>&1); then
            retval=$?
            echo "$output"
            fail "Command failed with exit code $retval: $*"
        fi
    else
        # Normal mode: Suppress output unless there's an error
        if ! output=$("$@" 2>&1); then
            retval=$?
            echo "$output"
            fail "Command failed with exit code $retval: $*"
        fi
    fi

    return 0
}

[[ -f "$log_file" ]] && rm -f "$log_file"

if [[ "$debug_mode" -eq 1 ]]; then
    trap 'debug' DEBUG
fi

set_path() {
    PATH="/usr/lib/ccache:$workspace/bin:$PATH"
    export PATH
}

set_pkg_config_path() {
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export PKG_CONFIG_PATH
}

set_environment() {
    log "INFO" "Setting environment variables..."
    
    # Base CFLAGS
    CFLAGS="$optimization_level -pipe"
    CXXFLAGS="$optimization_level -pipe"
    
    # Add architecture-specific flags
    if [[ "$generic_build" -eq 0 ]]; then
        CFLAGS+=" -march=native -mtune=native"
        CXXFLAGS+=" -march=native -mtune=native"
    fi
    
    CFLAGS+=" -fstack-protector-strong"
    CXXFLAGS+=" -fstack-protector-strong"
    
    CPPFLAGS="-D_FORTIFY_SOURCE=2"

    if [[ "$static_build" -eq 1 ]]; then
        LDFLAGS="-static -L/usr/lib/x86_64-linux-gnu -Wl,-z,relro -Wl,-z,now"
    else
        LDFLAGS="-L/usr/lib/x86_64-linux-gnu -Wl,-z,relro -Wl,-z,now"
    fi

    CC="gcc"
    CXX="g++"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS

    if find /usr/local/ /opt/ -type f -name nvcc 2>/dev/null | grep -q 'nvcc'; then
        cuda_check="--enable-offload-targets=nvptx-none"
        log "INFO" "CUDA support enabled"
    else
        cuda_check=""
        log "INFO" "CUDA support not found"
    fi
}

verify_checksum() {
    local file version
    file=$1
    version=$2
    
    # For GCC 14, the signature file format is different
    if [[ "${version%%.*}" == "14" ]]; then
        # Skip checksum for GCC 14 as it uses a different signature format
        log "INFO" "Skipping checksum verification for GCC $version (using different signature format)"
        return 0
    fi

    local sig_url="https://ftp.gnu.org/gnu/gcc/gcc-${version}/gcc-${version}.tar.xz.sig"
    
    if ! expected_checksum=$(curl -fsSL "$sig_url" | grep -oP '(?<=SHA512 CHECKSUM: )[a-f0-9]+'); then
        warn "Could not retrieve checksum from $sig_url"
        warn "Proceeding without checksum verification"
        return 0
    fi

    if [[ -z "$expected_checksum" ]]; then
        warn "No checksum found in the signature file"
        warn "Proceeding without checksum verification"
        return 0
    fi

    actual_checksum=$(sha512sum "$file" | awk '{print $1}')
    if [[ "$expected_checksum" != "$actual_checksum" ]]; then
        fail "Checksum mismatch for $file"
    fi

    return 0
}

check_disk_space() {
    local required_space available_space
    # Each GCC version needs:
    # - ~15GB for source and build files
    # - ~5GB for prerequisites
    # - ~2GB safety margin
    # Total: 22GB per version
    required_space=$((22000 * ${#selected_versions[@]}))  # 22GB per version in MB
    
    available_space=$(df -m "$build_dir" | awk 'NR==2 {print $4}')
    if [[ $available_space -lt $required_space ]]; then
        fail "Insufficient disk space. Required: ${required_space}MB (${#selected_versions[@]} versions × 22GB), Available: ${available_space}MB"
    fi
    
    # Warn if less than 10% extra space available
    local recommended_space=$((required_space * 110 / 100))
    if [[ $available_space -lt $recommended_space ]]; then
        warn "Low disk space. Recommended to have at least 10% more than required (${recommended_space}MB)"
    fi
}

trim_binaries() {
    local bin_dir install_dir version
    version=$1
    if [[ -z "$user_prefix" ]]; then
        install_dir="/usr/local/programs/gcc-$version"
    else
        install_dir="${user_prefix}-$version"
    fi

    bin_dir="$install_dir/bin"
    log "INFO" "Trimming binary filenames in $bin_dir"

    if [[ "$dry_run" -eq 1 ]]; then
        log "Dry run: would rename x86_64-linux-gnu-* binaries in $bin_dir"
        return
    fi

    for file in "$bin_dir"/x86_64-linux-gnu-*; do
        if [[ -f "$file" ]]; then
            local new_name="${file##*/}"
            new_name="${new_name#x86_64-linux-gnu-}"
            verbose_logging sudo mv "$file" "$bin_dir/$new_name"
            log "INFO" "Renamed $file to $new_name"
        fi
    done
}

save_static_binaries() {
    local install_dir save_dir version
    version=$1
    if [[ -z "$user_prefix" ]]; then
        install_dir="/usr/local/programs/gcc-$version"
    else
        install_dir="${user_prefix}-$version"
    fi

    save_dir="$PWD/gcc-${version}-saved-binaries"

    if [[ "$static_build" -eq 1 && "$save_binaries" -eq 1 ]]; then
        log "INFO" "Saving static binaries to $save_dir"
        if [[ "$dry_run" -eq 1 ]]; then
            log "Dry run: would copy static binaries to $save_dir"
            return
        fi
        verbose_logging mkdir -p "$save_dir"

        local programs=(
            "cpp-$version" "c++-$version" "gccgo-$version" "gcc-$version"
            "gcc-ar-$version" "gcc-nm-$version" "gcc-ranlib-$version" "gcov-$version"
            "gcov-dump-$version" "gcov-tool-$version" "gfortran-$version" "gnatbind-$version"
            "gnatchop-$version" "gnatclean-$version" "gnatkr-$version" "gnatlink-$version"
            "gnatls-$version" "gnatmake-$version" "gnatname-$version" "gnatprep-$version"
            "gnat-$version" "gofmt-$version" "go-$version" "g++-$version" "lto-dump-$version"
        )

        for program in "${programs[@]}"; do
            local source_file="$install_dir/bin/$program"
            if [[ -f "$source_file" ]]; then
                verbose_logging sudo cp -f "$source_file" "$save_dir/$program"
                log "INFO" "Copied $program to $save_dir"
            else
                warn "Binary not found: $source_file"
            fi
        done

        log "INFO" "Static binaries saved to $save_dir"
    fi
}

download() {
    local url file version
    url=$1
    file=$(basename "$url")
    version=$(echo "$file" | grep -oP 'gcc-\K[0-9.]+(?=\.tar\.[a-z]+)')
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if [[ -f "$build_dir/$file" ]]; then
            # Try to extract the file to test if it's valid
            if ! tar -tf "$build_dir/$file" &>/dev/null; then
                warn "Existing file $file appears to be corrupted. Removing and retrying download..."
                if [[ "$keep_build_dir" -eq 0 ]]; then
                    rm -f "$build_dir/$file"
                else
                    warn "Keeping corrupted file due to -k flag. Please remove manually and try again."
                    return 1
                fi
            else
                log "INFO" "File $file already exists, but will be verified during extraction."
                return 0
            fi
        fi

        if [[ ! -f "$build_dir/$file" ]]; then
            log "INFO" "Downloading $file..."
            if ! wget --show-progress -cqO "$build_dir/$file" "$url"; then
                warn "Download attempt $attempt of $max_attempts failed"
                if [[ "$keep_build_dir" -eq 0 ]]; then
                    rm -f "$build_dir/$file"
                else
                    warn "Keeping partial download due to -k flag. Please remove manually and try again."
                    return 1
                fi
                ((attempt++))
                continue
            fi
        fi

        # Verify the downloaded file
        if ! tar -tf "$build_dir/$file" &>/dev/null; then
            warn "Downloaded file $file is corrupted."
            if [[ "$keep_build_dir" -eq 0 ]]; then
                warn "Removing and retrying..."
                rm -f "$build_dir/$file"
            else
                warn "Keeping corrupted file due to -k flag. Please remove manually and try again."
                return 1
            fi
            ((attempt++))
            continue
        fi

        return 0
    done

    fail "Failed to download $file after $max_attempts attempts. Please run the script again to retry."
}

create_symlinks() {
    local version=$1
    local install_dir
    if [[ -z "$user_prefix" ]]; then
        install_dir="/usr/local/programs/gcc-$version"
    else
        install_dir="${user_prefix}-$version"
    fi

    if [[ ! -d "$install_dir" ]]; then
        warn "No installation directory found for GCC $version"
        log "INFO" "Listing contents of /usr/local/programs:"
        ls -l /usr/local/programs 2>/dev/null || true
        return
    fi

    local bin_dir="$install_dir/bin"
    log "INFO" "Creating symlinks for GCC $version (${install_dir##*/})..."

    if [[ ! -d "$bin_dir" ]]; then
        warn "Binary directory not found: $bin_dir"
        log "INFO" "Listing contents of $install_dir:"
        ls -l "$install_dir"
        return
    fi

    log "INFO" "Contents of $bin_dir:"
    ls -l "$bin_dir"

    local symlink_count=0
    if [[ "$dry_run" -eq 1 ]]; then
        for file in "$bin_dir"/*; do
            if [[ -f "$file" && -x "$file" && ! "$file" =~ x86_64-linux-gnu ]]; then
                local base_name
                base_name=$(basename "$file")
                log "INFO" "Dry run: would create symlink ln -sf $file /usr/local/bin/$base_name"
                ((symlink_count++))
            fi
        done
    else
        for file in "$bin_dir"/*; do
            if [[ -f "$file" && -x "$file" && ! "$file" =~ x86_64-linux-gnu ]]; then
                local base_name
                base_name=$(basename "$file")
                verbose_logging sudo ln -sf "$file" "/usr/local/bin/$base_name"
                log "INFO" "Created symlink for $base_name"
                ((symlink_count++))
            fi
        done
    fi

    log "INFO" "Created $symlink_count symlinks for GCC $version"
}

install_deps() {
    local -a missing_pkgs=() pkgs=()
    log "INFO" "Installing dependencies..."

    pkgs=(
        autoconf autoconf-archive automake binutils bison
        build-essential ccache curl flex gawk gcc gnat libc6-dev
        libisl-dev libtool libtool-bin make m4 patch texinfo
        zlib1g-dev libzstd-dev libc6-dev libc6-dev-i386 linux-libc-dev
        linux-libc-dev:i386
    )

    # Check packages in parallel using background jobs
    for pkg in "${pkgs[@]}"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" || missing_pkgs+=("$pkg") &
    done
    wait  # Wait for all package checks to complete

    if [[ -n "${missing_pkgs[*]}" ]]; then
        if [[ "$dry_run" -eq 0 ]]; then
            verbose_logging sudo apt update
            verbose_logging sudo apt install -y "${missing_pkgs[@]}"
        else
            log "INFO" "Dry run: would install ${missing_pkgs[*]}"
        fi
    else
        log "INFO" "All required packages are already installed."
    fi
}

get_latest_version() {
    local version=$1
    local cache_file="$build_dir/.version_cache"
    local cache_age=3600  # Cache for 1 hour

    # Create cache directory if it doesn't exist
    mkdir -p "$build_dir"

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_timestamp
        cache_timestamp=$(stat -c %Y "$cache_file")
        local current_time
        current_time=$(date +%s)
        local age=$((current_time - cache_timestamp))

        if [[ $age -lt $cache_age ]]; then
            # Use cached version if available
            if cached_version=$(grep "^$version:" "$cache_file" | cut -d: -f2); then
                if [[ -n "$cached_version" ]]; then
                    echo "$cached_version"
                    return 0
                fi
            fi
        fi
    fi

    # Fetch latest version from GNU FTP site
    local latest_version
    latest_version=$(curl -fsS "https://ftp.gnu.org/gnu/gcc/" | \
                    grep -oP "gcc-${version}[0-9.]+/" | \
                    sed 's/gcc-//;s/\///' | \
                    sort -V | \
                    tail -n1)

    if [[ -n "$latest_version" ]]; then
        # Update cache
        mkdir -p "$(dirname "$cache_file")"
        if [[ -f "$cache_file" ]]; then
            # Remove old entry for this version
            sed -i "/^$version:/d" "$cache_file"
        fi
        echo "$version:$latest_version" >> "$cache_file"
        echo "$latest_version"
        return 0
    fi

    return 1
}

post_build_tasks() {
    local short_version version install_dir
    version=$1
    short_version="${version%%.*}"

    if [[ -z "$user_prefix" ]]; then
        install_dir="/usr/local/programs/gcc-$version"
    else
        install_dir="${user_prefix}-$version"
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Dry run: would run libtool --finish for gcc-$version"
    else
        if [[ -d "$install_dir/libexec/gcc/x86_64-pc-linux-gnu/$short_version" ]]; then
            verbose_logging sudo libtool --finish "$install_dir/libexec/gcc/x86_64-pc-linux-gnu/$short_version"
        elif [[ -d "$install_dir/libexec/gcc/x86_64-linux-gnu/$short_version" ]]; then
            verbose_logging sudo libtool --finish "$install_dir/libexec/gcc/x86_64-linux-gnu/$short_version"
        elif [[ -d "$install_dir/libexec/gcc/$pc_type/$short_version" ]]; then
            verbose_logging sudo libtool --finish "$install_dir/libexec/gcc/$pc_type/$short_version"
        else
            fail "The script could not find the correct folder for libtool to run --finish on. Line: $LINENO"
        fi
    fi

    create_symlinks "$version"
}

ld_linker_path() {
    local version
    version=$1
    if [[ "$dry_run" -eq 0 ]]; then
        [[ -d "$install_dir/lib64" ]] && echo "$install_dir/lib64" | sudo tee "/etc/ld.so.conf.d/custom_gcc-$version.conf" >/dev/null
        [[ -d "$install_dir/lib" ]] && echo "$install_dir/lib" | sudo tee -a "/etc/ld.so.conf.d/custom_gcc-$version.conf" >/dev/null
        sudo ldconfig
    else
        log "Dry run: Would now create the \"/etc/ld.so.conf/\" config files."
    fi
}

create_additional_soft_links() {
    local install_dir="$1"

    if [[ -d "$install_dir/lib/pkgconfig" ]]; then
        if [[ "$dry_run" -eq 0 ]]; then
            find "$install_dir/lib/pkgconfig" -type f -name '*.pc' | while read -r file; do
                sudo ln -sf "$file" "/usr/local/lib/pkgconfig/"
            done
        else
            log "Dry run: would create additional soft links in /usr/local/lib/pkgconfig/"
        fi
    fi
}

build_done() {
    local package version
    package=$1
    version=$2
    log "INFO" "Successfully built $package $version."
}

build() {
    local package version options
    package=$1
    version=$2
    shift 2
    options=("$@")  # Accept options as an array

    log "INFO" "Building $package $version..."

    cd "$build_dir" || fail "Failed to change directory to $build_dir"

    case "$package" in
        gcc)
            check_disk_space 5000
            download "https://ftp.gnu.org/gnu/gcc/gcc-$version/gcc-$version.tar.xz" || fail "Failed to download gcc-$version.tar.xz"
            if [[ "$dry_run" -eq 1 ]]; then
                log "INFO" "Dry run: would extract gcc-$version.tar.xz and build GCC"
                return 0
            fi
            if ! verify_checksum "gcc-$version.tar.xz" "$version"; then
                fail "Checksum verification failed for gcc-$version.tar.xz"
            fi

            # Clean up any previous build attempts
            rm -rf "gcc-$version" build
            verbose_logging tar -Jxf "gcc-$version.tar.xz"
            cd "gcc-$version" || fail "Failed to change directory to gcc-$version"
            verbose_logging ./contrib/download_prerequisites || fail "Failed to download prerequisites"
            
            # Clean and recreate build directory
            rm -rf build
            verbose_logging mkdir -p build
            cd build || fail "Failed to create and enter build directory"
            
            # Configure with proper options
            if ! verbose_logging ../configure \
                --prefix="$install_dir" \
                --build="$target_arch" \
                --host="$target_arch" \
                --target="$target_arch" \
                --disable-multilib \
                --enable-languages=c,c++ \
                "${options[@]}"; then
                fail "Configure failed. Check the output above for errors."
            fi

            if ! verbose_logging make "-j$threads"; then
                warn "Parallel make failed, trying single-threaded build..."
                if ! verbose_logging make; then
                    fail "Make failed. Check the output above for errors."
                fi
            fi

            if ! verbose_logging sudo make install-strip; then
                fail "Make install failed. Check the output above for errors."
            fi
            ;;
        autoconf)
            download "https://ftp.gnu.org/gnu/autoconf/autoconf-$version.tar.xz"
            if [[ "$dry_run" -eq 1 ]]; then
                log "INFO" "Dry run: would extract autoconf-$version.tar.xz and build autoconf"
                return 0
            fi
            verbose_logging tar -Jxf "autoconf-$version.tar.xz"
            cd "autoconf-$version" || fail "Failed to change directory to autoconf-$version"
            verbose_logging ./configure --prefix="$workspace"
            verbose_logging make "-j$threads"
            verbose_logging make install
            ;;
    esac
}

cleanup_build_folders() {
    if [[ "$keep_build_dir" -eq 1 ]]; then
        log "INFO" "Keeping build folders as requested via -k flag"
        return 0
    fi
    
    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Dry run: would cleanup build folders in $build_dir"
    else
        find "$build_dir" -mindepth 1 -delete 2>/dev/null || true
    fi
}

cleanup() {
    if [[ "$keep_build_dir" -ne 1 ]]; then
        log "INFO" "Cleaning up..."
        if [[ "$dry_run" -eq 0 ]]; then
            if ! rm -rf "$build_dir"/* 2>/dev/null; then
                log "WARNING" "Failed to clean some files, attempting with sudo"
                sudo rm -rf "$build_dir"/* || fail "Failed to clean build directory"
            fi
            log "INFO" "Removed temporary build files"
        else
            log "INFO" "Dry run: would remove temporary build files"
        fi
    else
        log "INFO" "Keeping build directory: $build_dir"
    fi
}

install_autoconf() {
    if ! command -v autoconf &>/dev/null; then
        build "autoconf" "2.69"
        build_done "autoconf" "2.69"
    else
        log "INFO" "autoconf is already installed."
    fi
}

select_versions() {
    local -a versions=(10 11 12 13 14)
    selected_versions=()

    echo -e "\n${GREEN}Select the GCC version(s) to install:${NC}\n"
    echo -e "${CYAN}1. Single version${NC}"
    echo -e "${CYAN}2. Custom versions${NC}"

    echo
    while true; do
        read -p "Enter your choice (1-2): " choice
        if [[ "$choice" =~ ^[1-2]$ ]]; then
            break
        fi
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
    done

    case "$choice" in
        1)
            echo -e "\n${GREEN}Select a single GCC version to install:${NC}\n"
            for ((i=0; i<${#versions[@]}; i++)); do
                echo -e "${CYAN}$((i+1)). GCC ${versions[i]}${NC}"
            done
            echo
            while true; do
                read -p "Enter your choice (1-${#versions[@]}): " single_choice
                if [[ "$single_choice" =~ ^[1-9][0-9]*$ ]] && \
                   ((single_choice >= 1 && single_choice <= ${#versions[@]})); then
                    break
                fi
                echo -e "${RED}Invalid choice. Please enter a number between 1 and ${#versions[@]}.${NC}"
            done
            selected_versions+=("${versions[$((single_choice-1))]}")
            ;;
        2)
            while true; do
                read -p "Enter comma-separated versions or ranges (e.g., 11,14 or 11-14): " custom_choice
                if [[ "$custom_choice" =~ ^[0-9,.-]+$ ]]; then
                    break
                fi
                echo -e "${RED}Invalid input. Please use only numbers, commas, and hyphens.${NC}"
            done
            IFS=',' read -ra custom_versions <<< "$custom_choice"
            for ver in "${custom_versions[@]}"; do
                if [[ $ver =~ ^[0-9]+$ ]]; then
                    if [[ " ${versions[*]} " =~ " ${ver} " ]]; then
                        selected_versions+=("$ver")
                    else
                        warn "Version $ver is not available and will be skipped."
                    fi
                elif [[ $ver =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    start=${BASH_REMATCH[1]}
                    end=${BASH_REMATCH[2]}
                    if ((start > end)); then
                        warn "Invalid range $start-$end (start > end). Skipping."
                        continue
                    fi
                    for ((i=start; i<=end; i++)); do
                        if [[ " ${versions[*]} " =~ " $i " ]]; then
                            selected_versions+=("$i")
                        else
                            warn "Version $i is not available and will be skipped."
                        fi
                    done
                else
                    warn "Invalid version or range: $ver. Skipping."
                fi
            done
            ;;
    esac

    if [[ "${#selected_versions[@]}" -eq 0 ]]; then
        fail "No valid GCC versions were selected."
    fi

    # Get latest version for each selected version and build
    for version in "${selected_versions[@]}"; do
        latest_version=$(get_latest_version "$version")
        if [[ -z "$latest_version" ]]; then
            fail "Failed to determine latest version for GCC $version"
        fi
        build_gcc "$latest_version"
    done
}

build_state() {
    local action=$1
    local stage=$2
    local state_file="$build_dir/.build_state"
    
    case "$action" in
        save)
            echo "$stage" > "$state_file"
            ;;
        load)
            [[ -f "$state_file" ]] && cat "$state_file"
            ;;
        clear)
            rm -f "$state_file"
            ;;
    esac
}

build_gcc() {
    local version install_dir short_version configure_options=() common_options=()

    version=$1
    short_version="${version%%.*}"

    if [[ -z "$user_prefix" ]]; then
        install_dir="/usr/local/programs/gcc-$version"
        # Create the programs directory with sudo if it doesn't exist
        if [[ ! -d "/usr/local/programs" ]]; then
            if [[ "$dry_run" -eq 1 ]]; then
                log "INFO" "Dry run: would create directory /usr/local/programs"
            else
                verbose_logging sudo mkdir -p "/usr/local/programs"
                verbose_logging sudo chown "$USER:$USER" "/usr/local/programs"
            fi
        fi
    else
        install_dir="${user_prefix}-$version"
    fi

    # Set up configure options with all the custom settings
    common_options=(
        "--prefix=$install_dir"
        "--build=$pc_type"
        "--host=$pc_type"
        "--target=$pc_type"
        "--disable-assembly"
        "--disable-bootstrap"
        "--disable-isl-version-check" 
        "--disable-libada"
        "--disable-libsanitizer"
        "--disable-libssp"
        "--disable-libvtv"
        "--disable-lto"
        "--disable-multilib"
        "--disable-nls"
        "--disable-vtable-verify"
        "--disable-werror"
        "--enable-checking=release"
        "--enable-clocale=gnu"
        "--enable-default-pie"
        "--enable-gnu-unique-object"
        "--enable-languages=all"
        "--enable-libphobos-checking=release"
        "--enable-libstdcxx-debug"
        "--enable-libstdcxx-time=yes"
        "--enable-linker-build-id"
        "--enable-multiarch"
        "--enable-plugin"
        "--enable-shared"
        "--enable-threads=posix"
        "--libdir=$install_dir/lib"
        "--libexecdir=$install_dir/libexec"
        "--program-prefix=$pc_type-"
        "--program-suffix=-$short_version"
        "--with-abi=m64"
        "--with-arch-32=i686"
        "--with-default-libstdcxx-abi=new"
        "--with-gcc-major-version-only"
        "--with-gnu-as"
        "--with-gnu-ld"
        "--with-isl=/usr"
        "--with-linker-hash-style=gnu"
        "--with-system-zlib"
        "--with-target-system-zlib=auto"
        "--with-tune=generic"
    )

    # Add CUDA check option if CUDA is available
    [[ -n "$cuda_check" ]] && common_options+=("$cuda_check")

    # Version-specific options
    case "$short_version" in
        9|10|11) 
            configure_options=("${common_options[@]}")
            ;;
        12) 
            configure_options=("${common_options[@]}" "--with-link-serialization=2")
            ;;
        13|14) 
            configure_options=(
                "${common_options[@]}"
                "--disable-vtable-verify"
                "--enable-cet"
                "--enable-link-serialization=2"
                "--enable-host-pie"
            )
            ;;
        *)  
            fail "GCC version not found. Line: $LINENO"
            ;;
    esac

    # Create and enter build directory
    cd "$workspace/gcc-$version" || fail "Failed to change to GCC source directory"
    rm -rf build
    mkdir -p build
    cd build || fail "Failed to create and enter build directory"

    log "INFO" "Starting build process for GCC $version"
    log "INFO" "Configuring GCC $version..."

    # Configure with proper array expansion
    if ! verbose_logging ../configure "${configure_options[@]}"; then
        fail "Configure failed. Check the output above for errors."
    fi
    log "INFO" "Configuration completed successfully"

    # Build GCC
    log "INFO" "Building GCC $version..."
    if ! make_gcc; then
        fail "Build failed. Check the output above for errors."
    fi
    log "INFO" "Build completed successfully"

    # Install GCC
    log "INFO" "Installing GCC $version..."
    if ! install_gcc; then
        fail "Installation failed. Check the output above for errors."
    fi
    log "INFO" "Installation completed successfully"

    # Post-installation tasks
    post_build_tasks "$version"
    ld_linker_path "$version"
    create_additional_soft_links "$install_dir"
    trim_binaries "$version"
    save_static_binaries "$version"
    build_done "gcc" "$version"
}

check_dependencies() {
    local -A deps=(
        [build-essential]="gcc g++ make"
        [curl]="curl"
        [autoconf]="autoconf"
        [automake]="automake"
        [libtool]="libtool"
        [pkg-config]="pkg-config"
        [texinfo]="texinfo"
    )
    
    local missing_pkgs=()
    
    for pkg in "${!deps[@]}"; do
        if ! dpkg -l "$pkg" &>/dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done
    
    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        log "WARNING" "Missing required packages: ${missing_pkgs[*]}"
        if [[ "$dry_run" -eq 1 ]]; then
            log "INFO" "Dry run: would install ${missing_pkgs[*]}"
            return 0
        fi
        
        if ! sudo apt-get update; then
            fail "Failed to update package lists"
        fi
        
        if ! sudo apt-get install -y "${missing_pkgs[@]}"; then
            fail "Failed to install required packages"
        fi
    fi
}

trap_errors() {
    local exit_code=$?
    local line_no=$1
    
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Script failed at line $line_no with exit code $exit_code"
        if [[ -f "$build_dir/.build_state" ]]; then
            log "INFO" "Build failed during stage: $(build_state load)"
        fi
        cleanup
        exit $exit_code
    fi
}

trap 'trap_errors $LINENO' ERR

check_feature_requirements() {
    # Check disk space (in MB)
    local required_space=5000
    local available_space
    available_space=$(df -m "$(dirname "$build_dir")" | awk 'NR==2 {print $4}')
    
    if [[ "$available_space" -lt "$required_space" ]]; then
        fail "Insufficient disk space. Required: ${required_space}MB, Available: ${available_space}MB"
    fi
    
    # Check memory requirements (in MB)
    local required_memory=2000
    local available_memory
    available_memory=$(free -m | awk '/^Mem:/ {print $2}')
    
    if [[ "$available_memory" -lt "$required_memory" ]]; then
        fail "Insufficient memory. Required: ${required_memory}MB, Available: ${available_memory}MB"
    fi
}

check_and_create_dir() {
    local dir=$1
    local use_sudo=${2:-0}
    local mode=${3:-755}
    
    if [[ ! -d "$dir" ]]; then
        if [[ $use_sudo -eq 1 ]]; then
            sudo mkdir -p "$dir" || return 1
            sudo chmod "$mode" "$dir" || return 1
            sudo chown "$USER:$USER" "$dir" || return 1
        else
            mkdir -p "$dir" || return 1
            chmod "$mode" "$dir" || return 1
        fi
    elif [[ ! -w "$dir" && $use_sudo -eq 1 ]]; then
        sudo chown "$USER:$USER" "$dir" || return 1
    fi
    return 0
}

extract_source() {
    local version=$1
    local src_file="gcc-$version.tar.xz"
    local url="https://ftp.gnu.org/gnu/gcc/gcc-$version/$src_file"
    
    if ! download "$url"; then
        fail "Failed to download GCC source"
    fi
    
    cd "$workspace" || fail "Failed to change to workspace directory"
    if ! tar xf "$build_dir/$src_file"; then
        fail "Failed to extract GCC source"
    fi
    
    cd "gcc-$version" || fail "Failed to change to GCC source directory"
    return 0
}

configure_gcc() {
    local options=("$@")
    
    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Would configure GCC with options: ${options[*]}"
        return 0
    fi
    
    if ! ./configure "${options[@]}"; then
        fail "GCC configuration failed"
    fi
    return 0
}

make_gcc() {
    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Would build GCC"
        return 0
    fi
    
    echo -e "\n${GREEN}[INFO]${NC} Building GCC (this may take a while)..."
    local start_time=$(date +%s)
    
    if [[ "$debug_mode" -eq 1 ]]; then
        # Full output in debug mode
        if ! make -j"$threads"; then
            log "WARNING" "Parallel make failed, trying single-threaded"
            if ! make; then
                fail "GCC build failed"
            fi
        fi
    else
        # Show filtered progress updates
        if ! make -j"$threads" 2>&1 | while read -r line; do
            # Filter out duplicate recipe warnings and only show unique messages
            case "$line" in
                *"Entering directory"*)
                    echo -e "\n${GREEN}[BUILD]${NC} Starting: ${line##* }"
                    ;;
                *"Leaving directory"*)
                    echo -e "${GREEN}[BUILD]${NC} Completed: ${line##* }"
                    ;;
                *"error:"*)
                    echo -e "${RED}[ERROR]${NC} ${line##*: error: }"
                    return 1
                    ;;
                *"Making all in"*)
                    echo -e "${GREEN}[BUILD]${NC} ${line}"
                    ;;
                *"warning:"*)
                    # Only show non-recipe warnings
                    if [[ ! "$line" =~ "recipe for target" ]]; then
                        echo -e "${YELLOW}[WARNING]${NC} ${line##*: warning: }"
                    fi
                    ;;
            esac
            
            # Show periodic time updates
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            if ((elapsed % 300 == 0 && elapsed > 0)); then  # Every 5 minutes
                echo -e "\n${GREEN}[INFO]${NC} Build in progress - $((elapsed/60)) minutes elapsed"
            fi
        done; then
            log "WARNING" "Parallel make failed, trying single-threaded"
            if ! make 2>&1 | while read -r line; do
                case "$line" in
                    *"Making"*|*"make["*"]"*)
                        echo -e "${GREEN}[BUILD]${NC} ${line}"
                        ;;
                    *"error:"*)
                        echo -e "${RED}[ERROR]${NC} ${line##*: error: }"
                        ;;
                    *"warning:"*)
                        # Only show non-recipe warnings
                        if [[ ! "$line" =~ "recipe for target" ]]; then
                            echo -e "${YELLOW}[WARNING]${NC} ${line##*: warning: }"
                        fi
                        ;;
                esac
            done; then
                fail "GCC build failed"
            fi
        fi
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log "INFO" "Build completed in $((duration/60)) minutes and $((duration%60)) seconds"
    return 0
}

install_gcc() {
    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Would install GCC"
        return 0
    fi
    
    if ! sudo make install; then
        fail "GCC installation failed"
    fi
    return 0
}

summary() {
    log "INFO" "Build Summary:"
    for version in "${selected_versions[@]}"; do
        log "INFO" "- GCC $version installation completed"
    done
}

main() {
    parse_args "$@"
    [[ -n "$log_file" ]] && setup_logging
    
    check_dependencies
    check_feature_requirements
    
    if [[ "$EUID" -eq 0 ]]; then
        fail "This script must be run without root or sudo"
    fi
    
    # Create necessary directories
    check_and_create_dir "$packages" 0 755 || fail "Failed to create packages directory"
    check_and_create_dir "$workspace" 0 755 || fail "Failed to create workspace directory"
    
    cleanup_build_folders
    
    threads=$(nproc --all)
    
    set_path
    set_pkg_config_path
    set_environment
    install_deps
    install_autoconf
    select_versions
    
    for version in "${selected_versions[@]}"; do
        latest_version=$(get_latest_version "$version")
        if [[ -z "$latest_version" ]]; then
            fail "Failed to determine latest version for GCC $version"
        fi
        build_gcc "$latest_version"
    done
    
    cleanup
    summary
    
    log "INFO" "Build completed successfully!"
}

main "$@"
