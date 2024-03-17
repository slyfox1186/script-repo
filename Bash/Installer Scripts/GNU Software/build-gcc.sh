#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc.sh
# Build GNU GCC
# Versions available:  9|10|11|12|13
# Features: Automatically sources the latest release of each version.
# Updated: 03.17.2024

set -eou pipefail

build_dir="/tmp/gcc-build-script"
workspace="$build_dir/workspace"
verbose=0
log_file=""
LDFLAGS=""
version=""
versions=()

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo "Usage: ./build-gcc.sh [OPTIONS]"
    echo "Options:"
    printf "  %-25s %s\n" "-p, --prefix DIR" "Set the installation prefix (default: /usr/local)"
    printf "  %-25s %s\n" "-v, --verbose" "Enable verbose logging"
    printf "  %-25s %s\n" "-l, --log-file FILE" "Specify a log file for output"
    printf "  %-25s %s\n" "-k, --keep-build-dir" "Keep the temporary build directory after completion"
    printf "  %-25s %s\n" "-h, --help" "Show this help message"
    exit 0
}

log() {
    local message="$1"
    local timestamp=$(date +'%m.%d.%Y %I:%M:%S %p')
    if [[ "$verbose" -eq 1 ]]; then
        echo -e "\\n${GREEN}[INFO]${NC} $timestamp $message\\n"
    fi
    if [[ -n "$log_file" ]]; then
        echo "$timestamp $message" >> "$log_file"
    fi
}

warn() {
    local message="$1"
    local timestamp=$(date +'%m.%d.%Y %I:%M:%S %p')
    echo -e "${YELLOW}[WARN]${NC} $timestamp $message"
    if [[ -n "$log_file" ]]; then
        echo "$timestamp WARNING: $message" >> "$log_file"
    fi
}

fail() {
    local message="$1"
    local timestamp=$(date +'%m.%d.%Y %I:%M:%S %p')
    echo -e "${RED}[ERROR]${NC} $timestamp $message"
    if [[ -n "$log_file" ]]; then
        echo "$timestamp ERROR: $message" >> "$log_file"
    fi
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -p|--prefix)
                install_prefix="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=1
                shift
                ;;
            -l|--log-file)
                log_file="$2"
                shift 2
                ;;
            -k|--keep-build-dir)
                keep_build_dir=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)  fail "Unknown option: $1. Use -h or --help for usage information." ;;
        esac
    done
}

set_ccache_dir() {
    if [[ -d "/usr/lib/ccache/bin" ]]; then
        ccache_dir="/usr/lib/ccache/bin"
    elif [[ -d "/usr/lib/ccache" ]]; then
        ccache_dir="/usr/lib/ccache"
    else
        fail "Unable to locate the ccache directory. Please make sure ccache is installed."
    fi
}

