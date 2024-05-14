#!/usr/bin/env bash

# Disable specific shellcheck warnings that are not applicable after optimizations
# shellcheck disable=SC1091,SC2001,SC2068,SC2086,SC2155,SC2162,SC2317

## Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-python3
## Purpose: Install Python3 from the source code acquired from the official website: https://www.python.org/downloads
## Features: Static build, OpenSSL backend
## Updated: 05.13.24
## Script version: 2.6

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

script_ver=2.6
prog_name="python3"
python_version=3.12.3
archive_url="https://www.python.org/ftp/python/$python_version/Python-$python_version.tar.xz"
cwd="$PWD/python3-build-script"
openssl_prefix=$(dirname "$(readlink -f "$(type -P openssl)")")

compiler="gcc"
lto="no"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -v, --version    Set the Python version (default: 3.12.3)"
    echo "  -l, --list       List available Python3 versions"
    echo "  -c, --clang      Use clang instead of gcc"
    echo "  -t, --lto        Set LTO value (yes, no, thin, full)"
    echo "  -h, --help       Display this help message"
    echo
}

list_versions() {
    curl -fsS "https://www.python.org/ftp/python/" | grep -oP 'href="[^"]*\K[0-9]+\.[0-9]+\.[0-9]+' | sort -uV
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            python_version="$2"
            archive_url="https://www.python.org/ftp/python/$python_version/Python-$python_version.tar.xz"
            install_dir="/usr/local/$prog_name-$python_version"
            shift 2
            ;;
        -l|--list)
            list_versions
            exit 0
            ;;
        -c|--clang)
            compiler="clang"
            shift
            ;;
        -t|--lto)
            lto="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

archive_name="$prog_name-$python_version"
install_dir="/usr/local/$archive_name"

install_required_packages() {
    local pkg
    local -a pkgs missing_packages

    pkgs=(
        autoconf autoconf-archive autogen automake binutils build-essential ccache clang
        curl git itstool libb2-dev libexempi-dev libgnome-desktop-3-dev libhandy-1-dev 
        libpeas-dev libpeasd-3-dev libssl-dev libtool libtool-bin llvm m4 nasm openssl
        python3 valgrind yasm zlib1g-dev
    )

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        sudo apt install "${missing_packages[@]}" || fail "Failed to install required packages. Line: $LINENO"
    else
        echo "All required packages are already installed."
    fi
}

if [[ "$lto" == "thin" && "$compiler" != "clang" ]]; then
    echo "Error: LTO 'thin' can only be used with clang."
    exit 1
fi

if [[ "$lto" == "thin" && "$compiler" == "clang" ]]; then
    if ! command -v llvm-ar &> /dev/null; then
        echo "Error: llvm-ar is required for a --with-lto=thin build with clang but could not be found."
        exit 1
    fi

    # Verify compatibility between clang and llvm-ar versions
    clang_version=$(clang --version | grep -oP 'clang-\K[0-9]+')
    llvm_ar_version=$(llvm-ar --version | grep -oP 'LLVM \K[0-9]+')
    
    if [[ "$clang_version" != "$llvm_ar_version" ]]; then
        echo "Error: Mismatch between clang version ($clang_version) and llvm-ar version ($llvm_ar_version)."
        exit 1
    fi
fi

exit_function() {
    printf "\n%s\n%s\n\n" "Make sure to star this repository to show your support!" "$web_repo"
    exit 0
}

fail() {
    echo "Error occurred at line $1."
    echo "Please report errors at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

trap 'fail $LINENO' ERR

cleanup() {
    sudo rm -fr "$cwd"
}

show_ver_fn() {
    save_ver="$(sudo find "$install_dir/" -type f -name "python3.12" | grep -oP '[0-9\.]+$' | xargs -I{} echo python{})"
    printf "\n%s\n" "The newly installed version is: $save_ver"
}

prepare_environment() {
    echo "Python3 Build Script - v$script_ver"
    echo "==============================================="

    [[ -d "$cwd" ]] && rm -fr "$cwd"
    mkdir -p "$cwd"

    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig"
    export PATH PKG_CONFIG_PATH
}

set_compiler_flags() {
    if [[ "$compiler" == "clang" ]]; then
        CC="clang"
        CXX="clang++"
    else
        CC="gcc"
        CXX="g++"
    fi

    CFLAGS="-O2 -fPIE -pipe -mtune=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security"
    LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,--enable-new-dtags -Wl,-rpath=${install_dir}/lib"
    export CC CFLAGS CXX CXXFLAGS CPPFLAGS LDFLAGS
}

verify_gcc_version=$(gcc --version | awk 'NR==1{split($3,a,"."); print a[1]}')
verify_gpp_version=$(g++ --version | awk 'NR==1{split($3,a,"."); print a[1]}')

if [[ "$compiler" == "gcc" ]]; then
    if [[ "$verify_gcc_version" -eq 13 ]] || [[ "$verify_gpp_version" -eq 13 ]]; then
        clear
        echo "You must use gcc/g++ version 12 or lower."
        echo "The current setup is using: gcc-$verify_gcc_version and g++-$verify_gpp_version"
        echo "Please edit the \"CC\" and \"CXX\" variables in the script to change versions."
        exit 1
    fi
fi

download_and_extract_python() {
    if [[ ! -f "$cwd/$python_version.tar.xz" ]]; then
        curl -LSso "$cwd/$python_version.tar.xz" "$archive_url"
    fi
    if [[ -d "$cwd/$python_version" ]]; then
        rm -fr "$cwd/${python_version:?}"
    fi
    mkdir -p "$cwd/$python_version/build"

    tar -xf "$cwd/$python_version.tar.xz" -C "$cwd/$python_version" --strip-components 1 || fail "Failed to extract: $cwd/$python_version.tar.xz. Line: $LINENO"
}

ld_linker_path() {
    echo "$install_dir/lib/python${python_version::-2}/lib-dynload" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    sudo ldconfig
}

create_soft_links() {
    [[ -d "$install_dir/bin" ]] && sudo ln -sf "$install_dir/bin/"* "/usr/local/bin/"
    [[ -d "$install_dir/lib/pkgconfig" ]] && sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    [[ -d "$install_dir/include" ]] && sudo ln -sf "$install_dir/include/"* "/usr/local/include/"
}

create_user_site() {
    mkdir -p "$HOME/.local/lib/python$python_version/site-packages"
}

build_python() {
    echo
    echo "Build Python3 - v$python_version"
    echo "==============================================="
    echo

    cd "$cwd/$python_version" || exit 1
    autoreconf -fi
    cd build || exit 1
    ../configure --prefix="$install_dir" \
                 --disable-ipv6 \
                 --disable-test-modules \
                 --enable-optimizations \
                 --with-ensurepip=install \
                 --with-lto=$lto \
                 --with-openssl-rpath=auto \
                 --with-openssl="$openssl_prefix" \
                 --with-pkg-config=yes \
                 --with-ssl-default-suites=openssl \
                 --with-valgrind || fail "Configuration failed. Line: $LINENO"

    make "-j$(nproc --all)" || fail "Failed to execute: make -j$(nproc --all). Line: $LINENO"
    sudo make install || fail "Failed to execute: make altinstall. Line: $LINENO"
}

# Main script execution
main() {
    prepare_environment
    install_required_packages  
    set_compiler_flags
    download_and_extract_python
    build_python
    [[ -d "$install_dir/lib" ]] && ld_linker_path
    create_soft_links
    create_user_site
    show_ver_fn
    cleanup
    exit_function
}

main "$@"
