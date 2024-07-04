#!/usr/bin/env bash
# shellcheck disable=SC2068,SC2162,SC2317 source=/dev/null

# GitHub: https://github.com/slyfox1186/ffmpeg-build-script
#
# Script version: 3.9.3
# Updated: 07.03.24
#
# Purpose: build ffmpeg from source code with addon development libraries
#          also compiled from source to help ensure the latest functionality
# Supported Distros: Debian 11|12
#                    Ubuntu (20|22|24).04
#                    Arch Linux (No longer supported due to the low need.)
# Supported architecture: x86_64
# CUDA SDK Toolkit: Updated to version 12.5.0

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

# Define global variables
script_name="${0##*/}"
script_version="3.9.3"
cwd="$PWD/ffmpeg-build-script"
mkdir -p "$cwd"; cd "$cwd" || exit 1
if [[ "$PWD" =~ ffmpeg-build-script\/ffmpeg-build-script ]]; then
    cd ../
    rm -fr ffmpeg-build-script
    cwd="$PWD"
fi
packages="$cwd/packages"
workspace="$cwd/workspace"
google_speech_flag=false
# Set a regex string to match and then exclude any found release candidate versions of a program. Utilize stable releases only.
git_regex='(Rc|rc|rC|RC|alpha|beta|early|init|next|pending|pre|tentative)+[0-9]*$'
debug=OFF

# Pre-defined color variables
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Print script banner
echo
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner "FFmpeg Build Script - v$script_version"

# Create output directories
mkdir -p "$packages" "$workspace"

# Set the CC/CPP compilers + customized compiler optimization flags
source_compiler_flags() {
    CFLAGS="-O3 -pipe -fPIC -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-I$workspace/include -D_FORTIFY_SOURCE=2"
    LDFLAGS="-L$workspace/lib64 -L$workspace/lib -Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"
    EXTRALIBS="-ldl -lpthread -lm -lz"
    export CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_update() {
    echo -e "${GREEN}[UPDATE]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

exit_fn() {
    echo
    echo -e "${GREEN}[INFO]${NC} Make sure to ${YELLOW}star${NC} this repository to show your support!"
    echo -e "${GREEN}[INFO]${NC} https://github.com/slyfox1186/script-repo"
    echo
    exit 0
}

fail() {
    echo
    echo -e "${RED}[ERROR]${NC} $1"
    echo
    echo -e "${GREEN}[INFO]${NC} For help or to report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    echo
    if $google_speech_flag; then
        google_speech "The FFmpeg build script encountered a fatal error." &>/dev/null
    fi
    exit 1
}

cleanup() {
    local choice

    echo
    read -p "Do you want to clean up the build files? (yes/no): " choice

    case "$choice" in
        [yY]*|[yY][eE][sS]*)
            rm -fr "$cwd"
            ;;
        [nN]*|[nN][oO]*)
            ;;
        *)  unset choice
            cleanup
            ;;
    esac
}

disk_space_requirements() {
    # Set the required install directory size in megabytes
    INSTALL_DIR_SIZE=7001
    log "Required install directory size: $(echo "$INSTALL_DIR_SIZE / 1024" | bc -l | awk '{printf "%.2f", $1}')G"

    # Calculate the minimum required disk space with a 20% buffer
    MIN_DISK_SPACE=$(echo "$INSTALL_DIR_SIZE * 1.2" | bc -l | awk '{print int($1)}')
    warn "Minimum required disk space (including 20% buffer): $(echo "$MIN_DISK_SPACE / 1024" | bc -l | awk '{printf "%.2f", $1}')G"

    # Get the available disk space in megabytes
    AVAILABLE_DISK_SPACE=$(df -BM . | awk '{print $4}' | tail -n1 | sed 's/M//')
    warn "Available disk space: $(echo "$AVAILABLE_DISK_SPACE / 1024" | bc -l | awk '{printf "%.2f", $1}')G"

    # Compare the available disk space with the minimum required
    if (( $(echo "$AVAILABLE_DISK_SPACE < $MIN_DISK_SPACE" | bc -l) )); then
        warn "Insufficient disk space."
        warn "Minimum required (including 20% buffer): $(echo "$MIN_DISK_SPACE / 1024" | bc -l | awk '{printf "%.2f", $1}')G"
        fail "Available disk space: $(echo "$AVAILABLE_DISK_SPACE / 1024" | bc -l | awk '{printf "%.2f", $1}')G"
    else
        log "Sufficient disk space available."
    fi
}

display_ffmpeg_versions() {
    local file files
    files=( [0]=ffmpeg [1]=ffprobe [2]=ffplay )

    echo
    for file in ${files[@]}; do
        if command -v "$file" >/dev/null 2>&1; then
            "$file" -version
            echo
        fi
    done
}

show_versions() {
    local choice

    echo
    read -p "Display the installed versions? (yes/no): " choice

    case "$choice" in
        [yY]*|[yY][eE][sS]*|"")
            display_ffmpeg_versions
            ;;
        [nN]*|[nN][oO]*)
            ;;
        *)  unset choice
            show_versions
            ;;
    esac
}

# Function to ensure no cargo or rustc processes are running
ensure_no_cargo_or_rustc_processes() {
    local running_processes
    running_processes=$(pgrep -fl 'cargo|rustc')
    if [[ -n "$running_processes" ]]; then
        warn "Waiting for cargo or rustc processes to finish..."
        while pgrep -x cargo &>/dev/null || pgrep -x rustc &>/dev/null; do
            sleep 3
        done
        log "No cargo or rustc processes running."
    fi
}

# Function to check if cargo-c is installed and install it if not
check_and_install_cargo_c() {
    if ! command -v cargo-cinstall &>/dev/null; then
        warn "cargo-c could not be found and will be installed..."

        ensure_no_cargo_or_rustc_processes

        # Perform cleanup only when it's safe
        cargo clean 2>/dev/null
        find "$HOME/.cargo/registry/index" -type f -name ".cargo-lock" -delete

        # Install cargo-c
        execute cargo install cargo-c
    fi
}

install_windows_hardware_acceleration() {
    local file
    declare -A files=(
        ["objbase.h"]="https://raw.githubusercontent.com/wine-mirror/wine/master/include/objbase.h"
        ["dxva2api.h"]="https://download.videolan.org/pub/contrib/dxva2api.h"
        ["windows.h"]="https://raw.githubusercontent.com/tpn/winsdk-10/master/Include/10.0.10240.0/um/Windows.h"
        ["direct.h"]="https://raw.githubusercontent.com/tpn/winsdk-10/master/Include/10.0.10240.0/km/crt/direct.h"
        ["dxgidebug.h"]="https://raw.githubusercontent.com/apitrace/dxsdk/master/Include/dxgidebug.h"
        ["dxva.h"]="https://raw.githubusercontent.com/nihon-tc/Rtest/master/header/Microsoft%20SDKs/Windows/v7.0A/Include/dxva.h"
        ["intrin.h"]="https://raw.githubusercontent.com/yuikns/intrin/master/intrin.h"
        ["arm_neon.h"]="https://raw.githubusercontent.com/gcc-mirror/gcc/master/gcc/config/arm/arm_neon.h"
        ["conio.h"]="https://raw.githubusercontent.com/zoelabbb/conio.h/master/conio.h"
    )

    for file in "${!files[@]}"; do
        curl -LSso "$workspace/include/$file" "${files[$file]}"
    done
}

install_rustc() {
    echo "Installing RustUp"
    curl -fsS --proto '=https' --tlsv1.2 'https://sh.rustup.rs' | sh -s -- --default-toolchain stable -y &>/dev/null
    source "$HOME/.cargo/env"
    [[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"
    [[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"
}

check_ffmpeg_version() {
    local ffmpeg_repo
    ffmpeg_repo="$1"

    ffmpeg_git_version=$(git ls-remote --tags "$ffmpeg_repo" |
                         awk -F'/' '/n[0-9]+(\.[0-9]+)*(-dev)?$/ {print $3}' |
                         grep -Ev '\-dev' | sort -ruV | head -n1)
    echo "$ffmpeg_git_version"
}

download() {
    local download_file download_path download_url giflib_regex output_directory target_directory target_file
    download_path="$packages"
    download_url="$1"
    download_file="${2:-"${1##*/}"}"
    giflib_regex='cfhcable\.dl\.sourceforge\.net'

    if [[ "$download_file" =~ tar\. ]]; then
        output_directory="${download_file%.*}"
        output_directory="${output_directory%.*}"
    else
        output_directory="${download_file%.*}"
    fi

    target_file="$download_path/$download_file"
    target_directory="$download_path/$output_directory"

    if [[ -f "$target_file" ]]; then
        log "$download_file is already downloaded."
    else
        log "Downloading \"$download_url\" saving as \"$download_file\""
        if ! curl -LSso "$target_file" "$download_url"; then
            warn "Failed to download \"$download_file\". Second attempt in 3 seconds..."
            sleep 3
            curl -LSso "$target_file" "$download_url" || fail "Failed to download \"$download_file\". Exiting... Line: $LINENO"
        fi
        log "Download Completed"
    fi

    [[ -d "$target_directory" ]] && rm -fr "$target_directory"
    mkdir -p "$target_directory"

    if ! tar -xf "$target_file" -C "$target_directory" --strip-components 1 2>/dev/null; then
        rm "$target_file"
        [[ "$download_url" =~ $giflib_regex ]] && return 0
        fail "Failed to extract the tarball \"$download_file\" and was deleted. Re-run the script to try again. Line: $LINENO"
    fi

    log "File extracted: $download_file"

    cd "$target_directory" || fail "Failed to cd into \"$target_directory\". Line: $LINENO"
}

git_caller() {
    git_url="$1"
    repo_name="$2"
    third_flag="$3"
    recurse_flag=0

    [[ "$3" == "recurse" ]] && recurse_flag=1

    version=$(git_clone "$git_url" "$repo_name" "$third_flag")
    version="${version//Cloning completed: /}"
}

git_clone() {
    local repo_flag repo_name repo_url target_directory version
    repo_url="$1"
    repo_name="${2:-${1##*/}}"
    repo_name="${repo_name//\./-}"
    repo_flag="$3"
    target_directory="$packages/$repo_name"

    case "$repo_flag" in
        ant)
            version=$(git ls-remote --tags "https://github.com/apache/ant.git" |
                      awk -F'/' '/\/v?[0-9]+\.[0-9]+(\.[0-9]+)?(\^\{\})?$/ {tag = $4; sub(/^v/, "", tag); if (tag !~ /\^\{\}$/) print tag}' |
                      sort -ruV | head -n1)
            ;;
        ffmpeg)
            version=$(git ls-remote --tags "https://git.ffmpeg.org/ffmpeg.git" |
                      awk -F/ '/\/n?[0-9]+\.[0-9]+(\.[0-9]+)?(\^\{\})?$/ {tag = $3; sub(/^[v]/, "", tag); print tag}' |
                      grep -v '\^{}' | sort -ruV | head -n1)
            ;;
        *)
            version=$(git ls-remote --tags "$repo_url" |
                      awk -F'/' '/\/v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9]+)?(\^\{\})?$/ {tag = $3; sub(/^v/, "", tag); print tag}' |
                      grep -v '\^{}' | sort -ruV | head -n1)
            [[ -z "$version" ]] && version=$(git ls-remote "$repo_url" | awk '/HEAD/ {print substr($1,1,7)}')
            [[ -z "$version" ]] && version="unknown"
            ;;
    esac

    [[ -f "$packages/$repo_name.done" ]] && store_prior_version=$(cat "$packages/$repo_name.done")

    if [[ ! "$version" == "$store_prior_version" ]]; then
        if [[ "$recurse_flag" -eq 1 ]]; then
            recurse="--recursive"
        elif [[ -n "$3" ]]; then
            target_directory="$download_path/$3"
        fi
        [[ -d "$target_directory" ]] && rm -fr "$target_directory"
        if ! git clone --depth 1 $recurse -q "$repo_url" "$target_directory"; then
            warn "Failed to clone \"$target_directory\". Second attempt in 5 seconds..."
            sleep 5
            git clone --depth 1 $recurse -q "$repo_url" "$target_directory" || fail "Failed to clone \"$target_directory\". Exiting script. Line: $LINENO"
        fi
        cd "$target_directory" || fail "Failed to cd into \"$target_directory\". Line: $LINENO"
    fi

    echo "Cloning completed: $version"
}

gnu_repo() {
    local repo
    repo="$1"
    repo_version=$(curl -fsS "$repo" | grep -oP '[a-z]+-\K(([0-9.]*[0-9]+)){2,}' | sort -ruV | head -n1)
}

github_repo() {
    local count max_attempts repo url url_flag
    repo="$1"
    url="$2"
    url_flag="$3"
    count=1
    max_attempts=10

    [[ -z "$repo" || -z "$url" ]] && fail "Git repository and URL are required. Line: $LINENO"

    while [[ "$count" -le "$max_attempts" ]]; do
        if [[ "$url_flag" -eq 1 ]]; then
            repo_version=$(
                        curl -fsSL "https://github.com/xiph/rav1e/tags/" |
                        grep -oP 'p[0-9]+\.tar\.gz' | sed 's/\.tar\.gz//g' |
                        head -n1
                   )
            if [[ -n "$repo_version" ]]; then
                return 0
            else
                continue
            fi
        else
            if [[ "$repo" == "FFmpeg/FFmpeg" ]]; then
                curl_cmd=$(curl -fsSL "https://github.com/FFmpeg/FFmpeg/tags" | grep -oP 'href="[^"]*[0-9]\..*\.tar\.gz"' | grep -v '\-dev' | sort -ruV)
            else
                curl_cmd=$(curl -fsSL "https://github.com/$repo/$url" | grep -oP 'href="[^"]*\.tar\.gz"')
            fi
        fi

        line=$(echo "$curl_cmd" | grep -oP 'href="[^"]*\.tar\.gz"' | sed -n "${count}p")
        if echo "$line" | grep -qP 'v*(\d+[._]\d+(?:[._]\d*){0,2})\.tar\.gz'; then
            repo_version=$(echo "$line" | grep -oP '(\d+[._]\d+(?:[._]\d+){0,2})')
            break
        else
            ((count++))
        fi
    done

    while [[ "$repo_version" =~ $git_regex ]]; do
        curl_cmd=$(curl -fsSL "https://github.com/$repo/$url" | grep -oP 'href="[^"]*\.tar\.gz"')
        line=$(echo "$curl_cmd" | grep -oP 'href="[^"]*\.tar\.gz"' | sed -n "${count}p")
        if echo "$line" | grep -qP 'v*(\d+[._]\d+(?:[._]\d*){0,2})\.tar\.gz'; then
            repo_version=$(echo "$line" | grep -oP '(\d+[._]\d+(?:[._]\d+){0,2})')
            break
        else
            ((count++))
        fi
    done
}

fetch_repo_version() {
    local api_path base_url commit_id_jq_filter count project short_id_jq_filter version_jq_filter
    base_url="$1"
    project="$2"
    api_path="$3"
    version_jq_filter="$4"
    short_id_jq_filter="$5"
    commit_id_jq_filter="$6"
    count=0

    response=$(curl -fsS "$base_url/$project/$api_path") || fail "Failed to fetch data from $base_url/$project/$api_path in the function \"fetch_repo_version\". Line: $LINENO"

    version=$(echo "$response" | jq -r ".[$count]$version_jq_filter")
    while [[ "$version" =~ $git_regex ]]; do
        ((++count))
        version=$(echo "$response" | jq -r ".[$count]$version_jq_filter")
        [[ -z "$version" || "$version" == "null" ]] && fail "No suitable release version found in the function \"fetch_repo_version\". Line: $LINENO"
    done

    short_id=$(echo "$response" | jq -r ".[$count]$short_id_jq_filter")
    commit_id=$(echo "$response" | jq -r ".[$count]$commit_id_jq_filter")

    repo_version="${version#v}"
    repo_version_1="$commit_id"
    repo_short_version_1="$short_id"
}

find_git_repo() {
    local git_repo url url_action url_flag
    url="$1"
    git_repo="$2"
    url_action="$3"
    url_flag="$4"

    case "$url_flag" in
        enabled) set_url_flag=1 ;;
        *) set_url_flag=0 ;;
    esac

    case "$url_action" in
        B) set_type="branches" ;;
        T) set_type="tags" ;;
        *) set_type="$3" ;;
    esac

    case "$git_repo" in
        1) set_repo="github_repo" ;;
        2) fetch_repo_version "https://code.videolan.org/api/v4/projects" "$url" "repository/$set_type" ".name" ".commit.short_id" ".commit.id"; return 0 ;;
        3) fetch_repo_version "https://gitlab.com/api/v4/projects" "$url" "repository/tags" ".name" ".commit.short_id" ".commit.id"; return 0 ;;
        4) fetch_repo_version "https://gitlab.freedesktop.org/api/v4/projects" "$url" "repository/tags" ".name" ".commit.short_id" ".commit.id"; return 0 ;;
        5) fetch_repo_version "https://gitlab.gnome.org/api/v4/projects" "$url" "repository/tags" ".name" ".commit.short_id" ".commit.id"; return 0 ;;
        6) fetch_repo_version "https://salsa.debian.org/api/v4/projects" "$url" "repository/tags" ".name" ".commit.short_id" ".commit.id"; return 0 ;;
        *) fail "Unsupported repository type in the function \"find_git_repo\". Line: $LINENO" ;;
    esac

    "$set_repo" "$url" "$set_type" "$set_url_flag" 2>/dev/null
}

