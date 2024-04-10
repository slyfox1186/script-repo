#!/usr/bin/env bash
# shellcheck disable=SC2162,SC2317

##  GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-tools.sh
##  Purpose: Install the latest versions of: CMake, Ninja, Meson, & Golang
##  Updated: 04.04.24
##  Script Version: 3.1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}
warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}
fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo
    echo "To report a bug please create an issue at:"
    echo "https://github.com/slyfox1186/script-repo/issues"
    echo
    exit 1
}

if [[ "$EUID" -eq 0 ]]; then
    fail "You must run this script without root or with sudo."
fi

script_ver=3.1
cwd="$PWD/build-tools-script"
web_repo="https://github.com/slyfox1186/script-repo"
latest="false"
debug="OFF"
cpu_threads=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || nproc --all)

echo -e "${GREEN}Build-tools script ${YELLOW}version $script_ver${NC}"
echo "===================================="

mkdir -p "$cwd"

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-g -O3 -pipe -fno-plt -march=native"
    CPPFLAGS="-I/usr/local/include"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
}
set_compiler_flags

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

PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/usr/local/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/share/pkgconfig\
"
export PKG_CONFIG_PATH

exit_fn() {
    echo
    log "The script has completed"
    echo
    echo -e "${GREEN}Make sure to ${YELLOW}star ${GREEN}this repository to show your support!${NC}"
    log "$web_repo"
    echo
    exit 0
}

cleanup() {
    echo
    read -p "Do you want to remove the build files? (yes/no): " choice

    case "$choice" in
        [yY][eE][sS]*|[yY]*|"")
            rm -fr "$cwd"
            ;;
        [nN][oO]*|[nN]*)
            ;;
        *) unset choice
           cleanup
           ;;
    esac
}

show_versions() {
    echo
    log "The updated versions are:"
    echo
    echo "CMake:  $(cmake --version | sed -e 's/cmake version //g' -e 's/CMake suite maintained and supported by Kitware (kitware.com\/cmake).//g' | xargs -n1)"
    echo "Ninja:  $(ninja --version)"  
    echo "Meson:  $(meson --version)"
    echo "GoLang: $(go version | grep -Eo '[0-9\.]+ | xargs -n1')"
}

execute() {
    echo "$ $*"
    if [[ "$debug" = "ON" ]]; then
        if ! output="$("$@")"; then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail "Failed to execute: $*"
        fi
    else 
        if ! output="$("$@" 2>&1)"; then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail "Failed to execute: $*"  
        fi
    fi
}

download() {
    dl_path="$cwd"
    dl_url="$1"
    dl_file="${2:-${1##*/}}"
    output_dir="${dl_file%.*}"
    output_dir="${3:-${output_dir%.*}}"
    target_file="$dl_path/$dl_file"
    target_dir="$dl_path/$output_dir"
    
    if [[ -f "$target_file" ]]; then
        warn "The file $dl_file is already downloaded."
    else
        log "Downloading $dl_url saving as $dl_file"
        if ! curl -LSso "$target_file" "$dl_url"; then
            echo
            warn "The script failed to download $dl_file and will try again in 10 seconds..."
            sleep 10
            if ! curl -LSso "$target_file" "$dl_url"; then
                fail "The script failed to download $dl_file twice and will now exit: Line $LINENO"
            fi
        fi
        log "Download Completed"
    fi

    [[ -d "$target_dir" ]] && rm -fr "$target_dir"
    mkdir -p "$target_dir"
    
    if [[ -n "$3" ]]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>&1; then
            rm "$target_file"
            fail "The script failed to extract $dl_file so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>&1; then
            rm "$target_file" 
            fail "The script failed to extract $dl_file so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    fi
    
    log "File extracted: $dl_file"
    cd "$target_dir" || fail "Unable to change the working directory to: $target_dir. Line: $LINENO"
}

