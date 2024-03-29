#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-aria2
##  Purpose: Build aria2 from source code
##  Updated: 03.07.24
##  Script version: 2.0
##  Features:
##            - static build
##            - openssl backend
##            - increased the max connections from 16 to 128
##  Added:
##         - display a menu by passing -h or --help as arguments to the script
##         - build a service by passing an argument to the script
##         - builds everything in temporary directories in the /tmp folder and removes them when done
##         - updated Aria2 to the latest version - 1.37.0
##         - if OpenSSL is manually installed using the build-openssl script then use its certs directory instead of the default.
##         - build jemalloc from the latest source code
##         - runpath to LDFLAGS
##  Fixed: Soft linking error

script_ver="2.0"
echo "GitHub Script for building aria2 from source. Version: $script_ver"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[LOG]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $*"; }
handle_error() { echo -e "${RED}[ERROR]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $*"; exit 1; }

display_help() {
    echo "Usage: $0 [OPTION]..."
    echo "Build aria2 from source code."
    echo
    echo "Options:"
    echo "  -s, --service     Create aria2 service"
    echo "  -h, --help        Display this help message and exit"
    echo
    exit 0
}

set_compiler_options() {
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-g -O3 -pipe -fno-plt -march=native"
    CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
    export CC CFLAGS CXX CXXFLAGS
}

# Check if help argument is passed
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    display_help
fi

install_packages() {
    local pkgs=(autoconf autoconf-archive autogen automake build-essential ca-certificates
                ccache curl libssl-dev libtool libtool-bin m4 pkg-config zlib1g-dev)
    log "Attempting to install required packages..."
    apt install -y "${pkgs[@]}"
    for pkg in "${pkgs[@]}"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" || handle_error "Failed to install: $pkg"
    done
    echo
    log "Installation of required packages completed."
}

github_latest_release_version() { curl -sLH "Content-Type: text/plain" "https://gitver.optimizethis.net" | bash -s "$1"; }

libgpg_latest_release_version() {
    local url="$1"
    local latest_version=$(curl -s "$url" | grep -Eo 'href="libgpg-error-[0-9]+\.[0-9]+\.tar\.bz2"' | head -n1 | grep -Eo '[0-9]+\.[0-9]+')
    [[ -z "$latest_version" ]] && { echo "Failed to find the latest version of libgpg-error."; exit 1; } || echo "$latest_version"
}

prepare_build_environment() {
    build_dir="$PWD/aria2-build"
    temp_dir="/tmp/aria2-temp-$(date +%s)"
    log "Creating build directory: $build_dir"
    mkdir -p "$build_dir"
    cd "$build_dir" || handle_error "Failed to create or navigate to build directory."
    log "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir"
}

build_jemalloc() {
    log "Compiling jemalloc..."
    echo
    local jemalloc_version=$(github_latest_release_version "https://github.com/jemalloc/jemalloc.git")
    local jemalloc_url="https://github.com/jemalloc/jemalloc/releases/download/$jemalloc_version/jemalloc-$jemalloc_version.tar.bz2"
    curl -Ls "$jemalloc_url" | tar -xj
    cd "jemalloc-$jemalloc_version"
    ./configure --prefix="$temp_dir/jemalloc"
    make "-j$(nproc)" && make install
    cd ../
}

build_libgpg_error() {
    echo
    log "Compiling libgpg-error..."
    echo
    local libgpg_error_version=$(libgpg_latest_release_version "https://gnupg.org/ftp/gcrypt/libgpg-error/")
    local libgpg_error_url="https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-$libgpg_error_version.tar.bz2"
    curl -Ls "$libgpg_error_url" | tar -xj
    cd "libgpg-error-${libgpg_error_version}"
    ./configure --prefix="$temp_dir/libgpg-error"
    make "-j$(nproc)" && make install
    cd ../
}

compile_aria2() {
    echo
    log "Compiling Aria2..."
    echo
    local aria2_version=$(github_latest_release_version "https://github.com/aria2/aria2.git")
    local aria2_url="https://github.com/aria2/aria2/releases/download/release-$aria2_version/aria2-$aria2_version.tar.xz"
    curl -Ls "$aria2_url" | tar -xJ
    cd "aria2-$aria2_version"
    sed -i "s/1, 16/1, 128/g" "src/OptionHandlerFactory.cc"
    PATH="$temp_dir/jemalloc/bin:$temp_dir/libgpg-error/bin:$PATH" \
    ./configure --prefix=/usr/local \
                --enable-static \
                --disable-shared \
                --without-gnutls \
                --with-openssl \
                --with-ca-bundle=$(find /etc/ -type f -name ca-certificates.crt) \
                --with-jemalloc="$temp_dir/jemalloc" \
                LDFLAGS="-L$temp_dir/jemalloc/lib -L$temp_dir/libgpg-error/lib" \
                CPPFLAGS="-I$temp_dir/jemalloc/include -I$temp_dir/libgpg-error/include"
    make "-j$(nproc)" && \
    make install
    cd ../
}

create_aria2_service() {
    echo
    log "Creating aria2 service..."
    echo
    tee /etc/systemd/system/aria2.service > /dev/null <<EOT
[Unit]
Description=Aria2 Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/aria2c --enable-rpc --rpc-listen-all
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOT

    systemctl daemon-reload
    systemctl enable aria2
    systemctl start aria2
    log "Aria2 service created and started."
    echo
}

cleanup() {
    log "Cleaning up..."
    rm -fr "$build_dir" "$temp_dir"
    log "Cleanup completed."
}

main() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "This script must be run as root or with sudo."
        exit 1
    fi

    log "Starting aria2 build process..."
    echo

    set_compiler_options
    install_packages
    prepare_build_environment
    build_jemalloc
    build_libgpg_error
    compile_aria2
    
    for arg in "$@"; do
        case $arg in
            -s|--service)
                create_aria2_service
                ;;
            *)
                ;;
        esac
    done
    
    cleanup
    echo
    log "Aria2 build process completed successfully."
}

main "$@"