execute() {
        echo "$ $*"

        if [[ "$debug" == "ON" ]]; then
            if ! output=$("$@"); then
                notify-send -t 5000 "Failed to execute $*" 2>/dev/null
                fail "Failed to execute $*"
            fi
        else
            if ! output=$("$@" 2>/dev/null); then
                notify-send -t 5000 "Failed to execute $*" 2>/dev/null
                fail "Failed to execute $*"
            fi
        fi
}

build() {
    echo
    echo -e "${GREEN}Building${NC} ${YELLOW}$1${NC} - ${GREEN}version ${YELLOW}$2${NC}"
    echo "========================================================"

    if [[ -f "$packages/$1.done" ]]; then
        if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        elif "$LATEST"; then
            echo "$1 is outdated and will be rebuilt with latest version $2"
            return 0
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

library_exists() {
    if ! [[ -x $(pkg-config --exists --print-errors "$1" 2>&1) ]]; then
        return 1
    fi
    return 0
}

determine_libtool_version() {
    case "$STATIC_VER" in
        20.04|22.04|23.04|23.10)
            libtool_version="2.4.6"
            ;;
        11|12|24.04|msft)
            libtool_version="2.4.7"
            ;;
    esac
}

# Function to setup a python virtual environment and install packages with pip
setup_python_venv_and_install_packages() {
    local -a parse_package
    local parse_path="$1"
    shift
    parse_package=("$@")

    echo "Creating a Python virtual environment at $parse_path..."
    python3 -m venv "$parse_path" || fail "Failed to create virtual environment"

    echo "Activating the virtual environment..."
    source "$parse_path/bin/activate" || fail "Failed to activate virtual environment"

    echo "Installing Python packages: ${parse_package[*]}..."
    pip install "${parse_package[@]}" || fail "Failed to install packages"

    echo "Deactivating the virtual environment..."
    deactivate

    echo "Python virtual environment setup and package installation completed."
}

find_cuda_json_file() {
    if [[ -f "/opt/cuda/version.json" ]]; then
        locate_cuda_json_file="/opt/cuda/version.json"
    elif [[ -f "/usr/local/cuda/version.json" ]]; then
        locate_cuda_json_file="/usr/local/cuda/version.json"
    fi

    echo "$locate_cuda_json_file"
}

# PRINT THE SCRIPT OPTIONS
usage() {
    echo
    echo "Usage: $script_name [options]"
    echo
    echo "Options:"
    echo "  -h, --help                        Display usage information"
    echo "   --compiler=<gcc|clang>           Set the default CC and CXX compiler (default: gcc)"
    echo "  -b, --build                       Starts the build process"
    echo "  -c, --cleanup                     Remove all working dirs"
    echo "  -g, --google-speech               Enable Google Speech for audible error messages (google_speech must already be installed to work)."
    echo "  -j, --jobs <number>               Set the number of CPU threads for parallel processing"
    echo "  -l, --latest                      Force the script to build the latest version of dependencies if newer version is available"
    echo "  -n, --enable-gpl-and-non-free     Enable GPL and non-free codecs - https://ffmpeg.org/legal.html"
    echo "  -v, --version                     Display the current script version"
    echo
    echo "Example: bash $script_name --build --compiler=clang -j 8"
    echo
}

COMPILER_FLAG=""
CONFIGURE_OPTIONS=()
LATEST=false
LDEXEFLAGS=""
NONFREE_AND_GPL=false

while (("$#" > 0)); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            echo
            log "The script version is: $script_version"
            exit 0
            ;;
        -n|--enable-gpl-and-non-free)
            CONFIGURE_OPTIONS+=("--enable-"{gpl,libsmbclient,libcdio,nonfree})
            NONFREE_AND_GPL=true
            shift
            ;;
        -b|--build)
            bflag="-b"
            shift
            ;;
        -c|--cleanup)
            cflag="-c"
            cleanup
            shift
            ;;
        -l|--latest)
            LATEST=true
            shift
            ;;
        --compiler=gcc|--compiler=clang)
            COMPILER_FLAG="${1#*=}"
            shift
            ;;
        -j|--jobs)
            threads="$2"
            shift 2
            ;;
        -g|--google-speech)
            google_speech_flag=true
            shift
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$threads" ]]; then
    # Set the available CPU thread and core count for parallel processing (speeds up the build process)
    if [[ -f /proc/cpuinfo ]]; then
        threads=$(grep --count ^processor /proc/cpuinfo)
    else
        threads=$(nproc --all)
    fi
fi
MAKEFLAGS="-j$threads"

if [[ -z "$COMPILER_FLAG" ]] || [[ "$COMPILER_FLAG" == "gcc" ]]; then
    CC="gcc"
    CXX="g++"
elif [[ "$COMPILER_FLAG" == "clang" ]]; then
    CC="clang"
    CXX="clang++"
else
    fail "Invalid compiler specified. Valid options are 'gcc' or 'clang'."
fi
export CC CXX MAKEFLAGS

echo
log "Utilizing $threads CPU threads"
echo

if "$NONFREE_AND_GPL"; then
    warn "With GPL and non-free codecs enabled"
    echo
fi

if [[ -n "$LDEXEFLAGS" ]]; then
    echo "The script has been configured to run in full static mode."
    echo
fi

source_path() {
    ccache_dir="/usr/lib/ccache"
    PATH="$ccache_dir:/usr/local/cuda/bin:$workspace/bin:$HOME/.local/bin:$PATH"
    export PATH
}
source_path

remove_duplicate_paths() {
    local -a path_array
    local IFS new_path seen
    IFS=':'
    path_array=("$PATH")

    declare -A seen

    for path in "${path_array[@]}"; do
        if [[ -n "$path" && ! -v seen[$path] ]]; then
            seen[$path]=1
            if [[ -z "$new_path" ]]; then
                new_path="$path"
            else
                new_path="$new_path:$path"
            fi
        fi
    done

    PATH="$new_path"
    export PATH
}
remove_duplicate_paths

# Set the pkg_config_path variable
PKG_CONFIG_PATH="$workspace/lib64/pkgconfig:$workspace/lib/x86_64-linux-gnu/pkgconfig:$workspace/lib/pkgconfig:$workspace/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/lib64/x86_64-linux-gnu:/usr/local/lib64/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/share/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_PATH

check_amd_gpu() {
    if lshw -C display 2>&1 | grep -Eioq "amdgpu|amd"; then
        echo "AMD GPU detected"
    elif dpkg -l 2>&1 | grep -iq "amdgpu"; then
        echo "AMD GPU detected"
    elif lspci 2>&1 | grep -i "amd"; then
        echo "AMD GPU detected"
    else
        echo "No AMD GPU detected"
    fi
}

check_remote_cuda_version() {
    # Use curl to fetch the HTML content of the page
    local base_version cuda_regex html update_version

    html=$(curl -fsS "https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html")

    # Parse the version directly from the fetched content
    cuda_regex='CUDA\ ([0-9]+\.[0-9]+)(\ Update\ ([0-9]+))?'
    if [[ "$html" =~ $cuda_regex ]]; then
        base_version="${BASH_REMATCH[1]}"
        update_version="${BASH_REMATCH[3]}"
        remote_cuda_version="$base_version"

        # Append the update number if present
        if [[ -n "$update_version" ]]; then
            remote_cuda_version+=".$update_version"
        else
            remote_cuda_version+=".0"
        fi
    fi
}

set_java_variables() {
    source_path
    if [[ -d "/usr/lib/jvm/" ]]; then
        locate_java=$(
                     find /usr/lib/jvm/ -type d -name "java-*-openjdk*" |
                     sort -ruV | head -n1
                  )
    else
        latest_openjdk_version=$(
                                 apt-cache search '^openjdk-[0-9]+-jdk-headless$' |
                                 sort -ruV | head -n1 | awk '{print $1}'
                             )
        if apt -y install $latest_openjdk_version; then
            set_java_variables
        else
            fail "Could not install openjdk. Line: $LINENO"
        fi
    fi
    java_include=$(
                  find /usr/lib/jvm/ -type f -name "javac" |
                  sort -ruV | head -n1 | xargs dirname |
                  sed 's/bin/include/'
              )
    CPPFLAGS+=" -I$java_include"
    JDK_HOME="$locate_java"
    JAVA_HOME="$locate_java"
    PATH="$PATH:$JAVA_HOME/bin"
    export CPPFLAGS JDK_HOME JAVA_HOME PATH
    remove_duplicate_paths
}

set_ant_path() {
    export ANT_HOME="$workspace/ant"
    if [[ ! -d "$workspace/ant/bin" ]] || [[ ! -d "$workspace/ant/lib" ]]; then
        mkdir -p "$workspace/ant/bin" "$workspace/ant/lib" 2>/dev/null
    fi
}

