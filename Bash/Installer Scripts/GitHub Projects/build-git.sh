#!/usr/bin/env bash

# Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-git.sh
# Purpose: Build Git
# Updated: 05.06.24
# Script version: 1.5

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Set the variables
script_ver=1.5
prog_name="git"
version=$(curl -fsS "https://github.com/git/git/tags/" | grep -oP 'href="[^"]*/tag/v?\K([0-9.])+' | sort -ruV | head -n1)
dir_name="$prog_name-$version"
archive_url="https://github.com/git/git/archive/refs/tags/v$version.tar.gz"
archive_ext="${archive_url//*.}"
tar_file="$dir_name.tar.$archive_ext"
install_dir="/usr/local/$dir_name"
cwd="$PWD/$dir_name-build-script"
keep_build="false"
compiler="gcc"
verbose="true"

# Function to display help menu
display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -v, --version      Set the Git version number for installation"
    echo "  -k, --keep         Keep build files post-execution (default: remove)"
    echo "  -c, --compiler     Set the compiler (default: gcc, alternative: clang)"
    echo "  -p, --prefix       Set the prefix used by configure (default: /usr/local/git-VERSION)"
    echo "  -n, --no-verbose   Suppress logging"
    echo "  -l, --list         List all available Git versions"
    echo "  -h, --help         Display this help menu"
}

# Function to parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                version="$2"
                shift 2
                ;;
            -k|--keep)
                keep_build="true"
                shift
                ;;
            -c|--compiler)
                if [[ ! "$2" == "clang" ]]; then
                    fail "The alternative compiler must be \"clang\" if you pass the --compiler argument, otherwise \"gcc\" is enabled by default. Please re-run the script and modify your agruments accordingly."
                else
                    compiler="$2"
                fi
                shift 2
                ;;
            -p|--prefix)
                prefix="$2"
                shift 2
                ;;
            -n|--no-verbose)
                verbose="false"
                shift
                ;;
            -l|--list)
                list_git_versions
                exit 0
                ;;
            -h|--help)
                display_help
                exit 0
                ;;
            *)  echo -e "${RED}[fail]${NC} Invalid argument: $1"
                display_help
                exit 1
                ;;
        esac
    done
}

# Function to log messages
log() {
    if [[ "$verbose" == true ]]; then
        echo -e "${GREEN}[LOG]${NC} $1"
    fi
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

echo "$prog_name build script - v$script_ver"
echo "==============================================="
echo

# Create functions
exit_fn() {
    echo
    log "The script has completed"
    log "${GREEN}Make sure to ${YELLOW}star ${GREEN}this repository to show your support!${NC}"
    log "${CYAN}https://github.com/slyfox1186/script-repo${NC}"
    exit 0
}

# Function to clean up build files
cleanup() {
    if [[ "$keep_build" == "true" ]]; then
        log "Keeping the build files as requested."
    else
        log "Cleaning up build files..."
        sudo rm -rf "$cwd"
    fi
}

install_required_packages() {
    local -a missing_pkgs pkgs
    local pkg
    pkgs=(
        autoconf autoconf-archive build-essential gettext libcurl4-gnutls-dev libexpat1-dev
        libpcre2-dev libssl-dev libticonv-dev libtool m4 perl "$compiler" zlib1g-dev
   )

    missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ "${#missing_pkgs[@]}" -gt 0 ]; then
        sudo apt update
        sudo apt install "${missing_pkgs[@]}"
    fi
}

set_compiler_flags() {
    CC="$compiler"
    CXX="$compiler++"
    CFLAGS="-O2 -fPIC -fPIE -mtune=native -DNDEBUG -fstack-protector-strong -Wno-unused-parameter"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

download_archive() {
    wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    [[ -d "$cwd/$dir_name" ]] && sudo rm -fr "$cwd/$dir_name"
    mkdir -p "$cwd/$dir_name"
    tar -zxf "$cwd/$tar_file" -C "$cwd/$dir_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

configure_build() {
    cd "$cwd/$dir_name" || fail "Failed to cd into \"$cwd/$dir_name\". Line: $LINENO"
    autoreconf -fi
    curl_prefix=$(find /usr/ -type f -name curl 2>/dev/null | sort -ruV | head -n1 | awk -F'/bin/curl' '{print $1}' | grep -oP '^/usr(/local)?')
    ./configure --prefix="$install_dir" --with-libpcre2 --with-curl="$curl_prefix" \
                 --with-iconv=/usr --with-editor="$(type -P nano)" --with-shell="$(type -P sh)" \
                 --with-perl="$(type -P perl)" --with-python="$(type -P python3)" || fail "Failed to execute: meson setup. Line: $LINENO"
}

compile_build() {
    make "-j$(nproc --all)" || fail "Failed to execute: make build. Line: $LINENO"
}

install_build() {
    sudo make install || fail "Failed execute: sudo make install. Line: $LINENO"
}

create_soft_links() {
    sudo ln -sf "$install_dir/bin/"* "/usr/local/bin/"
    sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    sudo ln -sf "$install_dir/include/"* "/usr/local/include/"
}

main_menu() {
    # Create output directory
    if [[ -d "$cwd" ]]; then
        sudo rm -fr "$cwd/$dir_name"
    fi
    mkdir -p "$cwd"

    parse_arguments "$@"
    install_required_packages
    set_compiler_flags
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    create_soft_links
    cleanup
    exit_fn
}

main_menu "$@"

