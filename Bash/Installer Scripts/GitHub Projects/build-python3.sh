#!/usr/bin/env bash

# Disable specific shellcheck warnings that are not applicable after optimizations
# Shellcheck disable=sc1091,sc2001,sc2068,sc2086,sc2155,sc2162,sc2317

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-python3
##  Purpose: Install Python3 from the source code acquired from the official website: https://www.python.org/downloads
##  Features: Static build, OpenSSL backend
##  Updated: 01.27.24
##  Script version: 2.4 (Optimized and Corrected)

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

script_ver=2.4
python_version=3.12.2
archive_url="https://www.python.org/ftp/python/$python_version/Python-$python_version.tar.xz"
install_dir="/usr/local"
cwd="$PWD/python3-build-script"
openssl_prefix=$(dirname $(readlink -f $(type -P openssl)))

exit_fn() {
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
    local choice

    echo
    echo "========================================================="
    echo "       Would you like to clean up the build files?       "
    echo "========================================================="
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choices are (1 or 2): " choice

    case "$choice" in
        1) rm -fr "$cwd" ;;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

show_ver_fn() {
    save_ver="$(sudo find /usr/local/ -type f -name "python3.12" | grep -oP '[0-9\.]+$' | xargs -I{} echo python{})"
    printf "\n%s\n" "The newly installed version is: $save_ver"
}

check_root() {
    if [[ $(id -u) -ne 0 ]]; then
        echo "You must run this script as root or with sudo."
        exit 1
    fi
}

prepare_environment() {
    echo "Python3 Build Script - v$script_ver"
    echo "==============================================="

    [[ -d "$cwd" ]] && rm -fr "$cwd"
    mkdir -p "$cwd"

    export PATH="\
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
    export PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig\
"
}

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-g -O3 -pipe -fno-plt -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    export CC CFLAGS CXX CXXFLAGS CPPFLAGS
}

verify_gcc_version=$(gcc --version | awk 'NR==1{split($3,a,"."); print a[1]}')
verify_gpp_version=$(g++ --version | awk 'NR==1{split($3,a,"."); print a[1]}')

if [[ "$verify_gcc_version" -eq 13 ]] || [[ "$verify_gpp_version" -eq 13 ]]; then
    clear
    echo "You must use gcc/g++ version 12 or lower."
    echo "The current setup is using: gcc-$verify_gcc_version and g++-$verify_gpp_version"
    echo "Please edit the \"CC\" and \"CXX\" variables in the script to change versions."
    exit 1
fi

download_and_extract_python() {
    if [[ ! -f "$cwd/$python_version.tar.xz" ]]; then
        curl -Lso "$cwd/$python_version.tar.xz" "$archive_url"
    fi
    if [[ -d "$cwd/$python_version" ]]; then
        rm -fr "$cwd/${python_version:?}"
    fi
    mkdir -p "$cwd/$python_version/build"

    tar -xf "$cwd/$python_version.tar.xz" -C "$cwd/$python_version" --strip-components 1 || fail "Failed to extract: $cwd/$python_version.tar.xz. Line: $LINENO"
}

install_required_packages() {
    local pkgs missing_packages

    pkgs=(
        autoconf autoconf-archive autogen automake binutils build-essential ccache
        curl git itstool libb2-dev libexempi-dev libgnome-desktop-3-dev libhandy-1-dev
        libpeas-dev libpeasd-3-dev libssl-dev libtool libtool-bin m4 nasm openssl python3
        valgrind yasm zlib1g-dev
    )

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#Missing_packages[@]} -gt 0 ]]; then
        apt install -y ${missing_packages[@]} || fail "Failed to install required packages. Line: $LINENO"
    else
        echo "All required packages are already installed."
    fi
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
                 --disable-test-modules \
                 --enable-optimizations \
                 --with-ensurepip=install \
                 --with-lto=no \
                 --with-openssl-rpath=auto \
                 --with-openssl="$openssl_prefix" \
                 --with-pkg-config=yes \
                 --with-ssl-default-suites=openssl \
                 --with-valgrind || fail "Configuration failed. Line: $LINENO"

    make "-j$(nproc --all)" || fail "Failed to execute: make -j$(nproc --all). Line: $LINENO"
    make altinstall || fail "Failed to execute: make altinstall. Line: $LINENO"
}

# Main script execution
check_root
prepare_environment
install_required_packages
set_compiler_flags
download_and_extract_python
build_python
show_ver_fn
cleanup
exit_fn
