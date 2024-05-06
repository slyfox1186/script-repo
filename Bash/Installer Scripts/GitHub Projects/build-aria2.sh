#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-aria2.sh
##  Purpose: Build aria2 from source code with hardening options
##  Updated: 05.06.24
##  Script version: 2.4

script_ver="2.4"

echo "aria2 build script - version $script_ver"
echo "==============================================="
echo

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

export ARIA2_STATIC="no"

log() {
    echo -e "${GREEN}[LOG]${NC} $*"
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
    echo "  $0                     # Build aria2 from source with hardening options"
    echo "  $0 --static            # Build aria2 from source with hardening options and set as statically linked"
    echo "  $0 -s --static         # Build aria2 with hardening options, create a systemd service, and set as statically linked"
    echo "  $0 -d -c --static      # Build aria2 with debug mode, cleanup enabled, and set as statically linked"
    echo
    exit 0
}

set_compiler_options() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -fPIC -fPIE -mtune=native -DNDEBUG -fstack-protector-strong -Wno-unused-parameter"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
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
                autoconf autoconf-archive automake build-essential
                ca-certificates ccache curl libgoogle-perftools-dev
                libssl-dev libtool m4 pkg-config zlib1g-dev
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
    local url="$1"
    local latest_version=$(curl -fsS "$url" | grep -oP 'href="libgpg-error-[0-9]+\.[0-9]+\.tar\.bz2"' | head -n1 | grep -oP '[0-9]+\.[0-9]+')
    if [[ -z "$latest_version" ]]; then
        echo "Failed to find the latest version of libgpg-error."
        exit 1
    else
        echo "$latest_version"
    fi
}

prepare_build_environment() {
    build_dir="$cwd/aria2-build"
    temp_dir="/tmp/aria2-temp-$(date +%s)"
    log "Creating build directory: $build_dir"
    mkdir -p "$build_dir"
    cd "$build_dir" || fail "Failed to create or navigate to build directory."
    log "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir"
}

build_libgpg_error() {
    local libgpg_error_url libgpg_error_version
    echo
    log "Compiling libgpg-error..."
    echo
    libgpg_error_version=$(libgpg_latest_release_version "https://gnupg.org/ftp/gcrypt/libgpg-error/")
    libgpg_error_url="https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-$libgpg_error_version.tar.bz2"
    curl -sSL "$libgpg_error_url" | tar -jx
    cd "libgpg-error-$libgpg_error_version" || exit 1
    ./configure --prefix="$temp_dir/libgpg-error" --enable-static --disable-shared || fail "Failed to configure libgpg-error. Line $LINENO"
    make "-j$(nproc --all)" || fail "Failed to build libgpg-error. Line $LINENO"
    sudo make install || fail "Failed to install libgpg-error. Line $LINENO"
    cd ../
}

build_c_ares() {
    local c_ares_url c_ares_version
    echo
    log "Compiling c-ares..."
    echo
    c_ares_version=$(source_the_latest_version "https://github.com/c-ares/c-ares.git")
    c_ares_url="https://github.com/c-ares/c-ares/archive/refs/tags/cares-${c_ares_version//./_}.tar.gz"
    curl -sSL "$c_ares_url" | tar -zx
    cd "c-ares-cares-$c_ares_version" || exit 1
    autoreconf -fi
    ./configure --prefix="$temp_dir/c-ares" --enable-static --disable-shared || fail "Failed to configure c-ares. Line $LINENO"
    make "-j$(nproc --all)" || fail "Failed to build c-ares. Line $LINENO"
    sudo make install || fail "Failed to install c-ares. Line $LINENO"
    cd ../
}

build_sqlite3() {
    local sqlite_url sqlite_version
    echo
    log "Compiling sqlite3..."
    echo
    sqlite_version=$(source_the_latest_version "https://github.com/sqlite/sqlite.git")
    sqlite_url="https://github.com/sqlite/sqlite/archive/refs/tags/version-$sqlite_version.tar.gz"
    curl -sSL "https://github.com/sqlite/sqlite/archive/refs/tags/version-3.45.3.tar.gz" | tar -zx
    cd "sqlite-version-$sqlite_version" || exit 1
    ./configure --prefix="$temp_dir/sqlite3" --enable-static --disable-shared || fail "Failed to configure sqlite. Line $LINENO"
    make "-j$(nproc --all)" || fail "Failed to build sqlite. Line $LINENO"
    sudo make install || fail "Failed to install sqlite. Line $LINENO"
    cd ../
}

