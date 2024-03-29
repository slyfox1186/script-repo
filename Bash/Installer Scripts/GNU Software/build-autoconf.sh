#!/usr/bin/env bash

# Build GNU Autoconf - v1.1 - 03.08.24
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-autoconf.sh

set -eo pipefail
trap 'fail "Error occurred on line: $LINENO".' ERR

version=1.1
program_name=autoconf
archive_url="https://ftp.gnu.org/gnu/autoconf/$program_name-latest.tar.xz"
install_prefix=/usr/local
build_dir="/tmp/$program_name-$version-build"
verbose=0

usage() {
    echo "Usage: ./build-autoconf.sh [OPTIONS]"
    echo "Options:"
    printf "  %-25s %s\n" "-p, --prefix DIR" "Set the installation prefix (default: $install_prefix)"
    printf "  %-25s %s\n" "-v, --verbose" "Enable verbose logging"
    printf "  %-25s %s\n" "-h, --help" "Show this help message"
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
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
    if [[ $verbose -eq 1 ]]; then
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
    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y --no-install-recommends autoconf autoconf-archive autogen automake autopoint autotools-dev binutils bison build-essential bzip2 ccache curl libc6-dev libpth-dev libtool libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev yasm
    elif command -v dnf &>/dev/null; then
        dnf install -y autoconf autoconf-archive autogen automake autopoint autotools-dev binutils bison bzip2 ccache curl gcc gcc-c++ kernel-devel libpth-devel libtool libtool-ltdl-devel lzip lzma-devel m4 make nasm perl-Thread-Queue tar texinfo xz yasm zlib-devel
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm --needed autoconf autoconf-archive autogen automake gettext binutils bison bzip2 ccache curl gcc libtool m4 make nasm texinfo xz yasm zlib
    else
        fail "Unsupported package manager. Please install the required dependencies manually."
    fi
}

set_env_vars() {
    log_msg "Setting environment variables..."
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-O3 -pipe -fno-plt -march=native"
    CXXFLAGS="-O3 -pipe -fno-plt -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_prefix/$program_name/lib"
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/lib64/pkgconfig:/lib/pkgconfig"
    export CC CFLAGS CPPFLAGS CXX CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

download_archive() {
    log_msg "Downloading archive..."
    archive_name="$program_name-latest.tar.xz"
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
                 --host="$(gcc -dumpmachine)"
}

compile_build() {
    log_msg "Compiling..."
    make -j"$(nproc)"
}

install_build() {
    log_msg "Installing..."
    make install
}

create_symlinks() {
    log_msg "Creating symlinks..."
    for file in "$install_prefix/$program_name"/bin/*; do
        ln -sfn "$file" "$install_prefix/bin/$(basename "$file" | sed 's/^\w*-//')"
    done
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
        fail "You must run this script with root/sudo."
    fi

    [[ -d "$build_dir" ]] && rm -rf "$build_dir"
    mkdir -p "$build_dir"

    install_deps
    set_env_vars
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    create_symlinks
    cleanup

    log_msg "Build completed successfully!"
    log_msg "Make sure to star this repository to show your support!"
    log_msg "https://github.com/slyfox1186/script-repo"
}

main "$@"
