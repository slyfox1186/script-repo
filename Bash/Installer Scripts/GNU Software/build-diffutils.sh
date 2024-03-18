#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-diffutils
##  Purpose: build gnu diffutils
##  Updated: 08.01.23
##  Script version: 1.1

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script WITHOUT root/sudo."
    exit 1
fi

# Set the variables
script_ver=1.1
archive_dir=diffutils-3.10
archive_url=https://ftp.gnu.org/gnu/diffutils/diffutils-3.10.tar.xz
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.${archive_ext}"
cwd="$PWD/diffutils-build-script"
install_dir=/usr/local

echo "diffutils build script version $script_ver"
echo "==============================================="
echo

# Create output directory
[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

# Set compiler optimization flags
CC="gcc"
CXX="g++"
CFLAGS="-g -O3 -pipe -fno-plt -march=native"
CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CC CFLAGS CXX CXXFLAGS

# Set the path variable
PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"
export PATH

# Set the pkg_config_path variable
PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig\
"
export PKG_CONFIG_PATH

# Create functions
exit_fn() {
    echo
    echo "Make sure to star this repository to show your support!" \
    echo "$https://github.com/slyfox1186/script-repo"
    exit 0
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
        1) sudo rm -fr "$cwd";;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

# Install required apt packages
pkgs=(autoconf autoconf-archive autogen automake binutils build-essential ccache
      cmake curl git libgmp-dev libintl-perl libmpfr-dev libreadline-dev libsigsegv-dev
      libtool libtool-bin lzip m4 nasm ninja-build texinfo zlib1g-dev yasm)

for pkg in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"
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

# Create output directory
[[ -d "$cwd/$archive_dir" ]] && sudo rm -fr "$cwd/$archive_dir"
mkdir -p "$cwd/$archive_dir/build"

# Extract archive files
if ! tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    echo "Failed to extract: $cwd/$archive_name"
    exit 1
fi

# Build program from source
cd "$cwd/$archive_dir" || exit 1
autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir"       \
             --{build,host}=x86_64-linux-gnu \
             --disable-nls                   \
             --enable-threads=posix
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: $LINENO"
fi
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: $LINENO"
fi

sudo ldconfig

# Prompt user to clean up files
cleanup

# Show exit message
exit_fn
