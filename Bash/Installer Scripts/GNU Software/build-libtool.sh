#!/Usr/bin/env bash


if [ "$EUID" -ne 0 ]; then
    echo -e "\nThis script must be run with root privileges. Please run it again with 'sudo' or as root.\n"
    exit 1
fi

script_ver="1.3"
archive_dir="libtool-2.4.7"
archive_url="https://ftp.gnu.org/gnu/libtool/$archive_dir.tar.xz"
cwd="$PWD/libtool-build-script"

echo -e "\n========== libtool Build Script v$script_ver ==========\n"

echo "Preparing build environment..."
rm -fr "$cwd" && mkdir -p "$cwd"

export CC="gcc"
export CXX="g++"
export CFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CXXFLAGS="$CFLAGS"

echo "Installing required packages..."
apt update && apt install autoconf autoconf-archive autogen automake build-essential ccache cmake curl git libltdl-dev

echo "Downloading libtool archive..."
if [ ! -f "$cwd/$archive_dir.tar.xz" ]; then
    curl -Lso "$cwd/$archive_dir.tar.xz" "$archive_url" || { echo "Failed to download libtool archive."; exit 1; }
fi

echo "Extracting archive..."
mkdir -p "$cwd/$archive_dir/build"
tar -xf "$cwd/$archive_dir.tar.xz" -C "$cwd/$archive_dir" --strip-components=1 || { echo "Failed to extract libtool archive."; exit 1; }

echo "Building libtool from source..."
cd "$cwd/$archive_dir/build" || exit 1
../configure --prefix=/usr/local --enable-ltdl-install
if ! make "-j$(nproc)"; then
     echo "Failed to build and install libtool. Line: $LINENO"
     exit 1
fi
if ! make install; then
     echo "Failed to build and install libtool. Line: $LINENO"
     exit 1
fi

echo
read -p "Do you want to clean up the build files? [Y/n]: " choice
if [[ "$choice" =~ ^(yes|y| ) ]] || [[ -z "$choice" ]]; then
    echo "Cleaning up..."
    rm -fr "$cwd"
fi

echo -e "\nlibtool has been successfully built and installed.\n"
echo "Thank you for using this script. For more tools and scripts, visit our GitHub repository:"
echo "https://github.com/slyfox1186/script-repo"
