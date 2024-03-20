#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/util-linux/Installer%20Scripts/GNU%20Software/build-jq
##  Purpose: Build jq
##  Updated: 12.04.23
##  Script version: 1.0

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables
script_ver=1.1
jq_ver=1.7.1
archive_dir="jq-$jq_ver"
archive_url="https://github.com/jqlang/jq/releases/download/$archive_dir/$archive_dir.tar.gz"
cwd="$PWD/jq-build-script"
install_dir="/usr/local/$archive_dir"

GREEN='\033[32m'
RED='\033[31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
}

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O3 -pipe -fno-plt -march=native"
    CXXFLAGS="-O3 -pipe -fno-plt -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    export CC CFLAGS CPPFLAGS CXX CXXFLAGS LDFLAGS

}

# Create output directory jemalloc
log "Creating output directories"
echo
[[ -d "$cwd/$archive_dir" ]] && sudo rm -fr "$cwd/$archive_dir" "$install_dir"
mkdir -p "$cwd/$archive_dir/build"
sudo mkdir -p "$install_dir/bin"

# Change into the working directory
cd "$cwd" || exit 1

# Download the archive file
if [[ ! -f "$cwd/$archive_dir.tar.gz" ]]; then
    log "Downloading the source code"
    wget -cqO "$cwd/$archive_dir.tar.gz" "$archive_url"
    echo
else
    log "Source code already downloaded"
    echo
fi

# Extract the archive file
log "Extacting archive file"
tar -zxf "$cwd/$archive_dir.tar.gz" -C "$cwd/$archive_dir" --strip-components 1
echo

cd "$cwd/$archive_dir" || exit 1
log "Configuring JQ"
echo
set_compiler_flags
autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir" || fail "Failed to configure JQ"
log "Building JQ"
make "-j$(nproc --all)" || fail "Failed to build JQ"
log "Installing JQ"
sudo make install || fail "Failed to install JQ"

# Create soft links to a common path
echo
log "Creating soft links"
sudo ln -sf "$install_dir/bin/jq" /usr/local/bin/ || fail "Failed to create soft links"

# Print the updated jq version
echo
log "The updated jq file is located at: $(type -P jq)"
echo

log "Removing leftover files"
echo
sudo rm -fr "$cwd" || fail "Failed to remove leftover files"