nvidia_architecture() {
    if [[ -n $(find_cuda_json_file) ]]; then
        gpu_name=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -n1)

        case "$gpu_name" in
            "Quadro P2000"|"NVIDIA GeForce GT 1010"|"NVIDIA GeForce GTX 1030"|"NVIDIA GeForce GTX 1050"|"NVIDIA GeForce GTX 1060"|"NVIDIA GeForce GTX 1070"|"NVIDIA GeForce GTX 1080"|"NVIDIA TITAN Xp"|"NVIDIA Tesla P40"|"NVIDIA Tesla P4")
                nvidia_arch_type="compute_61,code=sm_61"
                ;;
            "NVIDIA GeForce GTX 1180"|"NVIDIA GeForce GTX Titan V"|"Quadro GV100"|"NVIDIA Tesla V100")
                nvidia_arch_type="compute_70,code=sm_70"
                ;;
            "NVIDIA GeForce GTX 1660 Ti"|"NVIDIA GeForce RTX 2060"|"NVIDIA GeForce RTX 2070"|"NVIDIA GeForce RTX 2080"|"Quadro 4000"|"Quadro 5000"|"Quadro 6000"|"Quadro 8000"|"NVIDIA T1000"|"NVIDIA T2000"|"NVIDIA Tesla T4")
                nvidia_arch_type="compute_75,code=sm_75"
                ;;
            "NVIDIA GeForce RTX 3050"|"NVIDIA GeForce RTX 3060"|"NVIDIA GeForce RTX 3070"|"NVIDIA GeForce RTX 3080"|"NVIDIA GeForce RTX 3080 Ti"|"NVIDIA GeForce RTX 3090"|"NVIDIA RTX A2000"|"NVIDIA RTX A3000"|"NVIDIA RTX A4000"|"NVIDIA RTX A5000"|"NVIDIA RTX A6000")
                nvidia_arch_type="compute_86,code=sm_86"
                ;;
            "NVIDIA GeForce RTX 4080"|"NVIDIA GeForce RTX 4090")
                nvidia_arch_type="compute_89,code=sm_89"
                ;;
            "NVIDIA H100")
                nvidia_arch_type="compute_90,code=sm_90"
                ;;
            *) echo "If you get a driver version \"mismatch\" when executing the command \"nvidia-smi\", reboot your PC and rerun the script."
               echo
               fail "Failed to set the variable \"nvidia_arch_type\". Line: $LINENO"
               ;;
        esac
    else
        return 1
    fi
}

download_cuda() {
    local -a options
    local choice cuda_pin_url cuda_url cuda_version_number distro installer_path pin_file pkg_ext user_choice version version_serial
    cuda_last_known_update="12.5.0"
    if [[ ! "$remote_cuda_version" == "$remote_cuda_version" ]]; then
        fail "The script needs to be updated manually. Please report and skip this section until the next update."
    else
        cuda_version_number="$remote_cuda_version"
    fi
    cuda_pin_url="https://developer.download.nvidia.com/compute/cuda/repos"
    cuda_url="https://developer.download.nvidia.com/compute/cuda/$cuda_version_number"

    echo
    echo "Pick your Linux version from the list below:"
    echo "Supported architecture: x86_64"
    echo

    options=(
        "Debian 10"
        "Debian 11"
        "Debian 12"
        "Ubuntu 20.04"
        "Ubuntu 22.04"
        "Ubuntu 24.04"
        "Ubuntu WSL"
        "Skip"
    )

    version_serial="12.5.1-555.42.06-1"
    select choice in "${options[@]}"; do
        case "$choice" in
            "Debian 10") distro="debian10"; version="10-12-5"; pkg_ext="deb"; installer_path="local_installers/cuda-repo-debian${version}-local_${version_serial}_amd64.deb" ;;
            "Debian 11") distro="debian11"; version="11-12-5"; pkg_ext="deb"; installer_path="local_installers/cuda-repo-debian${version}-local_${version_serial}_amd64.deb" ;;
            "Debian 12") distro="debian12"; version="12-12-5"; pkg_ext="deb"; installer_path="local_installers/cuda-repo-debian${version}-local_${version_serial}_amd64.deb" ;;
            "Ubuntu 20.04") distro="ubuntu2004"; version="12-5"; pkg_ext="pin"; pin_file="${distro}/x86_64/cuda-${distro}.pin"; installer_path="local_installers/cuda-repo-${distro}-${version}-local_${version_serial}_amd64.deb" ;;
            "Ubuntu 22.04") distro="ubuntu2204"; version="12-5"; pkg_ext="pin"; pin_file="${distro}/x86_64/cuda-${distro}.pin"; installer_path="local_installers/cuda-repo-${distro}-${version}-local_${version_serial}_amd64.deb" ;;
            "Ubuntu 24.04") distro="ubuntu2404"; version="12-5"; pkg_ext="pin"; pin_file="${distro}/x86_64/cuda-${distro}.pin"; installer_path="local_installers/cuda-repo-${distro}-${version}-local_${version_serial}_amd64.deb" ;;
            "Ubuntu WSL") distro="wsl-ubuntu"; version="12-5"; version_ext="12.5.1-1"; pkg_ext="pin"; pin_file="${distro}/x86_64/cuda-${distro}.pin"; installer_path="local_installers/cuda-repo-${distro}-${version}-local_${version_ext}_amd64.deb" ;;
            Skip) return ;;
            *) echo "Invalid choice. Please try again."; continue ;;
        esac
        break
    done

    echo
    echo "Downloading the CUDA SDK Toolkit - version $cuda_version_number"

    mkdir -p "$packages/nvidia-cuda"

    if [[ "$distro" == debian* ]]; then
        distro="${distro//[0-9][0-9]}"
    fi

    package_name="$packages/nvidia-cuda/cuda-$distro-$cuda_version_number.$pkg_ext"
    case "$pkg_ext" in
        "deb"|"pin")
            wget --show-progress -cqO "$package_name" "$cuda_url/$installer_path"
            dpkg -i "$package_name"
            
            # Dynamically find and copy the CUDA keyring file
            cuda_repo_dir="/var/cuda-repo-${distro}${version//./-}-local"
            cuda_keyring_file=$(find "$cuda_repo_dir" -name "cuda-*-keyring.gpg" 2>/dev/null | head -n 1)
            
            if [ -n "$cuda_keyring_file" ]; then
                execute cp -f "$cuda_keyring_file" /usr/share/keyrings/
                log "Copied CUDA keyring file: $cuda_keyring_file"
                
                # Add the CUDA repository to sources.list
                echo "deb [signed-by=/usr/share/keyrings/$(basename "$cuda_keyring_file")] file://$cuda_repo_dir /" | sudo tee /etc/apt/sources.list.d/cuda-repository.list
                
                # Update package lists
                apt update

                # Install cuda-keyring package
                apt install -y cuda-keyring
            else
                warn "CUDA keyring file not found in $cuda_repo_dir. Manual intervention may be required."
            fi

            if [[ "$pkg_ext" == "pin" ]]; then
                wget --show-progress -cqO "/etc/apt/preferences.d/cuda-repository-pin-600" "$cuda_pin_url/$pin_file"
            elif [[ "$distro" == "debian"* ]]; then
                add-apt-repository -y contrib
            fi
            ;;
        *)
            echo "Unsupported package extension: $pkg_ext"
            exit 1
            ;;
    esac

    # Update package lists again and install CUDA toolkit
    apt update
    apt install -y cuda-toolkit-12-5
}

# Function to detect the environment and check for an NVIDIA GPU
check_nvidia_gpu() {
    local found
    path_exists=0
    found=0
    gpu_info=""

    if ! grep -Eiq '(microsoft|slyfox1186)' /proc/version; then
        if lspci | grep -qi nvidia; then
            is_nvidia_gpu_present="NVIDIA GPU detected"
        else
            is_nvidia_gpu_present="NVIDIA GPU not detected"
        fi
    else
        for dir in "/mnt/c" "/c"; do
            if [[ -d "$dir/Windows/System32" ]]; then
                path_exists=1
                if [[ -f "$dir/Windows/System32/cmd.exe" ]]; then
                    gpu_info=$("$dir/Windows/System32/cmd.exe" /d /c "wmic path win32_VideoController get name | findstr /i nvidia" 2>/dev/null)
                    if [[ -n "$gpu_info" ]]; then
                        found=1
                        is_nvidia_gpu_present="NVIDIA GPU detected"
                        break
                    fi
                fi
            fi
        done

        if [[ "$path_exists" -eq 0 ]]; then
            is_nvidia_gpu_present="C drive paths '/mnt/c/' and '/c/' do not exist."
        elif [[ "$found" -eq 0 ]]; then
            is_nvidia_gpu_present="NVIDIA GPU not detected"
        fi
    fi
}

get_local_cuda_version() {
    [[ -f "/usr/local/cuda/version.json" ]] && jq -r '.cuda.version' < "/usr/local/cuda/version.json"
}

# Required Geforce CUDA development packages
install_cuda() {
    local choice

    echo "Checking GPU Status"
    echo "========================================================"
    amd_gpu_test=$(check_amd_gpu)
    check_nvidia_gpu

    if [[ -n "$amd_gpu_test" ]] && [[ "$is_nvidia_gpu_present" == "NVIDIA GPU not detected" ]]; then
        log "AMD GPU detected."
        log "Nvidia GPU not detected"
        warn "CUDA Hardware Acceleration will not be enabled"
        return 0
    elif [[ "$is_nvidia_gpu_present" == "NVIDIA GPU detected" ]]; then
        log "Nvidia GPU detected"
        log "Determining if CUDA is installed..."
        check_remote_cuda_version
        local_cuda_version=$(get_local_cuda_version)

        if [[ -z "$local_cuda_version" ]]; then
            echo "The latest CUDA version available is: $remote_cuda_version"
            echo "CUDA is not currently installed."
            echo
            read -p "Do you want to install the latest CUDA version? (yes/no): " choice
            [[ "$choice" =~ ^(yes|y)$ ]] && download_cuda
        elif [[ "$local_cuda_version" == "$remote_cuda_version" ]]; then
            log "CUDA is already installed and up to date."
            return 0
        else
            echo "The installed CUDA version is: $local_cuda_version"
            echo "The latest CUDA version available is: $remote_cuda_version"
            read -p "Do you want to update/reinstall CUDA to the latest version? (yes/no): " choice
            [[ "$choice" =~ ^(yes|y)$ ]] && download_cuda || return 0
        fi
    else
        gpu_flag=1
    fi
    return 0
}

# Required build packages
apt_pkgs() {
    local -a available_packages missing_packages pkgs unavailable_packages
    local libcpp_pkg libcppabi_pkg libunwind_pkg openjdk_pkg pkg reboot_choice

    # Function to find the latest version of a package by pattern
    find_latest_version() {
        apt-cache search "$1" | sort -ruV | head -n1 | awk '{print $1}'
    }

    # Use the function to find the latest versions of specific packages
    nvidia_driver=$(find_latest_version '^nvidia-driver[0-9-]*$')
    nvidia_utils=$(find_latest_version '^nvidia-utils-[0-9]+$')
    openjdk_pkg=$(find_latest_version '^openjdk-[0-9]+-jdk$')
    libcpp_pkg=$(find_latest_version '^libc\+\+-[0-9]+-dev$')
    libcppabi_pkg=$(find_latest_version '^libc\+\+abi-[0-9]+-dev$')
    libunwind_pkg=$(find_latest_version '^libunwind-[0-9]+-dev$')
    gcc_plugin_pkg=$(find_latest_version '^gcc-[1-3]*-plugin-dev$')

    # Define an array of apt package names
    pkgs=(
        $1 $libcppabi_pkg $libcpp_pkg $libunwind_pkg $nvidia_driver $nvidia_utils $openjdk_pkg $gcc_plugin_pkg
        asciidoc autoconf autoconf-archive automake autopoint bc binutils bison build-essential cargo ccache checkinstall
        curl doxygen fcitx-libs-dev flex flite1-dev gawk gcc gettext gimp-data git gnome-desktop-testing gnustep-gui-runtime
        golang-go google-perftools gperf gtk-doc-tools guile-3.0-dev help2man imagemagick jq junit ladspa-sdk lib32stdc++6
        libasound2-dev libass-dev libaudio-dev libavfilter-dev libbabl-0.1-0 libbluray-dev libbpf-dev libbs2b-dev libbz2-dev
        libc6 libc6-dev libcaca-dev libcairo2-dev libcdio-dev libcdio-paranoia-dev libcdparanoia-dev libchromaprint-dev
        libcjson-dev libcodec2-dev libcrypto++-dev libcurl4-openssl-dev libdav1d-dev libdbus-1-dev libde265-dev libdevil-dev
        libdmalloc-dev libdrm-dev libdvbpsi-dev libebml-dev libegl1-mesa-dev libffi-dev libflac-dev libgbm-dev libgdbm-dev
        libgegl-common libgl1-mesa-dev libgles2-mesa-dev libglfw3-dev libglib2.0-dev libglu1-mesa-dev libgme-dev libgmock-dev
        libgnutls28-dev libgoogle-perftools-dev libgsm1-dev libgtest-dev libgvc6 libibus-1.0-dev libintl-perl libjack-dev
        libladspa-ocaml-dev libldap2-dev libleptonica-dev liblilv-dev liblz-dev liblzma-dev liblzo2-dev libmathic-dev libmatroska-dev
        libmbedtls-dev libmetis5 libmfx-dev libmodplug-dev libmp3lame-dev libmusicbrainz5-dev libnuma-dev libpango1.0-dev libperl-dev
        libplacebo-dev libpocketsphinx-dev libportaudio-ocaml-dev libpsl-dev libpstoedit-dev libpulse-dev librabbitmq-dev libraw-dev
        librtmp-dev librubberband-dev librust-gstreamer-base-sys-dev libsctp-dev libserd-dev libshine-dev libsmbclient-dev libsnappy-dev
        libsndio-dev libspeex-dev libsphinxbase-dev libsqlite3-dev libsratom-dev libssh-dev libssl-dev libsystemd-dev libtalloc-dev
        libtesseract-dev libticonv-dev libtool libwavpack-dev libtwolame-dev libudev-dev libv4l-dev libva-dev libvdpau-dev libvidstab-dev
        libvlccore-dev libvo-amrwbenc-dev libvpl-dev libx11-dev libxcursor-dev libxext-dev libxfixes-dev libxi-dev libxkbcommon-dev libxrandr-dev
        libxss-dev libxvidcore-dev libzmq3-dev libzvbi-dev libzzip-dev lsb-release lshw lzma-dev m4 mesa-utils pandoc python3 python3-pip
        python3-venv ragel re2c scons texi2html texinfo tk-dev unzip valgrind wget xmlto
    )

    if [[ "$OS" == "Debian" ]] && [[ "$is_nvidia_gpu_present" == "NVIDIA GPU detected" ]]; then
        pkgs+=("nvidia-smi")
    fi

    # Initialize arrays for missing, available, and unavailable packages
    available_packages=()
    missing_packages=()
    unavailable_packages=()

    log "Checking package installation status..."

    # Loop through the array to find missing packages
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    # Check availability of missing packages and categorize them
    for pkg in "${missing_packages[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            available_packages+=("$pkg")
        else
            unavailable_packages+=("$pkg")
        fi
    done

    # Print unavailable packages
    if [[ "${#unavailable_packages[@]}" -gt 0 ]]; then
        echo
        warn "Unavailable packages:"
        printf "          %s\n" "${unavailable_packages[@]}"
    fi

    # Install available missing packages
    if [[ "${#available_packages[@]}" -gt 0 ]]; then
        echo
        log "Installing available missing packages:"
        printf "       %s\n" "${available_packages[@]}"
        echo
        apt update
        apt install "${available_packages[@]}"
        apt -y autoremove
        echo
    else
        log "No missing packages to install or all missing packages are unavailable."
        echo
    fi

    amd_gpu_test=$(check_amd_gpu)
    check_nvidia_gpu
    if [[ -n "$amd_gpu_test" ]] && [[ "$is_nvidia_gpu_present" == "NVIDIA GPU not detected" ]]; then
        return 0
    else
        if ! nvidia-smi &>/dev/null; then
            echo
            echo "You most likely just updated your nvidia-driver version because the \"nvidia-smi\" command is no longer working and won't until you reboot your PC."
            echo "This is imporant because it is required for the script to complete. My (recommendation) is you for you to reboot your PC now and then re-run this script."
            echo
            read -p "Do you want to reboot now? (y/n): " reboot_choice
            echo
            case "$reboot_choice" in
                [yY]*|[yY][eE][sS]*)
                    reboot
                    ;;
                [nN]*|[nN][oO]*)
                    ;;
            esac
        fi
    fi
}

