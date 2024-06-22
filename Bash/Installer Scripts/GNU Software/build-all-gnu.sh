#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-all-gnu.sh
# Purpose: Build various GNU programs from source code
# Updated: 06.22.24
# Version: 1.4

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# List of available programs
available_programs=(
    autoconf autoconf-archive bash gawk grep gzip libtool
    make nano parallel pkg-config sed tar texinfo wget which
)

# Consolidated list of required packages for all programs
MASTER_PKGS="autoconf autoconf-archive automake build-essential bzip2 ccache curl libc6-dev"
MASTER_PKGS+=" libintl-perl libtool lzip lzma lzma-dev m4 texinfo xz-utils zlib1g-dev"

# Specific package lists for each program (excluding those already in MASTER_PKGS)
BASH_PKGS="libacl1-dev libattr1-dev liblzma-dev libzstd-dev lzip lzop"
GAWK_PKGS="libgmp-dev libmpfr-dev libreadline-dev libsigsegv-dev lzip"
GREP_PKGS="libltdl-dev libsigsegv-dev"
GZIP_PKGS="libzstd-dev zstd"
MAKE_PKGS="libdmalloc-dev libsigsegv2"
NANO_PKGS="libncurses5-dev libpth-dev nasm"
PKG_CONFIG_PKGS="libglib2.0-dev libpopt-dev"
SED_PKGS="autopoint autotools-dev libaudit-dev librust-polling-dev valgrind"
TAR_PKGS="libacl1-dev libattr1-dev libbz2-dev liblzma-dev libzstd-dev lzip lzop"
PARALLEL_PKGS="autogen binutils bison lzip yasm"
WGET_PKGS="gfortran libcurl4-openssl-dev libexpat1-dev libgcrypt20-dev libgpgme-dev libssl-dev libunistring-dev"
WHICH_PKGS="curl gcc make tar"

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

show_usage() {
    echo -e "${YELLOW}Usage:${NC} $0 [OPTIONS]"
    echo
    echo -e "${YELLOW}Description:${NC} Build various GNU programs from source code."
    echo
    echo -e "${YELLOW}Options:${NC}"
    echo "  -h, --help           Show this help message and exit"
    echo "  -p, --programs       Specify the programs to build (comma-separated, or 'all' for all programs)"
    echo
    echo -e "${YELLOW}Available Programs:${NC}"
    printf "%s\n" "${available_programs[@]}"
    echo
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 -p all"
    echo "  $0 -p bash,make,grep"
}

# Parse command-line options
programs=""
version=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -p|--programs)
            shift
            programs="$1"
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
    shift
done

# Check for the root user
if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Display available programs and prompt for programs if not specified via arguments
if [[ -z "$programs" ]]; then
    echo "Available Programs: ${available_programs[*]}"
    echo "You can also choose 'all' to install all available programs."
    echo
    read -p "Enter the programs to build (comma-separated): " programs
    clear
fi

