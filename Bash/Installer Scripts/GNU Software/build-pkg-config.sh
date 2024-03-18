#!/Usr/bin/env bash


if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    echo
    exit 1
fi

script_ver=1.5
archive_dir=pkg-config-0.29.2
archive_url="https://pkgconfig.freedesktop.org/releases/$archive_dir.tar.gz"
archive_ext="$archive_url//*."
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/pkg-config-build-script"
install_dir=/usr

echo "pkg-config build script - v$script_ver"
echo "==============================================="
echo
sleep 2

if [ -d "$cwd" ]; then
    sudo rm -fr "$cwd"
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
/bin\
"
export PATH

PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/share/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/lib/pkgconfig\
"
export PKG_CONFIG_PATH

exit_fn() {
    echo
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    echo
    exit 0
}

fail_fn() {
    echo
    echo "[ERROR] $1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    echo
    exit 1
}

cleanup_fn() {
    local choice
    echo
    echo "%s\n%s\n%s\n\n%s\n%s\n\n"
    echo "============================================"
    echo "  Do you want to clean up the build files?  "
    echo "============================================"
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choices are (1 or 2): " choice
    echo

    case "$choice" in
        1) sudo rm -fr "$cwd";;
        2) ;;
        *) unset choice
           cleanup_fn
           ;;
    esac
}

pkgs=("$1" autoconf autoconf-archive autogen automake build-essential
      ca-certificates ccache clang curl libaria2-0 libaria2-0-dev libc-ares-dev
      libdmalloc-dev libgcrypt20-dev libgmp-dev libgnutls28-dev libgpg-error-dev
      libjemalloc-dev libmbedtls-dev libnghttp2-dev librust-openssl-dev libsqlite3-dev
      libssh2-1-dev libssh-dev libssl-dev libxml2-dev pkg-config zlib1g-dev
)

for pkg in ${pkgs[@]}; do
    missing_pkg="$(sudo dpkg -l | grep -o $pkg)"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+=" $pkg"
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
fi

if [ ! -f "$cwd/$archive_name" ]; then
    curl -Lso "$cwd/$archive_name" "$archive_url"
fi

if [ -d "$cwd/$archive_dir" ]; then
    sudo rm -fr "$cwd/$archive_dir"
fi
mkdir -p "$cwd/$archive_dir/build"

if ! tar -zxf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    echo "Failed to extract: $cwd/$archive_name"
    echo
    exit 1
fi

cd "$cwd/$archive_dir" || exit 1
autoconf
cd build || exit 1
../configure --prefix="$install_dir" \
             --enable-indirect-deps \
             --with-internal-glib \
             --with-pc-path="$PKG_CONFIG_PATH" \
             --with-pic \
             PKG_CONFIG=$(type -P pkg-config)
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "make -j$(nproc --all). Line: $LINENO"
fi
echo
if ! sudo make install; then
    fail_fn "sudo make install. Line: $LINENO"
fi

cleanup_fn

exit_fn