check_avx512() {
    # Checking if /proc/cpuinfo exists on the system
    if [[ ! -f "/proc/cpuinfo" ]]; then
        echo "Error: /proc/cpuinfo does not exist on this system."
        return 2
    fi

    # Search for AVX512 flag in cpuinfo
    if grep -q "avx512" "/proc/cpuinfo"; then
        echo "ON"
    else
        echo "OFF"
    fi
}

fix_libiconv() {
    if [[ -f "$workspace/lib/libiconv.so.2" ]]; then
        execute cp -f "$workspace/lib/libiconv.so.2" "/usr/lib/libiconv.so.2"
        execute ln -sf "/usr/lib/libiconv.so.2" "/usr/lib/libiconv.so"
    else
        fail "Unable to locate the file \"$workspace/lib/libiconv.so.2\""
    fi
}

fix_libstd_libs() {
    local libstdc_path
    libstdc_path=$(find /usr/lib/x86_64-linux-gnu/ -type f -name 'libstdc++.so.6.0.*' | sort -ruV | head -n1)
    if [[ ! -f "/usr/lib/x86_64-linux-gnu/libstdc++.so" ]] && [[ -f "$libstdc_path" ]]; then
        ln -sf "$libstdc_path" "/usr/lib/x86_64-linux-gnu/libstdc++.so"
    fi
}

fix_x265_libs() {
    local x265_libs x265_libs_trim
    x265_libs=$(find "$workspace/lib/" -type f -name 'libx265.so.*' | sort -rV | head -n1)
    x265_libs_trim=$(echo "$x265_libs" | sed "s:.*/::" | head -n1)

    cp -f "$x265_libs" "/usr/lib/x86_64-linux-gnu"
    ln -sf "/usr/lib/x86_64-linux-gnu/$x265_libs_trim" "/usr/lib/x86_64-linux-gnu/libx265.so"
}

find_latest_nasm_version() {
    latest_nasm_version=$(
                    curl -fsS "https://www.nasm.us/pub/nasm/stable/" |
                    grep -oP 'nasm-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.xz)' |
                    sort -ruV | head -n1
                )
}

get_openssl_version() {
    openssl_version=$(
                curl -fsS "https://www.openssl.org/source/" |
                grep -oP 'openssl-\K3\.0\.[0-9]+' | sort -ruV |
                head -n1
            )
}

debian_msft() {
    case "$VER" in
        11) apt_pkgs "$debian_pkgs $1" ;;
        12) apt_pkgs "$debian_pkgs $1" ;;
        *) fail "Failed to parse the Debian MSFT version. Line: $LINENO" ;;
    esac
}

debian_os_version() {
    if [[ "$1" == "yes_wsl" ]]; then
        STATIC_VER="msft"
        debian_wsl_pkgs="$2"
    fi

    debian_pkgs=(
                 cppcheck libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev libyuv-utils libyuv0
                 libhwy-dev libsrt-gnutls-dev libyuv-dev libsharp-dev libdmalloc5 libumfpack5
                 libsuitesparseconfig5 libcolamd2 libcholmod3 libccolamd2 libcamd2 libamd2
                 software-properties-common libclang-16-dev libgegl-0.4-0 libgoogle-perftools4
            )

    case "$STATIC_VER" in
        msft)          debian_msft "$debian_wsl_pkgs" ;;
        11)            apt_pkgs "$1 ${debian_pkgs[*]}" ;;
        12|trixie|sid) apt_pkgs "$1 ${debian_pkgs[*]} librist-dev" ;;
        *)             fail "Could not detect the Debian release version. Line: $LINENO" ;;
    esac
}

ubuntu_msft() {
    case "$STATIC_VER" in
        23.04) apt_pkgs "$ubuntu_common_pkgs $jammy_pkgs $ubuntu_wsl_pkgs" ;;
        22.04) apt_pkgs "$ubuntu_common_pkgs $jammy_pkgs $ubuntu_wsl_pkgs" ;;
        20.04) apt_pkgs "$ubuntu_common_pkgs $focal_pkgs $ubuntu_wsl_pkgs" ;;
        *) fail "Failed to parse the Ubuntu MSFT version. Line: $LINENO" ;;
    esac
}

ubuntu_os_version() {
    if [[ "$1" = "yes_wsl" ]]; then
        VER="msft"
        ubuntu_wsl_pkgs="$2"
    fi

    ubuntu_common_pkgs="cppcheck libgegl-0.4-0 libgoogle-perftools4"
    focal_pkgs="libcunit1 libcunit1-dev libcunit1-doc libdmalloc5 libhwy-dev libreadline-dev librust-jemalloc-sys-dev librust-malloc-buf-dev"
    focal_pkgs+=" libsrt-doc libsrt-gnutls-dev libvmmalloc-dev libvmmalloc1 libyuv-dev nvidia-utils-535 libcamd2 libccolamd2 libcholmod3"
    focal_pkgs+=" libcolamd2 libsuitesparseconfig5 libumfpack5 libamd2"
    jammy_pkgs="libacl1-dev libdecor-0-dev liblz4-dev libmimalloc-dev libpipewire-0.3-dev libpsl-dev libreadline-dev librust-jemalloc-sys-dev"
    jammy_pkgs+=" librust-malloc-buf-dev libsrt-doc libsvtav1-dev libsvtav1dec-dev libsvtav1enc-dev libtbbmalloc2 libwayland-dev libclang1-15"
    jammy_pkgs+=" libcamd2 libccolamd2 libcholmod3 libcolamd2 libsuitesparseconfig5 libumfpack5 libamd2"
    lunar_kenetic_pkgs="libhwy-dev libjxl-dev librist-dev libsrt-gnutls-dev libsvtav1-dev libsvtav1dec-dev libsvtav1enc-dev libyuv-dev"
    lunar_kenetic_pkgs+=" cargo-c libcamd2 libccolamd2 libcholmod3 libcolamd2 libsuitesparseconfig5 libumfpack5 libamd2"
    mantic_pkgs="libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev libhwy-dev libsrt-gnutls-dev libyuv-dev libcamd2"
    mantic_pkgs+=" libccolamd2 libcholmod3 cargo-c libsuitesparseconfig5 libumfpack5 libjxl-dev libamd2"
    noble_pkgs="cargo-c libcamd3 libccolamd3 libcholmod5 libcolamd3 libsuitesparseconfig7"
    noble_pkgs+=" libumfpack6 libjxl-dev libamd3 libgegl-0.4-0t64 libgoogle-perftools4t64"
    case "$STATIC_VER" in
        msft)
            ubuntu_msft
            ;;
        24.04)
            apt_pkgs "$2 $noble_pkgs"
            ;;
        23.10)
            apt_pkgs "$1 $mantic_pkgs $lunar_kenetic_pkgs $jammy_pkgs $focal_pkgs"
            ;;
        23.04|22.10)
            apt_pkgs "$1 $ubuntu_common_pkgs $lunar_kenetic_pkgs $jammy_pkgs"
            ;;
        22.04)
            apt_pkgs "$1 $ubuntu_common_pkgs $jammy_pkgs"
            ;;
        20.04)
            apt_pkgs "$1 $ubuntu_common_pkgs $focal_pkgs"
            ;;
        *)
            fail "Could not detect the Ubuntu release version. Line: $LINENO"
            ;;
    esac
}

clear

# Test the OS and its version
find_lsb_release=$(find /usr/bin/ -type f -name lsb_release)

get_os_version() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_TMP="$NAME"
        VER_TMP="$VERSION_ID"
        OS=$(echo "$OS_TMP" | awk '{print $1}')
        VER=$(echo "$VER_TMP" | awk '{print $1}')
        STATIC_OS="$OS"
        STATIC_VER="$VER"
    elif [[ -n "$find_lsb_release" ]]; then
        OS=$(lsb_release -d | awk '{print $2}')
        VER=$(lsb_release -r | awk '{print $2}')
    else
        fail "Failed to define \"\$OS\" and/or \"\$VER\". Line: $LINENO"
    fi
}
get_os_version

# Check if running Windows WSL2
if [[ $(grep -i "Microsoft" /proc/version) ]]; then
    wsl_flag="yes_wsl"
    STATIC_OS="WSL2"
[[ "$OS" == "WSL2" ]] && STATIC_OS="WSL2"
fi

# Use the function to find the latest versions of specific packages
libnvidia_encode_wsl=$(apt-cache search '^libnvidia-encode[0-9]+$' | sort -ruV | head -n1 | awk '{print $1}')
wsl_common_pkgs="cppcheck libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev libyuv-utils"
wsl_common_pkgs+=" libyuv0 libsharp-dev libdmalloc5 $libnvidia_encode_wsl"

# Install required APT packages
echo "Installing the required APT packages"
echo "========================================================"
log "Checking installation status of each package..."

nvidia_encode_utils_version() {
    nvidia_utils_version=$(
                           apt-cache search '^nvidia-utils-.*' 2>/dev/null |
                           grep -oP '^nvidia-utils-[0-9]+' |
                           sort -ruV | head -n1
                       )

    nvidia_encode_version=$(
                            apt-cache search '^libnvidia-encode.*' 2>&1 |
                            grep -oP '^libnvidia-encode-[0-9]+' |
                            sort -ruV | head -n1
                       )
}

nvidia_encode_utils_version
case "$STATIC_OS" in
    WSL2) case "$OS" in
              Debian|n/a) debian_os_version "$wsl_flag" "$wsl_common_pkgs" ;;
              Ubuntu)     ubuntu_os_version "$wsl_flag" "$wsl_common_pkgs" ;;
          esac
          ;;
    Debian|n/a) debian_os_version "$nvidia_encode_version" "$nvidia_utils_version" ;;
    Ubuntu)     ubuntu_os_version "$nvidia_encode_version" "$nvidia_utils_version" ;;
esac

# Check minimum disk space requirements
echo
echo "Checking disk space requirements..."
echo "========================================================"
disk_space_requirements
log "Disk space check completed."
echo

# Set the JAVA variables
set_java_variables

# Check if the CUDA folder exists to determine the installation status
iscuda=$(find /usr/local/cuda/ -type f -name nvcc 2>/dev/null | sort -ruV | head -n1)
cuda_path=$(find /usr/local/cuda/ -type f -name nvcc 2>/dev/null | sort -ruV | head -n1 | grep -oP '^.*/bin?')

# Prompt the user to install the GeForce CUDA SDK-Toolkit
install_cuda

# Update the ld linker search paths
ldconfig

#
# Install the Global Tools
#

echo
box_out_banner_global() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner_global "Installing Global Tools"

