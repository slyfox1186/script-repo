#!/usr/bin/env bash
# shellcheck disable=SC2162,SC2317

##  GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-tools.sh
##  Purpose: Install the latest versions of: CMake, Ninja, Meson, & Golang
##  Updated: 07.02.24
##  Script Version: 3.3

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

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

script_ver=3.3
cwd="$PWD/build-tools-script"
latest=false
debug=OFF
cpu_threads=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || nproc --all)

echo -e "${GREEN}Build-tools script ${YELLOW}version $script_ver${NC}"
echo "===================================="

mkdir -p "$cwd"

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-I/usr/local/include -I/usr/include"
    LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/programs/lib"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}
set_compiler_flags

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

exit_function() {
    echo
    log "The script has completed"
    echo
    echo -e "${GREEN}Make sure to ${YELLOW}star ${GREEN}this repository to show your support!${NC}"
    log "https://github.com/slyfox1186/script-repo"
    echo
    exit 0
}

cleanup() {
    echo
    read -p "Do you want to remove the build files? (yes/no): " choice

    case "$choice" in
        [yY][eE][sS]*|[yY]*|"")
            sudo rm -fr "$cwd"
            ;;
        [nN][oO]*|[nN]*)
            ;;
        *) unset choice
           cleanup
           ;;
    esac
}

verify_go_installation() {
    local go_path="$GOROOT/bin/go"
    if [[ -x "$go_path" ]]; then
        log "Go binary found at $go_path"
        log "Go version: $("$go_path" version)"
    else
        warn "Go binary not found at $go_path"
        warn "Checking for Go in PATH..."
        if command -v go >/dev/null 2>&1; then
            log "Go found in PATH"
            log "Go version: $(go version)"
            log "Go path: $(which go)"
        else
            warn "Go not found in PATH"
        fi
    fi
}

ensure_goroot_set() {
    if [[ -z "$GOROOT" ]]; then
        local go_version=$(ls -d /usr/local/programs/golang-* 2>/dev/null | sort -V | tail -n1)
        if [[ -n "$go_version" ]]; then
            export GOROOT="$go_version"
            export PATH="$PATH:$GOROOT/bin"
            log "GOROOT set to $GOROOT"
        else
            warn "Unable to find Go installation directory"
        fi
    fi
}

show_versions() {
    echo
    log "The updated versions are:"
    echo
    echo "CMake:  $(cmake --version | awk '{print $3}' | head -n1)"
    echo "Ninja:  $(ninja --version)"
    echo "Meson:  $(meson --version)"

    if [[ -n "$GOROOT" && -x "$GOROOT/bin/go" ]]; then
        echo "GoLang: $("$GOROOT/bin/go" version | awk '{print $3}' | sed 's/go//')"
    else
        echo "GoLang: Not found or GOROOT not set correctly"
        echo "GOROOT: $GOROOT"
        echo "PATH: $PATH"

        # Check if go binary exists in the expected location
        if [[ -x "$GOROOT/bin/go" ]]; then
            echo "Go binary exists at $GOROOT/bin/go"
            echo "Go version: $("$GOROOT/bin/go" version)"
        else
            echo "Go binary not found at $GOROOT/bin/go"
        fi
    fi
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

    if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>&1; then
        rm "$target_file"
        fail "The script failed to extract $dl_file so it was deleted. Please re-run the script. Line: $LINENO"
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

ld_linker_path() {
    local install_dir name
    name="$1"
    install_dir="$2"

    echo -e "$install_dir/lib" | sudo tee "/etc/ld.so.conf.d/custom_$name.conf" >/dev/null
    sudo ldconfig
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
        else
            current_version=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)
            latest_version=$(apt-cache policy "$pkg" | grep Candidate | awk '{print $2}')
            if [[ "$current_version" != "$latest_version" ]]; then
                missing_packages+=("$pkg")
                warn "$pkg version $current_version is installed. It will be updated to $latest_version."
            else
                log "$pkg version $current_version is already installed and up-to-date. Skipping."
            fi
        fi
    done

    if [[ "${#missing_packages[@]}" -gt 0 ]]; then
        log "Installing missing or outdated packages: ${missing_packages[*]}"
        sudo apt update
        sudo apt install -y "${missing_packages[@]}"
    else
        log "The required apt packages are already installed and up-to-date."
    fi
}

search_for_golang_version() {
    if command -v go >/dev/null 2>&1; then
        go version | grep -oP '[\d\.]+' | head -n1
    else
        echo "Not installed"
    fi
}

get_first_word() {
    echo "$1" | awk '{print $1}'
}

add_go_path_to_bashrc() {
    local version="$1"
    local bashrc="$HOME/.bashrc"
    local go_root="/usr/local/programs/golang-$version"

    log "Updating GOROOT and PATH in .bashrc file..."
    sed -i '/^export GOROOT=.*$/d' "$bashrc"
    sed -i '/^export PATH=.*\$GOROOT\/bin.*$/d' "$bashrc"
    echo "" >> "$bashrc"
    echo "export GOROOT=\"$go_root\"" >> "$bashrc"
    echo "export PATH=\"\$PATH:\$GOROOT/bin\"" >> "$bashrc"
    log "GOROOT and PATH updated in .bashrc successfully."

    # Set GOROOT and update PATH for the current session
    export GOROOT="$go_root"
    export PATH="$PATH:$GOROOT/bin"
}

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS=$(get_first_word "$NAME")
elif lsb_release -d &>/dev/null; then
    OS=$(lsb_release -d | awk '{print $2}')
else
    fail "Failed to define the \$OS and/or \$VER variables. Line: $LINENO"
fi

