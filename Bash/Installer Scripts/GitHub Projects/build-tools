#!/usr/bin/env bash
# Shellcheck disable=sc2162,sc2317

##  Github: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-tools
##  Purpose: Install the latest versions of: CMake, Ninja, Meson, & Golang
##  Updated: 02.16.24
##  Added: Automatic version check for Golang.

if [ "$EUID" -eq 0 ]; then
    printf "%s\n\n" "You must run this script without root or sudo.
    exit 1
fi

# Create script variables
script_ver=2.8
cwd="$PWD/build-tools-script"
install_dir="/usr/local"
web_repo="https://github.com/slyfox1186/script-repo"
latest=false
debug=OFF # Change the debug variable to "ON" for help troubleshooting issues

# Print script banner
printf "%s\n%s\n" "Build-tools script: v$script_ver" "===================================="
sleep 2

# Get cpu core count for parallel processing
cpu_threads=$(grep -c ^processor '/proc/cpuinfo' 2>/dev/null || nproc --all)

# Create output directories
mkdir -p "$cwd"

# Set the cc/cxx compilers & the compiler optimization flags
CC=gcc
CXX=g++
CFLAGS="-g -O3 -pipe -fno-plt -march=native"
CXXFLAGS="$CFLAGS"
export CC CXX CFLAGS CXXFLAGS

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

# Set the pkg_config_path variable
PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/usr/local/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/share/pkgconfig\
"
export PKG_CONFIG_PATH

# Create functions
exit_fn() {
    printf "\n%s\n\n%s\n%s\n\n" "The script has completed" "Make sure to star this repository to show your support!" "$web_repo"
    exit 0
}

fail_fn() {
    echo "Error: $1"
    echo
    echo "To report a bug please create an issue at:"
    echo "$web_repo/issues"
    echo
    exit 1
}

cleanup_fn() {
    local choice
    echo
    echo "Do you want to remove the build files?"
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choices are (1 or 2): " choice

    case "$choice" in
        1) sudo rm -fr "$cwd" ;;
        2) return 0 ;;
        *) unset choice
           clear
           cleanup_fn
           ;;
    esac
}

show_versions_fn() {
    local show_cmake_ver show_ninja_ver show_meson_ver show_go_ver

    show_cmake_ver=$(cmake --version | sed -e 's/cmake version //g' -e 's/CMake suite maintained and supported by Kitware (kitware.com\/cmake).//g' | xargs -n1)
    show_ninja_ver=$(ninja --version)
    show_meson_ver=$(meson --version)
    show_go_ver=$(go version | grep -Eo '[0-9\.]+ | xargs -n1')

    printf "\n%s\n\n" "The updated versions are:"
    echo "CMake:  $show_cmake_ver"
    echo "Ninja:  $show_ninja_ver"
    echo "Meson:  $show_meson_ver"
    echo "GoLang: $show_go_ver"
}

execute() {
    echo "$ $*"

    if [ "$debug" = "ON" ]; then
        if ! output="$("$@")"; then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail_fn "Failed to execute: $*"
        fi
    else
        if ! output="$("$@" 2>&1)"; then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail_fn "Failed to execute: $*"
        fi
    fi
}

download() {
    dl_path="$cwd"
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

    if [ -f "$target_file" ]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! curl -Lso "$target_file" "$dl_url"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! curl -Lso "$target_file" "$dl_url"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit:Line $LINENO"
            fi
        fi
        echo "Download Completed"
    fi

    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    fi
    mkdir -p "$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: $LINENO"
}

build() {
    printf "\n%s\n%s\n" "Building $1 - version $2" "===================================="

    if [ -f "$cwd/$1.done" ]; then
        if grep -Fx "$2" "$cwd/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $cwd/$1.done lockfile to rebuild it."
            return 1
        elif "$latest"; then
            echo "$1 is outdated and will be rebuilt using version $2"
            return 0
        else
            echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $cwd/$1.done lockfile."
            return 1
        fi
    fi
    return 0
}

