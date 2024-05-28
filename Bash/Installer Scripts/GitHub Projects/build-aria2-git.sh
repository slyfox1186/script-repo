#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-aria2.sh
##  Purpose: Build aria2 from source code
##  Updated: 04.17.24
##  Script version: 2.2

script_ver="2.2"
echo "GitHub Script for building aria2 from source. Version: $script_ver"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[LOG]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $*"
}

handle_error() {
    echo -e "${RED}[ERROR]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $*"
    exit 1
}

display_help() {
    echo "Usage: $0 [OPTION]..."
    echo "Build aria2 from source code."
    echo
    echo "Options:"
    echo "  -s, --service     Create aria2 service"
    echo "  -d, --debug       Enable debug mode for more detailed output"
    echo "  -c, --cleanup     Clean up build files after compilation"
    echo "  -h, --help        Display this help message and exit"
    echo
    echo "Examples:"
    echo "  $0                  # Build aria2 from source"
    echo "  $0 -s               # Build aria2 and create a systemd service"
    echo "  $0 -d -c            # Build aria2 with debug mode and cleanup enabled"
    echo
    exit 0
}

set_compiler_options() {
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-O3 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    export CC CFLAGS CXX CXXFLAGS
}

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig"
export PATH PKG_CONFIG_PATH

install_packages() {
    local pkgs=(autoconf autoconf-archive autogen automake build-essential ca-certificates
                ccache curl libssl-dev libtool libtool-bin m4 pkg-config zlib1g-dev)
    log "Attempting to install required packages..."
    sudo apt install -y "${pkgs[@]}"
    for pkg in "${pkgs[@]}"; do
        sudo dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" || handle_error "Failed to install: $pkg"
    done
    echo
    log "Installation of required packages completed."
}

github_latest_release_version() {
    curl -LSs "https://gitver.optimizethis.net" | bash -s "$1"
}

libgpg_latest_release_version() {
    local url="$1"
    local latest_version=$(curl -fsS "$url" | grep -Eo 'href="libgpg-error-[0-9]+\.[0-9]+\.tar\.bz2"' | head -n1 | grep -Eo '[0-9]+\.[0-9]+')
    if [[ -z "$latest_version" ]]; then
        echo "Failed to find the latest version of libgpg-error."
        exit 1
    else
        echo "$latest_version"
    fi
}

build_jemalloc() {
    log "Compiling jemalloc..."
    echo
    local jemalloc_version=$(github_latest_release_version "https://github.com/jemalloc/jemalloc.git")
    local jemalloc_url="https://github.com/jemalloc/jemalloc/releases/download/$jemalloc_version/jemalloc-$jemalloc_version.tar.bz2"
    curl -Ls "$jemalloc_url" | tar -xj
    cd "jemalloc-$jemalloc_version" || exit 1
    ./configure --prefix="$temp_dir/jemalloc"
    make "-j$(nproc)" && \
    sudo make install
    cd ../
}

build_libgpg_error() {
    echo
    log "Compiling libgpg-error..."
    echo
    local libgpg_error_version=$(libgpg_latest_release_version "https://gnupg.org/ftp/gcrypt/libgpg-error/")
    local libgpg_error_url="https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-$libgpg_error_version.tar.bz2"
    curl -Ls "$libgpg_error_url" | tar -xj
    cd "libgpg-error-$libgpg_error_version" || exit 1
    ./configure --prefix="$temp_dir/libgpg-error"
    make "-j$(nproc)" && \
    sudo make install
    cd ../
}

build_c_ares() {
    echo "Compiling c-ares..."
    local c_ares_version=$(github_latest_release_version "https://github.com/c-ares/c-ares.git")
    local c_ares_url="https://github.com/c-ares/c-ares/releases/download/cares-${c_ares_version//./_}/c-ares-$c_ares_version.tar.gz"
    curl -Ls "$c_ares_url" | tar -xz
    cd "c-ares-$c_ares_version"
    ./configure --prefix="$temp_dir/c-ares"
    make "-j$(nproc)" && make install
    cd ../
}

build_sqlite3() {
    echo "Compiling sqlite3..."
    local sqlite_version=$(github_latest_release_version "https://github.com/sqlite/sqlite.git" "version-")
    local sqlite_url="https://www.sqlite.org/2023/sqlite-autoconf-${sqlite_version//./0}.tar.gz"
    curl -Ls "$sqlite_url" | tar -xz
    cd "sqlite-autoconf-${sqlite_version//./0}"
    ./configure --prefix="$temp_dir/sqlite3"
    make "-j$(nproc)" && make install
    cd ../
}

compile_aria2() {
    echo
    log "Compiling Aria2..."
    echo
    local aria2_url="https://github.com/aria2/aria2.git"
    [[ -d "$temp_dir/aria2-git" ]] && sudo rm -fr "$temp_dir/aria2-git"
    sudo git clone --depth 1 "$aria2_url" "$temp_dir/aria2-git" 
    cd "$temp_dir/aria2-git" || exit 1
    sudo sed -i "s/1, 16/1, 128/g" "src/OptionHandlerFactory.cc"
    sudo autoreconf -fi
    PATH="$temp_dir/jemalloc/bin:$temp_dir/libgpg-error/bin:$PATH" \
    sudo ./configure --prefix=/usr/local \
                     --enable-static \
                     --disable-shared \
                     --without-gnutls \
                     --with-openssl \
                     --with-ca-bundle=$(sudo find /etc/ -type f -name ca-certificates.crt) \
                     --with-jemalloc="$temp_dir/jemalloc" \
                     --with-libcares="$temp_dir/c-ares" \
                     --with-sqlite3="$temp_dir/sqlite3" \
                     LDFLAGS="-L$temp_dir/jemalloc/lib -L$temp_dir/libgpg-error/lib -L$temp_dir/c-ares/lib -L$temp_dir/sqlite3/lib" \
                     CPPFLAGS="-I$temp_dir/jemalloc/include -I$temp_dir/libgpg-error/include -I$temp_dir/c-ares/include -I$temp_dir/sqlite3/include"
    sudo make "-j$(nproc)" && \
    sudo make install
    cd ../
}

create_aria2_service() {
    echo
    log "Creating aria2 service..."
    echo
    sudo tee /etc/systemd/system/aria2.service >/dev/null <<EOT
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

    sudo systemctl daemon-reload
    sudo systemctl enable aria2
    sudo systemctl start aria2
    log "Aria2 service created and started."
    echo
}

cleanup() {
    echo "Cleaning up..."
    sudo rm -fr "$build_dir" "$temp_dir"
    
    if [[ "$create_service" = true && "$cleanup" = true ]]; then
        echo "Removing aria2 service..."
        sudo systemctl stop aria2
        sudo systemctl disable aria2
        sudo rm /etc/systemd/system/aria2.service
        sudo systemctl daemon-reload
    fi
    
    echo "Cleanup completed."
}

main() {
    if [[ "$EUID" -eq 0 ]]; then
        echo "This script must be run without root or with sudo."
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
            -c|--cleanup)
                cleanup="true"
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

    log "Starting aria2 build process..."
    echo

    set_compiler_options
    install_packages
    mkdir -p "$temp_dir"
    build_jemalloc
    build_libgpg_error
    build_c_ares
    build_sqlite3
    compile_aria2
    
    if [[ "$create_service" = true ]]; then
        create_aria2_service
    fi
    
    if [[ "$cleanup" = true ]]; then
        cleanup
    fi
    
    echo
    log "Aria2 build process completed successfully."
}

main "$@"
