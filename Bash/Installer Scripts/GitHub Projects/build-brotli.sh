#!/usr/bin/env bash
# shellcheck disable=SC2162,SC2317

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-brotli.sh
##  Purpose: Build GNU BROTLI
##  Updated: 03.22.24
##  Script version: 1.3

# Set variables
cwd="$PWD/brotli-build-script"
debug="OFF"
script_version=1.2

# Set color variables
RED='\033[[0;31m'
GREEN='\033[[0;32m'
YELLOW='\033[[0;33m'
NC='\033[[0m'

# Create logging functions
log() {
    echo -e "${GREEN}[[INFO]]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[[WARNING]]${NC} $1"
}

fail() {
    echo -e "${RED}[[ERROR]]${NC} $1"
    echo
    echo "To report a bug create an issue at: "
    echo "https://github.com/slyfox1186/script-repo/issues"
    echo
    exit 1
}

# Create output directory
create_dir() {
    [[ -d "$cwd" ]] && sudo rm -fr "$cwd"
    mkdir -p "$cwd"
}

# Set compiler optimization flags
set_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-rpath,/usr/local/programs/brotli-${version}/lib"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
}

# Set the path variable
set_path() {
    PATH="/usr/lib/ccache:$PATH"
    export PATH
}

# Set the pkg_config_path variable
set_pkg_config_path() {
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CXXFLAGS PATH PKG_CONFIG_PATH
}

# Exit function
exit_function() {
    log "Make sure to star this repository to show your support!"
    log "https://github.com/slyfox1186/script-repo"
    exit 0
}

# Cleanup function
cleanup_fn() {
    while true; do
        echo
        echo "============================================"
        echo "  Do you want to clean up the build files?  "
        echo "============================================"
        echo
        echo "[1] Yes"
        echo "[2] No"
        echo
        read -rp "Your choices are (1 or 2): " choice
        case "$choice" in
            1)
                sudo rm -fr "$cwd" "$0"
                break
                ;;
            2)
                break
                ;;
            *)
                warn "Invalid choice. Please try again."
                ;;
        esac
    done
}

# Build function
build() {
    log "Building $1 - version $2"
    echo

    if [[ -f "$cwd/$1.done" ]]; then
        if grep -Fx "$2" "$cwd/$1.done" >/dev/null; then
            log "$1 version $2 already built. Remove $cwd/$1.done lockfile to rebuild it."
            return 1
        else
            warn "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $cwd/$1.done lockfile."
            return 1
        fi
    fi
    return 0
}

# Execute function
execute() {
    log "$ $*"

    if [[ "$debug" = "ON" ]]; then
        if ! output=$("$@"); then
            fail "Failed to execute: $*"
        fi
    else
        if ! output=$("$@" 2>&1); then
            fail "Failed to execute: $*"
        fi
    fi
}

# Download function
download() {
    dl_path="$cwd"
    dl_url="$1"
    dl_file="${2:-${dl_url##*/}}"

    if [[ "$dl_file" =~ tar. ]]; then
        output_dir="${dl_file%.*}"
        output_dir="${3:-${output_dir%.*}}"
    else
        output_dir="${3:-${dl_file%.*}}"
    fi

    target_file="$dl_path/$dl_file"
    target_dir="$dl_path/$output_dir"

    if [[ -f "$target_file" ]]; then
        log "The file \"$dl_file\" is already downloaded."
        echo
    else
        log "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! curl -Lso "$target_file" "$dl_url"; then
            warn "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! curl -Lso "$target_file" "$dl_url"; then
                fail "The script failed to download \"$dl_file\" twice and will now exit:Line $LINENO"
            fi
        fi
        log "Download Completed"
        echo
    fi

    if [[ -d "$target_dir" ]]; then
        sudo rm -fr "$target_dir"
    fi

    mkdir -p "$target_dir"

    if [[ -n "$3" ]]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    fi

    log "File extracted: $dl_file"
    echo

    cd "$target_dir" || fail "Unable to change the working directory to: $target_dir. Line: $LINENO"
}

parse_release_version() {
    curl -fsSL "https://gitver.optimizethis.net" | bash -s "$1"
}

# Get latest release version from GitHub
get_latest_release() {
    version=$(parse_release_version "https://github.com/google/brotli.git")
    local url="https://github.com/google/brotli/archive/refs/tags/v$version.tar.gz"
    curl -Lso "brotli-$version.tar.gz" "$url"
}

# Mark build as done
build_done() {
    echo "$2" > "$cwd/$1.done"
}

# Check and install dependencies
check_dependencies() {
    pkgs=(asciidoc binutils bison build-essential cmake curl ninja-build)

    missing_pkgs=()
    for pkg in ${pkgs[@]}; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        sudo apt-get install -y "${missing_pkgs[@]}"
        sudo apt-get autoremove -y
    fi
}

# Display help menu
display_help() {
    echo "Usage: $0 [[options]]"
    echo
    echo "Options:"
    echo "  -h, --help         Display this help menu"
    echo "  -l, --latest       Force rebuild of the program even if already built"
    echo "  -d, --debug        Enable debug mode for more verbose output"
    echo "  -i, --install      Install the program (default)"
    echo
    echo "Description:"
    echo "  This script builds the Brotli compression library from source."
    echo "  It downloads the latest release, compiles it with optimized flags,"
    echo "  and installs it to /usr/local/brotli-VERSION."
    echo
    echo "  The script checks for dependencies and installs any missing packages."
    echo "  It also sets up the necessary environment variables and paths."
    echo
    echo "  By default, the script will not rebuild Brotli if it has already been built."
    echo "  Use the --latest flag to force a rebuild, or remove the lockfile in $cwd/brotli.done."
    echo
    echo "Examples:"
    echo "  $0 --latest"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            debug="ON"
            ;;
        -h|--help)
            display_help
            ;;
        *)
            warn "Unknown argument: $1"
            display_help
            ;;
    esac
    shift
done

# Main script
if [[ "$EUID" -eq 0 ]]; then
    fail "You must run this script without root or sudo."
fi

log "Brotli build script - v$script_version"
log "========================================"
echo

create_dir
check_dependencies
set_flags
set_path
set_pkg_config_path

get_latest_release
if build "brotli" "$version"; then
    download "https://github.com/google/brotli/archive/refs/tags/v$version.tar.gz" "brotli-$version.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="/usr/local/programs/brotli-$version" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DBUILD_TESTING=OFF \
                  -G Ninja -Wno-dev
    execute sudo ninja "-j$(nproc --all)" -C build
    execute sudo ninja "-j$(nproc --all)" -C build install
    execute sudo ln -sf "/usr/local/brotli-$version/bin/"{brotli,brotli-decompressor} /usr/local/bin/
    build_done "brotli" "$version"
fi

cleanup_fn
exit_function
