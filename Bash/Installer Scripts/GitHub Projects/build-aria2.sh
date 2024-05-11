#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-aria2.sh
##  Purpose: Build aria2 from source code with hardening options
##  Updated: 05.11.24
##  Script version: 2.6

script_ver="2.6"

echo "aria2 build script - version $script_ver"
echo "==============================================="
echo

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

export ARIA2_STATIC="no"

log() {
    echo -e "${GREEN}[LOG]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

display_help() {
    echo "Usage: $0 [OPTION]..."
    echo "Build aria2 from source code with hardening options."
    echo
    echo "Options:"
    echo "  -s, --service       Create aria2 service"
    echo "  -d, --debug         Enable debug mode for more detailed output"
    echo "  -S, --static        Set aria2 as statically linked (ARIA2_STATIC=yes)"
    echo "  -h, --help          Display this help message and exit"
    echo
    echo "Examples:"
    echo "  $0                     # Build aria2 from source"
    echo "  $0 --static            # Build aria2 from source and set as statically linked"
    echo "  $0 -s --static         # Build aria2 and create a systemd service, and set as statically linked"
    echo "  $0 -d --static         # Build aria2 with debug mode, and set as statically linked"
    echo
    exit 0
}

set_compiler_options() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -fPIC -fPIE -mtune=native -DNDEBUG -fstack-protector-strong -Wno-unused-parameter"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now -Wl,-rpath,/usr/local/lib"
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}


PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:\
/usr/bin:\
/bin\
"
export PATH

PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig\
"
export PKG_CONFIG_PATH

install_packages() {
    local pkgs=(
                autoconf autoconf-archive automake build-essential ca-certificates
                ccache curl google-perftools libgoogle-perftools-dev libssl-dev
                libtool m4 pkg-config zlib1g-dev
            )
    log "Attempting to install required packages..."
    echo
    for pkg in "${pkgs[@]}"; do
        if sudo dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=" $pkg"
        fi
    done
    [[ -n "$missing_pkgs" ]] && sudo apt -y install $missing_pkgs
    echo
    log "Installation of required packages completed."
    echo
}

source_the_latest_version() {
    curl -sSL "https://gitver.optimizethis.net" | bash -s "$1"
}

libgpg_latest_release_version() {
    local latest_version url
    url="$1"
    latest_version=$(curl -fsS "$url" | grep -oP 'href="libgpg-error-[0-9]+\.[0-9]+\.tar\.bz2"' | head -n1 | grep -oP '[0-9]+\.[0-9]+')
    if [[ -z "$latest_version" ]]; then
        echo "Failed to find the latest version of libgpg-error."
        exit 1
    else
        echo "$latest_version"
    fi
}

prepare_build_environment() {
    temp_dir="/tmp/aria2-temp-$(date +%s)"
    log "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir"
    working="$temp_dir/working"
    log "Creating temporary directory: $working"
    mkdir -p "$working"
}

build_libgpg_error() {
    local libgpg_error_version
    echo
    log "Compiling libgpg-error..."
    echo
    libgpg_error_version=$(libgpg_latest_release_version "https://gnupg.org/ftp/gcrypt/libgpg-error/")
    curl -Lso "libgpg-error-$libgpg_error_version.tar.bz2" "https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-$libgpg_error_version.tar.bz2"
    mkdir -p "libgpg-error-$libgpg_error_version/build"
    tar -jxf "libgpg-error-$libgpg_error_version.tar.bz2" -C "libgpg-error-$libgpg_error_version" --strip-components 1
    cd "libgpg-error-$libgpg_error_version/build" || exit 1
    ../configure --prefix="$working" --enable-static --disable-shared || fail "Failed to configure libgpg-error. Line $LINENO"
    make "-j$(nproc --all)" || fail "Failed to build libgpg-error. Line $LINENO"
    sudo make install || fail "Failed to install libgpg-error. Line $LINENO"
    cd ../..
}

build_c_ares() {
    local c_ares_version
    echo
    log "Compiling c-ares..."
    echo
    c_ares_version=$(source_the_latest_version "https://github.com/c-ares/c-ares.git")
    curl -Lso "cares-$c_ares_version.tar.gz" "https://github.com/c-ares/c-ares/archive/refs/tags/cares-${c_ares_version//./_}.tar.gz"
    mkdir -p "cares-$c_ares_version/build"
    tar -zxf "cares-$c_ares_version.tar.gz" -C "cares-$c_ares_version" --strip-components 1
    cd "cares-$c_ares_version" || exit 1
    autoreconf -fi
    cd build || exit 1
    ../configure --prefix="$working" --enable-static --disable-shared || fail "Failed to configure c-ares. Line $LINENO"
    make "-j$(nproc --all)" || fail "Failed to build c-ares. Line $LINENO"
    sudo make install || fail "Failed to install c-ares. Line $LINENO"
    cd ../..
}