# Retrieve and store current versions of packages
current_cmake_version=$(cmake --version 2>/dev/null | awk '{print $3}' | head -n1)
current_ninja_version=$(ninja --version 2>/dev/null)
current_meson_version=$(meson --version 2>/dev/null)
current_go_version=$(search_for_golang_version)

echo
log "Current versions:"
log "CMake: $current_cmake_version"
log "Ninja: $current_ninja_version"
log "Meson: $current_meson_version"
log "GoLang: $current_go_version"

# Fetch latest versions dynamically
latest_cmake_version=$(curl -fsS "https://github.com/Kitware/CMake/tags" | grep -oP '\/tag\/v\K\d+\.\d+\.\d+(?!.*rc)' | sort -ruV | head -n1)
latest_ninja_version=$(curl -fsS "https://github.com/ninja-build/ninja/tags" | grep -oP '\/tag\/v\K\d+\.\d+\.\d+(?!.*rc)' | sort -ruV | head -n1)
latest_meson_version=$(curl -fsS "https://github.com/mesonbuild/meson/tags" | grep -oP '\/tag\/\K\d+\.\d+\.\d+(?!.*rc)' | sort -ruV | head -n1)
latest_go_version=$(curl -fsS https://go.dev/dl/ | grep -oP 'go\K\d+\.\d+\.\d+(?!.*rc)' | sort -ruV | head -n1)

echo
log "Latest versions:"
log "CMake: $latest_cmake_version"
log "Ninja: $latest_ninja_version"
log "Meson: $latest_meson_version"
log "GoLang: $latest_go_version"

# Compare and build/install if necessary
if [[ "$current_cmake_version" != "$latest_cmake_version" ]]; then
    if build "cmake" "$latest_cmake_version"; then
        prog_cmake="cmake"
        download "https://github.com/Kitware/CMake/archive/refs/tags/v$latest_cmake_version.tar.gz" "$prog_cmake-$latest_cmake_version.tar.gz"
        execute ./bootstrap --prefix="/usr/local/programs/$prog_cmake-$latest_cmake_version" --enable-ccache --parallel="$cpu_threads" --qt-gui
        execute make "-j$cpu_threads"
        execute sudo make install
        sudo ln -sf "/usr/local/programs/$prog_cmake-$latest_cmake_version/bin/cmake" "/usr/local/bin/cmake"
        sudo ln -sf "/usr/local/programs/$prog_cmake-$latest_cmake_version/bin/cmake-gui" "/usr/local/bin/cmake-gui"
        ld_linker_path "$prog_cmake" "/usr/local/programs/$prog_cmake-$latest_cmake_version"
        build_done "cmake" "$latest_cmake_version"
    fi
else
    log "CMake version $latest_cmake_version is already installed and up-to-date. Skipping build."
fi

if [[ "$current_ninja_version" != "$latest_ninja_version" ]]; then
    if build "ninja" "$latest_ninja_version"; then
        prog_ninja="ninja"
        download "https://github.com/ninja-build/ninja/archive/refs/tags/v$latest_ninja_version.tar.gz" "$prog_ninja-$latest_ninja_version.tar.gz"
        re2c_path="$(command -v re2c)"
        execute cmake -B build -DCMAKE_INSTALL_PREFIX="/usr/local/programs/$prog_ninja-$latest_ninja_version" \
                      -DCMAKE_BUILD_TYPE=Release -DRE2C="$re2c_path" -DBUILD_TESTING=OFF \
                      -Wno-dev
        execute make "-j$cpu_threads" -C build
        execute sudo make -C build install
        sudo ln -sf "/usr/local/programs/$prog_ninja-$latest_ninja_version/bin/ninja" "/usr/local/bin/ninja"
        ld_linker_path "$prog_ninja" "/usr/local/programs/$prog_ninja-$latest_ninja_version"
        build_done "ninja" "$latest_ninja_version"
    fi
else
    log "Ninja version $latest_ninja_version is already installed and up-to-date. Skipping build."
fi

if [[ "$current_meson_version" != "$latest_meson_version" ]]; then
    if build "meson" "$latest_meson_version"; then
        download "https://github.com/mesonbuild/meson/archive/refs/tags/$latest_meson_version.tar.gz" "meson-$latest_meson_version.tar.gz"
        execute python3 setup.py build
        execute sudo python3 setup.py install --prefix=/usr/local
        sudo ln -sf "/usr/local/lib/python3.10/site-packages/meson" "/usr/local/bin/meson"
        build_done "meson" "$latest_meson_version"
    fi
else
    log "Meson version $latest_meson_version is already installed and up-to-date. Skipping build."
fi

if [[ "$current_go_version" != "$latest_go_version" ]]; then
    if build "golang" "$latest_go_version"; then
        download "https://go.dev/dl/go$latest_go_version.linux-amd64.tar.gz" "golang-$latest_go_version.tar.gz"
        sudo rm -rf "/usr/local/programs/golang-$latest_go_version"
        sudo mkdir -p "/usr/local/programs/golang-$latest_go_version"
        sudo tar -C "/usr/local/programs/golang-$latest_go_version" --strip-components=1 -xzf "$cwd/golang-$latest_go_version.tar.gz"
        sudo ln -sf "/usr/local/programs/golang-$latest_go_version/bin/go" "/usr/local/bin/go"
        build_done "golang" "$latest_go_version"
        add_go_path_to_bashrc "$latest_go_version"
        # Source .bashrc to apply changes immediately
        source "$HOME/.bashrc"
        verify_go_installation
    fi
else
    log "GoLang version $latest_go_version is already installed and up-to-date. Skipping build."
    # Ensure GOROOT is set even if Go is not newly installed
    export GOROOT="/usr/local/programs/golang-$latest_go_version"
    export PATH="$PATH:$GOROOT/bin"
    verify_go_installation
fi

sudo ldconfig
ensure_goroot_set
show_versions
cleanup
exit_function
