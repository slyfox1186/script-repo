#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-jq.sh
##  Purpose: Build jq
##  Updated: 05.06.24
##  Script version: 1.2

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

GREEN='\033[32m'
RED='\033[31m'
NC='\033[0m'

# Set the variables
script_ver=1.3
prog_name="jq"
version=$(curl -fsS "https://github.com/jqlang/jq/tags/" | grep -oP '/tag/jq-\K\d+\.\d+\.\d+' | sort -ruV | head -n1)
dir_name="$prog_name-$version"
archive_url="https://github.com/jqlang/jq/releases/download/$prog_name-$version/$prog_name-$version.tar.gz"
archive_ext="${archive_url//*.}"
tar_file="$dir_name.tar.$archive_ext"
install_dir="/usr/local/programs/$dir_name"
cwd="$PWD/$dir_name-build-script"

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

echo "$prog_name build script - version $script_ver"
echo "==============================================="
echo

# Create functions
exit_function() {
    echo
    log "The script has completed"
    log "${GREEN}Make sure to ${YELLOW}star ${GREEN}this repository to show your support!${NC}"
    log "${CYAN}https://github.com/slyfox1186/script-repo${NC}"
    exit 0
}

cleanup() {
    sudo rm -fr "$cwd"
}

install_required_packages() {
    local -a missing_pkgs=() pkgs=()
    local pkg
    pkgs=(
        autoconf autoconf-archive build-essential ccache curl git libtool m4 pkg-config
   )

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ "${#missing_pkgs[@]}" -gt 0 ]; then
        sudo apt update
        sudo apt install "${missing_pkgs[@]}"
    fi
}

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -fPIC -fPIE -flto -mtune=native -DNDEBUG -fstack-protector-strong -Wno-unused-parameter"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

download_archive() {
    wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    tar -zxf "$cwd/$tar_file" -C "$cwd/$dir_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

configure_build() {
    cd "$cwd/$dir_name" || fail "cd into $cwd/$dir_name. Line: $LINENO"
    autoreconf -fi
    cd build || exit 1
    ../configure --prefix="$install_dir" || fail "Failed to configure $prog_name. Line: $LINENO"
}

compile_build() {
    make "-j$(nproc --all)" || fail "Failed to build $prog_name. Line: $LINENO"
}

install_build() {
    sudo make install || fail "Failed to install $prog_name. Line: $LINENO"
}

create_soft_links() {
    sudo ln -sf "$install_dir/bin/"* "/usr/local/bin/" || fail "Failed to create soft links. Line: $LINENO"
    sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    sudo ln -sf "$install_dir/include/"* "/usr/local/include/"
}

create_linker_config_file() {
    echo "$install_dir/lib" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    sudo ldconfig
}

main_menu() {
    # Create output directory
    if [[ -d "$dir_name" ]]; then
        sudo rm -fr "$dir_name"
    fi
    mkdir -p "$cwd/$dir_name/build"

    install_required_packages
    set_compiler_flags
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    create_soft_links
    create_linker_config_file
    cleanup
    exit_function
}

main_menu "$@"
