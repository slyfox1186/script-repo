#!/Usr/bin/env bash


clear

if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi


script_ver=1.2
archive_dir=m4-latest
archive_url=https://ftp.gnu.org/gnu/m4/m4-latest.tar.xz
archive_ext="$archive_url//*."
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/m4-build-script"
install_dir=/usr/local
web_repo=https://github.com/slyfox1186/script-repo

printf "%s\n%s\n\n" \
    "m4 build script - v$script_ver" \
    "==============================================="

if [ -d "$cwd" ]; then
    rm -fr "$cwd"
fi
mkdir -p "$cwd"

CC=gcc
CXX=g++
CFLAGS="-g -O3 -pipe -fno-plt -march=native"
CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CC CFLAGS CXX CXXFLAGS

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
/bin:\
/usr/local/games:\
/usr/games:\
/snap/bin\
"
export PATH

PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig:\
/lib64/pkgconfig:\
/lib/pkgconfig:\
/lib/x86_64-linux-gnu/pkgconfig\
"
export PKG_CONFIG_PATH

exit_fn() {
    printf "\n%s\n\n%s\n\n" \
        "Make sure to star this repository to show your support!" \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n%s\n\n%s\n\n" \
        "Error: $1" \
        "To report a bug create an issue at: $web_repo/issues"
    exit 1
}

cleanup_fn() {
    local choice

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        "============================================" \
        "  Do you want to clean up the build files?  " \
        "============================================" \
        "[1] Yes" \
        "[2] No"
    read -p "Your choices are (1 or 2): " choice

    case "$choice" in
        1)      rm -fr "$cwd" ;;
        2)      return ;;
        *)
                unset choice
                echo
                cleanup_fn
                ;;
    esac
}

pkgs=(
    "autoconf" "autoconf-archive" "autogen" "automake" "binutils" "bison"
    "build-essential" "bzip2" "ccache" "curl" "libc6-dev" "libpth-dev"
    "libtool" "libtool-bin" "lzip" "lzma-dev" "m4" "nasm" "texinfo" "zlib1g-dev"
    "yasm"
)

for i in ${pkgs[@]}
do
    missing_pkg="$(dpkg -l | grep -o "$i")"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+=" $i"
    fi
done

if [ -n "$missing_pkgs" ]; then
    apt install $missing_pkgs
    apt -y autoremove
fi

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

cd "$cwd/$archive_dir/build" || exit 1
../configure --prefix="$install_dir" \
             --disable-nls \
             --disable-gcc-warnings \
             --enable-c++ \
             --enable-threads=posix \
             --with-dmalloc
make "-j$(nproc --all)"
if ! make install; then
    fail_fn "Failed to execute: make install. Line: $LINENO"
    exit 1
fi

cleanup_fn

exit_fn
