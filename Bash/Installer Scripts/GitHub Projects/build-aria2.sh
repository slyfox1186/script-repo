#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-aria2.sh
##  Purpose: Build aria2 from source code with hardening options
##  Updated: 05.24.24
##  Script version: 2.8

script_ver="2.8"

echo "aria2 build script - version $script_ver"
echo "==============================================="
echo

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ARIA2_STATIC="no"
CFLAGS_OPTION="-march=native"

log() { echo -e "${GREEN}[LOG]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

display_help() {
    cat <<EOF
Usage: $0 [OPTION]...
Build aria2 from source code with hardening options.

Options:
  -h, --help          Display this help message and exit
  -d, --debug         Enable debug mode for more detailed output
  -g, --generic       Set CFLAGS to -O2 -pipe -mtune=generic
  -n, --native        Set CFLAGS to -O2 -pipe -march=native (default)
  -s, --static        Set aria2 as statically linked (ARIA2_STATIC=yes)

Examples:
  $0                     # Build aria2 from source
  $0 --debug --generic   # Build aria2 with CFLAGS set to -O2 -pipe -mtune=generic
  $0 --static            # Build aria2 from source and set as statically linked
  $0 -d -g -s            # Build aria2 with debug mode, generic tuning, and set as statically linked
EOF
    exit 0
}

set_compiler_options() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe $CFLAGS_OPTION -fPIC -fPIE -DNDEBUG -fstack-protector-strong -Wno-unused-parameter"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-I/usr/local/include -I/usr/include -D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now -Wl,-rpath,/usr/local/lib"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

print_env() {
    echo
    log "Environment variables:"
    log "CC=$CC"
    log "CXX=$CXX"
    log "CFLAGS=$CFLAGS"
    log "CXXFLAGS=$CXXFLAGS"
    log "CPPFLAGS=$CPPFLAGS"
    log "LDFLAGS=$LDFLAGS"
    echo
}

install_packages() {
    local pkgs missing_pkgs
    pkgs=(
        autoconf autoconf-archive automake autopoint build-essential
        ca-certificates ccache curl google-perftools libgoogle-perftools-dev
        libssl-dev libxml2-dev libtool m4 pkg-config tcl-dev zlib1g-dev
    )
    log "Attempting to install required packages..."
    missing_pkgs=($(comm -23 <(printf "%s\n" "${pkgs[@]}" | sort) <(dpkg-query -W -f='${Package}\n' | sort) | tr '\n' ' '))
    [[ ${#missing_pkgs[@]} -gt 0 ]] && sudo apt-get install -y "${missing_pkgs[@]}"
    log "Installation of required packages completed."
}

install_ca_certs() {
    local certs_ssl_dir="/etc/ssl/certs/cacert.pem"
    if [[ ! -f "$certs_ssl_dir" ]]; then
        curl -LSso "cacert.pem" "https://curl.se/ca/cacert.pem"
        sudo cp -f "cacert.pem" "$certs_ssl_dir"
    fi
    type -P update-ca-certificates &>/dev/null && sudo update-ca-certificates
}

fix_tcmalloc_lib() {
    local lib_path
    lib_path=$(sudo find /usr/lib/x86_64-linux-gnu -regextype posix-extended -regex '.*/libtcmalloc_minimal\.so\.[4-9]$')
    if [[ -n "$lib_path" ]] && [[ ! -L "/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so" ]]; then
        sudo ln -sf "$lib_path" "/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so"
        log "Created a link for the broken tcmalloc_minimal library file."
    else
        log "The required tcmalloc .so files were already created."
    fi
}

build_library() {
    local name url configure_args version
    name="$1"
    url="$2"
    configure_args="$3"

    case "${name}" in
        aria2)
            version=$(curl -fsSL "${url}" | grep -oP 'href="[^"]*-\K[\d.]+(?=\.tar\.)' | head -n1)
            curl -Lso "${name}-${version}.tar.gz" "https://github.com/aria2/aria2/archive/refs/tags/release-${version}.tar.gz"
            ;;
        c-ares)
            version=$(basename "${url}" | grep -oP '\d+\.\d+\.\d+(?=\.tar\.gz)')
            curl -Lso "${name}-${version}.tar.gz" "${url}"
            ;;
        libxml2)
            version=$(curl -fsSL "${url}" | grep -oP 'href="[^"]*\K\d+\.\d+\.\d+(?=\.tar\.gz)' | head -n1)
            curl -Lso "${name}-${version}.tar.gz" "https://github.com/GNOME/libxml2/archive/refs/tags/v${version}.tar.gz"
            ;;
        sqlite3)
            version=$(curl -fsSL "${url}" | grep -oP 'href="[^"]*-\K[\d.]+(?=\.tar\.)' | head -n1)
            curl -Lso "${name}-${version}.tar.gz" "https://github.com/sqlite/sqlite/archive/refs/tags/version-${version}.tar.gz"
            ;;
        *)
            version=$(curl -fsSL "${url}" | grep -oP 'href="[^"]*-\K[\d.]+(?=\.tar\.)' | head -n1)
            curl -Lso "${name}-${version}.tar.gz" "${url}/${name}-${version}.tar.gz"
            ;;
    esac

    mkdir -p "${name}-${version}"
    tar -zxf "${name}-${version}.tar.gz" -C "${name}-${version}" --strip-components 1
    cd "${name}-${version}" || exit 1

    if [[ "${name}" == "aria2" ]]; then
        autoreconf -fi
        sed -i "s/1, 16/1, 128/g" "src/OptionHandlerFactory.cc"
        TCMALLOC_CFLAGS="-I/usr/include"
        TCMALLOC_LIBS="-L/usr/lib/x86_64-linux-gnu -ltcmalloc_minimal"
        CPPFLAGS="-I${temp_dir}/include $CPPFLAGS"
        LDFLAGS="-L${temp_dir}/lib $LDFLAGS"
        PATH="/usr/lib/ccache:$PATH"
        PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
        PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
        PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
        export CPPFLAGS LDFLAGS PKG_CONFIG PKG_CONFIG_PATH PATH TCMALLOC_CFLAGS TCMALLOC_LIBS
    fi

    ./configure $configure_args || fail "Failed to configure ${name}. Line ${LINENO}"
    make -j$(nproc) || fail "Failed to build ${name}. Line ${LINENO}"
    sudo make install || fail "Failed to install ${name}. Line ${LINENO}"
    cd ../
}

