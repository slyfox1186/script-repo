#!/Usr/bin/env bash



if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

script_ver=2.4
python_version=3.12.2
archive_url="https://www.python.org/ftp/python/$python_version/Python-$python_version.tar.xz"
install_dir="/usr/local"
cwd="$PWD/python3-build-script"
openssl_prefix=$(dirname "$(readlink -f "$(type -P openssl)")")

exit_fn() {
    printf "\n%s\n%s\n\n" "Make sure to star this repository to show your support!" "$web_repo"
    exit 0
}

fail_fn() {
    echo
    echo "$1"
    echo "Please report errors at: https://github.com/slyfox1186/script-repo/issues"
    echo
    exit 1
}

cleanup_fn() {
    local choice

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        "========================================================" \
        "        Do you want to clean up the build files?        " \
        "========================================================" \
        "[1] Yes" \
        "[2] No"
    read -p "Your choices are (1 or 2): " choice

    case "$choice" in
        1)      rm -fr "$cwd" ;;
        2)      return ;;
        *)      unset choice
                cleanup_fn
                ;;
    esac
}

show_ver_fn() {
    save_ver="$(sudo find $install_dir -type f -name 'python3.12' | grep -Eo '[0-9\.]+$')"
    printf "\n%s\n\n" "The installed Python3 version is: $save_ver"
    sleep 3
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "You must run this script with root or sudo."
        exit 1
    fi
}

prepare_environment() {
    echo "Python3 Build Script - v$script_ver"
    echo '==============================================='
    sleep 2

    [ -d "$cwd" ] && rm -fr "$cwd"
    mkdir -p "$cwd"

    export PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/cuda/bin:/usr/local/x86_64-linux-gnu/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games:/snap/bin"
    export PKG_CONFIG_PATH="/usr/share/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/lib/pkgconfig"
}

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-g -O3 -pipe -fno-plt -march=native"
    CXXFLAGS="$CFLAGS"

    export CC CFLAGS CXX CXXFLAGS
}

download_and_extract_python() {
    if [ ! -f "$cwd/$python_version.tar.xz" ]; then
        curl -Lso "$cwd/$python_version.tar.xz" "$archive_url"
    fi
    if [ -d "$cwd/$python_version" ]; then
        rm -fr "$cwd/$python_version:?"
    fi
    mkdir -p "$cwd/$python_version/build"

    tar -xf "$cwd/$python_version.tar.xz" -C "$cwd/$python_version" --strip-components 1 || fail_fn "Failed to extract: $cwd/$python_version.tar.xz. Line: $LINENO"
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
        if ! dpkg-query -W -f='$Status' $pkg 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=($pkg)
        fi
    done

        apt install -y ${missing_packages[@]} || fail_fn "Failed to install required packages. Line: $LINENO"
    else
        echo "All required packages are already installed."
    fi
}

build_python() {
    echo -e "\nBuild Python3 - v$python_version\n==============================================="
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
                 --with-valgrind || fail_fn "Configuration failed. Line: $LINENO"

    make "-j$(nproc)" || fail_fn "Failed to execute: make -j$(nproc). Line: $LINENO"
    make altinstall || fail_fn "Failed to execute: make altinstall. Line: $LINENO"
}

check_root
prepare_environment
install_required_packages
set_compiler_flags
download_and_extract_python
build_python
show_ver_fn
cleanup_fn
exit_fn
