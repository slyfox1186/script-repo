#!/usr/bin/env bash

# Build GNU Automake - v1.1 - 03.08.24
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-automake.sh

set -eo pipefail
trap 'fail "Error occurred on line: $LINENO"' ERR

version="1.1"
program_name=automake
program_version="1.16.5"
archive_url="https://ftp.gnu.org/gnu/automake/$program_name-$program_version.tar.xz"
install_prefix=/usr/local
build_dir="/tmp/$program_name-$version-build"
verbose=0

usage() {
    echo "Usage: ./build-automake.sh [OPTIONS]"
    echo "Options:"
    printf "  %-25s %s\n" "-p, --prefix DIR" "Set the installation prefix (default: $install_prefix)"
    printf "  %-25s %s\n" "-v, --verbose" "Enable verbose logging"
    printf "  %-25s %s\n" "-h, --help" "Show this help message"
    exit 0
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
            -h|--help)
                usage
                ;;
            *)
                fail "Unknown option: $1. Use -h or --help for usage information."
                ;;
        esac
    done
}

log_msg() {
    if [[ "$verbose" -eq 1 ]]; then
        echo "$1"
    fi
}

fail() {
    echo "$1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

install_deps() {
    log_msg "Installing dependencies..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y --no-install-recommends autoconf autoconf-archive autogen automake autopoint autotools-dev binutils bison build-essential bzip2 ccache curl libc6-dev libpth-dev libtool libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev yasm
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y autoconf autoconf-archive autogen automake autopoint autotools-dev binutils bison bzip2 ccache curl gcc gcc-c++ kernel-devel libpth-devel libtool libtool-ltdl-devel lzip lzma-devel m4 make nasm perl-Thread-Queue tar texinfo xz yasm zlib-devel
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm --needed autoconf autoconf-archive autogen automake gettext binutils bison bzip2 ccache curl gcc libtool m4 make nasm texinfo xz yasm zlib
    else
        fail "Unsupported package manager. Please install the required dependencies manually."
    fi
}

set_env_vars() {
    log_msg "Setting environment variables..."
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-I$install_prefix/include -I$install_prefix/include/$(gcc -dumpmachine) -D_FORTIFY_SOURCE=2"
    LDFLAGS="-L$install_prefix/lib64 -L$install_prefix/lib -L$install_prefix/lib/$(gcc -dumpmachine) -Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_prefix/$program_name/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CFLAGS CPPFLAGS CXX CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

download_archive() {
    log_msg "Downloading archive..."
    archive_name="$program_name-$program_version.tar.xz"
    if [[ ! -f "$build_dir/$archive_name" ]]; then
        curl -fsSL "$archive_url" -o "$build_dir/$archive_name"
    fi
}

extract_archive() {
    log_msg "Extracting archive..."
    tar -xf "$build_dir/$archive_name" -C "$build_dir" --strip-components 1
}

configure_build() {
    log_msg "Configuring build..."
    cd "$build_dir"
    autoreconf -fi
    mkdir -p build && cd build
    ../configure --prefix="$install_prefix/$program_name" \
                 --build="$(gcc -dumpmachine)" \
                 --host="$(gcc -dumpmachine)" \
                 --enable-silent-rules
}

compile_build() {
    log_msg "Compiling..."
    make "-j$(nproc --all)"
}

install_build() {
    log_msg "Installing..."
    make install
}

create_symlinks() {
    log_msg "Creating symlinks..."
    for file in "$install_prefix/$program_name/bin/"*; do
        ln -sfn "$file" "$install_prefix/bin/$(basename "$file" | sed 's/^\w*-//')"
    done
}

copy_m4_files() {
    log_msg "Copying M4 files..."
    mkdir -p "$install_prefix/share/aclocal"
    cp /usr/share/aclocal/*.m4 "$install_prefix/share/aclocal/"
}

cleanup() {
    log_msg "Cleaning up..."
    read -rp "Remove temporary build directory '$build_dir'? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$build_dir"
    fi
}

main() {
    parse_args "$@"

    if [[ "$EUID" -ne 0 ]]; then
        fail "You must run this script with root or sudo."
    fi

    [[ -d "$build_dir" ]] &&  rm -rf "$build_dir"
    mkdir -p "$build_dir"

    install_deps
    set_env_vars
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    create_symlinks
    copy_m4_files
    cleanup

    log_msg "Build completed successfully!"
    log_msg "Make sure to star this repository to show your support!"
    log_msg "https://github.com/slyfox1186/script-repo"
}

main "$@"