# Alert the user that an AMD GPU was found without a Geforce GPU present
if [[ "$gpu_flag" -eq 1 ]]; then
    printf "\n%s\n" "An AMD GPU was detected without a Nvidia GPU present."
fi

# Source the compiler flags
source_compiler_flags

if build "m4" "latest"; then
    download "https://ftp.gnu.org/gnu/m4/m4-latest.tar.xz"
    execute ./configure --prefix="$workspace" --enable-c++ --enable-threads=posix
    execute make "-j$threads"
    execute make install
    build_done "m4" "latest"
fi

if build "autoconf" "2.72"; then
    download "https://ftp.gnu.org/gnu/autoconf/autoconf-2.72.tar.xz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" M4="$workspace/bin/m4"
    execute make "-j$threads"
    execute make install
    build_done "autoconf" "2.72"
fi

determine_libtool_version
if build "libtool" "$libtool_version"; then
    download "https://ftp.gnu.org/gnu/libtool/libtool-$libtool_version.tar.xz"
    execute ./configure --prefix="$workspace" --with-pic M4="$workspace/bin/m4"
    execute make "-j$threads"
    execute make install
    build_done "libtool" "$libtool_version"
fi

gnu_repo "https://pkgconfig.freedesktop.org/releases/"
if build "pkg-config" "$repo_version"; then
    download "https://pkgconfig.freedesktop.org/releases/pkg-config-$repo_version.tar.gz"
    execute autoconf
    execute ./configure --prefix="$workspace" --enable-silent-rules --with-pc-path="$PKG_CONFIG_PATH" --with-internal-glib
    execute make "-j$threads"
    execute make install
    build_done "pkg-config" "$repo_version"
fi

find_git_repo "Kitware/CMake" "1" "T"
if build "cmake" "$repo_version"; then
    download "https://github.com/Kitware/CMake/archive/refs/tags/v$repo_version.tar.gz" "cmake-$repo_version.tar.gz"
    execute ./bootstrap --prefix="$workspace" --parallel="$threads" --enable-ccache
    execute make "-j$threads"
    execute make install
    build_done "cmake" "$repo_version"
fi

find_git_repo "mesonbuild/meson" "1" "T"
if build "meson" "$repo_version"; then
    download "https://github.com/mesonbuild/meson/archive/refs/tags/$repo_version.tar.gz" "meson-$repo_version.tar.gz"
    execute python3 setup.py build
    execute python3 setup.py install --prefix=/usr/local
    build_done "meson" "$repo_version"
fi

find_git_repo "ninja-build/ninja" "1" "T"
if build "ninja" "$repo_version"; then
    download "https://github.com/ninja-build/ninja/archive/refs/tags/v$repo_version.tar.gz" "ninja-$repo_version.tar.gz"
    re2c_path="$(command -v re2c)"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                           -DRE2C="$re2c_path" -DBUILD_TESTING=OFF -Wno-dev
    execute make "-j$threads" -C build
    execute make -C build install
    build_done "ninja" "$repo_version"
fi

find_git_repo "facebook/zstd" "1" "T"
if build "libzstd" "$repo_version"; then
    download "https://github.com/facebook/zstd/archive/refs/tags/v$repo_version.tar.gz" "libzstd-$repo_version.tar.gz"
    cd "build/meson" || exit 1
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=both \
                              --strip \
                              -Dbin_tests=false
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "libzstd" "$repo_version"
fi

find_git_repo "816" "2" "T"
if build "librist" "$repo_version"; then
    download "https://code.videolan.org/rist/librist/-/archive/v$repo_version/librist-v$repo_version.tar.bz2" "librist-$repo_version.tar.bz2"
    execute meson setup build --prefix="$workspace" --buildtype=release \
                              --default-library=static --strip -D{built_tools,test}=false
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "librist" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-librist")

find_git_repo "madler/zlib" "1" "T"
if build "zlib" "$repo_version"; then
    download "https://github.com/madler/zlib/releases/download/v$repo_version/zlib-$repo_version.tar.gz"
    execute ./configure --prefix="$workspace"
    execute make "-j$threads"
    execute make install
    build_done "zlib" "$repo_version"
fi

if "$NONFREE_AND_GPL"; then
    get_openssl_version
    if build "openssl" "$openssl_version"; then
        download "https://www.openssl.org/source/openssl-$openssl_version.tar.gz"
        execute ./Configure --prefix="$workspace" enable-{egd,md2,rc5,trace} threads zlib \
                            --with-rand-seed=os --with-zlib-include="$workspace/include" \
                            --with-zlib-lib="$workspace/lib"
        execute make "-j$threads"
        execute make install_sw
        build_done "openssl" "$openssl_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-openssl")
else
    gnu_repo "https://ftp.gnu.org/gnu/gmp/"
    if build "gmp" "$repo_version"; then
        download "https://ftp.gnu.org/gnu/gmp/gmp-$repo_version.tar.xz"
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make "-j$threads"
        execute make install
        build_done "gmp" "$repo_version"
    fi
    gnu_repo "https://ftp.gnu.org/gnu/nettle/"
    if build "nettle" "$repo_version"; then
        download "https://ftp.gnu.org/gnu/nettle/nettle-$repo_version.tar.gz"
        execute ./configure --prefix="$workspace" --enable-static --disable-{documentation,openssl,shared} \
                            --libdir="$workspace/lib" CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make "-j$threads"
        execute make install
        build_done "nettle" "$repo_version"
    fi
    gnu_repo "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/"
    if build "gnutls" "$repo_version"; then
        download "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-$repo_version.tar.xz"
        execute ./configure --prefix="$workspace" --disable-{cxx,doc,gtk-doc-html,guile,libdane,nls,shared,tests,tools} \
                            --enable-{local-libopts,static} --with-included-{libtasn1,unistring} --without-p11-kit \
                            CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS"
        execute make "-j$threads"
        execute make install
        build_done "gnutls" "$repo_version"
    fi
fi

find_git_repo "yasm/yasm" "1" "T"
if build "yasm" "$repo_version"; then
    download "https://github.com/yasm/yasm/archive/refs/tags/v$repo_version.tar.gz" "yasm-$repo_version.tar.gz"
    execute autoreconf -fi
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF -DYASM_BUILD_TESTS=OFF -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "yasm" "$repo_version"
fi

find_latest_nasm_version
if build "nasm" "$latest_nasm_version"; then
    find_latest_nasm_version
    download "https://www.nasm.us/pub/nasm/stable/nasm-$latest_nasm_version.tar.xz"
    execute autoupdate
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-pedantic --enable-ccache
    execute make "-j$threads"
    execute make install
    build_done "nasm" "$latest_nasm_version"
fi

if build "giflib" "5.2.2"; then
    download "https://cfhcable.dl.sourceforge.net/project/giflib/giflib-5.2.2.tar.gz?viasf=1"
    # Parellel building not available for this library
    execute make
    execute make PREFIX="$workspace" install
    build_done "giflib" "5.2.2"
fi

gnu_repo "https://ftp.gnu.org/gnu/libiconv/"
if build "libiconv" "$repo_version"; then
    download "https://ftp.gnu.org/gnu/libiconv/libiconv-$repo_version.tar.gz"
    execute ./configure --prefix="$workspace" --enable-static --with-pic
    execute make "-j$threads"
    execute make install
    fix_libiconv
    build_done "libiconv" "$repo_version"
fi

# UBUNTU BIONIC FAILS TO BUILD XML2
if [[ "$STATIC_VER" != "18.04" ]]; then
    find_git_repo "1665" "5" "T"
    if build "libxml2" "$repo_version"; then
        download "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$repo_version/libxml2-v$repo_version.tar.bz2" "libxml2-$repo_version.tar.bz2"
        CFLAGS+=" -DNOLIBTOOL"
        execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF -G Ninja -Wno-dev
        execute ninja "-j$threads" -C build
        execute ninja -C build install
        build_done "libxml2" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-libxml2")
fi

find_git_repo "pnggroup/libpng" "1" "T"
if build "libpng" "$repo_version"; then
    download "https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.43.tar.gz" "libpng-$repo_version.tar.gz"
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-hardware-optimizations=yes --with-pic
    execute make "-j$threads"
    execute make install-header-links install-library-links install
    build_done "libpng" "$repo_version"
fi

find_git_repo "4720790" "3" "T"
if build "libtiff" "$repo_version"; then
    download "https://gitlab.com/libtiff/libtiff/-/archive/v$repo_version/libtiff-v$repo_version.tar.bz2" "libtiff-$repo_version.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-{docs,sphinx,tests} --enable-cxx --with-pic
    execute make "-j$threads"
    execute make install
    build_done "libtiff" "$repo_version"
fi

if "$NONFREE_AND_GPL"; then
    find_git_repo "nkoriyama/aribb24" "1" "T"
    if build "aribb24" "$repo_version"; then
        download "https://github.com/nkoriyama/aribb24/archive/refs/tags/v$repo_version.tar.gz" "aribb24-$repo_version.tar.gz"
        execute autoreconf -fi
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make "-j$threads"
        execute make install
        build_done "aribb24" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-libaribb24")
fi

find_git_repo "7950" "4"
repo_version="${repo_version#VER-}"
repo_version_1="${repo_version//-/.}"
if build "freetype" "$repo_version_1"; then
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/VER-$repo_version/freetype-VER-$repo_version.tar.bz2" "freetype-$repo_version_1.tar.bz2"
    extracmds=("-D"{harfbuzz,png,bzip2,brotli,zlib,tests}"=disabled")
    execute ./autogen.sh
    execute meson setup build --prefix="$workspace" --buildtype=release --default-library=static --strip "${extracmds[@]}"
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "freetype" "$repo_version_1"
fi
CONFIGURE_OPTIONS+=("--enable-libfreetype")

find_git_repo "890" "4"
if build "fontconfig" "$repo_version"; then
    download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$repo_version/fontconfig-$repo_version.tar.bz2"
    extracmds=("--disable-"{docbook,docs,nls,shared})
    LDFLAGS+=" -DLIBXML_STATIC"
    sed -i "s|Cflags:|& -DLIBXML_STATIC|" "fontconfig.pc.in"
    execute autoupdate
    execute ./autogen.sh --noconf
    execute ./configure --prefix="$workspace" "${extracmds[@]}" --enable-{iconv,static} --with-arch="$(uname -m)" --with-libiconv-prefix=/usr
    execute make "-j$threads"
    execute make install
    build_done "fontconfig" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libfontconfig")

find_git_repo "harfbuzz/harfbuzz" "1" "T"
if build "harfbuzz" "$repo_version"; then
    download "https://github.com/harfbuzz/harfbuzz/archive/refs/tags/$repo_version.tar.gz" "harfbuzz-$repo_version.tar.gz"
    extracmds=("-D"{benchmark,cairo,docs,glib,gobject,icu,introspection,tests}"=disabled")
    execute meson setup build --prefix="$workspace" --buildtype=release --default-library=static --strip "${extracmds[@]}"
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "harfbuzz" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libharfbuzz")

git_caller "https://github.com/fribidi/c2man.git" "c2man-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute ./Configure -desO \
                        -D bin="$workspace/bin" \
                        -D cc="/usr/bin/cc" \
                        -D d_gnu="/usr/lib/x86_64-linux-gnu" \
                        -D gcc="/usr/bin/gcc" \
                        -D installmansrc="$workspace/share/man" \
                        -D ldflags="$LDFLAGS" \
                        -D libpth="/usr/lib64 /usr/lib" \
                        -D locincpth="$workspace/include /usr/local/include /usr/include" \
                        -D loclibpth="$workspace/lib64 $workspace/lib /usr/local/lib64 /usr/local/lib" \
                        -D osname="$OS" \
                        -D prefix="$workspace" \
                        -D privlib="$workspace/lib/c2man" \
                        -D privlibexp="$workspace/lib/c2man"
    execute make depend
    execute make "-j$threads"
    execute make install
    build_done "$repo_name" "$version"
fi

find_git_repo "fribidi/fribidi" "1" "T"
if build "fribidi" "$repo_version"; then
    download "https://github.com/fribidi/fribidi/archive/refs/tags/v$repo_version.tar.gz" "fribidi-$repo_version.tar.gz"
    extracmds=("-D"{docs,tests}"=false")
    execute autoreconf -fi
    execute meson setup build --prefix="$workspace" --buildtype=release --default-library=static "${extracmds[@]}"
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "fribidi" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libfribidi")

find_git_repo "libass/libass" "1" "T"
if build "libass" "$repo_version"; then
    download "https://github.com/libass/libass/archive/refs/tags/$repo_version.tar.gz" "libass-$repo_version.tar.gz"
    execute autoupdate
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$threads"
    execute make install
    build_done "libass" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libass")

find_git_repo "freeglut/freeglut" "1" "T"
if build "freeglut" "$repo_version"; then
    download "https://github.com/freeglut/freeglut/releases/download/v$repo_version/freeglut-$repo_version.tar.gz"
    CFLAGS+=" -DFREEGLUT_STATIC"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF -DFREEGLUT_BUILD_{DEMOS,SHARED_LIBS}=OFF -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "freeglut" "$repo_version"
fi

git_caller "https://chromium.googlesource.com/webm/libwebp" "libwebp-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"  "libwebp-git"
    execute autoreconf -fi
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON -DZLIB_INCLUDE_DIR="$workspace/include" \
                  -DWEBP_BUILD_{ANIM_UTILS,EXTRAS,VWEBP}=OFF -DWEBP_BUILD_{CWEBP,DWEBP}=ON \
                  -DWEBP_ENABLE_SWAP_16BIT_CSP=OFF -DWEBP_LINK_STATIC=ON -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi
