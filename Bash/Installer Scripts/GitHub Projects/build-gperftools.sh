#!/usr/bin/env bash

# Function to display the help menu
display_help() {
    echo "This script automatically downloads and installs the latest version of gperftools from GitHub."
    echo "If a version number is provided, it will download and install that specific version."
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h              Display this help menu"
    echo "  -v VERSION      Manually specify the version number to download and install"
    echo "  -p PREFIX       Specify the installation prefix (default: /usr/local/gperftools-VERSION)"
    echo
    echo "Examples:"
    echo "  $0                                # Download and install the latest version"
    echo "  $0 -v 2.15 -p /usr/local          # Install version 2.15 to /usr/local"
}

# Parse command-line arguments
while getopts ":hv:p:" opt; do
    case $opt in
        h)
            display_help
            exit 0
            ;;
        v)
            version="$OPTARG"
            ;;
        p)
            prefix="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            display_help
            exit 1
            ;;
    esac
done

# Install requried apt pacakges if not already
sudo apt -y install autoconf autoconf-archive build-essential ccache curl libtool m4

# Find the latest version number if not manually specified
if [ -z "$version" ]; then
    version=$(curl -fsS "https://github.com/gperftools/gperftools/tags/" | grep -oP '(?<=gperftools-)[0-9]+.[0-9]+' | sort -rV | head -n1)
fi

# Set default prefix if not provided
if [ -z "$prefix" ]; then
    prefix="/usr/local/gperftools-$version"
fi

# Set the working directory
cwd="$PWD/gperftools-build-script"
mkdir -p "$cwd"
cd "$cwd" || exit 1

# Download the source code tar.gz file if it doesn't exist
source_file="gperftools-$version.tar.gz"
if [ ! -f "$source_file" ]; then
    download_url="https://github.com/gperftools/gperftools/releases/download/gperftools-$version/gperftools-$version.tar.gz"
    echo "Downloading gperftools $version from: $download_url"
    curl -LsO "$download_url"
fi

# Create the "working" directory
mkdir -p "working/build"

# Extract the source code files
echo
echo "Extracting source code files..."
if ! tar -zxf "$source_file" -C "working" --strip-components=1; then
    echo "Extraction failed. Deleting the archive file and redownloading..."
    rm -f "$source_file"
    curl -LsO "$download_url"
    tar -zxf "$source_file" -C "working" --strip-components=1
fi

# Change to the "working" directory
cd "working" || exit 1

# Set compiler flags for optimization and hardening
CC="ccache gcc"
CXX="ccache g++"
CFLAGS="-O2 -march=native -mtune=native -fstack-protector-strong -D_FORTIFY_SOURCE=2"
CXXFLAGS="$CFLAGS"
LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,-rpath,$prefix/lib"
export CC CXX CFLAGS CXXFLAGS LDFLAGS

# Configure, build, and install gperftools
echo
echo "Configuring, building, and installing gperftools..."
autoreconf -fi
cd build
../configure --prefix="$prefix" --with-pic --with-tcmalloc-pagesize=128 --enable-optimizations
make "-j$(nproc --all)"
sudo make install

# Create symlinks in /usr/local
echo
echo "Creating symlinks in /usr/local..."
sudo ln -sf "$prefix/bin/"* "/usr/local/bin/"
sudo ln -sf "$prefix/lib/"*.so* "/usr/local/lib/"
sudo ln -sf "$prefix/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
sudo ln -sf "$prefix/include/gperftools/"* "/usr/local/include/gperftools/"
sudo ln -sf "$prefix/share/doc/gperftools/"* "/usr/local/share/doc/gperftools/"
sudo ln -sf "$prefix/share/man/man1/"* "/usr/local/share/man/man1/"
sudo ln -sf "$prefix/share/man/man3/"* "/usr/local/share/man/man3/"

# Clean up the build files
echo
echo "Cleaning up build files..."
cd "$cwd"
sudo rm -fr "$cwd"

# Update linker libraries
sudo ldconfig

echo
echo "gperftools $version has been successfully installed to $prefix"
echo "Symlinks have been created in /usr/local"
