#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-autoconf-archive.sh
##  Purpose: build gnu autoconf-archive
##  Updated: 03.16.24
##  Script version: 1.1

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or with sudo."
    exit 1
fi

# Set the variables
archive_dir=autoconf-archive-2023.02.20
archive_url="https://ftp.gnu.org/gnu/autoconf-archive/$archive_dir.tar.xz"
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/autoconf-archive-build-script"
install_dir=/usr/local

# Create output directory
[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

# Set the C +CPP compilers & their compiler optimization flags
CC="gcc"
CXX="g++"
CFLAGS="-O3 -pipe -fno-plt -march=native -mtune=native"
CXXFLAGS="$CFLAGS"
export CC CFLAGS CXX CXXFLAGS

# Set the path variable
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

# Set the PKG_CONFIG_PATH variable
PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig:\
/lib64/pkgconfig:\
/lib/pkgconfig:\
/lib/x86_64-linux-gnu/pkgconfig\
"
export PKG_CONFIG_PATH

# Create functions
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
    echo
    read -p "Remove temporary build directory '$cwd'? [y/N] " response
    case "$response" in
        [yY]*|"")
        sudo rm -rf "$cwd"
        log_msg "Build directory removed."
        ;;
        [nN]*) ;;
    esac
}

# Install required apt packages
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
    sudo apt install $missing_pkgs
fi

# Download the archive file
if [[ ! -f "$cwd/$archive_name" ]]; then
    curl -Lso "$cwd/$archive_name" "$archive_url"
fi

# Create the output directory
[[ -d "$cwd/$archive_dir" ]] && rm -fr "$cwd/$archive_dir"
mkdir -p "$cwd/$archive_dir/build"

# Extract the archive files
if ! tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    echo "Failed to extract: $cwd/$archive_name"
    exit 1
fi

# Build the program from source
cd "$cwd/$archive_dir" || exit 1
autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir"
echo
if ! make "-j$(nproc --all)"; then
    fail "Failed to execute: make -j$(nproc --all). Line: $LINENO"
fi
echo
if ! sudo make install; then
    fail "Failed to execute: make install. Line: $LINENO"
fi

# Prompt user to clean up files
cleanup

# Show exit message
exit_fn