build_sqlite3() {
    local sqlite_version
    echo
    log "Compiling sqlite3..."
    echo
    sqlite_version=$(source_the_latest_version "https://github.com/sqlite/sqlite.git")
    curl -Lso "sqlite-$sqlite_version.tar.gz" "https://github.com/sqlite/sqlite/archive/refs/tags/version-$sqlite_version.tar.gz"
    mkdir -p "sqlite-$sqlite_version/build"
    tar -zxf "sqlite-$sqlite_version.tar.gz" -C "sqlite-$sqlite_version" --strip-components 1
    cd "sqlite-$sqlite_version/build" || exit 1
    ../configure --prefix="$working" --enable-static --disable-shared || fail "Failed to configure sqlite. Line $LINENO"
    make "-j$(nproc --all)" || fail "Failed to build sqlite. Line $LINENO"
    sudo make install || fail "Failed to install sqlite. Line $LINENO"
    cd ../..
}

# Install ca certs from curl's official website
install_ca_certs() {
    certs_ssl_dir="/etc/ssl/certs/cacert.pem"
    if [[ ! -f "$certs_ssl_dir"  ]]; then
        curl -LSso "cacert.pem" "https://curl.se/ca/cacert.pem"
        sudo cp -f "cacert.pem" "$certs_ssl_dir"
    fi

    if type -P update-ca-certificates &>/dev/null; then
        sudo update-ca-certificates
    fi
}

fix_tcmalloc_lib() {
    lib_path=$(find /usr/lib/x86_64-linux-gnu -regextype posix-extended -regex '.*/libtcmalloc_minimal\.so\.[4-9]$')

    if [[ -n "$lib_path" ]] && [[ ! -L "/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so" ]]; then
        sudo ln -sf "$lib_path" "/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so"
        log "Created a link for the broken tcmalloc_minimal library file."
    else
        log "The required tcmalloc .so files were already created."
    fi
}

build_aria2() {
    local aria2_version
    echo
    log "Compiling Aria2..."
    echo
    aria2_version=$(source_the_latest_version "https://github.com/aria2/aria2.git")
    curl -Lso "aria2-$aria2_version.tar.xz" "https://github.com/aria2/aria2/releases/download/release-$aria2_version/aria2-$aria2_version.tar.xz"
    mkdir -p "aria2-$aria2_version/build"
    tar -Jxf "aria2-$aria2_version.tar.xz" -C "aria2-$aria2_version" --strip-components 1
    cd "aria2-$aria2_version" || exit 1
    autoreconf -fi
    sed -i "s/1, 16/1, 128/g" "src/OptionHandlerFactory.cc"
    cd build || exit 1
    ../configure --prefix=/usr/local --disable-static --enable-shared \
                --without-gnutls --with-openssl --with-ca-bundle="$certs_ssl_dir" \
                --with-tcmalloc --with-libcares="$working" --with-sqlite3="$working" \
                --enable-lto --enable-profile-guided-optimization \
                LDFLAGS="-L$working/lib $LDFLAGS" \
                CPPFLAGS="-I$working/include $CPPFLAGS" || fail "Failed to configure aria2. Line $LINENO"
    make "-j$(nproc --all)" || fail "Failed to build aria2. Line $LINENO"
    sudo make install || fail "Failed to install aria2. Line $LINENO"
    cd ../..
}

cleanup() {
    echo
    log "Cleaning up..."
    echo
    sudo rm -fr "$temp_dir"
    echo
    log "Cleanup completed."
    echo
}

main() {
    if [[ "$EUID" -eq 0 ]]; then
        echo "This script must be run without root or sudo."
        exit 1
    fi

    # Check command line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--debug)
                set -x
                ;;
            -S|--static)
                export ARIA2_STATIC="yes"
                ;;
            -h|--help)
                display_help
                ;;
            *)
                echo "Unknown option: $1"
                display_help
                ;;
        esac
        shift
    done

    echo
    log "Starting aria2 build process with ARIA2_STATIC set to $ARIA2_STATIC..."
    echo

    set_compiler_options
    install_packages
    prepare_build_environment
    cd "$temp_dir" || exit 1
    build_libgpg_error
    build_c_ares
    build_sqlite3
    install_ca_certs
    fix_tcmalloc_lib
    build_aria2
    cleanup

    echo
    log "Aria2 build process completed successfully."
    echo
}

main "$@"