set_env_vars() {
    log "Setting environment variables..."
    CC="gcc"
    CXX="g++"
    CFLAGS="-g -O3 -pipe -march=native"
    CXXFLAGS="-g -O3 -pipe -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath"
    LDFLAGS+=",/usr/local/gcc-$version/lib64,-rpath,/usr/local/gcc-$version/lib"
    PATH="$ccache_dir:$workspace/bin:$HOME/perl5/bin:$HOME/.cargo/bin:"
    PATH+="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:"
    PKG_CONFIG_PATH+="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:"
    PKG_CONFIG_PATH+="/usr/lib64/pkgconfig:/usr/lib/pkgconfig"
    export CC CFLAGS CPPFLAGS CXX CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

install_deps() {
    log "Installing dependencies..."
    local deps=(
                autoconf autoconf-archive automake binutils bison build-essential
                ccache curl flex gawk gcc g++ gnat libc6-dev libtool make m4 patch
                texinfo zlib1g-dev
           )
    if command -v apt-get &>/dev/null; then
        apt-get update
        for dep in "${deps[@]}"; do
            if ! dpkg -s "$dep" >/dev/null 2>&1; then
                apt-get install -y "$dep"
            fi
        done
    elif command -v dnf &>/dev/null; then
        for dep in "${deps[@]}"; do
            if ! rpm -q "$dep" >/dev/null 2>&1; then
                dnf install -y "$dep"
            fi
        done
    elif command -v pacman &>/dev/null; then
        for dep in "${deps[@]}"; do
            if ! pacman -Qs "$dep" >/dev/null 2>&1; then
                pacman -S --noconfirm --needed "$dep"
            fi
        done
    else
        fail "Unsupported package manager. Please install the required dependencies manually."
    fi
}

download() {
    local url="$1"
    local filename="${url##*/}"
    if [[ ! -f "$build_dir/$filename" ]]; then
        log "Downloading $url"
        curl -fsSLo "$build_dir/$filename" "$url"
    fi

    local extract_dir="${filename%.tar.xz}"
    if [[ ! -d "$build_dir/$extract_dir" ]]; then
        log "Extracting $filename"
        if ! tar -xf "$build_dir/$filename" -C "$working"; then
            fail "Failed to extract $filename"
        fi
    else
        log "Source directory $build_dir/$extract_dir already exists"
    fi
}

install_autoconf() {
    log "Installing autoconf 2.69"
    wget --show-progress -cqO "$build_dir/autoconf-2.69.tar.xz" "https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz"
    mkdir -p "$build_dir/autoconf-2.69/build" "$workspace"
    tar -xf "$build_dir/autoconf-2.69.tar.xz" -C "$build_dir/autoconf-2.69" --strip-components 1
    cd "$build_dir/autoconf-2.69" || fail "Failed to change directory to $build_dir/autoconf-2.69. Line: $LINENO"
    autoupdate
    autoconf
    cd build || fail "Failed to change directory to build. Line: $LINENO"
    ../configure --prefix="$build_dir/workspace"
    make "-j$(nproc --all)"
    make install
}

get_latest_gcc_version() {
    local major_version="$1"
    curl -fsS "https://ftp.gnu.org/gnu/gcc/" | grep -Eo "gcc-$major_version\.[0-9]+\.[0-9]+" | sort -rV | head -n1 | cut -d- -f2
}

build_gcc() {
    local version="$1"
    local languages="$2"
    local configure_options="$3"

    log "Building GCC $version"
    download "https://ftp.gnu.org/gnu/gcc/gcc-$version/gcc-$version.tar.xz"

    local gcc_dir="$build_dir/gcc-$version"
    if [[ ! -d "$gcc_dir" ]]; then
        fail "GCC $version source directory not found: $gcc_dir"
    fi

    cd "$gcc_dir" || fail "Failed to change directory to $gcc_dir"

    log "Running autoreconf and downloading prerequisites"
    autoreconf -fi
    ./contrib/download_prerequisites

    mkdir -p builddir
    cd builddir || fail "Failed to change directory to builddir"

    log "Configuring GCC $version"
    ../configure --prefix="/usr/local/gcc-$version" \
                 --enable-languages="$languages" \
                 --disable-multilib --with-system-zlib \
                 "$configure_options"

    log "Compiling GCC $version"
    make "-j$(nproc --all)"

    log "Installing GCC $version"
    make install-strip
}

create_symlinks() {
    local version="$1"
    log "Creating symlinks for GCC $version..."

    local bin_dir="/usr/local/gcc-$version/bin"
    local target_dir="/usr/local/bin"

    local programs=(
        c++ cpp g++ gcc gcc-ar gcc-nm gcc-ranlib
        gcov gcov-dump gcov-tool gfortran gnat gnatbind
        gnatchop gnatclean gnatkr gnatlink gnatls gnatmake
        gnatname gnatprep lto-dump
    )

    for program in "${programs[@]}"; do
        local source_path="$bin_dir/$program"
        if [[ -x "$source_path" ]]; then
            local symlink_path="$target_dir/$program-$version"
            ln -sfn "$source_path" "$symlink_path"
            log "Created symlink: $symlink_path -> $source_path"
        fi
    done
}

select_versions() {
    local -a versions=(9 10 11 12 13)
    local -a selected_versions=()

    echo -e "\\n${GREEN}Select the GCC version(s) to install:${NC}\\n"
    echo -e "${CYAN}1. Single version${NC}"
    echo -e "${CYAN}2. All versions${NC}"
    echo -e "${CYAN}3. Custom versions${NC}"

    echo
    read -p "Enter your choice: " choice

    case "$choice" in
        1)
            echo -e "\\n${GREEN}Select a single GCC version to install:${NC}\\n"
            for ((i=0; i<${#versions[@]}; i++)); do
                echo -e "${CYAN}$((i+1)). GCC ${versions[i]}${NC}"
            done
            echo
            read -p "Enter your choice: " single_choice
            selected_versions+=("${versions[$((single_choice-1))]}")
            ;;
        2)
            selected_versions=("${versions[@]}")
            ;;
        3)
            read -p "Enter comma-separated versions or ranges (e.g., 11,13 or 11-13): " custom_choice
            IFS=',' read -ra custom_versions <<< "$custom_choice"
            for version in "${custom_versions[@]}"; do
                if [[ $version =~ ^[0-9]+$ ]]; then
                    selected_versions+=("$version")
                elif [[ $version =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    start=${BASH_REMATCH[1]}
                    end=${BASH_REMATCH[2]}
                    for ((i=start; i<=end; i++)); do
                        selected_versions+=("$i")
                    done
                else
                    fail "Invalid version or range: $version"
                fi
            done
            ;;
        *)
            fail "Invalid choice: $choice"
            ;;
    esac

    if [[ "${#selected_versions[@]}" -eq 0 ]]; then
        fail "No GCC versions selected."
    fi

    # Install GCC's recommended version of autoconf (version 2.69)
    install_autoconf

    for version in "${selected_versions[@]}"; do
        latest_version=$(get_latest_gcc_version "$version")
        case "$version" in
            10)
                build_gcc "$latest_version" "c,c++,fortran,objc,obj-c++,ada" "--enable-checking=release --with-arch-32=i686"
                ;;
            11|12|13)
                build_gcc "$latest_version" "c,c++,fortran,objc,obj-c++,ada" "--enable-checking=release"
                ;;
        esac
        create_symlinks "$latest_version"
    done
}

