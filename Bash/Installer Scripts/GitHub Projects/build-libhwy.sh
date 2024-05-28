#!/usr/bin/env bash
# shellcheck source=/dev/null disable=sc2016,sc2034,sc2046,sc2066,sc2068,sc2086,SC2162,SC2317

##  Install libhwy
##  Supported OS: Debian, Ubuntu
##  Updated: 04.30.24
##  Script version: 1.1

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables
script_ver="1.1"
install_prefix="/usr/local"
cwd="$PWD/libhwy-build-script"
packages="$cwd/packages"
workspace="$cwd/workspace"
debug=OFF

# Create output directories
mkdir -p "$packages" "$workspace"

# Get cpu core count for parallel processing
if [[ -f "/proc/cpuinfo" ]]; then
    cpu_threads="$(grep -c ^processor /proc/cpuinfo)"
else
    cpu_threads="$(nproc --all)"
fi

# Set the compilers
CC="gcc"
CXX="g++"
# Set compiler optimization flags
CFLAGS='-g -O3 -pipe -fno-plt -march=native'
CXXFLAGS="$CFLAGS"
CPPFLAGS="-I$workspace/include -I/usr/local/include -I/usr/include"
LDFLAGS="-L$workspace/lib64 -L$workspace/lib -L$workspace/lib/x86_64-linux-gnu -L/usr/local/lib64"
LDFLAGS+=' -L/usr/local/lib -L/usr/lib/x86_64-linux-gnu -L/usr/lib64 -L/usr/lib -L/lib64 -L/lib'
MAKEFLAGS="-j$(nproc --all)"
export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS MAKEFLAGS

echo
echo "libhwy build script - v$script_ver"
echo "========================================="
echo "This script will utilize ($cpu_threads) CPU threads for parallel processing to accelerate the build process."
echo

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig"
export PATH PKG_CONFIG_PATH