# Install ca certs from curl's official website
install_ca_certs() {
    if [[ ! -f "/etc/ssl/certs/cacert.pem" ]]; then
        curl -LSso "cacert.pem" "https://curl.se/ca/cacert.pem"
        sudo cp -f "cacert.pem" "/etc/ssl/certs/cacert.pem"
    fi

    if type -P update-ca-certificates &>/dev/null; then
        sudo update-ca-certificates
    fi
}

build_aria2() {
    local aria2_url aria2_version
    echo
    log "Compiling Aria2..."
    echo
    aria2_version=$(source_the_latest_version "https://github.com/aria2/aria2.git")
    aria2_url="https://github.com/aria2/aria2/releases/download/release-$aria2_version/aria2-$aria2_version.tar.xz"
    curl -sSL "$aria2_url" | tar -Jx
    cd "aria2-$aria2_version" || exit 1
    sed -i "s/1, 16/1, 128/g" "src/OptionHandlerFactory.cc"
    ./configure --prefix=/usr/local --enable-static --disable-shared \
                --without-gnutls --with-openssl \
                --with-ca-bundle="/etc/ssl/certs/cacert.pem" \
                --with-tcmalloc --with-libcares="$temp_dir/c-ares" \
                --with-sqlite3="$temp_dir/sqlite3" --enable-lto --enable-profile-guided-optimization \
                LDFLAGS="-L$temp_dir/libgpg-error/lib -L$temp_dir/c-ares/lib -L$temp_dir/sqlite3/lib $LDFLAGS" \
                CPPFLAGS="-I$temp_dir/libgpg-error/include -I$temp_dir/c-ares/include -I$temp_dir/sqlite3/include $CPPFLAGS" || fail "Failed to configure aria2. Line $LINENO"
    make "-j$(nproc --all)" || fail "Failed to build aria2. Line $LINENO"
    sudo make install || fail "Failed to install aria2. Line $LINENO"
    cd ../
}

create_aria2_service() {
    echo
    log "Creating aria2 service..."
    echo
    sudo tee "/etc/systemd/system/aria2.service" >/dev/null <<EOT
[Unit]
Description=Aria2 Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/aria2c --enable-rpc --rpc-listen-all --rpc-secure --rpc-certificate=/path/to/cert.pem --rpc-private-key=/path/to/key.pem --rpc-secure-policy-file=/etc/aria2/aria2.seccomp
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOT

    sudo mkdir -p "/etc/aria2"
    sudo tee "/etc/aria2/aria2.seccomp" >/dev/null <<EOT
POLICY aria2
ALLOW {BASIC_SYSCALLS}
ALLOW {FILESYSTEM_SYSCALLS}
ALLOW {PROCESS_CONTROL_SYSCALLS}
ALLOW {MEMORY_SYSCALLS}
ALLOW {SELECT_SYSCALLS}
ALLOW {TIME_SYSCALLS}
ALLOW {SOCKET_SYSCALLS}
ALLOW {SIGNAL_SYSCALLS}
EOT

    sudo systemctl daemon-reload
    sudo systemctl enable aria2
    sudo systemctl start aria2
    echo
    log "Aria2 service created and started."
    echo
}

cleanup() {
    echo
    log "Cleaning up..."
    echo
    sudo rm -fr "$build_dir" "$temp_dir"
    echo
    log "Cleanup completed."
    echo
}

main() {
    if [[ "$EUID" -eq 0 ]]; then
        echo "This script must be run without root or sudo."
        exit 1
    fi
    
    create_service="false"
    cleanup="false"

    # Check command line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--service)
                create_service="true"
                ;;
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

    cwd="$PWD"

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
    build_aria2
    cleanup

    [[ "$create_service" = true ]] && create_aria2_service    
    
    echo
    log "Aria2 build process completed successfully."
    echo
}

main "$@"