build_done() { echo "$2" > "$cwd/$1.done"; }

# Install required apt/pacman packages
pkgs_arch_fn() {
    pkgs_arch=(
        autoconf automake autogen bluez-qt5 base-devel ccache cmake curl
        git libnghttp2 libnghttp3 openssl python python-pip qt5-base
        qt6-base
    )

# Remove any locks on pacman
    [ -f "/var/lib/pacman/db.lck" ] && sudo rm "/var/lib/pacman/db.lck"

    for i in ${pkgs_arch[@]}
    do
        missing_pkg="$(sudo pacman -Qi | grep -o "$i")"

        if [ -z "$missing_pkg" ]; then
            missing_pkgs+=" $i"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
         sudo pacman -Sq --needed --noconfirm $missing_pkgs
    fi

    [ -n "$(sudo find /usr/lib/python3* -type f -name 'EXTERNALLY-MANAGED')" ] && sudo rm "$rm_pip_lock"

# Install python pip packages
    pip install -q --user --no-input requests setuptools wheel
}

pkgs_fn() {
    pkgs=(
        autoconf autoconf-archive automake autogen build-essential ccache
        cmake curl git libssl-dev libtool libtool-bin m4 python3 python3-pip
        qtbase5-dev
    )

# Initialize arrays for missing, available, and unavailable packages
    missing_packages=()
    available_packages=()
    unavailable_packages=()

# Loop through the array to find missing packages
    for pkg in "${pkgs[@]}"
    do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

# Check availability of missing packages and categorize them
    for pkg in "${missing_packages[@]}"
    do
        if apt-cache show "$pkg" > /dev/null 2>&1; then
            available_packages+=("$pkg")
        else
            unavailable_packages+=("$pkg")
        fi
    done

# Print unavailable packages
    if [ "${#Unavailable_packages[@]}" -gt 0 ]; then
        echo "Unavailable packages: ${unavailable_packages[*]}"
    fi

# Install available missing packages
    if [ "${#Available_packages[@]}" -gt 0 ]; then
        echo "Installing available missing packages: ${available_packages[*]}"
        sudo apt install "${available_packages[@]}"
    else
        echo "No missing packages to install or all missing packages are unavailable."
    fi
}

# Function to find the latest release version of golang
find_latest_golang_version() {
# Use curl to fetch the html content and grep to find lines with download links
    local versions=$(curl -s https://go.dev/dl/ | grep -oP 'go[0-9]+\.[0-9]+\.[0-9]+\.linux-amd64.tar.gz' | sort -Vr | uniq | head -n 1)

# Extract and print the version number
    local latest_version=$(echo $versions | awk -F. '{print $1"."$2"."$3}' | sed 's/go//g' | sed 's/.linux-amd64.tar.gz//g')
    
    echo "$latest_version"
}

# Call the function and store its output in a variable
latest_version=$(find_latest_golang_version)

git_1_fn() {
# Initial cnt
    local cnt curl_cmd git_repo
    git_repo="$1"
    cnt=1

# Loop until the condition is met or a maximum limit is reached
    while [ $cnt -le 10 ]
    do
        curl_cmd="$(curl -sSL "https://github.com/$git_repo/tags")"

# Extract the specific line
        line=$(echo "$curl_cmd" | grep -o 'href="[^"]*\.tar\.gz"' | sed -n "${cnt}p")

# Check if the line matches the pattern (version without 'rc'/'rc')
        if echo "$line" | grep -qP '[v]*(\d+\.\d+(?:\.\d*){0,2})\.tar\.gz'; then
# Extract and print the version number
            g_ver=$(echo "$line" | grep -oP '(\d+\.\d+(?:\.\d+){0,2})')
            break
        else
# Increment the cnt if no match is found
            ((cnt++))
        fi
    done

# Check if a version was found
    if [ $cnt -gt 10 ]; then
        fail_fn "No matching version found without RC/rc suffix."
    fi
}

add_go_path_command_to_bashrc() {
    local command='PATH="$PATH:$GOROOT/bin"'
    local bashrc="$HOME/.bashrc"

    echo "Checking if command is already in .bashrc file..."
    if grep -Fq "$command" "$bashrc"; then
        echo "Command already exists in .bashrc. No action taken."
    else
        echo "Adding command to .bashrc file..."
        if echo "$command" >> "$bashrc"; then
            echo "Command added to .bashrc successfully."
        else
            echo "Failed to add GOROOT to the USER's PATH!"
        fi
    fi
}

# Function to extract the first word from a string
get_first_word() { echo "$1" | awk '{print $1}'; }

# Try to detect the os using /etc/os-release, fall back to lsb_release if available
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$(get_first_word "$NAME")
elif lsb_release -d &>/dev/null; then
    OS=$(lsb_release -d | awk '{print $2}')
else
    fail_fn "Failed to define the \$OS and/or \$VER variables. Line: $LINENO"
fi

case "$OS" in
    Arch)   pkgs_arch_fn ;;
    *)      pkgs_fn ;;
