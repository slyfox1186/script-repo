#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-
##  Purpose: build gnu which
##  Updated: 12.10.23
##  Script version: 1.0

if [ "$EUID" -eq 0 ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# SET THE VARIABLES
script_ver="1.0"
archive_dir=which-2.21
archive_url="https://carlowood.github.io/which/$archive_dir.tar.gz"
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/which-build-script"
install_dir=/usr/local

echo "which build script version $script_ver"
echo "==============================================="
echo

# CREATE OUTPUT DIRECTORY
[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

# Set the C + CPP compilers and their compiler optimization flags
CC="gcc"
CXX="g++"
CFLAGS="-O3 -pipe -march=native"
CXXFLAGS="-O3 -pipe -march=native"
export CC CFLAGS CXX CXXFLAGS

# SET THE PATH VARIABLE
PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"
export PATH

# SET THE PKG_CONFIG_PATH VARIABLE
PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig\
"
export PKG_CONFIG_PATH

# CREATE FUNCTIONS
exit_fn() {
    echo
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    echo
    exit 0
}

fail() {
    echo
    echo "$1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    echo
    exit 1
}

cleanup_fn() {
    local choice

    echo "============================================"
    echo "  Do you want to clean up the build files?  "
    echo "============================================"
    echo '[1] Yes'
    echo '[2] No'
    echo
    read -p 'Your choices are (1 or 2): ' choice

    case "$choice" in
        1) sudo rm -fr "$cwd" ;;
        2) echo ;;
        *) unset choice
           clear
           cleanup_fn
           ;;
    esac
}

# INSTALL REQUIRED APT PACKAGES
pkgs=(autoconf autoconf-archive autogen automake autopoint autotools-dev binutils
      bison build-essential bzip2 bzip2 ccache curl libc6-dev libpth-dev libtool
      libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev yasm)

for pkg in ${pkgs[@]}; do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+=" $pkg"
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
    sudo apt -y autoremove
    clear
fi

# DOWNLOAD THE ARCHIVE FILE
if [ ! -f "$cwd/$archive_name" ]; then
    curl -Lso "$cwd/$archive_name" "$archive_url"
fi

# CREATE OUTPUT DIRECTORY
if [ -d "$cwd/$archive_dir" ]; then
    sudo rm -fr "$cwd/$archive_dir"
fi
mkdir -p "$cwd/$archive_dir/build"

# EXTRACT ARCHIVE FILES
if ! tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    printf "%s\n\n" "Failed to extract: $cwd/$archive_name"
    exit 1
fi

# BUILD PROGRAM FROM SOURCE
cd "$cwd/$archive_dir" || exit 1
autoupdate
autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir" \
             --enable-silent-rules
echo
if ! make "-j$(nproc --all)"; then
    fail "Failed to execute: make -j$(nproc --all). Line: $LINENO"
fi
echo
if ! sudo make install; then
    fail "Failed to execute: sudo make install. Line: $LINENO"
fi

# PROMPT USER TO CLEAN UP FILES
cleanup_fn

# SHOW EXIT MESSAGE
exit_fn