# Define functions
fail_fn() {
    echo
    echo "$1"
    echo "You can enable the script's debugging feature by changing the variable \"debug\" to \"ON\""
    echo "To report a bug visit: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

exit_function() {
    echo
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    exit 0
}

cleanup() {
    local choice
 
    echo
    echo "Do you want to cleanup the build files?"
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p 'Your choices are (1 or 2): ' choice
    clear

    case "$choice" in
        1) sudo rm -fr "$cwd" ;;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

# Scrape github website for the latest repo version

git_1_fn() {
    local curl_cmd github_repo github_url

    github_repo="$1"
    github_url="$2"

    if curl_cmd="$(curl -fsSL "https://api.github.com/repos/$github_repo/$github_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
    fi

}

git_ver_fn() {
    git_1_fn "$1" "releases" 2>/dev/null
}

execute() {
    echo "$ $*"

    if [[ "$debug" = "ON" ]]; then
        if ! output=$("$@"); then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail_fn "Failed to execute: $*"
        fi
    else
        if ! output=$("$@" 2>&1); then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail_fn "Failed to execute: $*"
        fi
    fi
}

download() {
    dl_path="$packages"
    dl_url="$1"
    dl_file="${2:-"${1##*/}"}"

    if [[ "$dl_file" =~ tar. ]]; then
        output_dir="${dl_file%.*}"
        output_dir="${3:-"${output_dir%.*}"}"
    else
        output_dir="${3:-"${dl_file%.*}"}"
    fi

    target_file="$dl_path/$dl_file"
    target_dir="$dl_path/$output_dir"

    if [[ -f "$target_file" ]]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! wget -cqO "$target_file" "$dl_url"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! wget -cqO "$target_file" "$dl_url"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit. Line: $LINENO"
            fi
        fi
        echo "Download Completed"
    fi

    if [[ -d "$target_dir" ]]; then
        sudo rm -fr "$target_dir"
    fi
    mkdir -p "$target_dir"

    if [[ -n "$3" ]]; then
        if ! tar -zxf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    else
        if ! tar -zxf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    fi

    echo "File extracted: $dl_file"
    echo

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: $LINENO"
}

download_git() {
    local dl_path dl_url dl_file target_dir

    dl_path="$packages"
    dl_url="$1"
    dl_file="${2:-"${1##*/}"}"
    dl_file="${dl_file//\./-}"
    target_dir="$dl_path/$dl_file"

    if [[ -n "$3" ]]; then
        output_dir="$dl_path/$3"
        target_dir="$output_dir"
    fi

    [[ -d "$target_dir" ]] && sudo rm -fr "$target_dir"

    echo "Downloading $dl_url as $dl_file"

    if ! git clone -q "$dl_url" "$target_dir"; then
        printf "\n%s\n\n" "The script failed to clone the directory \"$target_dir\" and will try again in 10 seconds..."
        sleep 10
        if ! git clone -q "$dl_url" "$target_dir"; then
            fail_fn "The script failed to clone the directory \"$target_dir\" twice and will now exit the buildLine: $LINENO"
        fi
    else
        printf "%s\n\n" "Successfully cloned: $target_dir"
    fi

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: $LINENO"
}

build() {
    echo
    echo "building $1 - version $2"
    echo "===================================="
    echo

    if [[ -f "$packages/$1.done" ]]; then
        if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        else
            echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $packages/$1.done lockfile."
            return 1
        fi
    fi

    return 0
}

build_done() {
    echo "$2" > "$packages/$1.done"
}

installed() {
    return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}')
}

find_lsb_release="$(sudo find /usr -type f -name 'lsb_release')"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_TMP="$NAME"
    VER_TMP="$VERSION_ID"
    CODENAME="$VERSION_CODENAME"
    OS="$(echo "$OS_TMP" | awk '{print $1}')"
    VER="$(echo "$VER_TMP" | awk '{print $1}')"
elif [[ -n "$find_lsb_release" ]]; then
    OS="$(lsb_release -d | awk '{print $2}')"
    VER="$(lsb_release -r | awk '{print $2}')"
else
    fail_fn "Failed to define the \$OS and/or \$VER variables. Line: $LINENO"
fi

# Install required apt/pacman packages

pkgs_arch_fn() {
    pkgs=(autoconf autoconf-archive autogen automake xorg-util-macros autogen
          base-devel ccache cmake curl git gtest jq libtool m4 ninja openssl
          pkg-config python python-pip python-setuptools qt6-base)

    if [[ -f /var/lib/pacman/db.lck ]]; then
        sudo rm /var/lib/pacman/db.lck
    fi

    for pkg in ${pkgs[@]}; do
        missing_pkg="$(sudo pacman -Qi | grep -o "$pkg")"

        if [[ -z "$missing_pkg" ]]; then
            missing_pkgs+="$pkg "
        fi
    done

    if [[ -n "$missing_pkgs" ]]; then
         sudo pacman -S --noconfirm $missing_pkgs
    fi

    rm_pip_lock="$(sudo find /usr/lib/python3* -type f -name "EXTERNALLY-MANAGED")"
    if [[ -n "$rm_pip_lock" ]]; then
        sudo rm "$rm_pip_lock"
    fi

# Install python pip packages
    pip uninstall -q -y setuptools 2>/dev/null
    sudo pip install -q --no-input setuptools 2>/dev/null
}

pkgs_fn() {
    pkgs=(autoconf autoconf-archive autogen automake autotools-dev
          build-essential ccache cmake curl libgtest-dev libtool
          libtool-bin m4 ninja-build pkg-config)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+="$pkg "
        fi
    done

    if [[ -n "$missing_pkgs" ]]; then
        sudo apt update
        sudo apt install $missing_pkgs
        sudo apt -y autoremove
        clear
    fi
}

case "$OS" in
    Arch)   pkgs_arch_fn;;
    *)      pkgs_fn;;
esac

echo
echo "Installing required apt packages"
echo "================================================"
echo

if [[ -n "$missing_pkgs" ]]; then
    sudo apt update
    sudo apt install $missing_pkgs
    sudo apt -y autoremove
    echo "The required APT packages were installed."
else
    echo "The required APT packages are already installed."
fi

# Build libraries from source
git_ver_fn "google/highway" "R"
if build "libhwy" "$g_ver"; then
    download "https://github.com/google/highway/archive/refs/tags/$g_ver.tar.gz" "libhwy-$g_ver.tar.gz"
    CFLAGS+=" -DHWY_COMPILE_ALL_ATTAINABLE"
    CXXFLAGS+="$CFLAGS"
    execute cmake -S . \
                  -DCMAKE_INSTALL_PREFIX="$install_prefix" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DHWY_ENABLE_TESTS=OFF \
                  -DHWY_SYSTEM_GTEST=OFF \
                  -DBUILD_TESTING=OFF \
                  -DHWY_ENABLE_EXAMPLES=OFF \
                  -DHWY_FORCE_STATIC_LIBS=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads"
    execute sudo ninja install
    build_done "libhwy" "$g_ver"
fi

sudo ldconfig

# Cleanup leftover files
cleanup

# Display exit message
exit_function