start_build() {
    local temp_dir
    temp_dir="/tmp/aria2-$$"
    mkdir -p "${temp_dir}"
    cd "${temp_dir}" || exit 1

    echo
    log "Building libgpg-error..."
    build_library "libgpg-error" "https://gnupg.org/ftp/gcrypt/libgpg-error/" "--prefix=${temp_dir} --enable-static --disable-shared"
    echo
    log "Building c-ares..."
    build_library "c-ares" "https://github.com/c-ares/c-ares/releases/download/cares-1_29_0/c-ares-1.29.0.tar.gz" "--prefix=${temp_dir} --enable-static --disable-shared"
    echo
    log "Building sqlite3..."
    build_library "sqlite3" "https://github.com/sqlite/sqlite/tags/" "--prefix=${temp_dir} --enable-static --disable-shared"
    install_ca_certs
    fix_tcmalloc_lib
    echo
    log "Building aria2..."
    build_library "aria2" "https://github.com/aria2/aria2/tags/" "--prefix=/usr/local --enable-static --disable-nls --enable-libaria2 --disable-shared --without-gnutls --with-openssl --enable-lto --with-tcmalloc --with-libiconv-prefix=/usr --with-ca-bundle=$certs_ssl_dir --enable-profile-guided-optimization"
}

main() {
    if [[ "$EUID" -eq 0 ]]; then
        echo "This script must be run without root or sudo."
        exit 1
    fi

    for arg in "$@"; do
        case "$arg" in
            -d|--debug)
                set -x
                shift
                ;;
            -s|--static)
                ARIA2_STATIC="yes"
                shift
                ;;
            -g|--generic)
                CFLAGS_OPTION="-mtune=generic"
                shift
                ;;
            -n|--native)
                CFLAGS_OPTION="-march=native"
                shift
                ;;
            -h|--help)
                display_help
                ;;
            *)
                display_help
                ;;
        esac
    done

    export ARIA2_STATIC

    set_compiler_options
    print_env
    install_packages
    start_build
    echo
    log "Aria2 build process completed successfully."
}

main "$@"
