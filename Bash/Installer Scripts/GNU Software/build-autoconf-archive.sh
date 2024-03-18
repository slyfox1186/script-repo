#!/Usr/bin/env bash


if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

archive_dir=autoconf-archive-2023.02.20
archive_url=https://ftp.gnu.org/gnu/autoconf-archive/$archive_dir.tar.xz
archive_ext="$archive_url//*."
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/autoconf-archive-build-script"
install_dir=/usr/local

if [ -d "$cwd" ]; then
    rm -fr "$cwd"
fi
mkdir -p "$cwd"

CC="gcc"
CXX="g++"
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
    echo
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail() {
    echo
    echo "$1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

cleanup() {
    local choice

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        "============================================" \
        "  Do you want to clean up the build files?  " \
        "============================================" \
        "[1] Yes" \
        "[2] No"
    read -p "Your choices are (1 or 2): " choice

    case "$choice" in
        1) rm -fr "$cwd" ;;
        2) ;;
        *) unset choice
           clear
           cleanup
           ;;
    esac
}

pkgs=(
      autoconf autoconf-archive autogen automake autopoint autotools-dev binutils
      bison build-essential bzip2 bzip2 ccache curl libc6-dev libpth-dev libtool
      libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev yasm
  )

for pkg in ${pkgs[@]}; do
    missing_pkg="$(dpkg -l | grep -o "$pkg")"
    if [[ -z "$missing_pkg" ]]; then
        missing_pkgs+="$pkg "
    fi
done

if [[ -n "$missing_pkgs" ]]; then
    apt install $missing_pkgs
    clear
fi

if [[ ! -f "$cwd/$archive_name" ]]; then
    curl  -Lso "$cwd/$archive_name" "$archive_url"
fi

if [[ -d "$cwd/$archive_dir" ]]; then
    rm -fr "$cwd/$archive_dir"
fi
mkdir -p "$cwd/$archive_dir/build"

if ! tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    echo "Failed to extract: $cwd/$archive_name"
    exit 1
fi

cd "$cwd/$archive_dir" || exit 1
autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir"

echo
if ! make "-j$(nproc --all)"; then
    fail "Failed to execute: make -j$(nproc --all). Line: $LINENO"
    exit 1
fi

echo
if ! make install; then
    fail "Failed to execute: make install. Line: $LINENO"
    exit 1
fi

cleanup

exit_fn