# Function to check and install required packages
required_packages() {
    local -a pkgs
    local pkg

    pkgs=($MASTER_PKGS)

    if [[ "$1" == "all" ]]; then
        pkgs+=("$BASH_PKGS" "$GAWK_PKGS" "$GREP_PKGS" "$GZIP_PKGS" "$MAKE_PKGS" "$NANO_PKGS" "$PKG_CONFIG_PKGS" "$SED_PKGS" "$TAR_PKGS" "$PARALLEL_PKGS" "$WGET_PKGS" "$WHICH_PKGS")
    else
        for prog in "${progs[@]}"; do
            case "$prog" in
                bash)
                    pkgs+=("$BASH_PKGS")
                    ;;
                gawk)
                    pkgs+=("$GAWK_PKGS")
                    ;;
                grep)
                    pkgs+=("$GREP_PKGS")
                    ;;
                gzip)
                    pkgs+=("$GZIP_PKGS")
                    ;;
                make)
                    pkgs+=("$MAKE_PKGS")
                    ;;
                nano)
                    pkks+=("$NANO_PKGS")
                    ;;
                pkg-config)
                    pkgs+=("$PKG_CONFIG_PKGS")
                    ;;
                sed)
                    pkgs+=("$SED_PKGS")
                    ;;
                tar)
                    pkgs+=("$TAR_PKGS")
                    ;;
                parallel)
                    pkgs+=("$PARALLEL_PKGS")
                    ;;
                wget)
                    pkgs+=("$WGET_PKGS")
                    ;;
                which)
                    pkgs+=("$WHICH_PKGS")
                    ;;
            esac
        done
    fi

    # Remove duplicate packages and sort alphabetically
    pkgs=($(echo "${pkgs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    local -a available_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if apt-cache show "$pkg" &> /dev/null; then
            available_pkgs+=("$pkg")
        else
            log "Package $pkg is not available in the apt database and will be skipped."
        fi
    done

    if [[ "${#available_pkgs[@]}" -gt 0 ]]; then
        sudo apt update
        sudo apt install -y "${available_pkgs[@]}"
    fi
}

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath=$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

get_latest_version_url() {
    local prog_name version
    prog_name=$1
    if [[ "$prog_name" == "pkg-config" ]]; then
        version=$(curl -fsS "https://pkgconfig.freedesktop.org/releases/" | grep -oP 'pkg-config-\K[0-9]+\.[0-9\.]+(?=\.tar\.gz)' | sort -ruV | head -n1)
    else
        version=$(curl -fsS "https://ftp.gnu.org/gnu/$prog_name/" | grep -oP "$prog_name-\K([0-9.]+)(?=\.tar\.)" | sort -ruV | head -n1)
    fi
    if [[ -z "$version" ]]; then
        fail "Failed to find the latest version for $prog_name. Please check the program name or the respective server."
    fi
    echo "$version"
}

download_and_extract() {
    local archive_url

    if [[ "$prog_name" == "pkg-config" ]]; then
        archive_url="https://pkgconfig.freedesktop.org/releases/pkg-config-$version.tar.gz"
    else
        archive_url="https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar"
        for ext in lz xz bz2 gz; do
            wget --spider "$archive_url.$ext" &>/dev/null && archive_url+=".$ext" && break
        done
    fi

    wget --show-progress -cqO "$cwd/$archive_name.${archive_url##*.}" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
    tar -xf "$cwd/$archive_name.${archive_url##*.}" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$archive_name.${archive_url##*.}"
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"
    
    case "$prog_name" in
        autoconf)
            ./configure --prefix="$install_dir" || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        bash)
            ./configure --prefix="$install_dir" --enable-static-link --enable-multibyte || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        findutils)
            ./configure --prefix="$install_dir" --enable-threads=posix --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        gawk)
            ./configure --prefix="$install_dir" --disable-nls --with-readline=/usr --with-mpfr=/usr || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        grep)
            ./configure --prefix="$install_dir" --disable-nls --enable-threads=posix --with-libsigsegv --with-libsigsegv-prefix=/usr || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        gzip)
            ./configure --prefix="$install_dir" --disable-gcc-warnings --enable-silent-rules || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        libtool)
            ./configure --prefix="$install_dir" --enable-ltdl-install || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        make)
            ./configure --prefix="$install_dir" --disable-nls --enable-year2038 --with-dmalloc --with-libsigsegv-prefix=/usr || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        nano)
            ./configure --prefix="$install_dir" --enable-utf8 || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        pkg-config)
            ./configure --prefix="$install_dir" --with-internal-glib --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        sed)
            ./configure --prefix="$install_dir" --enable-threads=posix --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        tar)
            ./configure --prefix="$install_dir" --disable-nls --disable-gcc-warnings --with-bzip2="$(command -v bzip2)" \
                        --with-lzip="$(command -v lzip)" --with-lzma="$(command -v lzma)" --with-xz="$(command -v xz)" \
                        --with-zstd="$(command -v zstd)" --with-lzop="$(command -v lzop)" --with-gzip="$(command -v gzip)" || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        wget)
            autoreconf -fi -I /usr/share/aclocal || fail "Failed to execute: autoreconf. Line: $LINENO"
            ./configure --prefix="$install_dir" --with-ssl=openssl --with-libssl-prefix="$cwd" --with-metalink \
                        --with-libunistring-prefix=/usr --with-libcares --without-ipv6 --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        which)
            autoconf || fail "Failed to execute: autoconf. Line: $LINENO"
            ./configure --prefix="$install_dir" || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        make|wget)
            autoreconf -fi -I /usr/share/aclocal || fail "Failed to execute: autoreconf. Line: $LINENO"
            ./configure --prefix="$install_dir" || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        *)
            autoreconf -fi || fail "Failed to execute: autoreconf. Line: $LINENO"
            ./configure --prefix="$install_dir" --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
    esac
}

compile_and_install() {
    local version=$1
    make "-j$(nproc --all)" || fail "Failed to execute: make build. Line: $LINENO"
    sudo make install || fail "Failed execute: make install. Line: $LINENO"
}

create_soft_links() {
    # Check and link files in the bin directory
    if [ -d "$install_dir/bin" ] && [ "$(find "$install_dir/bin" -type f | wc -l)" -gt 0 ]; then
        sudo ln -sf "$install_dir/bin/"* "/usr/local/bin/"
    fi

    # Check and link .pc files in the lib/pkgconfig directory
    if [ -d "$install_dir/lib/pkgconfig" ] && [ "$(find "$install_dir/lib/pkgconfig" -name '*.pc' | wc -l)" -gt 0 ]; then
        sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    fi

    # Check and link files in the include directory
    if [ -d "$install_dir/include" ] && [ "$(find "$install_dir/include" -type f | wc -l)" -gt 0 ]; then
        sudo ln -sf "$install_dir/include/"* "/usr/local/include/"
    fi
}

ld_linker_path() {
    local ld_file="/etc/ld.so.conf.d/custom_libs.conf"
    if [[ ! -f "$ld_file" ]]; then
        echo -e "$install_dir/lib" | sudo tee "$ld_file" >/dev/null
    else
        grep -qxF "$install_dir/lib" "$ld_file" || echo "$install_dir/lib" | sudo tee -a "$ld_file" >/dev/null
    fi
    sudo ldconfig
}

cleanup() {
    sudo rm -fr "$cwd"
}

build_program() {
    local prog_name version
    prog_name="$1"
    version="$2"

    echo
    log "Building $prog_name"
    if [[ -z "$version" ]]; then
        version=$(get_latest_version_url "$prog_name")
    fi
    archive_name="$prog_name-$version"
    install_dir="/usr/local/programs/$archive_name"
    cwd="/tmp/$prog_name-build-script"
    tar_file="$archive_name.$(date +%s)"
    mkdir -p "$cwd/$archive_name/build"
    set_compiler_flags
    download_and_extract
    configure_build
    compile_and_install "$version"
    ld_linker_path
    create_soft_links
    cleanup
}

# Build each specified program
IFS=',' read -ra progs <<< "$programs"
if [[ "$programs" == "all" ]]; then
    progs=("${available_programs[@]}")
fi

required_packages "${progs[@]}"

for prog in "${progs[@]}"; do
    build_program "$prog" "$version"
done

echo
log "All specified programs have been built and installed successfully."
