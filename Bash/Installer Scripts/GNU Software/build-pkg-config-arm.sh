#!/Usr/bin/env bash


clear

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi


script_ver=1.3
archive_dir=pkg-config-0.29.2
archive_url=https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz
archive_ext="$archive_url//*."
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD"/pkg-config-build-script
install_dir=/usr
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
web_repo=https://github.com/slyfox1186/script-repo

printf "%s\n%s\n\n" \
    "pkg-config build script - v$script_ver" \
    '==============================================='


if [ -d "$cwd" ]; then
    sudo rm -fr "$cwd"
fi
mkdir -p "$cwd"


export CC=gcc CXX=g++


export {CFLAGS,CXXFLAGS}='-g -O3 -pipe -fno-plt -march=native'


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
/lib64/pkgconfig:\
/lib/pkgconfig:\
/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/ssl/lib/pkgconfig:\
/usr/local/lib/aarch64-linux-gnu/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/aarch64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig\
"
export PKG_CONFIG_PATH


exit_fn() {
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug create an issue at: $web_repo/issues"
    exit 1
}

cleanup_fn() {
    local choice

    printf "%s\n%s\n%s\n\n%s\n%s\n\n" \
        '============================================' \
        '  Do you want to clean up the build files?  ' \
        '============================================' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice

    case "$choice" in
        1)      sudo rm -fr "$cwd";;
        2)      echo;;
        *)
                clear
                printf "%s\n\n" 'Bad user input. Reverting script...'
                sleep 3
                unset choice
                clear
                cleanup_fn
                ;;
    esac
}


pkgs=("$1" autoconf autoconf-archive autogen automake build-essential ca-certificates ccache clang curl
      libaria2-0 libaria2-0-dev libc-ares-dev libdmalloc-dev libgcrypt20-dev libgmp-dev libgnutls28-dev
      libgpg-error-dev libjemalloc-dev libmbedtls-dev libnghttp2-dev librust-openssl-dev libsqlite3-dev
      libssh2-1-dev libssh-dev libssl-dev libxml2-dev pkg-config zlib1g-dev)

for i in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep $i)"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+=" $i"
    fi
done
unset i

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
    clear
fi


if [ ! -f "$cwd/$archive_name" ]; then
    curl -A "$user_agent" -Lso "$cwd/$archive_name" "$archive_url"
fi


if [ -d "$cwd/$archive_dir" ]; then
    sudo rm -fr "$cwd/$archive_dir"
fi
mkdir -p "$cwd/$archive_dir/build"


if ! tar -zxf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    printf "%s\n\n" "Failed to extract: $cwd/$archive_name"
    exit 1
fi


cd "$cwd/$archive_dir/build" || exit 1
../configure --prefix="$install_dir"           \
             --enable-indirect-deps              \
             --with-internal-glib                \
             --with-pc-path="$PKG_CONFIG_PATH" \
             --with-pic                          \
             PKG_CONFIG="$(type -P pkg-config)"
make "-j$(nproc --all)"
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: $LINENO"
    exit 1
fi

cleanup_fn

exit_fn