esac

# Check if the latest release is a "rc" aka release candidate and if so go back to the previous stable release
git_1_fn "Kitware/CMake"
if build "cmake" "$g_ver"; then
    download "https://github.com/Kitware/CMake/archive/refs/tags/v$g_ver.tar.gz" "cmake-$g_ver.tar.gz"
    execute ./bootstrap --prefix="$install_dir" --enable-ccache --parallel="$(nproc --all)" --qt-gui
    execute make "-j$cpu_threads"
    execute sudo make install
    build_done "cmake" "$g_ver"
fi

git_1_fn "ninja-build/ninja"
if build "ninja" "$g_ver"; then
    download "https://github.com/ninja-build/ninja/archive/refs/tags/v$g_ver.tar.gz" "ninja-$g_ver.tar.gz"
    re2c_path="$(type -P re2c)"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$install_dir" -DCMAKE_BUILD_TYPE=Release -DRE2C="$re2c_path" -DBUILD_TESTING=OFF -Wno-dev
    execute make "-j$cpu_threads" -C build
    execute sudo make -C build install
    build_done "ninja" "$g_ver"
fi

if [[ "$OS" == "Arch" ]]; then
    sudo pacman -Sq --needed --noconfirm meson 2>&1
else
    git_1_fn "mesonbuild/meson"
    if build "meson" "$g_ver"; then
        download "https://github.com/mesonbuild/meson/archive/refs/tags/$g_ver.tar.gz" "meson-$g_ver.tar.gz"
        execute python3 setup.py build
        execute sudo python3 setup.py install --prefix="$install_dir"
        build_done "meson" "$g_ver"
    fi
fi

# Remove leftover files from previous runs
if [ -d  "$install_dir/go" ]; then
    sudo rm -fr "$install_dir/go"
fi

# Install golang
if [[ "$OS" == "Arch" ]]; then
    sudo pacman -Sq --needed --noconfirm go
else
    if build "golang" "$latest_version"; then
        download "https://go.dev/dl/go${latest_version}.linux-amd64.tar.gz" "golang-${latest_version}.tar.gz"
        execute sudo cp -f "bin/go" "bin/gofmt" "$install_dir/bin"
        build_done "golang" "$latest_version"
    fi
    sudo mkdir -p "$install_dir/go"
    GOROOT="$install_dir/go"
    PATH="$PATH:$GOROOT/bin"
    export GOROOT PATH
    add_go_path_command_to_bashrc
    source "$HOME/.bashrc"
fi

# Ldconfig must be run next in order to update file changes
sudo ldconfig 2>/dev/null

# Show the newly installed version of each package
show_versions_fn

# Prompt the user to clean up the build files
cleanup_fn

# Show the exit message
exit_fn