CONFIGURE_OPTIONS+=("--enable-libwebp")

find_git_repo "google/highway" "1" "T"
if build "libhwy" "$repo_version"; then
    download "https://github.com/google/highway/archive/refs/tags/$repo_version.tar.gz" "libhwy-$repo_version.tar.gz"
    CFLAGS+=" -DHWY_COMPILE_ALL_ATTAINABLE"
    CXXFLAGS+=" -DHWY_COMPILE_ALL_ATTAINABLE"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_TESTING=OFF -DHWY_ENABLE_{EXAMPLES,TESTS}=OFF -DHWY_FORCE_STATIC_LIBS=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "libhwy" "$repo_version"
fi

find_git_repo "google/brotli" "1" "T"
if build "brotli" "$repo_version"; then
    download "https://github.com/google/brotli/archive/refs/tags/v$repo_version.tar.gz" "brotli-$repo_version.tar.gz"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "brotli" "$repo_version"
fi

find_git_repo "mm2/Little-CMS" "1" "T"
if build "lcms2" "$repo_version"; then
    download "https://github.com/mm2/Little-CMS/archive/refs/tags/lcms$repo_version.tar.gz" "lcms2-$repo_version.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static --with-threaded
    execute make "-j$threads"
    execute make install
    build_done "lcms2" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-lcms2")

find_git_repo "gflags/gflags" "1" "T"
if build "gflags" "$repo_version"; then
    download "https://github.com/gflags/gflags/archive/refs/tags/v$repo_version.tar.gz" "gflags-$repo_version.tar.gz"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_gflags_LIB=ON -DBUILD_STATIC_LIBS=ON -DINSTALL_HEADERS=ON \
                  -DREGISTER_{BUILD_DIR,INSTALL_PREFIX}=ON -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "gflags" "$repo_version"
fi

git_caller "https://github.com/KhronosGroup/OpenCL-SDK.git" "opencl-sdk-git" "recurse"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_{DOCS,EXAMPLES,SHARED_LIBS,TESTING}=OFF -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DCMAKE_C_FLAGS="$CFLAGS" -DOPENCL_HEADERS_BUILD_CXX_TESTS=OFF \
            -DOPENCL_ICD_LOADER_BUILD_SHARED_LIBS=OFF -DOPENCL_SDK_BUILD_{OPENGL_SAMPLES,SAMPLES}=OFF \
            -DOPENCL_SDK_TEST_SAMPLES=OFF -DTHREADS_PREFER_PTHREAD_FLAG=ON -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi
CONFIGURE_OPTIONS+=("--enable-opencl")

git_caller "https://github.com/imageMagick/jpeg-turbo.git" "jpeg-turbo-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute cmake -S . -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -G Ninja -Wno-dev
    execute ninja "-j$threads"
    execute ninja install
    build_done "$repo_name" "$version"
    build_done "$repo_name" "$version"
fi

if "$NONFREE_AND_GPL"; then
    git_caller "https://github.com/m-ab-s/rubberband.git" "rubberband-git"
    if build "$repo_name" "${version//\$ /}"; then
        echo "Cloning \"$repo_name\" saving version \"$version\""
        git_clone "$git_url"
        execute make "-j$threads" PREFIX="$workspace" install-static
        build_done "$repo_name" "$version"
    fi
    CONFIGURE_OPTIONS+=("--enable-librubberband")
fi

find_git_repo "c-ares/c-ares" "1" "T"
if build "c-ares" "$repo_version"; then
    download "https://github.com/c-ares/c-ares/archive/refs/tags/v$repo_version.tar.gz" "c-ares-$repo_version.tar.gz"
    execute autoreconf -fi
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                           -DCARES_{BUILD_CONTAINER_TESTS,BUILD_TESTS,SHARED,SYMBOL_HIDING}=OFF \
                           -DCARES_{BUILD_TOOLS,STATIC,STATIC_PIC,THREADS}=ON -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "c-ares" "$repo_version"
fi

git_caller "https://github.com/lv2/lv2.git" "lv2-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    case "$STATIC_VER" in
        11) lv2_switch=enabled ;;
        *)  lv2_switch=disabled ;;
    esac

    venv_packages=("lxml" "Markdown" "Pygments" "rdflib")
    setup_python_venv_and_install_packages "$workspace/python_virtual_environment/lv2-git" "${venv_packages[@]}"

    # Set PYTHONPATH to include the virtual environment's site-packages directory
    PYTHONPATH="$workspace/python_virtual_environment/lv2-git/lib/python$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')/site-packages"
    export PYTHONPATH

    PATH="$ccache_dir:$workspace/python_virtual_environment/lv2-git/bin:$PATH"
    remove_duplicate_paths

    # Assuming the build process continues here with Meson and Ninja
    execute meson setup build --prefix="$workspace" --buildtype=release --default-library=static --strip \
                              -D{docs,tests}=disabled -Donline_docs=false -Dplugins="$lv2_switch"
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
else
    # Set PYTHONPATH to include the virtual environment's site-packages directory
    PYTHONPATH="$workspace/python_virtual_environment/lv2-git/lib/python$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')/site-packages"
    export PYTHONPATH
    PATH="$ccache_dir:$workspace/python_virtual_environment/lv2-git/bin:$PATH"
    remove_duplicate_paths
fi

find_git_repo "7131569" "3" "T"
repo_version="${repo_version//waf-/}"
if build "waflib" "$repo_version"; then
    download "https://gitlab.com/ita1024/waf/-/archive/waf-$repo_version/waf-waf-$repo_version.tar.bz2" "waflib-$repo_version.tar.bz2"
    build_done "waflib" "$repo_version"
fi

find_git_repo "5048975" "3" "T"
if build "serd" "$repo_version"; then
    download "https://gitlab.com/drobilla/serd/-/archive/v$repo_version/serd-v$repo_version.tar.bz2" "serd-$repo_version.tar.bz2"
    extracmds=("-D"{docs,html,man,man_html,singlehtml,tests,tools}"=disabled")
    execute meson setup build --prefix="$workspace" --buildtype=release --default-library=static --strip -Dstatic=true "${extracmds[@]}"
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "serd" "$repo_version"
fi

find_git_repo "pcre2project/pcre2" "1" "T"
repo_version="${repo_version//2-/}"
if build "pcre2" "$repo_version"; then
    download "https://github.com/PCRE2Project/pcre2/archive/refs/tags/pcre2-$repo_version.tar.gz" "pcre2-$repo_version.tar.gz"
    execute autoupdate
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --enable-{jit,valgrind} \
                        --disable-shared
    execute make "-j$threads"
    execute make install
    build_done "pcre2" "$repo_version"
fi

find_git_repo "14889806" "3" "B"
if build "zix" "0.4.2"; then
    download "https://gitlab.com/drobilla/zix/-/archive/v0.4.2/zix-v0.4.2.tar.bz2" "zix-0.4.2.tar.bz2"
    extracmds=("-D"{benchmarks,docs,singlehtml,tests,tests_cpp}"=disabled")
    execute meson setup build --prefix="$workspace" --buildtype=release --default-library=static --strip "${extracmds[@]}"
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "zix" "0.4.2"
fi

find_git_repo "11853362" "3" "B"
if build "sord" "$repo_short_version_1"; then
    CFLAGS+=" -I$workspace/include/serd-0"
    download "https://gitlab.com/drobilla/sord/-/archive/$repo_version_1/sord-$repo_version_1.tar.bz2" "sord-$repo_short_version_1.tar.bz2"
    extracmds=("-D"{docs,tests,tools}"=disabled")
    execute meson setup build --prefix="$workspace" --buildtype=release --default-library=static --strip "${extracmds[@]}"
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "sord" "$repo_short_version_1"
fi

find_git_repo "11853194" "3" "T"
if build "sratom" "$repo_version"; then
    download "https://gitlab.com/lv2/sratom/-/archive/v$repo_version/sratom-v$repo_version.tar.bz2" "sratom-$repo_version.tar.bz2"
    extracmds=("-D"{docs,html,singlehtml,tests}"=disabled")
    execute meson setup build --prefix="$workspace" --buildtype=release --default-library=static --strip "${extracmds[@]}"
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "sratom" "$repo_version"
fi

find_git_repo "11853176" "3" "T"
if build "lilv" "$repo_version"; then
    download "https://gitlab.com/lv2/lilv/-/archive/v$repo_version/lilv-v$repo_version.tar.bz2" "lilv-$repo_version.tar.bz2"
    extracmds=("-D"{docs,html,singlehtml,tests,tools}"=disabled")
    execute meson setup build --prefix="$workspace" --buildtype=release --default-library=static --strip "${extracmds[@]}"
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "lilv" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-lv2")

git_caller "https://github.com/gypified/libmpg123.git" "libmpg123-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute rm -fr aclocal.m4
    execute aclocal --force -I m4
    execute autoconf -f -W all,no-obsolete
    execute autoheader -f -W all
    execute automake -a -c -f -W all,no-portability
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-static
    execute make "-j$threads"
    execute make install
    build_done "$repo_name" "$version"
fi

find_git_repo "akheron/jansson" "1" "T"
if build "jansson" "$repo_version"; then
    download "https://github.com/akheron/jansson/archive/refs/tags/v$repo_version.tar.gz" "jansson-$repo_version.tar.gz"
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$threads"
    execute make install
    build_done "jansson" "$repo_version"
fi

find_git_repo "jemalloc/jemalloc" "1" "T"
if build "jemalloc" "$repo_version"; then
    download "https://github.com/jemalloc/jemalloc/archive/refs/tags/$repo_version.tar.gz" "jemalloc-$repo_version.tar.gz"
    execute autoupdate
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-{debug,doc,fill,log,shared,prof,stats} --enable-{autogen,static,xmalloc}
    execute make "-j$threads"
    execute make install
    build_done "jemalloc" "$repo_version"
fi

git_caller "https://github.com/jacklicn/cunit.git" "cunit-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$threads"
    execute make install
    build_done "$repo_name" "$version"
fi

#
# Install the Audio Tools
#

echo
box_out_banner_audio() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner_audio "Installing Audio Tools"

find_git_repo "chirlu/soxr" "1" "T"
if build "libsoxr" "$repo_version"; then
    download "https://github.com/chirlu/soxr/archive/refs/tags/$repo_version.tar.gz" "libsoxr-$repo_version.tar.gz"
    mkdir build; cd build || exit 1
    execute cmake -S ../ -Wno-dev -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_TESTS=ON
    execute make "-j$threads"
    execute make test
    execute make install
    build_done "libsoxr" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libsoxr")

git_caller "https://github.com/libsdl-org/SDL.git" "sdl2-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF -DSDL_ALSA_SHARED=OFF -DSDL_{CCACHE,DISABLE_INSTALL_DOCS}=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi

find_git_repo "libsndfile/libsndfile" "1" "T"
if build "libsndfile" "$repo_version"; then
    download "https://github.com/libsndfile/libsndfile/releases/download/$repo_version/libsndfile-$repo_version.tar.xz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-static --with-pic
    execute make "-j$threads"
    execute make install
    build_done "libsndfile" "$repo_version"
fi

find_git_repo "xiph/ogg" "1" "T"
if build "libogg" "$repo_version"; then
    download "https://github.com/xiph/ogg/archive/refs/tags/v$repo_version.tar.gz" "libogg-$repo_version.tar.gz"
    execute autoreconf -fi
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=ON -DCPACK_{BINARY_DEB,SOURCE_ZIP}=OFF \
                  -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "libogg" "$repo_version"
fi

if "$NONFREE_AND_GPL"; then
    find_git_repo "mstorsjo/fdk-aac" "1" "T"
    if build "libfdk-aac" "$repo_version"; then
        download "https://github.com/mstorsjo/fdk-aac/archive/refs/tags/v$repo_version.tar.gz" "libfdk-aac-$repo_version.tar.gz"
        execute autoupdate
        execute ./autogen.sh
        execute ./configure --prefix="$workspace" --disable-shared
        execute make "-j$threads"
        execute make install
        build_done "libfdk-aac" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-libfdk-aac")
fi

find_git_repo "xiph/vorbis" "1" "T"
if build "vorbis" "$repo_version"; then
    download "https://github.com/xiph/vorbis/archive/refs/tags/v$repo_version.tar.gz" "vorbis-$repo_version.tar.gz"
    execute ./autogen.sh
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF -DOGG_INCLUDE_DIR="$workspace/include" \
                  -DOGG_LIBRARY="$workspace/lib/libogg.so" -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "vorbis" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libvorbis")

find_git_repo "xiph/opus" "1" "T"
if build "opus" "$repo_version"; then
    download "https://github.com/xiph/opus/archive/refs/tags/v$repo_version.tar.gz" "opus-$repo_version.tar.gz"
    execute autoreconf -fis
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF -DCPACK_SOURCE_ZIP=OFF -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "opus" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libopus")

find_git_repo "hoene/libmysofa" "1" "T"
if build "libmysofa" "$repo_version"; then
    download "https://github.com/hoene/libmysofa/archive/refs/tags/v$repo_version.tar.gz" "libmysofa-$repo_version.tar.gz"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "libmysofa" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libmysofa")