cleanup() {
    if [[ "$keep_build_dir" -ne 1 ]]; then
        log "Cleaning up..."
        rm -rf "$build_dir"
        log "Removed temporary build directory: $build_dir"
    else
        log "Temporary build directory retained: $build_dir"
    fi
}

summary() {
    echo -e "\\n${GREEN}Summary:${NC}\\n"
    echo -e "  Installed GCC version(s): ${CYAN}${selected_versions[*]}${NC}"
    echo -e "  Installation prefix: ${CYAN}$install_prefix${NC}"
    echo -e "  Build directory: ${CYAN}$build_dir${NC}"
    echo -e "  Temporary build directory retained: ${CYAN}$([[ "$keep_build_dir" -eq 1 ]] && echo "Yes" || echo "No")${NC}"
    echo -e "  Log file: ${CYAN}$log_file${NC}"
}

main() {
    parse_args "$@"

    if [[ "$EUID" -ne 0 ]]; then
        fail "This script must be run as root or with sudo."
    fi

    if [[ -d "$build_dir" ]]; then
        rm -rf "$build_dir"
    fi
    mkdir -p "$build_dir"

    set_ccache_dir
    set_env_vars
    install_deps
    select_versions
    cleanup
    summary

    log "Build completed successfully!"
    echo -e "${GREEN}Make sure to star this repository to show your support!${NC}"
    echo "https://github.com/slyfox1186/script-repo"
}

main "$@"
