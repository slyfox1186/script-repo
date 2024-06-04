#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-attr.sh
##  Purpose: build gnu attr
##  Updated: 03.18.24
##  Script version: 1.1

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables
script_ver=1.1
archive_dir=attr-2.5.1
archive_url="https://download.savannah.gnu.org/releases/attr/$archive_dir.tar.gz"
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/attr-build-script"
install_dir=/usr/local

echo "attr build script version $script_ver"
echo "==============================================="
echo

# Create output directory
[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

# Set the c + cpp compilers
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
export CC CFLAGS CXX CXXFLAGS

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

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
    echo "============================================"
    echo "  Do you want to clean up the build files?  "
    echo "============================================"
    echo 
    echo "[[1]] Yes"
    echo "[[2]] No"
    echo
    read -p "Your choices are (1 or 2): " choice

    case "${choice}" in
        1) sudo rm -fr "$cwd" ;;
        2) ;;
        *) unset choice
           clear
           cleanup
           ;;
    esac
}

# Install required apt packages
pkgs=(autoconf autoconf-archive autogen automake autopoint autotools-dev binutils bison
      build-essential bzip2 bzip2 ccache curl libc6-dev libpth-dev git libtool libtool-bin
      lzip pkg-config m4 nasm texinfo zlib1g-dev yasm zlib1g-dev)

for pkg in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"

    if [[ -z "$missing_pkg" ]]; then
        missing_pkgs+=" $pkg"
    fi
done

if [[ -n "$missing_pkgs" ]]; then
    sudo apt install $missing_pkgs
fi

# Download the archive file
[[ ! -f "$cwd/$archive_name" ]] && curl -Lso "$cwd/$archive_name" "$archive_url"

# Create output directory
[[ -d "$cwd/$archive_dir" ]] && sudo rm -fr "$cwd/$archive_dir"
mkdir -p "$cwd/$archive_dir/build"

# Extract archive files
if ! tar -zxf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    printf "%s\n\n" "Failed to extract: $cwd/$archive_name"
    exit 1
fi

# Build program from source
cd "$cwd/$archive_dir" || exit 1
autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir" --disable-nls -with-pic
echo
if ! make "-j$(nproc --all)"; then
    fail "Failed to execute: make -j$(nproc --all). Line: $LINENO"
fi
echo
if ! sudo make install; then
    fail "Failed to execute: sudo make install. Line: $LINENO"
fi

# Prompt user to clean up files
cleanup

# Show exit message
exit_fn