find_git_repo "webmproject/libvpx" "1" "T"
if build "libvpx" "$repo_version"; then
    download "https://github.com/webmproject/libvpx/archive/refs/tags/v$repo_version.tar.gz" "libvpx-$repo_version.tar.gz"
    execute sed -i 's/#include "\.\/vpx_tpl\.h"/#include ".\/vpx\/vpx_tpl.h"/' "vpx/vpx_ext_ratectrl.h"
    execute ./configure --prefix="$workspace" --as=yasm --disable-{examples,shared,unit-tests} \
                        --enable-{better-hw-compatibility,libyuv,multi-res-encoding} \
                        --enable-{postproc,small,vp8,vp9,vp9-highbitdepth,vp9-postproc,webm-io}
    execute make "-j$threads"
    execute make install
    build_done "libvpx" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libvpx")

find_git_repo "8143" "6"
repo_version="${repo_version//debian\//}"
if build "opencore-amr" "$repo_version"; then
    download "https://salsa.debian.org/multimedia-team/opencore-amr/-/archive/debian/$repo_version/opencore-amr-debian-$repo_version.tar.bz2" "opencore-amr-$repo_version.tar.bz2"
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j${threads}"
    execute make install
    build_done "opencore-amr" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libopencore-"{amrnb,amrwb})

if build "liblame" "3.100"; then
    download "https://master.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz?viasf=1" "liblame-3.100.tar.gz"
    execute ./configure --prefix="$workspace" --disable-{gtktest,shared} \
                        --enable-nasm --with-libiconv-prefix=/usr
    execute make "-j$threads"
    execute make install
    build_done "liblame" "3.100"
fi
CONFIGURE_OPTIONS+=("--enable-libmp3lame")

# find_git_repo "xiph/theora" "1" "T"
if build "libtheora" "1.1.1"; then
    download "https://github.com/xiph/theora/archive/refs/tags/v1.1.1.tar.gz" "libtheora-1.1.1.tar.gz"
    execute autoupdate
    execute ./autogen.sh
    sed "s/-fforce-addr//g" "configure" > "configure.patched"
    chmod +x "configure.patched"
    execute mv "configure.patched" "configure"
    execute rm "config.guess"
    execute curl -LSso "config.guess" "https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess"
    chmod +x "config.guess"
    execute ./configure --prefix="$workspace" --disable-{examples,oggtest,sdltest,shared,vorbistest} \
                        --enable-static --with-ogg-includes="$workspace/include" --with-ogg-libraries="$workspace/lib" \
                        --with-ogg="$workspace" --with-sdl-prefix="$workspace" --with-vorbis-includes="$workspace/include" \
                        --with-vorbis-libraries="$workspace/lib" --with-vorbis="$workspace"
    execute make "-j$threads"
    execute make install
    build_done "libtheora" "1.1.1"
fi
CONFIGURE_OPTIONS+=("--enable-libtheora")

#
# Install the Video Tools
#

echo
box_out_banner_video() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner_video "Installing Video Tools"

git_caller "https://aomedia.googlesource.com/aom" "av1-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
                  -DCONFIG_AV1_{DECODER,ENCODER,HIGHBITDEPTH,TEMPORAL_DENOISING}=1 \
                  -DCONFIG_DENOISE=1 -DCONFIG_DISABLE_FULL_PIXEL_SPLIT_8X8=1 \
                  -DENABLE_CCACHE=1 -DENABLE_{EXAMPLES,TESTS}=0 -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi
CONFIGURE_OPTIONS+=("--enable-libaom")

# Rav1e fails to build on Ubuntu Bionic and Debian 11 Bullseye
if [[ "$STATIC_VER" != "11" ]]; then
    find_git_repo "xiph/rav1e" "1" "T" "enabled"
    if build "rav1e" "$repo_version"; then
        install_rustc
        source "$HOME/.cargo/bin"
        [[ -f /usr/bin/rustc ]] && rm -f /usr/bin/rustc
        check_and_install_cargo_c
        download "https://github.com/xiph/rav1e/archive/refs/tags/$repo_version.tar.gz" "rav1e-$repo_version.tar.gz"
        rm -fr "$HOME/.cargo/registry/index/"* "$HOME/.cargo/.package-cache"
        execute cargo cinstall --prefix="$workspace" --library-type=staticlib --crt-static --release
        build_done "rav1e" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-librav1e")
fi

git_caller "https://github.com/sekrit-twc/zimg.git" "zimg-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url" "zimg-git"
    execute autoupdate
    execute ./autogen.sh
    execute git submodule update --init --recursive
    execute ./configure --prefix="$workspace" --with-pic
    execute make "-j$threads"
    execute make install
    build_done "$repo_name" "$version"
fi
CONFIGURE_OPTIONS+=("--enable-libzimg")

find_git_repo "AOMediaCodec/libavif" "1" "T"
if build "avif" "$repo_version"; then
    download "https://github.com/AOMediaCodec/libavif/archive/refs/tags/v$repo_version.tar.gz" "avif-$repo_version.tar.gz"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF -DAVIF_CODEC_AOM=ON -DAVIF_CODEC_AOM_{DECODE,ENCODE}=ON \
                  -DAVIF_ENABLE_{GTEST,WERROR}=OFF -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "avif" "$repo_version"
fi

find_git_repo "ultravideo/kvazaar" "1" "T"
if build "kvazaar" "$repo_version"; then
    download "https://github.com/ultravideo/kvazaar/releases/download/v$repo_version/kvazaar-$repo_version.tar.xz"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                           -DBUILD_SHARED_LIBS=OFF -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "kvazaar" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libkvazaar")

find_git_repo "76" "2" "T"
if build "libdvdread" "$repo_version"; then
    download "https://code.videolan.org/videolan/libdvdread/-/archive/$repo_version/libdvdread-$repo_version.tar.bz2"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-{apidoc,shared}
    execute make "-j$threads"
    execute make install
    build_done "libdvdread" "$repo_version"
fi

find_git_repo "363" "2" "T"
if build "udfread" "$repo_version"; then
    download "https://code.videolan.org/videolan/libudfread/-/archive/$repo_version/libudfread-$repo_version.tar.bz2"
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$threads"
    execute make install
    build_done "udfread" "$repo_version"
fi

set_ant_path
git_caller "https://github.com/apache/ant.git" "ant-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute chmod 777 -R "$workspace/ant"
    execute sh build.sh install-lite
    build_done "$repo_name" "$version"
fi
PATH="$PATH:$workspace/ant/bin"
remove_duplicate_paths

# Ubuntu Jammy and Noble both give an error so instead we will use the APT version
if [[ ! "$STATIC_VER" == "22.04" ]] && [[ ! "$STATIC_VER" == "24.04" ]]; then
    find_git_repo "206" "2" "T"
    if build "libbluray" "$repo_version"; then
        download "https://code.videolan.org/videolan/libbluray/-/archive/$repo_version/$repo_version.tar.gz" "libbluray-$repo_version.tar.gz"
        extracmds=("--disable-"{doxygen-doc,doxygen-dot,doxygen-html,doxygen-pdf,doxygen-ps,examples,extra-warnings,shared})
        execute autoupdate
        execute autoreconf -fi
        execute ./configure --prefix="$workspace" "${extracmds[@]}" --without-libxml2 --with-pic
        execute make "-j$threads"
        execute make install
        build_done "libbluray" "$repo_version"
    fi
fi
CONFIGURE_OPTIONS+=("--enable-libbluray")

find_git_repo "mediaarea/zenLib" "1" "T"
if build "zenlib" "$repo_version"; then
    download "https://github.com/MediaArea/ZenLib/archive/refs/tags/v$repo_version.tar.gz" "zenlib-$repo_version.tar.gz"
    cd Project/GNU/Library || exit 1
    execute autoupdate
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$threads"
    execute make install
    build_done "zenlib" "$repo_version"
fi

find_git_repo "MediaArea/MediaInfoLib" "1" "T"
if build "mediainfo-lib" "$repo_version"; then
    download "https://github.com/MediaArea/MediaInfoLib/archive/refs/tags/v$repo_version.tar.gz" "mediainfo-lib-$repo_version.tar.gz"
    cd "Project/GNU/Library" || exit 1
    execute autoupdate
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$threads"
    execute make install
    build_done "mediainfo-lib" "$repo_version"
fi

find_git_repo "MediaArea/MediaInfo" "1" "T"
if build "mediainfo-cli" "$repo_version"; then
    download "https://github.com/MediaArea/MediaInfo/archive/refs/tags/v$repo_version.tar.gz" "mediainfo-cli-$repo_version.tar.gz"
    cd "Project/GNU/CLI" || exit 1
    execute autoupdate
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-staticlibs --disable-shared
    execute make "-j$threads"
    execute make install
    execute cp -f "$packages/mediainfo-cli-$repo_version/Project/GNU/CLI/mediainfo" "/usr/local/bin/"
    build_done "mediainfo-cli" "$repo_version"
fi

if "$NONFREE_AND_GPL"; then
    find_git_repo "georgmartius/vid.stab" "1" "T"
    if build "vid-stab" "$repo_version"; then
        download "https://github.com/georgmartius/vid.stab/archive/refs/tags/v$repo_version.tar.gz" "vid-stab-$repo_version.tar.gz"
        execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF -DUSE_OMP=ON -G Ninja -Wno-dev
        execute ninja "-j$threads" -C build
        execute ninja -C build install
        build_done "vid-stab" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-libvidstab")
fi

if "$NONFREE_AND_GPL"; then
    find_git_repo "dyne/frei0r" "1" "T"
    if build "frei0r" "$repo_version"; then
        download "https://github.com/dyne/frei0r/archive/refs/tags/v$repo_version.tar.gz" "frei0r-$repo_version.tar.gz"
        execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF -DWITHOUT_OPENCV=OFF -G Ninja -Wno-dev
        execute ninja "-j$threads" -C build
        execute ninja -C build install
        build_done "frei0r" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-frei0r")
fi

git_caller "https://github.com/gpac/gpac.git" "gpac-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute ./configure --prefix="$workspace" --static-{bin,modules} --use-{a52,faad,freetype,mad}=local --sdl-cfg="$workspace/include/SDL3"
    execute make "-j$threads"
    execute make install
    execute cp -f bin/gcc/MP4Box /usr/local/bin
    build_done "$repo_name" "$version"
fi

find_git_repo "24327400" "3" "T"
if build "svt-av1" "$repo_version"; then
    download "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$repo_version/SVT-AV1-v$repo_version.tar.bz2" "svt-av1-$repo_version.tar.bz2"
    execute cmake -S . -B Build/linux -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DBUILD_{DEC,ENC}=ON -DBUILD_TESTING=OFF \
                  -DENABLE_AVX512="$(check_avx512)" -DNATIVE=ON -G Ninja -Wno-dev
    execute ninja "-j$threads" -C Build/linux
    execute ninja "-j$threads" -C Build/linux install
    [[ -f "Build/linux/SvtAv1Enc.pc" ]] && cp -f "Build/linux/SvtAv1Enc.pc" "$workspace/lib/pkgconfig"
    [[ -f "$workspace/lib/pkgconfig" ]] && cp -f "Build/linux/SvtAv1Dec.pc" "$workspace/lib/pkgconfig"
    build_done "svt-av1" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libsvtav1")

if "$NONFREE_AND_GPL"; then
    find_git_repo "536" "2" "B"
    if build "x264" "$repo_short_version_1"; then
        download "https://code.videolan.org/videolan/x264/-/archive/$repo_version_1/x264-$repo_version_1.tar.bz2" "x264-$repo_short_version_1.tar.bz2"
        execute ./configure --prefix="$workspace" --bit-depth=all --chroma-format=all --enable-debug --enable-gprof \
                            --enable-lto --enable-pic --enable-static --enable-strip --extra-cflags="-O2 -pipe -fPIC -march=native"
        execute make "-j$threads"
        execute make install-lib-static install
        build_done "x264" "$repo_short_version_1"
    fi
    CONFIGURE_OPTIONS+=("--enable-libx264")
fi

if "$NONFREE_AND_GPL"; then
    if build "x265" "3.6"; then
        download "https://bitbucket.org/multicoreware/x265_git/downloads/x265_3.6.tar.gz" "x265-3.6.tar.gz"
        fix_libstd_libs
        cd build/linux || exit 1
        rm -fr {8,10,12}bit 2>/dev/null
        mkdir -p {8,10,12}bit
        cd 12bit || exit 1
        echo "$ making 12bit binaries"
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release -DENABLE_{CLI,LIBVMAF,SHARED}=OFF \
                      -DEXPORT_C_API=OFF -DHIGH_BIT_DEPTH=ON -DMAIN12=ON -DNATIVE_BUILD=ON -G Ninja -Wno-dev
        execute ninja "-j$threads"
        echo "$ making 10bit binaries"
        cd ../10bit || exit 1
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release -DENABLE_{CLI,LIBVMAF,SHARED}=OFF \
                      -DENABLE_HDR10_PLUS=ON -DEXPORT_C_API=OFF -DHIGH_BIT_DEPTH=ON -DNATIVE_BUILD=ON -DNUMA_ROOT_DIR=/usr -G Ninja -Wno-dev
        execute ninja "-j$threads"
        echo "$ making 8bit binaries"
        cd ../8bit || exit 1
        ln -sf "../10bit/libx265.a" "libx265_main10.a"
        ln -sf "../12bit/libx265.a" "libx265_main12.a"
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                      -DENABLE_LIBVMAF=OFF -DENABLE_{PIC,SHARED}=ON -DEXTRA_LIB="x265_main10.a;x265_main12.a" \
                      -DEXTRA_LINK_FLAGS="-L." -DHIGH_BIT_DEPTH=ON -DLINKED_{10BIT,12BIT}=ON -DNATIVE_BUILD=ON \
                      -DNUMA_ROOT_DIR=/usr -G Ninja -Wno-dev
        execute ninja "-j$threads"

        mv "libx265.a" "libx265_main.a"

        execute ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF

        execute ninja install

        [[ -n "$LDEXEFLAGS" ]] && sed -i.backup "s/lgcc_s/lgcc_eh/g" "$workspace/lib/pkgconfig/x265.pc"

        fix_x265_libs # Fix the x265 shared library issue

        build_done "x265" "3.6"
    fi
    CONFIGURE_OPTIONS+=("--enable-libx265")
