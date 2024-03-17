#!/Usr/bin/env bash


clear

if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi


script_ver="1.2"
archive_dir="grep-3.11"
archive_url="https://ftp.gnu.org/gnu/grep/grep-3.11.tar.xz"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/grep-build-script"
install_dir="/usr/local"
web_repo="https://github.com/slyfox1186/script-repo"

printf "%s\n%s\n\n" \
    "grep build script - v$script_ver" \
    "==============================================="


if [ -d "$cwd" ]; then
    rm -fr "$cwd"
fi
mkdir -p "$cwd"


export CC="gcc" CXX="g++"


export CFLAGS="-g -O3 -pipe -fno-plt -march=native" CXXFLAGS="$CFLAGS"


export PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/cuda/bin:/usr/local/x86_64-linux-gnu/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games:/snap/bin"


export PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/share/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig:/lib64/pkgconfig:/lib/pkgconfig:/lib/x86_64-linux-gnu/pkgconfig"


exit_fn() {
    printf "\n%s\n\n%s\n\n" \
        "Make sure to star this repository to show your support!" \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "%s\n\n" "$1"
    exit 1
}

cleanup_fn() {
    local answer

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        "============================================" \
        "  Do you want to clean up the build files?  " \
        "============================================" \
        "[1] Yes" \
        "[2] No"
    read -p "Your choices are (1 or 2): " answer

    case "$answer" in
        1) rm -fr "$cwd" ;;
        2) return ;;
        *) clear
           printf "%s\n\n" "Bad user input. Reverting script..."
           sleep 3
           cleanup_fn
           ;;
    esac
}


pkgs_fn() {
    local i missing_pkgs
    pkgs=(
        "autoconf" "autoconf-archive" "autogen" "automake" "binutils" "build-essential" "ccache" "cmake" "curl" "git"
        "libgmp-dev" "libintl-perl" "libmpfr-dev" "libreadline-dev" "libsigsegv-dev" "libticonv-dev" "libtool"
        "libtool-bin" "lzip" "m4" "nasm" "ninja-build" "texinfo" "zlib1g-dev" "yasm"
    )

    for i in "${pkgs[@]}"; do
        if ! dpkg -l | grep -q "$i"; then
            missing_pkgs+=("$i")
        fi
    done

        apt install "${missing_pkgs[@]}"
        apt -y autoremove
        clear
    fi
}


if [ ! -f "$cwd/$archive_name" ]; then
    curl -Lso "$cwd/$archive_name" "$archive_url"
fi


if [ -d "$cwd/$archive_dir" ]; then
    rm -fr "$cwd/$archive_dir"
fi
mkdir -p "$cwd/$archive_dir/build"


if ! tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    printf "%s\n\n" "Failed to extract: $cwd/$archive_name"
    exit 1
fi


cd "$cwd/$archive_dir" || exit 1
autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir" \
             --disable-nls \
             --enable-gcc-warnings=no \
             --enable-threads=posix \
             --with-libsigsegv \
             --with-libsigsegv-prefix=/usr \
             --with-libiconv-prefix=/usr \
             --with-libintl-prefix=/usr \
             PKG_CONFIG="$(type -P pkg-config)" \
             PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: $LINENO"
fi
echo
if ! make install; then
    fail_fn "Failed to execute: make install. Line: $LINENO"
fi

cleanup_fn

exit_fn