build() {
    echo
    echo "Building $1 - version $2"
    echo "===================================="
    if [[ -f "$cwd/$1.done" ]]; then
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

build_done() {
    echo "$2" > "$cwd/$1.done"
}

arch_pkgs() {

    pkgs=(
        autoconf automake autogen bluez-qt5 base-devel
        ccache cmake curl git openssl python python-pip
    )
    
    [[ -f "/var/lib/pacman/db.lck" ]] && rm -f "/var/lib/pacman/db.lck"
    
    for pkg in "${pkgs[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            missing_pkgs+="$pkg "
        fi
    done
    
    [[ -n "$missing_pkgs" ]] && pacman -Sq --needed --noconfirm $missing_pkgs

    pip_lock=$(find /usr/lib/python3* -type f -name 'EXTERNALLY-MANAGED')
    if [[ -n "$pip_lock" ]]; then
        pip install --user --break-system-packages --no-input requests setuptools wheel
    else
        pip install --user --no-input requests setuptools wheel
    fi
}

apt_pkgs() {
    pkgs=(
        autoconf autoconf-archive automake autogen build-essential
        ccache cmake curl git libssl-dev libtool m4 python3 python3-pip
        qtbase5-dev
    )

    missing_packages=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            missing_packages+=("$pkg")
        fi  
    done

    if [[ "${#missing_packages[@]}" -gt 0 ]]; then
        log "Installing missing packages: ${missing_packages[*]}"
        sudo apt-get update
        sudo apt-get install -y "${missing_packages[@]}"
    else
        log "The required apt packages are already installed."
    fi
}

search_for_golang_version() {
    curl -fsS "https://go.dev/dl/" | grep -oP 'go[0-9]+\.[0-9]+\.[0-9]+\.*\.tar\.gz' |
    sort -rV | head -n1 | awk -F'.' '{print $1"."$2"."$3}' | sed 's/go//g' |
    sed 's/.linux-amd64.tar.gz//g'  
}
version=$(search_for_golang_version)

git_repo() {
    local count=1
    while [[ $count -le 10 ]]; do
        local line=$(curl -fsS "https://github.com/$1/tags/" | grep -oP 'href="[^"]*\.tar\.gz"' | sed -n "${count}p")
        if echo "$line" | grep -oPq 'v?(\d+\.\d+(?:\.\d*){0,2})\.tar\.gz'; then
            version=$(echo "$line" | grep -oP '(\d+\.\d+(?:\.\d+){0,2})')
            break
        else
            ((count++))
        fi
    done
    [[ $count -gt 10 ]] && fail "No matching version found without RC/rc suffix."
}

add_go_path_to_bashrc() {
    local bashrc="$HOME/.bashrc"
    
    log "Checking if command is already in .bashrc file..."
    if grep -Fq 'PATH="$PATH:$GOROOT/bin"' "$bashrc"; then
        log "Command already exists in .bashrc. No action taken."
    else  
        log "Adding command to .bashrc file..."
        if echo 'PATH="$PATH:$GOROOT/bin"' >> "$bashrc"; then
            log "Command added to .bashrc successfully."
        else
            fail "Failed to add GOROOT to the USER's PATH!"
        fi
    fi
}

get_first_word() {
    echo "$1" | awk '{print $1}'
}

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$(get_first_word "$NAME")  
elif lsb_release -d &>/dev/null; then
    OS=$(lsb_release -d | awk '{print $2}')
else
    fail "Failed to define the \$OS and/or \$VER variables. Line: $LINENO"
fi

case "$OS" in
    Arch) arch_pkgs ;;
    *) apt_pkgs ;;  
esac

git_repo "Kitware/CMake"
if build "cmake" "$version"; then
    download "https://github.com/Kitware/CMake/archive/refs/tags/v$version.tar.gz" "cmake-$version.tar.gz"
    execute ./bootstrap --prefix="/usr/local/cmake-$version" --enable-ccache --parallel="$cpu_threads" --qt-gui
    execute make "-j$cpu_threads"
    execute make install
    execute ln -sf "/usr/local/cmake-$version/bin/cmake" "/usr/local/bin/cmake"
    build_done "cmake" "$version"
fi

git_repo "ninja-build/ninja"  
if build "ninja" "$version"; then
    download "https://github.com/ninja-build/ninja/archive/refs/tags/v$version.tar.gz" "ninja-$version.tar.gz"
    re2c_path="$(command -v re2c)"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="/usr/local/ninja-$version" \
                  -DCMAKE_BUILD_TYPE=Release -DRE2C="$re2c_path" -DBUILD_TESTING=OFF \
                  -Wno-dev
    execute make "-j$cpu_threads" -C build
    execute make -C build install
    execute ln -sf "/usr/local/ninja-$version/bin/ninja" "/usr/local/bin/ninja"
    build_done "ninja" "$version"  
fi

if [[ "$OS" == "Arch" ]]; then
    pacman -Sq --needed --noconfirm meson
else
    sudo apt -y install meson
fi

[[ -d "/usr/local/go" ]] && rm -fr "/usr/local/go"

retrieve_golang_version() {
    local parse_go_url=$(curl -fsS https://go.dev/dl/ | grep -oP 'go[0-9]+\.[0-9]+\.[0-9]+\.linux-amd64.tar.gz' | sort -rV | uniq | head -n1)
    local latest_version=$(echo "$parse_go_url" | awk -F'.' '{print $1"."$2"."$3}' | sed 's/go//g' | sed 's/.linux-amd64.tar.gz//g')

    echo "$latest_version"
}

setup_gopath() {
    GOROOT="/usr/local/golang-$version"
    PATH="$PATH:$GOROOT/bin"
    export GOROOT PATH
    add_go_path_to_bashrc
    source "$HOME/.bashrc"
}

version=$(retrieve_golang_version)

if [[ "$OS" == "Arch" ]]; then
    pacman -Sq --needed --noconfirm go
else
    if build "golang" "$version"; then
        download "https://go.dev/dl/go$version.linux-amd64.tar.gz" "golang-$version.tar.gz"
        mkdir -p "/usr/local/golang-$version/bin"
        execute cp -f "bin/go" "bin/gofmt" "/usr/local/golang-$version/bin"
        build_done "golang" "$version"
    fi
    setup_gopath
fi

ldconfig
show_versions
cleanup
exit_fn