fi

if "$NONFREE_AND_GPL"; then
    if [[ -n "$iscuda" ]]; then
        if build "nv-codec-headers" "12.1.14.0"; then
            download "https://github.com/FFmpeg/nv-codec-headers/releases/download/n12.1.14.0/nv-codec-headers-12.1.14.0.tar.gz"
            execute make "-j$threads"
            execute make PREFIX="$workspace" install
            build_done "nv-codec-headers" "12.1.14.0"
        fi

        CONFIGURE_OPTIONS+=("--enable-"{cuda-nvcc,cuda-llvm,cuvid,nvdec,nvenc,ffnvcodec})

        if [[ -n "$LDEXEFLAGS" ]]; then
            CONFIGURE_OPTIONS+=("--enable-libnpp")
        fi

        PATH+=":$cuda_path"
        remove_duplicate_paths

        # Get the Nvidia GPU architecture to build CUDA
        # https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards
        nvidia_architecture
        CONFIGURE_OPTIONS+=("--nvccflags=-gencode arch=$nvidia_arch_type")
    fi

    # Vaapi doesn't work well with static links FFmpeg.
    if [[ -z "$LDEXEFLAGS" ]]; then
        # If the libva development SDK is installed, enable vaapi.
        if library_exists "libva"; then
            if build "vaapi" "1"; then
                build_done "vaapi" "1"
            fi
            CONFIGURE_OPTIONS+=("--enable-vaapi")
        fi
    fi

    find_git_repo "GPUOpen-LibrariesAndSDKs/AMF" "1" "T"
    if build "amf" "$repo_version"; then
        download "https://github.com/GPUOpen-LibrariesAndSDKs/AMF/archive/refs/tags/v$repo_version.tar.gz" "amf-$repo_version.tar.gz"
        execute rm -fr "$workspace/include/AMF"
        execute mkdir -p "$workspace/include/AMF"
        execute cp -fr "$packages/amf-$repo_version/amf/public/include/"* "$workspace/include/AMF/"
        build_done "amf" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-amf")
fi

if "$NONFREE_AND_GPL"; then
    find_git_repo "Haivision/srt" "1" "T"
    if build "srt" "$repo_version"; then
        download "https://github.com/Haivision/srt/archive/refs/tags/v$repo_version.tar.gz" "srt-$repo_version.tar.gz"
        export OPENSSL_ROOT_DIR="$workspace"
        export OPENSSL_LIB_DIR="$workspace/lib"
        export OPENSSL_INCLUDE_DIR="$workspace/include"
        execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF -DENABLE_{APPS,SHARED}=OFF -DENABLE_STATIC=ON \
                      -DUSE_STATIC_LIBSTDCXX=ON -G Ninja -Wno-dev
        execute ninja -C build "-j$threads"
        execute ninja -C build "-j$threads" install
        if [[ -n "$LDEXEFLAGS" ]]; then
            sed -i.backup "s/-lgcc_s/-lgcc_eh/g" "$workspace/lib/pkgconfig/srt.pc"
        fi
        build_done "srt" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-libsrt")
fi

if "$NONFREE_AND_GPL"; then
    find_git_repo "avisynth/avisynthplus" "1" "T"
    if build "avisynth" "$repo_version"; then
        download "https://github.com/AviSynth/AviSynthPlus/archive/refs/tags/v$repo_version.tar.gz" "avisynth-$repo_version.tar.gz"
        execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF -DHEADERS_ONLY=OFF -Wno-dev
        execute make "-j$threads" -C build VersionGen install
        build_done "avisynth" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-avisynth")
fi

# find_git_repo "vapoursynth/vapoursynth" "1" "T"
if build "vapoursynth" "R68"; then
    download "https://github.com/vapoursynth/vapoursynth/archive/refs/tags/R68.tar.gz" "vapoursynth-R68.tar.gz"

    venv_packages=("Cython==0.29.36")
    setup_python_venv_and_install_packages "$workspace/python_virtual_environment/vapoursynth" "${venv_packages[@]}"

    # Activate the virtual environment for the build process
    source "$workspace/python_virtual_environment/vapoursynth/bin/activate" || fail "Failed to re-activate virtual environment"

    # Explicitly set the PYTHON environment variable to the virtual environment's Python
    export PYTHON="$workspace/python_virtual_environment/vapoursynth/bin/python"

    PATH="$ccache_dir:$workspace/python_virtual_environment/vapoursynth/bin:$PATH"
    remove_duplicate_paths

    # Assuming autogen, configure, make, and install steps for VapourSynth
    execute autoupdate
    execute ./autogen.sh || fail "Failed to execute autogen.sh"
    execute ./configure --prefix="$workspace" --disable-shared || fail "Failed to configure"
    execute make -j"$threads" || fail "Failed to make"
    execute make install || fail "Failed to make install"

    # Deactivate the virtual environment after the build
    deactivate

    build_done "vapoursynth" "R68"
else
    # Explicitly set the PYTHON environment variable to the virtual environment's Python
    PYTHON="$workspace/python_virtual_environment/vapoursynth/bin/python"
    export PYTHON
    PATH="$ccache_dir:$workspace/python_virtual_environment/vapoursynth/bin:$PATH"
    remove_duplicate_paths
fi
CONFIGURE_OPTIONS+=("--enable-vapoursynth")

git_caller "https://chromium.googlesource.com/codecs/libgav1" "libgav1-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute git clone -q -b "20220623.1" --depth 1 "https://github.com/abseil/abseil-cpp.git" "third_party/abseil-cpp"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DABSL_{ENABLE_INSTALL,PROPAGATE_CXX_STD}=ON -DBUILD_SHARED_LIBS=OFF \
                  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_INSTALL_SBINDIR=sbin \
                  -DLIBGAV1_ENABLE_TESTS=OFF -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi
git_caller "https://chromium.googlesource.com/codecs/libgav1" "libgav1-git"

if "$NONFREE_AND_GPL"; then
    find_git_repo "8268" "6"
    repo_version="${repo_version//debian\/2%/}"
    if build "xvidcore" "$repo_version"; then
        download "https://salsa.debian.org/multimedia-team/xvidcore/-/archive/debian/2%25$repo_version/xvidcore-debian-2%25$repo_version.tar.bz2" "xvidcore-$repo_version.tar.bz2"
        cd "build/generic" || exit 1
        execute ./bootstrap.sh
        execute ./configure --prefix="$workspace"
        execute make "-j$threads"
        [[ -f "$workspace/lib/libxvidcore.so" ]] && rm "$workspace/lib/libxvidcore.so" "$workspace/lib/libxvidcore.so.4"
        execute make install
        build_done "xvidcore" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-libxvid")
fi

# Image libraries
echo
box_out_banner_images() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner_images "Installing Image Tools"

find_git_repo "strukturag/libheif" "1" "T"
if build "libheif" "$repo_version"; then
    download "https://github.com/strukturag/libheif/archive/refs/tags/v$repo_version.tar.gz" "libheif-$repo_version.tar.gz"
    source_compiler_flags
    CFLAGS="-O2 -pipe -fno-lto -fPIC -march=native"
    CXXFLAGS="-O2 -pipe -fno-lto -fPIC -march=native"
    export CFLAGS CXXFLAGS
    libde265_libs=$(find /usr/ -type f -name 'libde265.s*')
    if [[ -f "$libde265_libs" ]] && [[ ! -e "/usr/lib/x86_64-linux-gnu/libde265.so" ]]; then
        ln -sf "$libde265_libs" "/usr/lib/x86_64-linux-gnu/libde265.so"
        chmod 755 "/usr/lib/x86_64-linux-gnu/libde265.so"
    fi

    case "$STATIC_VER" in
        20.04) pixbuf_switch=OFF ;;
        *)     pixbuf_switch=ON ;;
    esac

    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DAOM_INCLUDE_DIR="$workspace/include" -DAOM_LIBRARY="$workspace/lib/libaom.a" \
                  -DBUILD_SHARED_LIBS=OFF -DLIBDE265_INCLUDE_DIR="$workspace/include" \
                  -DLIBDE265_LIBRARY="/usr/lib/x86_64-linux-gnu/libde265.so" \
                  -DLIBSHARPYUV_INCLUDE_DIR="$workspace/include/webp" -DLIBSHARPYUV_LIBRARY="$workspace/lib/libsharpyuv.so" \
                  -DWITH_AOM_{DECODER,ENCODER}=ON -DWITH_{DAV1D,EXAMPLES,REDUCED_VISIBILITY,SvtEnc,SvtEnc_PLUGIN,X265}=OFF \
                  -DWITH_GDK_PIXBUF="$pixbuf_switch" -DWITH_{LIBDE265,LIBSHARPYUV}=ON -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    source_compiler_flags
    build_done "libheif" "$repo_version"
fi

find_git_repo "uclouvain/openjpeg" "1" "T"
if build "openjpeg" "$repo_version"; then
    download "https://codeload.github.com/uclouvain/openjpeg/tar.gz/refs/tags/v$repo_version" "openjpeg-$repo_version.tar.gz"
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_{SHARED_LIBS,TESTING}=OFF -DBUILD_THIRDPARTY=ON -G Ninja -Wno-dev
    execute ninja "-j$threads" -C build
    execute ninja -C build install
    build_done "openjpeg" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libopenjpeg")

#
# Build FFmpeg
#

echo
box_out_banner_ffmpeg() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner_ffmpeg "Building FFmpeg"

# Get DXVA2 and other essential Windows header files
if [[ "$STATIC_OS" == "WSL2" ]]; then
    install_windows_hardware_acceleration
fi

# Run the 'ffmpeg -version' command and capture its output
if ffmpeg_version_output=$(ffmpeg -version 2>/dev/null); then
    # Extract the version number using grep and awk
    ffmpeg_version=$(echo "$ffmpeg_version_output" | grep -oP 'ffmpeg version \K\d+\.\d+')

    # Format the version number with the desired prefix
    ffmpeg_version_formatted="n$ffmpeg_version"

    echo
    log_update "The installed FFmpeg version is: $ffmpeg_version_formatted"
    log_update "The latest FFmpeg release version available: $ffmpeg_version_formatted"
else
    echo
    log_update "Failed to retrieve an installed FFmpeg version"
    log_update "The latest FFmpeg release version available is: Unknown"
fi

source_compiler_flags
CFLAGS="$CFLAGS -I$workspace/include/serd-0 -DCL_TARGET_OPENCL_VERSION=300 -DX265_DEPTH=12 -DENABLE_LIBVMAF=0"
LDFLAGS="$LDFLAGS"
if [[ -n "$iscuda" ]]; then
    CFLAGS+=" -I/usr/local/cuda/include"
    LDFLAGS+=" -L/usr/local/cuda/lib64"
fi

find_git_repo "FFmpeg/FFmpeg" "1" "T"
case "$VER" in
    11|12) repo_version="6.1.1" ;;
esac
if build "ffmpeg" "n${repo_version}"; then
    download "https://ffmpeg.org/releases/ffmpeg-$repo_version.tar.xz" "ffmpeg-n${repo_version}.tar.xz"
    mkdir build; cd build || exit 1
    ../configure --prefix="/usr/local" --arch="$(uname -m)" --cc="$CC" --cxx="$CXX" \
                 --disable-{debug,shared} "${CONFIGURE_OPTIONS[@]}" \
                 --enable-{chromaprint,ladspa,libbs2b,libcaca,libgme} \
                 --enable-{libmodplug,libshine,libsnappy,libspeex,libssh} \
                 --enable-{libtesseract,libtwolame,libv4l2,libvo-amrwbenc} \
                 --enable-{libzimg,libzvbi,lto,opengl,pic,pthreads,rpath} \
                 --enable-{small,static,version3,libgsm,libjack,libvpl} \
                 --extra-{cflags,cxxflags}="$CFLAGS" --extra-libs="$EXTRALIBS" \
                 --extra-ldflags="$LDFLAGS" --pkg-config-flags="--static" \
                 --extra-ldexeflags="$LDEXEFLAGS" --pkg-config="$workspace/bin/pkg-config" \
                 --pkgconfigdir="$PKG_CONFIG_PATH" --strip="$(type -P strip)"
    execute make "-j$threads"
    execute make install
    build_done "ffmpeg" "n${repo_version}"
fi

# Execute the ldconfig command to ensure that all library changes are detected by ffmpeg
ldconfig

# Display the version of each of the programs
show_versions

# Prompt the user to clean up the build files
cleanup

# Show exit message
exit_fn
