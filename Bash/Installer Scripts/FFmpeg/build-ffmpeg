#!/usr/bin/env bash
# shellcheck disable=SC2068,SC2162,SC2317 source=/dev/null

##  GitHub: https://github.com/slyfox1186/ffmpeg-build-script
##  Script version: 3.5.2
##  Updated: 03.10.24
##  Purpose: build ffmpeg from source code with addon development libraries
##           also compiled from source to help ensure the latest functionality
##  Supported Distros: Arch Linux
##                     Debian 11|12
##                     Ubuntu (20|22|23).04 & 23.10
##  Supported architecture: x86_64
##  CUDA SDK Toolkit: Updated to version 12.4.0

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

# Define global variables
SCRIPT_NAME="${0}"
SCRIPT_VERSION=3.5.2
CWD="$PWD/ffmpeg-build-script"
packages="$CWD/packages"
workspace="$CWD/workspace"
NONFREE_AND_GPL=false
LDEXEFLAGS=""
CONFIGURE_OPTIONS=()
LATEST=false
GIT_REGEX='(rc|RC|Rc|rC|alpha|beta)+[0-9]*$' # Set the regex variable to exclude release candidates
DEBUG=OFF

# Pre-defined color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Print script banner
echo
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf "-"; done)
    tput bold
    line=$(tput setaf 3)$line
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner "FFmpeg Build Script - v$SCRIPT_VERSION"

# Create output directories
mkdir -p "$packages" "$workspace"

# Set the CC/CPP compilers + customized compiler optimization flags
source_compiler_flags() {
    CFLAGS="-g -O3 -march=native"
    CXXFLAGS="-g -O3 -march=native"
    LDFLAGS="-L$workspace/lib64 -L$workspace/lib"
    CPPFLAGS="-I$workspace/include"
    EXTRALIBS="-ldl -lpthread -lm -lz"
    export CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
}
source_compiler_flags

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
    exit 1
}

cleanup() {
    local choice

    echo
    read -p "Do you want to clean up the build files? (yes/no): " choice

    case "$choice" in
        [yY]*|[yY][eE][sS]*)
            rm -fr "$CWD"
            ;;
        [nN]*|[nN][oO]*)
            ;;
        *)
            unset choice
            cleanup
            ;;
    esac
}

display_ffmpeg_versions() {
    echo
    local versions=("ffmpeg" "ffprobe" "ffplay")
    for version in ${versions[@]}; do
        if command -v "$version" >/dev/null 2>&1; then
            "$version" -version
            echo
        fi
    done
}

prompt_ffmpeg_versions() {
    local choice

    echo
    read -p "Do you want to print the installed FFmpeg & FFprobe versions? (yes/no): " choice

    case "$choice" in
        yes|y) display_ffmpeg_versions ;;
        no|n)  ;;
    esac
}

# Function to ensure no cargo or rustc processes are running
ensure_no_cargo_or_rustc_processes() {
    local running_processes=$(pgrep -fl 'cargo|rustc')
    if [ -n "$running_processes" ]; then
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
        cargo clean
        find "$HOME/.cargo/registry/index" -type f -name ".cargo-lock" -delete

        if ! cargo install cargo-c; then
            fail "Failed to execute: cargo install cargo-c."
        fi
        log_update "cargo-c installation completed."
    else
        log "cargo-c is already installed."
    fi
}

install_windows_hardware_acceleration() {
    curl -fsSLo "$workspace/include/dxva2api.h" "https://download.videolan.org/pub/contrib/dxva2api.h"
    curl -fsSLo "$workspace/include/objbase.h" "https://raw.githubusercontent.com/wine-mirror/wine/master/include/objbase.h"
    cp -f "$workspace/include/objbase.h" "$workspace/include/dxva2api.h" "/usr/include"
}

install_rustc() {
    get_rustc_ver=$(rustc --version |
                    grep -Eo '[0-9 \.]+' |
                    head -n1)
    if [[ ! "$get_rustc_ver" == "1.76.0" ]]; then
        echo "Installing RustUp"
        curl -fsS --proto '=https' --tlsv1.2 https://sh.rustup.rs | sh -s -- --default-toolchain stable -y &>/dev/null
        source "$HOME/.cargo/env"
        if ! source "$HOME/.zshrc"; then
            source "$HOME/.bashrc"
        fi
    fi
}

check_ffmpeg_version() {
    local ffmpeg_repo="$1"

    ffmpeg_git_version=$(git ls-remote --tags "$ffmpeg_repo" |
                         awk -F'/' '/n[0-9]+(\.[0-9]+)*(-dev)?$/ {print $3}' |
                         grep -Ev '\-dev' |
                         sort -rV |
                         head -n1)
    echo "$ffmpeg_git_version"
}

download() {
    download_path="$packages"
    download_url="$1"
    download_file="${2:-"${1##*/}"}"

    if [[ "$download_file" =~ tar. ]]; then
        output_directory="${download_file%.*}"
        output_directory="${3:-"${output_directory%.*}"}"
    else
        output_directory="${3:-"${download_file%.*}"}"
    fi

    target_file="$download_path/$download_file"
    target_directory="$download_path/$output_directory"

    if [[ -f "$target_file" ]]; then
        echo "$download_file is already downloaded."
    else
        echo "Downloading \"$download_url\" saving as \"$download_file\""
        if ! curl -fsSLo "$target_file" "$download_url"; then
            echo
            warn "Failed to download \"$download_file\". Second attempt in 10 seconds..."
            echo
            sleep 10
            if ! curl -fsSLo "$target_file" "$download_url"; then
                fail "Failed to download \"$download_file\". Exiting... Line: $LINENO"
            fi
        fi
        echo "Download Completed"
    fi

    rm -fr "$target_directory" 2>/dev/null
    mkdir -p "$target_directory"

    if [[ -n "$3" ]]; then
        if ! tar -xf "$target_file" -C "$target_directory" 2>/dev/null; then
           rm "$target_file"
           fail "Failed to extract the tarball \"$download_file\" and was deleted. Re-run the script to try again. Line: $LINENO"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_directory" --strip-components 1 2>/dev/null; then
            rm "$target_file"
            fail "Failed to extract the tarball \"$download_file\" and was deleted. Re-run the script to try again. Line: $LINENO"
        fi
    fi

    printf "%s\n\n" "File extracted: $download_file"

    cd "$target_directory" || fail "Failed to cd into \"$target_directory\". Line: $LINENO"
}

git_caller() {
    git_url="$1"
    repo_name="$2"
    third_flag="$3"
    recurse_flag=""

if [[ "$3" == "recurse" ]]; then
    recurse_flag=1
fi

version=$(git_clone "$git_url" "$repo_name" "$third_flag")
version="${version//Cloning completed: /}"
}

git_clone() {
    local repo_url="$1"
    local repo_name="${2:-"${1##*/}"}"
    local repo_name="${repo_name//\./-}"
    local repo_flag="$3"
    local target_directory="$packages/$repo_name"
    local version

    # Try to get the latest tag
    if [[ "$repo_flag" == "ant" ]]; then
        version=$(git ls-remote --tags "https://github.com/apache/ant.git" |
                  awk -F'/' '/\/v?[0-9]+\.[0-9]+(\.[0-9]+)?(\^\{\})?$/ {
                      tag = $4;
                      sub(/^v/, "", tag);
                      if (tag !~ /\^\{\}$/) print tag
                  }' |
                  sort -rV |
                  head -n1)
    elif [[ "$repo_flag" == "ffmpeg" ]]; then
        version=$(git ls-remote --tags "https://git.ffmpeg.org/ffmpeg.git" |
                  awk -F/ '/\/n?[0-9]+\.[0-9]+(\.[0-9]+)?(\^\{\})?$/ {
                      tag = $3;
                      sub(/^[v]/, "", tag);
                      print tag
                  }' |
                  grep -v '\^{}' |
                  sort -rV |
                  head -n1)
    else
        version=$(git ls-remote --tags "$repo_url" |
                  awk -F'/' '/\/v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9]+)?(\^\{\})?$/ {
                      tag = $3;
                      sub(/^v/, "", tag);
                      print tag
                  }' |
                  grep -v '\^{}' |
                  sort -rV |
                  head -n1)
        # If no tags found, use the latest commit hash as the version
        if [[ -z "$version" ]]; then
            version=$(git ls-remote "$repo_url" |
                      grep "HEAD" |
                      awk '{print substr($1,1,7)}')
            if [[ -z "$version" ]]; then
                version="unknown"
            fi
        fi
    fi

    [[ -f "$packages/$repo_name.done" ]] && store_prior_version=$(cat "$packages/$repo_name.done")

    if [[ ! "$version" == "$store_prior_version" ]]; then
        if [[ "$recurse_flag" -eq 1 ]]; then
            recurse="--recursive"
        elif [[ -n "$3" ]]; then
            target_directory="$download_path/$3"
        fi
        rm -fr "$target_directory" 2>/dev/null
        # Clone the repository
        if ! git clone --depth 1 $recurse -q "$repo_url" "$target_directory"; then
            echo
            warn "Failed to clone \"$target_directory\". Second attempt in 10 seconds..."
            echo
            sleep 3
            if ! git clone --depth 1 $recurse -q "$repo_url" "$target_directory"; then
                fail "Failed to clone \"$target_directory\". Exiting script. Line: $LINENO"
            fi
        fi
        cd "$target_directory" || fail "Failed to cd into \"$target_directory\". Line: $LINENO"
    fi

    echo "Cloning completed: $version"
    return 0
}

# Parse each git repoitory to find the latest release version number for each program
gnu_repo() {
    local url="$1"
    version=$(curl -fsS "$url" |
              grep -oP '[a-z]+-\K(([0-9\.]*[0-9]+)){2,}' |
              sort -rV |
              head -n1)
}

github_repo() {
    local repo="$1"
    local url="$2"
    local url_flag="$3"
    repo_version=""

    local count=1
    local max_attempts=10

    if [[ -z "$repo" || -z "$url" ]]; then
        echo -e "${RED}[ERROR]${NC} Git repository and URL are required."
        return 1
    fi

    [[ -n "$url_flag" ]] && url_flag=1

    while [ $count -le $max_attempts ]; do
        if [[ "$url_flag" -eq 1 ]]; then
            curl_cmd=$(curl -fsSL "https://github.com/xiph/rav1e/tags" |
                       grep -Eo 'href="[^"]*v?[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz"' |
                       head -n1)
        else
            curl_cmd=$(curl -fsSL "https://github.com/$repo/$url" | grep -o 'href="[^"]*\.tar\.gz"')
        fi

        # Extract the specific line
        line=$(echo "$curl_cmd" | grep -o 'href="[^"]*\.tar\.gz"' | sed -n "${count}p")

        # Check if the line matches the pattern (version without 'RC'/'rc')
        if echo "$line" | grep -qP '[v]*(\d+[\._]\d+(?:[\._]\d*){0,2})\.tar\.gz'; then
            # Extract and print the version number
            repo_version=$(echo "$line" | grep -oP '(\d+[\._]\d+(?:[\._]\d+){0,2})')
            break
        else
            # Increment the count if no match is found
            ((count++))
        fi
    done

    # Deny installing a release candidate
    while [[ $repo_version =~ $GIT_REGEX ]]; do
        curl_cmd=$(curl -fsSL "https://github.com/$repo/$url" | grep -o 'href="[^"]*\.tar\.gz"')

        # Extract the specific line
        line=$(echo "$curl_cmd" | grep -o 'href="[^"]*\.tar\.gz"' | sed -n "${count}p")

        # Check if the line matches the pattern (version without 'RC'/'rc')
        if echo "$line" | grep -qP '[v]*(\d+[\._]\d+(?:[\._]\d*){0,2})\.tar\.gz'; then
            # Extract and print the version number
            repo_version=$(echo "$line" | grep -oP '(\d+[\._]\d+(?:[\._]\d+){0,2})')
            break
        else
            # Increment the count if no match is found
            ((count++))
        fi
    done
}

fetch_repo_version() {
    local base_url="$1"
    local project="$2"
    local api_path="$3"
    local version_jq_filter="$4"
    local short_id_jq_filter="$5"
    local commit_id_jq_filter="$6"
    local count=0

    local api_url="$base_url/$project/$api_path" # Adjust per_page as needed to fetch more tags if necessary

    if ! response=$(curl -fsS "$api_url"); then
        fail "Failed to fetch data from $api_url in the function \"fetch_repo_version\". Line: $LINENO"
    fi

    local version=""
    local short_id=""
    local commit_id=""
    local version=$(echo "$response" | jq -r ".[$count]$version_jq_filter")

    if [[ ! "$base_url" == 536 ]]; then
        # Loop through responses to exclude Release candidates and find the first valid version
        while [[ $version =~ $GIT_REGEX ]]; do
            version=$(echo "$response" | jq -r ".[$count]$version_jq_filter")
            if [[ -z "$version" || "$version" == "null" ]]; then
                fail "No suitable version found in the function \"fetch_repo_version\". Line: $LINENO"
            fi
            ((count++))
        done
    fi

    local short_id=$(echo "$response" | jq -r ".[$count]$short_id_jq_filter")
    local commit_id=$(echo "$response" | jq -r ".[$count]$commit_id_jq_filter")

    # Remove leading 'v' from version
    repo_version="${version#v}"
    repo_version_1="$commit_id"
    repo_short_version_1="$short_id"

    return 0
}

find_git_repo() {
    local url="$1"
    local git_repo="$2"
    local url_action="$3"

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

    "$set_repo" "$url" "$set_type" 2>/dev/null
}

execute() {
        echo "$ $*"

        if [[ "$DEBUG" == "ON" ]]; then
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
        elif $LATEST; then
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
    if ! [[ -x $(pkg-config --exists --print-errors "$1" 2>/dev/null >/dev/null) ]]; then
        return 1
    fi
    return 0
}

# Function to setup a python virtual environment and install packages with pip
setup_python_venv_and_install_packages() {
    local parse_path="$1"
    shift
    local parse_package=("$@")

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
    if [[ -f /opt/cuda/version.json ]]; then
        locate_cuda_json_file=/opt/cuda/version.json
    elif [[ -f /usr/local/cuda/version.json ]]; then
        locate_cuda_json_file=/usr/local/cuda/version.json
    fi

    echo "$locate_cuda_json_file"
}

# PRINT THE SCRIPT OPTIONS
usage() {
    echo
    echo "Usage: $SCRIPT_NAME [options]"
    echo
    echo "Options:"
    echo "    -h, --help                       Display usage information"
    echo "    -v, --version                    Display the current script version"
    echo "    -c, --cleanup                    Remove all working dirs"
    echo "    -b, --build                      Starts the build process"
    echo "    -n, --enable-gpl-and-non-free    Enable GPL and non-free codecs - https://ffmpeg.org/legal.html"
    echo "    -l, --latest                     Force the script to build the latest version of dependencies if newer version is available"
    echo "    --compiler=gcc|clang             Set the default CC and CXX compiler (default: gcc)"
    echo "    -j, --jobs <num>                 Set the number of CPU threads for parallel processing"
    echo
    echo "Example: bash $SCRIPT_NAME --build --compiler=clang -j 8"
    echo
}

CONFIGURE_OPTIONS=()
NONFREE_AND_GPL=false
LATEST=false
compiler_flag=""

while (("$#" > 0)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -v|--version) echo; log "The script version is: $SCRIPT_VERSION"; exit 0 ;;
        -n|--enable-gpl-and-non-free)
            CONFIGURE_OPTIONS+=("--enable-"{gpl,libsmbclient,libcdio,nonfree})
            NONFREE_AND_GPL=true
            ;;
        -b|--build) bflag="-b" ;;
        -c|--cleanup) cflag="-c"; cleanup ;;
        -l|--latest) LATEST=true ;;
        --compiler=gcc|--compiler=clang)
            compiler_flag="${1#*=}"
            shift
            ;;
        -j|--jobs)
            cpu_threads="$2"
            shift 2
            ;;
        *) usage; exit 1 ;;
    esac
    shift
done

if [[ -z "$cpu_threads" ]]; then
    # Set the available CPU thread and core count for parallel processing (speeds up the build process)
    if [[ -f /proc/cpuinfo ]]; then
        cpu_threads=$(grep --count ^processor /proc/cpuinfo)
    else
        cpu_threads=$(nproc --all)
    fi
fi
MAKEFLAGS="-j$cpu_threads"
export MAKEFLAGS

if [[ -z "$compiler_flag" || "$compiler_flag" == "gcc" ]]; then
    CC="gcc"
    CXX="g++"
elif [[ "$compiler_flag" == "clang" ]]; then
    CC="clang"
    CXX="clang++"
else
    fail "Invalid compiler specified. Valid options are 'gcc' or 'clang'."
fi
export CC CXX

if [[ -z "$bflag" ]]; then
    if [[ -z "$cflag" ]]; then
        usage
        echo
        exit 1
    fi
    exit 0
fi

echo
log "Utilizing $cpu_threads CPU threads"

if $NONFREE_AND_GPL; then
    warn "With GPL and non-free codecs enabled"
    echo
fi

if [[ -n "$LDEXEFLAGS" ]]; then
    printf "%s\n\n" "The script has been configured to run in full static mode."
fi

# Set the path variable
if find /usr/local/ -maxdepth 1 -name cuda >/dev/null | head -n1; then
    cuda_bin_path=$(find /usr/local/ -maxdepth 1 -name "cuda" >/dev/null | head -n1)
    cuda_bin_path+=/bin
elif find /opt/ -maxdepth 1 -name cuda 2>/dev/null | head -n1; then
    cuda_bin_path=$(find /opt/ -maxdepth 1 -name "cuda" 2>/dev/null | head -n1)
    cuda_bin_path+=/bin
fi

if [[ -d /usr/lib/ccache/bin ]]; then
    set_ccache_dir=/usr/lib/ccache/bin
else
    set_ccache_dir=/usr/lib/ccache
fi

source_path() {
    PATH="$set_ccache_dir:$cuda_bin_path:$workspace/bin:$HOME/.local/bin:/usr/local/ant/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    export PATH
}
source_path

# Set the pkg_config_path variable
PKG_CONFIG_PATH="\
$workspace/lib64/pkgconfig:\
$workspace/lib/x86_64-linux-gnu/pkgconfig:\
$workspace/lib/pkgconfig:\
$workspace/share/pkgconfig:\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig:\
/lib64/pkgconfig:\
/lib/x86_64-linux-gnu/pkgconfig:\
/lib/pkgconfig\
"
export PKG_CONFIG_PATH

check_amd_gpu() {
    if lshw -C display 2>&1 | grep -qEio "AMD|amdgpu"; then
        echo "AMD GPU detected"
    elif dpkg -l 2>&1 | grep -qi "amdgpu"; then
        echo "AMD GPU detected"
    elif lspci 2>&1 | grep -i "AMD"; then
        echo "AMD GPU detected"
    else
        echo "No AMD GPU detected"
    fi
}

check_remote_cuda_version() {
    local url="https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html"

    # Use curl to fetch the HTML content of the page
    local content=$(curl -fsS "$url")

    # Parse the version directly from the fetched content
    local cuda_regex='CUDA\ ([0-9]+\.[0-9]+)(\ Update\ ([0-9]+))?'
    if [[ $content =~ $cuda_regex ]]; then
        local base_version=${BASH_REMATCH[1]}
        local update_version=${BASH_REMATCH[3]}
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
    locate_java=$(find /usr/lib/jvm/ -type d -name 'java-*-openjdk*' |
                  sort -rV |
                  head -n1)
    java_include=$(find /usr/lib/jvm/ -type f -name 'javac' |
                   sort -rV |
                   head -n1 |
                   xargs dirname |
                   sed 's/bin/include/')
    CPPFLAGS+=" -I$java_include"
    export CPPFLAGS
    export JDK_HOME="$locate_java"
    export JAVA_HOME="$locate_java"
    export PATH="$PATH:$JAVA_HOME/bin"
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
            *) fail "Failed to set the variable \"nvidia_arch_type\". Line: $LINENO" ;;
        esac
    else
        return 1
    fi
}

cuda_download() {
    local choice distro installer_path pin_file pkg_ext version
    local cuda_version_number="$remote_cuda_version"
    local cuda_pin_url="https://developer.download.nvidia.com/compute/cuda/repos"
    local cuda_url="https://developer.download.nvidia.com/compute/cuda/$cuda_version_number"

    echo "Pick your Linux version from the list below:"
    echo "Supported architecture: x86_64"
    echo
    options=(
        "Debian 10"
        "Debian 11"
        "Debian 12"
        "Ubuntu 20.04"
        "Ubuntu 22.04"
        "Ubuntu WSL"
        "Arch Linux"
        "Exit"
    )
    select choice in "${options[@]}"; do
        case "$choice" in
            "Debian 10")
                distro="debian10"
                version="10-12-4"
                pkg_ext="deb"
                installer_path="local_installers/cuda-repo-debian${version}-local_${cuda_version_number}-550.54.14-1_amd64.deb"
                ;;
            "Debian 11")
                distro="debian11"
                version="11-12-4"
                pkg_ext="deb"
                installer_path="local_installers/cuda-repo-debian${version}-local_${cuda_version_number}-550.54.14-1_amd64.deb"
                ;;
            "Debian 12")
                distro="debian12"
                version="12-12-4"
                pkg_ext="deb"
                installer_path="local_installers/cuda-repo-debian${version}-local_${cuda_version_number}-550.54.14-1_amd64.deb"
                ;;
            "Ubuntu 20.04")
                distro="ubuntu2004"
                version="12-4"
                pkg_ext="pin"
                pin_file="$distro/x86_64/cuda-ubuntu2004.pin"
                installer_path="local_installers/cuda-repo-${distro}-${version}-local_${cuda_version_number}-550.54.14-1_amd64.deb"
                ;;
            "Ubuntu 22.04")
                distro="ubuntu2204"
                version="12-4"
                pkg_ext="pin"
                pin_file="$distro/x86_64/cuda-ubuntu2204.pin"
                installer_path="local_installers/cuda-repo-${distro}-${version}-local_${cuda_version_number}-550.54.14-1_amd64.deb"
                ;;
            "Ubuntu WSL")
                distro="wsl-ubuntu"
                version="12-4"
                pkg_ext="pin"
                pin_file="$distro/x86_64/cuda-wsl-ubuntu.pin"
                installer_path="local_installers/cuda-repo-${distro}-${version}-local_${cuda_version_number}-1_amd64.deb"
                ;;
            "Arch Linux")
                git clone -q "https://gitlab.archlinux.org/archlinux/packaging/packages/cuda.git" || fail "Failed to clone Arch Linux CUDA repository"
                cd cuda || fail "Unable to cd into the Arch Linux cuda directory"
                makepkg -sif -C --needed --noconfirm || fail "The command makepkg failed to execute"
                return
                ;;
            "Exit")
                return
                ;;
            *)
                echo "Invalid choice. Please try again."
                continue
                ;;
        esac
        break
    done

    echo "Downloading the CUDA SDK Toolkit - version $cuda_version_number"

    mkdir -p "$packages/nvidia-cuda"

    if [[ "$distro" == debian* ]]; then
        distro="${distro//[0-9][0-9]}"
    fi

    if [[ "$pkg_ext" == "deb" ]]; then
        package_name="$packages/nvidia-cuda/cuda-$distro-$cuda_version_number.$pkg_ext"
        wget --show-progress -cqO "$package_name" "$cuda_url/$installer_path"
        dpkg -i "$package_name"
        cp -f /var/cuda-repo-${distro}${version}-local/cuda-*-keyring.gpg "/usr/share/keyrings/"
        [[ "$distro" == "debian"* ]] && add-apt-repository -y contrib
    elif [[ "$pkg_ext" == "pin" ]]; then
        wget --show-progress -cqO "/etc/apt/preferences.d/cuda-repository-pin-600" "$cuda_pin_url/$pin_file"
        package_name="$packages/nvidia-cuda/cuda-$distro-$cuda_version_number.deb"
        wget --show-progress -cqO "$package_name" "$cuda_url/$installer_path"
        dpkg -i "$package_name"
        cp -f /var/cuda-repo-${distro}-12-4-local/cuda-*-keyring.gpg "/usr/share/keyrings/"
    fi

    apt-get update
    apt-get install cuda-toolkit-12-4
}

# Function to detect the environment and check for an NVIDIA GPU
check_nvidia_gpu() {
    # Check for NVIDIA GPU in native Linux
    if ! grep -qi microsoft /proc/version; then
        if lspci | grep -i nvidia >/dev/null; then
            is_nvidia_gpu_present="NVIDIA GPU detected"
        else
            is_nvidia_gpu_present="NVIDIA GPU not detected"
        fi
    else
        # WSL environment: Define base directories
        local c_drive_paths=("/mnt/c" "/c")
        local path_exists=0
        local found=0
        local gpu_info=""

        for dir in "${c_drive_paths[@]}"; do
            if [[ -d "$dir/Windows/System32" ]]; then
                path_exists=1
                if [[ -f "$dir/Windows/System32/cmd.exe" ]]; then
                    # Attempt to suppress unnecessary messages by redirecting stderr to null
                    gpu_info=$("$dir/Windows/System32/cmd.exe" /d /c "wmic path win32_VideoController get name | findstr /i nvidia" 2>/dev/null)

                    if [[ -n "$gpu_info" ]]; then
                        found=1
                        is_nvidia_gpu_present="NVIDIA GPU detected"
                        break
                    fi
                fi
            fi
        done

        if [[ $path_exists -eq 0 ]]; then
            is_nvidia_gpu_present="C drive paths '/mnt/c/' and '/c/' do not exist."
        elif [[ $found -eq 0 ]]; then
            is_nvidia_gpu_present="NVIDIA GPU not detected"
        fi
    fi
}

get_local_cuda_version() {
    if [[ -f /usr/local/cuda/version.json ]]; then
        echo "$(cat /usr/local/cuda/version.json | jq -r '.cuda.version')"
    fi
}

# Required Geforce CUDA development packages
install_cuda() {
    local choice

    log "Checking GPU Status"
    echo "========================================================"
    amd_gpu_test=$(check_amd_gpu)
    check_nvidia_gpu

    if [[ -n "$amd_gpu_test" && "$is_nvidia_gpu_present" == "NVIDIA GPU not detected" ]]; then
        return 0
    fi

    if [[ "$is_nvidia_gpu_present" == "NVIDIA GPU detected" ]]; then
        log "Nvidia GPU detected"
        log "Determining if CUDA is installed..."
        check_remote_cuda_version
        local_cuda_version=$(get_local_cuda_version)

        if [[ -z "$local_cuda_version" ]]; then
            echo
            echo "The latest CUDA version available is: $remote_cuda_version"
            echo "CUDA is not currently installed."
            echo
            read -p "Do you want to install the latest CUDA version? (y/n): " choice
            case "$choice" in
                y|Y) cuda_download ;;
                *) return 0 ;;
            esac
        elif [[ "$local_cuda_version" == "$remote_cuda_version" ]]; then
            log "CUDA is already installed and up to date."
            return 0
        else
            echo
            echo "The installed CUDA version is: $local_cuda_version"
            echo "The latest CUDA version available is: $remote_cuda_version"
            echo
            read -p "Do you want to update/reinstall CUDA to the latest version? (y/n): " choice
            case "$choice" in
                y|Y) cuda_download ;;
                *) return 0 ;;
            esac
        fi

        [[ "$OS" == "Arch" ]] && cuda_path=$(find /opt/cuda* -type f -name nvcc)

        export PATH="$PATH:$cuda_path"
    else
        gpu_flag=1
    fi

    return 0
}

# Required build packages
apt_pkgs() {
    local pkg available_packages unavailable_packages
    local openjdk_pkg libcpp_pkg libcppabi_pkg libunwind_pkg

    # Function to find the latest version of a package by pattern
    find_latest_pkg_version() {
        apt-cache search --names-only "$1" 2>/dev/null | awk '{print $1}' | grep -Eo "$2" | sort -rV | head -n1
    }

    # Use the function to find the latest versions of specific packages
    nvidia_utils=$(find_latest_pkg_version 'nvidia-utils-[0-9]+$' 'nvidia-utils-[0-9]+$')
    openjdk_pkg=$(find_latest_pkg_version '^openjdk-[0-9]+-jdk$' '^openjdk-[0-9]+-jdk')
    libcpp_pkg=$(find_latest_pkg_version 'libc++*' 'libc\+\+-[0-9\-]+-dev')
    libcppabi_pkg=$(find_latest_pkg_version 'libc++abi*' 'libc\+\+abi-[0-9]+-dev')
    libunwind_pkg=$(find_latest_pkg_version 'libunwind*' 'libunwind-[0-9]+-dev')
    gcc_plugin_pkg=$(find_latest_pkg_version 'gcc-1*-plugin-dev'  'gcc-1[0-9]+-plugin-dev')

    # Define an array of apt package names
    pkgs=(
        $1 $libcppabi_pkg $libcpp_pkg $libunwind_pkg $nvidia_utils $openjdk_pkg $gcc_plugin_pkg ant apt asciidoc autoconf
        autoconf-archive automake autopoint binutils bison build-essential cargo cargo-c ccache checkinstall clang cmake
        curl doxygen fcitx-libs-dev flex flite1-dev freeglut3-dev frei0r-plugins-dev gawk gcc gettext gimp-data git
        gnome-desktop-testing gnustep-gui-runtime google-perftools gperf gtk-doc-tools guile-3.0-dev help2man jq junit
        ladspa-sdk lib32stdc++6 libamd2 libasound2-dev libass-dev libaudio-dev libavfilter-dev libbabl-0.1-0 libbluray-dev
        libbpf-dev libbs2b-dev libbz2-dev libc6 libc6-dev libcaca-dev libcairo2-dev libcamd2 libccolamd2 libcdio-dev
        libcdio-paranoia-dev libcdparanoia-dev libcholmod3 libchromaprint-dev libcjson-dev libcodec2-dev libcolamd2
        libcrypto++-dev libcurl4-openssl-dev libdav1d-dev libdbus-1-dev libde265-dev libdevil-dev libdmalloc-dev
        libdrm-dev libdvbpsi-dev libebml-dev libegl1-mesa-dev libffi-dev libgbm-dev libgdbm-dev libgegl-0.4-0
        libgegl-common libgimp2.0 libgl1-mesa-dev libgles2-mesa-dev libglib2.0-dev libgme-dev libgmock-dev
        libgnutls28-dev libgnutls30 libgoogle-perftools-dev libgoogle-perftools4 libgsm1-dev libgtest-dev libgvc6
        libibus-1.0-dev libiconv-hook-dev libintl-perl libjack-dev libjemalloc-dev libjxl-dev libladspa-ocaml-dev
        libldap2-dev libleptonica-dev liblilv-dev liblz-dev liblzma-dev liblzo2-dev libmathic-dev libmatroska-dev
        libmbedtls-dev libmetis5 libmfx-dev libmodplug-dev libmp3lame-dev libmusicbrainz5-dev libmysofa-dev libnuma-dev
        libopencore-amrnb-dev libopencore-amrwb-dev libopencv-dev libopenmpt-dev libopus-dev libpango1.0-dev
        libperl-dev libplacebo-dev libpocketsphinx-dev libpsl-dev libpstoedit-dev libpulse-dev librabbitmq-dev
        libraqm-dev libraw-dev librsvg2-dev librtmp-dev librubberband-dev librust-gstreamer-base-sys-dev libserd-dev
        libshine-dev libsmbclient-dev libsnappy-dev libsndfile1-dev libsndio-dev libsord-dev libsoxr-dev libspeex-dev
        libsphinxbase-dev libsqlite3-dev libsratom-dev libssh-dev libssl-dev libsuitesparseconfig5 libsystemd-dev
        libtalloc-dev libtheora-dev libticonv-dev libtool libtool-bin libtwolame-dev libudev-dev libumfpack5 libv4l-dev
        libva-dev libvdpau-dev libvidstab-dev libvlccore-dev libvo-amrwbenc-dev libvpx-dev libx11-dev libxcursor-dev
        libxext-dev libxfixes-dev libxi-dev libxkbcommon-dev libxrandr-dev libxss-dev libxvidcore-dev libzimg-dev
        libzmq3-dev libzstd-dev libzvbi-dev libzzip-dev llvm lsb-release lshw lzma-dev m4 mesa-utils meson nasm
        ninja-build pandoc python3 python3-pip python3-venv ragel re2c scons texi2html texinfo tk-dev unzip valgrind
        wget xmlto zlib1g-dev libclang-16-dev
    )

    [[ "$OS" == "Debian" ]] && pkgs+=("nvidia-smi")

    # Initialize arrays for missing, available, and unavailable packages
    missing_packages=()
    available_packages=()
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
        apt-get update
        apt-get install "${available_packages[@]}"
        echo
    else
        log "No missing packages to install or all missing packages are unavailable."
        echo
    fi
}

fix_libstd_libs() {
    local libstdc_path=$(find /usr/lib/x86_64-linux-gnu/ -type f -name 'libstdc++.so.6.0.*' | sort -rV | head -n1)
    if [[ -f "/usr/lib/x86_64-linux-gnu/libstdc++.so" ]] && [[ -f "$libstdc_path" ]]; then
        echo "$ ln -sf $libstdc_path /usr/lib/x86_64-linux-gnu/libstdc++.so"
        ln -sf "$libstdc_path" "/usr/lib/x86_64-linux-gnu/libstdc++.so"
    fi
}

fix_x265_libs() {
    local x265_libs x265_libs_trim

    x265_libs=$(find "$workspace/lib/" -type f -name 'libx265.so.*')
    x265_libs_trim=$(echo "$x265_libs" | sed "s:.*/::" | head -n1)

    case "$OS" in
        Arch) cp -f "$x265_libs" "/usr/lib"
              ln -sf "/usr/lib/$x265_libs_trim" "/usr/lib/libx265.so"
              ;;
        *)    cp -f "$x265_libs" "/usr/lib/x86_64-linux-gnu"
              ln -sf "/usr/lib/x86_64-linux-gnu/$x265_libs_trim" "/usr/lib/x86_64-linux-gnu/libx265.so"
              ;;
    esac
}

fix_pulse_meson_build_file() {
    local file_path=meson.build

    # Replace the original pa_version_minor and pa_version_micro blocks
    sed -i "/pa_version_major = version_split\[0\].split('v')\[0\]/a \\
if version_split.length() > 1\\n  pa_version_minor = version_split[1]\\nelse\\n  pa_version_minor = '0'\\nendif" "$file_path"

    sed -i "/pa_version_minor = '0'/a \\
\\nif version_split.length() > 2\\n  pa_version_micro = version_split[2]\\nelse\\n  pa_version_micro = '0'\\nendif" "$file_path"

    # Remove the original pa_version_minor and pa_version_micro lines
    sed -i '/pa_version_minor = version_split\[1\]/d' "$file_path"
    sed -i '/pa_version_micro = version_split\[2\]/d' "$file_path"
}

libpulse_fix_libs() {
    local pulse_version="$1"
    local libpulse_lib=$(find "$workspace/lib/" -type f -name "libpulsecommon-*.so" | head -n1)
    local libpulse_trim=$(echo "$libpulse_lib" |
                          sed 's:.*/::' |
                          head -n1)

    if [[ "$OS" == "Arch" ]]; then
        mkdir -p /usr/lib/pulseaudio
    else
        mkdir -p /usr/lib/x86_64-linux-gnu/pulseaudio
    fi

    if [[ -n "$libpulse_lib" ]]; then
        if [[ "$OS" == "Arch" ]]; then
            execute cp -f "$libpulse_lib" "/usr/lib/pulseaudio/libpulsecommon-$pulse_version.so"
            execute ln -sf "/usr/lib/pulseaudio/libpulsecommon-$pulse_version.so" "/usr/lib"
        else
            execute cp -f "$libpulse_lib" "/usr/lib/x86_64-linux-gnu/pulseaudio/libpulsecommon-$pulse_version.so"
            execute ln -sf "/usr/lib/x86_64-linux-gnu/pulseaudio/libpulsecommon-$pulse_version.so" "/usr/lib/x86_64-linux-gnu"
        fi
    fi
}

find_latest_nasm_version() {
    # URL of the NASM stable releases directory
    local url="https://www.nasm.us/pub/nasm/stable/"

    # Fetch the HTML, extract links, sort them, and get the last one
    local latest_version=$(curl -fsS $url |
                           grep -oP 'nasm-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.xz)' |
                           sort -rV |
                           head -n1)

    if [[ -z "$latest_version" ]]; then
        echo "Failed to find the latest NASM version."
        return 1
    fi

    # Print the version and download link without additional messages
    echo "$latest_version"
}

# To use the function and store its result in a variable:
latest_nasm_version=$(find_latest_nasm_version)

get_openssl_version() {
    repo_version=$(curl -fsS "https://www.openssl.org/source/" |
                   grep -oP 'openssl-3.1.[0-9]+.tar.gz' |
                   sort -rV |
                   head -n1 |
                   grep -oP '3.1.[0-9]+')
}

# Patch functions
patch_ffmpeg() {
    execute curl -fsSLo "mathops.patch" "https://raw.githubusercontent.com/slyfox1186/ffmpeg-build-script/main/patches/mathops.patch"
    execute patch -d "libavcodec/x86" -i "../../mathops.patch"
}

# Arch Linux function section
apache_ant() {
    if build "apache-ant" "git"; then
        git_clone "https://aur.archlinux.org/apache-ant-contrib.git" "apache-ant-AUR"
        execute makepkg -sif --cleanbuild --noconfirm --needed
        build_done "apache-ant" "git"
    fi
}

librist_arch() {
    if build "librist" "git"; then
        git_clone "https://aur.archlinux.org/librist.git" "librist-AUR"
        execute makepkg -sif --cleanbuild --noconfirm --needed
        build_done "librist" "git"
    fi
}

arch_os_ver() {
    local arch_pkgs pkg

    arch_pkgs=(av1an bluez-libs clang cmake dav1d devil docbook5-xml
               flite gdb gettext git gperf gperftools jdk17-openjdk
               ladspa jq libde265 libjpeg-turbo libjxl libjpeg6-turbo
               libmusicbrainz5 libnghttp2 libwebp libyuv meson nasm
               ninja numactl opencv pd perl-datetime texlive-basic
               texlive-binextra tk valgrind webp-pixbuf-loader xterm
               yasm)

    # Check for Pacman lock file and if Pacman is running
    if [[ -f /var/lib/pacman/db.lck ]]; then
        echo "Pacman lock file found. Checking if Pacman is running..."
        while pgrep -x pacman >/dev/null; do
            echo "Pacman is currently running. Waiting for it to finish..."
            sleep 3
        done

        if ! pgrep -x pacman >/dev/null; then
            echo "Pacman is not running. Removing stale lock file..."
            rm /var/lib/pacman/db.lck
        fi
    fi

    for pkg in "${arch_pkgs[@]}"; do
        echo "Installing $pkg..."
        pacman -Sq --needed --noconfirm $pkg 2>&1
    done

    # Set the path for the Python virtual environment
    local venv_path="$workspace/python_virtual_environment/arch_os"

    # Python packages to install
    local python_packages=(DateTime Sphinx wheel)

    # Call the function to setup Python venv and install packages
    setup_python_venv_and_install_packages "$venv_path" "${python_packages[@]}"
}

debian_msft() {
    get_os_version
    case "$VER" in
        11) apt_pkgs "${debian_pkgs[@]}" "$debian_wsl_pkgs" ;;
        12) apt_pkgs "${debian_pkgs[@]}" "$debian_wsl_pkgs" ;;
        *)     fail "Failed to parse the Debian MSFT version. Line: $LINENO" ;;
    esac
}

debian_os_version() {
    if [[ "$2" == "yes_wsl" ]]; then
        VER=msft
        debian_wsl_pkgs=$3
    fi

    debian_pkgs=(cppcheck libnvidia-encode1 libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev
                 libyuv-utils libyuv0 libhwy-dev libsrt-gnutls-dev libyuv-dev libsharp-dev
                 libdmalloc5 libumfpack5 libsuitesparseconfig5 libcolamd2 libcholmod3 libccolamd2
                 libcamd2 libamd2 software-properties-common)

    case "$VER" in
        msft)          debian_msft ;;
        12|trixie|sid) apt_pkgs $1 "${debian_pkgs[@]}" "librist-dev" ;;
        11)            apt_pkgs $1 "${debian_pkgs[@]}" ;;
        *)             fail "Could not detect the Debian release version. Line: $LINENO" ;;
    esac
}

ubuntu_msft() {
    case "$VER" in
        23.04) apt_pkgs "${ubuntu_common_pkgs[@]}" "${jammy_pkgs[@]}" "$ubuntu_wsl_pkgs" ;;
        22.04) apt_pkgs "${ubuntu_common_pkgs[@]}" "${jammy_pkgs[@]}" "$ubuntu_wsl_pkgs" ;;
        20.04) apt_pkgs "${ubuntu_common_pkgs[@]}" "${focal_pkgs[@]}" "$ubuntu_wsl_pkgs" ;;
        *)     fail "Failed to parse the Ubutnu MSFT version. Line: $LINENO" ;;
    esac
}

ubuntu_os_version() {
    if [[ "$2" = "yes_wsl" ]]; then
        VER=msft
        ubuntu_wsl_pkgs=$3
    fi

    ubuntu_common_pkgs=(cppcheck libamd2 libcamd2 libccolamd2 libcholmod3
                              libcolamd2 libsuitesparseconfig5 libumfpack5)
    focal_pkgs=(libcunit1 libcunit1-dev libcunit1-doc libdmalloc5 libhwy-dev
                      libreadline-dev librust-jemalloc-sys-dev librust-malloc-buf-dev
                      libsrt-doc libsrt-gnutls-dev libvmmalloc-dev libvmmalloc1
                      libyuv-dev nvidia-utils-535)
    jammy_pkgs=(libacl1-dev libdecor-0-dev liblz4-dev libmimalloc-dev
                      libpipewire-0.3-dev libpsl-dev libreadline-dev
                      librust-jemalloc-sys-dev librust-malloc-buf-dev
                      libsrt-doc libsvtav1-dev libsvtav1dec-dev
                      libsvtav1enc-dev libtbbmalloc2 libwayland-dev)
    lunar_kenetic_pkgs=(libhwy-dev libjxl-dev librist-dev libsrt-gnutls-dev
                              libsvtav1-dev libsvtav1dec-dev libsvtav1enc-dev libyuv-dev)
    mantic_pkgs=(libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev
                       libhwy-dev libsrt-gnutls-dev libyuv-dev)
    case "$VER" in
        msft)        ubuntu_msft ;;
        23.10)       apt_pkgs $1 "${mantic_pkgs[@]}" "${lunar_kenetic_pkgs[@]}" "${jammy_pkgs[@]}" "${focal_pkgs[@]}" ;;
        23.04|22.10) apt_pkgs $1 "${ubuntu_common_pkgs[@]}" "${lunar_kenetic_pkgs[@]}" "${jammy_pkgs[@]}" ;;
        22.04)       apt_pkgs $1 "${ubuntu_common_pkgs[@]}" "${jammy_pkgs[@]}" ;;
        20.04)       apt_pkgs $1 "${ubuntu_common_pkgs[@]}" "${focal_pkgs[@]}" ;;
        *)           fail "Could not detect the Ubuntu release version. Line: $LINENO" ;;
    esac
}

# Test the OS and its version
find_lsb_release=$(find /usr/bin/ -type f -name lsb_release)

get_os_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_TMP="$NAME"
        VER_TMP="$VERSION_ID"
        OS=$(echo "$OS_TMP" | awk '{print $1}')
        VER=$(echo "$VER_TMP" | awk '{print $1}')
    elif [[ -n "$find_lsb_release" ]]; then
        OS=$(lsb_release -d | awk '{print $2}')
        VER=$(lsb_release -r | awk '{print $2}')
    else
        fail "Failed to define \"\$OS\" and/or \"\$VER\". Line: $LINENO"
    fi

    nvidia_utils_version=$(apt list nvidia-utils-* 2>/dev/null |
                           grep -Eo '^nvidia-utils-[0-9]{3}' |
                           sort -rV |
                           uniq |
                           head -n1)

    nvidia_encode_version=$(apt list libnvidia-encode* 2>&1 |
                            grep -Eo 'libnvidia-encode-[0-9]{3}' |
                            sort -rV |
                            head -n1)
}
get_os_version

# Check if running Windows WSL2
get_wsl_version() {
    if [[ $(grep -i "microsoft" /proc/version) ]]; then
        wsl_flag="yes_wsl"
        OS="WSL2"
        wsl_common_pkgs=(cppcheck libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev
                         libyuv-utils libyuv0 libsharp-dev libdmalloc5 libnvidia-encode1
                         nvidia-smi)
    fi
}
get_wsl_version

# Install required APT packages
    echo "Installing the required APT packages"
    echo "========================================================"
    log "Checking installation status of each package..."

case "$OS" in
    WSL2)       get_os_version
                case "$OS" in
                    Debian|n/a) debian_os_version "$nvidia_encode_version $nvidia_utils_version" "$wsl_flag" "${wsl_common_pkgs[@]}" ;;
                    Ubuntu)     ubuntu_os_version "$nvidia_encode_version $nvidia_utils_version" "$wsl_flag" "${wsl_common_pkgs[@]}" ;;
                esac
                ;;
    Arch)       arch_os_ver ;;
    Debian|n/a) debian_os_version "$nvidia_encode_version $nvidia_utils_version" ;;
    Ubuntu)     ubuntu_os_version "$nvidia_encode_version $nvidia_utils_version" ;;
esac

# Set the JAVA variables
set_java_variables

# Check if the cuda folder exists to determine installation status
case "$OS" in
    Arch) iscuda=$(find /opt/cuda* -type f -name nvcc 2>/dev/null)
          cuda_path=$(find /opt/cuda* -type f -name nvcc 2>/dev/null | grep -Eo '^.*/bin?')
          ;;
    *)    iscuda=$(find /usr/local/cuda* -type f -name nvcc 2>/dev/null | sort -rV | head -n1)
          cuda_path=$(find /usr/local/cuda* -type f -name nvcc 2>/dev/null | sort -rV | head -n1 | grep -Eo '^.*/bin?')
          ;;
esac

# Prompt the user to install the geforce cuda sdk-toolkit
install_cuda

# Update the ld linker search paths
ldconfig

# Install the global tools
echo
box_out_banner_global() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf "-"; done)
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

if build "m4" "latest"; then
    download "https://ftp.gnu.org/gnu/m4/m4-latest.tar.xz"
    execute ./configure --prefix="$workspace" \
                        --disable-nls \
                        --enable-c++ \
                        --enable-threads=posix
    execute make "-j$cpu_threads"
    execute make install
    build_done "m4" "latest"
fi

if build "autoconf" "latest"; then
    download "http://ftp.gnu.org/gnu/autoconf/autoconf-latest.tar.xz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" M4="$workspace/bin/m4"
    execute make "-j$cpu_threads"
    execute make install
    build_done "autoconf" "latest"
fi

if [[ "$OS" == "Arch" ]]; then
    if build "libtool" "$version"; then
        pacman -Sq --needed --noconfirm libtool
        build_done "libtool" "$version"
    fi
else
    get_wsl_version
    if [[ "$VER" = "WSL2" ]]; then
        version=2.4.6
    else
        get_os_version
        case "$VER" in
            12|23.10|23.04) gnu_repo "https://ftp.gnu.org/gnu/libtool/" ;;
            *)              version=2.4.6 ;;
        esac
    fi
    if build "libtool" "$version"; then
        download "https://ftp.gnu.org/gnu/libtool/libtool-$version.tar.xz"
        execute ./configure --prefix="$workspace" --with-pic M4="$workspace/bin/m4"
        execute make "-j$cpu_threads"
        execute make install
        build_done "libtool" "$version"
    fi
fi

gnu_repo "https://pkgconfig.freedesktop.org/releases/"
if build "pkg-config" "$version"; then
    download "https://pkgconfig.freedesktop.org/releases/pkg-config-$version.tar.gz"
    execute autoconf
    execute ./configure --prefix="$workspace" --enable-silent-rules --with-pc-path="$PKG_CONFIG_PATH"
    execute make "-j$cpu_threads"
    execute make install
    build_done "pkg-config" "$version"
fi

find_git_repo "mesonbuild/meson" "1" "T"
if build "meson" "$repo_version"; then
    download "https://github.com/mesonbuild/meson/archive/refs/tags/$repo_version.tar.gz" "meson-$repo_version.tar.gz"
    execute python3 setup.py build
    execute python3 setup.py install --prefix="$workspace"
    build_done "meson" "$repo_version"
fi

if [[ "$OS" == "Arch" ]]; then
    librist_arch
else
    find_git_repo "816" "2" "T"
    if build "librist" "$repo_version"; then
        download "https://code.videolan.org/rist/librist/-/archive/v$repo_version/librist-v$repo_version.tar.bz2" "librist-$repo_version.tar.bz2"
        execute meson setup build --prefix="$workspace" \
                                  --buildtype=release \
                                  --default-library=static \
                                  --strip \
                                  -Dbuilt_tools=false \
                                  -Dtest=false
        execute ninja "-j$cpu_threads" -C build
        execute ninja -C build install
        build_done "librist" "$repo_version"
    fi
fi

find_git_repo "madler/zlib" "1" "T"
if build "zlib" "$repo_version"; then
    download "https://github.com/madler/zlib/releases/download/v$repo_version/zlib-$repo_version.tar.gz"
    execute ./configure --prefix="$workspace"
    execute make "-j$cpu_threads"
    execute make install
    build_done "zlib" "$repo_version"
fi


if $NONFREE_AND_GPL; then
    get_openssl_version
    if build "openssl" "$repo_version"; then
        download "https://www.openssl.org/source/openssl-$repo_version.tar.gz"
        execute ./Configure --prefix="$workspace" \
                            enable-egd \
                            enable-fips \
                            enable-md2 \
                            enable-rc5 \
                            enable-trace \
                            threads zlib \
                            --with-rand-seed=os \
                            --with-zlib-include="$workspace/include" \
                            --with-zlib-lib="$workspace/lib"
        execute make "-j$cpu_threads"
        execute make install_sw install_fips
        build_done "openssl" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-openssl")
else
    gnu_repo "https://ftp.gnu.org/gnu/gmp/"
    if build "gmp" "$version"; then
        download "https://ftp.gnu.org/gnu/gmp/gmp-$version.tar.xz"
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make "-j$cpu_threads"
        execute make install
        build_done "gmp" "$version"
    fi
    gnu_repo "https://ftp.gnu.org/gnu/nettle/"
    if build "nettle" "$version"; then
        download "https://ftp.gnu.org/gnu/nettle/nettle-$version.tar.gz"
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-openssl --disable-documentation --libdir="$workspace"/lib CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make "-j$cpu_threads"
        execute make install
        build_done "nettle" "$version"
    fi
    gnu_repo "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/"
    if build "gnutls" "$version"; then
        download "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-$version.tar.xz"
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-doc --disable-tools --disable-cxx --disable-tests --disable-gtk-doc-html --disable-libdane --disable-nls --enable-local-libopts --disable-guile --with-included-libtasn1 --with-included-unistring --without-p11-kit CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make "-j$cpu_threads"
        execute make install
        build_done "gnutls" "$version"
    fi
fi

find_git_repo "yasm/yasm" "1" "T"
if build "yasm" "$repo_version"; then
    download "https://github.com/yasm/yasm/archive/refs/tags/v$repo_version.tar.gz" "yasm-$repo_version.tar.gz"
    execute autoreconf -fi
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "yasm" "$repo_version"
fi

if build "nasm" "$latest_nasm_version"; then
    find_latest_nasm_version
    download "https://www.nasm.us/pub/nasm/stable/nasm-$latest_nasm_version.tar.xz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-pedantic --enable-ccache
    execute make "-j$cpu_threads"
    execute make install
    build_done "nasm" "$latest_nasm_version"
fi

if build "giflib" "5.2.1"; then
    download "https://cfhcable.dl.sourceforge.net/project/giflib/giflib-5.2.1.tar.gz"
    # Parellel building not available for this library
    execute make
    execute make PREFIX="$workspace" install
    build_done "giflib" "5.2.1"
fi

# UBUNTU BIONIC FAILS TO BUILD XML2
if [[ "$VER" != "18.04" ]]; then
    find_git_repo "1665" "5" "T"
    if build "libxml2" "$repo_version"; then
        download "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$repo_version/libxml2-v$repo_version.tar.bz2" "libxml2-$repo_version.tar.bz2"
        CFLAGS+=" -DNOLIBTOOL"
        execute ./autogen.sh
        execute cmake -B build \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF \
                      -G Ninja
        execute ninja "-j$cpu_threads" -C build
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
    execute make "-j$cpu_threads"
    execute make install-header-links install-library-links install
    build_done "libpng" "$repo_version"
fi

find_git_repo "4720790" "3" "T"
if build "libtiff" "$repo_version"; then
    download "https://gitlab.com/libtiff/libtiff/-/archive/v$repo_version/libtiff-v$repo_version.tar.bz2" "libtiff-$repo_version.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --disable-docs \
                        --disable-sphinx \
                        --disable-tests \
                        --enable-cxx \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "libtiff" "$repo_version"
fi

if $NONFREE_AND_GPL; then
    find_git_repo "nkoriyama/aribb24" "1" "T"
    if build "aribb24" "$repo_version"; then
        download "https://github.com/nkoriyama/aribb24/archive/refs/tags/v$repo_version.tar.gz" "aribb24-$repo_version.tar.gz"
        execute autoreconf -fi
        execute ./configure --prefix="$workspace" --disable-shared --with-pic
        execute make "-j$cpu_threads"
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
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
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
    execute ./autogen.sh --noconf
    execute autoupdate
    execute ./configure --prefix="$workspace" \
                        "${extracmds[@]}" \
                        --enable-iconv \
                        --enable-static \
                        --with-arch=$(uname -m) \
                        --with-libiconv-prefix=/usr
    execute make "-j$cpu_threads"
    execute make install
    build_done "fontconfig" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libfontconfig")

# UBUNTU BIONIC FAILS TO BUILD XML2
if [[ "$VER" != "18.04" ]]; then
    find_git_repo "harfbuzz/harfbuzz" "1" "T"
    if build "harfbuzz" "$repo_version"; then
        download "https://github.com/harfbuzz/harfbuzz/archive/refs/tags/$repo_version.tar.gz" "harfbuzz-$repo_version.tar.gz"
        extracmds=("-D"{benchmark,cairo,docs,glib,gobject,icu,introspection,tests}"=disabled")
        execute ./autogen.sh
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
        execute ninja "-j$cpu_threads" -C build
        execute ninja -C build install
        build_done "harfbuzz" "$repo_version"
    fi
fi

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
                        -D libpth="/usr/lib64 /usr/lib /lib64 /lib" \
                        -D locincpth="$workspace/include /usr/local/include /usr/include" \
                        -D loclibpth="$workspace/lib64 $workspace/lib /usr/local/lib64 /usr/local/lib" \
                        -D osname="$OS" \
                        -D prefix="$workspace" \
                        -D privlib="$workspace/lib/c2man" \
                        -D privlibexp="$workspace/lib/c2man"
    execute make depend
    execute make "-j$cpu_threads"
    execute make install
    build_done "$repo_name" "$version"
fi

find_git_repo "fribidi/fribidi" "1" "T"
if build "fribidi" "$repo_version"; then
    download "https://github.com/fribidi/fribidi/archive/refs/tags/v$repo_version.tar.gz" "fribidi-$repo_version.tar.gz"
    extracmds=("-D"{docs,tests}"=false")
    execute autoreconf -fi
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "fribidi" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libfribidi")

find_git_repo "libass/libass" "1" "T"
if build "libass" "$repo_version"; then
    download "https://github.com/libass/libass/archive/refs/tags/$repo_version.tar.gz" "libass-$repo_version.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "libass" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libass")

find_git_repo "freeglut/freeglut" "1" "T"
if build "freeglut" "$repo_version"; then
    download "https://github.com/freeglut/freeglut/releases/download/v$repo_version/freeglut-$repo_version.tar.gz"
    CFLAGS+=" -DFREEGLUT_STATIC"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DFREEGLUT_BUILD_SHARED_LIBS=OFF \
                  -DFREEGLUT_BUILD_STATIC_LIBS=ON \
                  -DFREEGLUT_PRINT_ERRORS=OFF \
                  -DFREEGLUT_PRINT_WARNINGS=OFF \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "freeglut" "$repo_version"
fi

git_caller "https://chromium.googlesource.com/webm/libwebp" "libwebp-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute autoreconf -fi
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DZLIB_INCLUDE_DIR="$workspace/include" \
                  -DWEBP_BUILD_ANIM_UTILS=OFF \
                  -DWEBP_BUILD_CWEBP=ON \
                  -DWEBP_BUILD_DWEBP=ON \
                  -DWEBP_BUILD_EXTRAS=OFF \
                  -DWEBP_BUILD_VWEBP=OFF \
                  -DWEBP_ENABLE_SWAP_16BIT_CSP=OFF \
                  -DWEBP_LINK_STATIC=ON \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi
CONFIGURE_OPTIONS+=("--enable-libwebp")

find_git_repo "google/highway" "1" "T"
if build "libhwy" "$repo_version"; then
    download "https://github.com/google/highway/archive/refs/tags/$repo_version.tar.gz" "libhwy-$repo_version.tar.gz"
    CFLAGS+=" -DHWY_COMPILE_ALL_ATTAINABLE"
    CXXFLAGS+=" -DHWY_COMPILE_ALL_ATTAINABLE"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DHWY_ENABLE_TESTS=OFF \
                  -DBUILD_TESTING=OFF \
                  -DHWY_ENABLE_EXAMPLES=OFF \
                  -DHWY_FORCE_STATIC_LIBS=ON \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "libhwy" "$repo_version"
fi

find_git_repo "google/brotli" "1" "T"
if build "brotli" "$repo_version"; then
    download "https://github.com/google/brotli/archive/refs/tags/v$repo_version.tar.gz" "brotli-$repo_version.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DBUILD_TESTING=OFF \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "brotli" "$repo_version"
fi

find_git_repo "mm2/Little-CMS" "1" "T"
if build "lcms2" "$repo_version"; then
    download "https://github.com/mm2/Little-CMS/archive/refs/tags/lcms$repo_version.tar.gz" "lcms2-$repo_version.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --with-pic --with-threaded
    execute make "-j$cpu_threads"
    execute make install
    build_done "lcms2" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-lcms2")

find_git_repo "gflags/gflags" "1" "T"
if build "gflags" "$repo_version"; then
    download "https://github.com/gflags/gflags/archive/refs/tags/v$repo_version.tar.gz" "gflags-$repo_version.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_gflags_LIB=ON \
                  -DBUILD_STATIC_LIBS=ON \
                  -DINSTALL_HEADERS=ON \
                  -DREGISTER_BUILD_DIR=ON \
                  -DREGISTER_INSTALL_PREFIX=ON \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "gflags" "$repo_version"
fi

git_caller "https://github.com/KhronosGroup/OpenCL-SDK.git" "opencl-sdk-git" "recurse"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute cmake \
            -S . \
            -B build \
            -DCMAKE_INSTALL_PREFIX="$workspace" \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_SHARED_LIBS=ON \
            -DBUILD_TESTING=OFF \
            -DBUILD_DOCS=OFF \
            -DBUILD_EXAMPLES=OFF \
            -DOPENCL_SDK_BUILD_SAMPLES=ON \
            -DOPENCL_SDK_TEST_SAMPLES=OFF \
            -DCMAKE_C_FLAGS="$CFLAGS" \
            -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DOPENCL_HEADERS_BUILD_CXX_TESTS=OFF \
            -DOPENCL_ICD_LOADER_BUILD_SHARED_LIBS=ON \
            -DOPENCL_SDK_BUILD_OPENGL_SAMPLES=OFF \
            -DOPENCL_SDK_BUILD_SAMPLES=OFF \
            -DOPENCL_SDK_TEST_SAMPLES=OFF \
            -DTHREADS_PREFER_PTHREAD_FLAG=ON \
            -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi

find_git_repo "DanBloomberg/leptonica" "1" "T"
repo_version="${repo_version//Leptonica version /}"
if build "leptonica" "$repo_version"; then
    download "https://github.com/DanBloomberg/leptonica/archive/refs/tags/$repo_version.tar.gz" "leptonica-$repo_version.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "leptonica" "$repo_version"
fi

find_git_repo "tesseract-ocr/tesseract" "1" "T"
if build "tesseract" "$repo_version"; then
    download "https://github.com/tesseract-ocr/tesseract/archive/refs/tags/$repo_version.tar.gz" "tesseract-$repo_version.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --disable-doc \
                        --with-extra-includes="$workspace/include" \
                        --with-extra-libraries="$workspace/lib" \
                        --with-pic \
                        --without-archive \
                        --without-curl
    execute make "-j$cpu_threads"
    execute make install
    build_done "tesseract" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libtesseract")

git_caller "https://github.com/imageMagick/jpeg-turbo.git" "jpeg-turbo-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute cmake -S . \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DENABLE_SHARED=ON \
                  -DENABLE_STATIC=ON \
                  -G Ninja
    execute ninja "-j$cpu_threads"
    execute ninja "-j$cpu_threads" install
    save_version=build_done "$repo_name" "$version"
    build_done "$repo_name" "$version"
fi

if $NONFREE_AND_GPL; then
    git_caller "https://github.com/m-ab-s/rubberband.git" "rubberband-git"
    if build "$repo_name" "${version//\$ /}"; then
        echo "Cloning \"$repo_name\" saving version \"$version\""
        git_clone "$git_url"
        execute make "-j$cpu_threads" PREFIX="$workspace" install-static
        build_done "$repo_name" "$version"
    fi
    CONFIGURE_OPTIONS+=("--enable-librubberband")
fi

find_git_repo "c-ares/c-ares" "1" "T"
repo_version="${repo_version//c-ares-/}"
g_tag="${repo_version//_/\.}"
if build "c-ares" "$g_tag"; then
    download "https://github.com/c-ares/c-ares/archive/refs/tags/cares-$repo_version.tar.gz" "c-ares-$repo_version.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --disable-debug \
                        --disable-warnings \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "c-ares" "$g_tag"
fi

git_caller "https://github.com/lv2/lv2.git" "lv2-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    case "$VER" in
        10|11) lv2_switch=enabled ;;
        *)     lv2_switch=disabled ;;
    esac

    venv_path="$workspace/python_virtual_environment/lv2-git"
    venv_packages=("lxml" "Markdown" "Pygments" "rdflib")
    setup_python_venv_and_install_packages "$venv_path" "${venv_packages[@]}"

    # Set PYTHONPATH to include the virtual environment's site-packages directory
    PYTHONPATH="$venv_path/lib/python$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')/site-packages"
    export PYTHONPATH

    # Optionally, ensure the virtual environment's Python is the first in PATH
    PATH="$venv_path/bin:$PATH"
    export PATH

    # Assuming the build process continues here with Meson and Ninja
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              -Ddocs=disabled \
                              -Donline_docs=false \
                              -Dplugins="$lv2_switch" \
                              -Dtests=disabled
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
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
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              -Dstatic=true \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "serd" "$repo_version"
fi

find_git_repo "pcre2project/pcre2" "1" "T"
repo_version="${repo_version//2-/}"
target_url="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$tag_urls/pcre2-$tag_urls.tar.gz"
if build "pcre2" "$repo_version"; then
    download "https://github.com/PCRE2Project/pcre2/archive/refs/tags/pcre2-$repo_version.tar.gz" "pcre2-$repo_version.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --enable-jit \
                        --enable-valgrind \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "pcre2" "$repo_version"
fi

find_git_repo "14889806" "3" "B"
if build "zix" "0.4.2"; then
    download "https://gitlab.com/drobilla/zix/-/archive/v0.4.2/zix-v0.4.2.tar.bz2" "zix-0.4.2.tar.bz2"
    extracmds=("-D"{benchmarks,docs,singlehtml,tests,tests_cpp}"=disabled")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "zix" "0.4.2"
fi

find_git_repo "11853362" "3" "B"
if build "sord" "$repo_short_version_1"; then
    CFLAGS+=" -I$workspace/include/serd-0"
    download "https://gitlab.com/drobilla/sord/-/archive/$repo_version_1/sord-$repo_version_1.tar.bz2" "sord-$repo_short_version_1.tar.bz2"
    extracmds=("-D"{docs,tests,tools}"=disabled")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "sord" "$repo_short_version_1"
fi

find_git_repo "11853194" "3" "T"
if build "sratom" "$repo_version"; then
    download "https://gitlab.com/lv2/sratom/-/archive/v$repo_version/sratom-v$repo_version.tar.bz2" "sratom-$repo_version.tar.bz2"
    extracmds=("-D"{docs,html,singlehtml,tests}"=disabled")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "sratom" "$repo_version"
fi

find_git_repo "11853176" "3" "T"
if build "lilv" "$repo_version"; then
    download "https://gitlab.com/lv2/lilv/-/archive/v$repo_version/lilv-v$repo_version.tar.bz2" "lilv-$repo_version.tar.bz2"
    extracmds=("-D"{docs,html,singlehtml,tests,tools}"=disabled")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
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
    execute ./configure --prefix="$workspace" \
                        --enable-static \
                        --with-cpu=x86-64
    execute make "-j$cpu_threads"
    execute make install
    build_done "$repo_name" "$version"
fi

find_git_repo "akheron/jansson" "1" "T"
if build "jansson" "$repo_version"; then
    download "https://github.com/akheron/jansson/archive/refs/tags/v$repo_version.tar.gz" "jansson-$repo_version.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "jansson" "$repo_version"
fi

find_git_repo "jemalloc/jemalloc" "1" "T"
if build "jemalloc" "$repo_version"; then
    download "https://github.com/jemalloc/jemalloc/archive/refs/tags/$repo_version.tar.gz" "jemalloc-$repo_version.tar.gz"
    extracmds1=("--disable-"{debug,doc,fill,log,shared,prof,stats})
    extracmds2=("--enable-"{autogen,static,xmalloc})
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        "${extracmds1[@]}" \
                        "${extracmds2[@]}"
    execute make "-j$cpu_threads"
    execute make install
    build_done "jemalloc" "$repo_version"
fi

git_caller "https://github.com/jacklicn/cunit.git" "cunit-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "$repo_name" "$version"
fi

# Install audio tools
echo
box_out_banner_audio() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf "-"; done)
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

git_caller "https://github.com/libsdl-org/SDL.git" "sdl2-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute cmake -S . -B build \
                       -DCMAKE_INSTALL_PREFIX="$workspace" \
                       -DCMAKE_BUILD_TYPE=Release \
                       -DBUILD_SHARED_LIBS=OFF \
                       -DSDL_ALSA_SHARED=OFF \
                       -DSDL_DISABLE_INSTALL_DOCS=ON \
                       -DSDL_CCACHE=ON \
                       -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi

find_git_repo "libsndfile/libsndfile" "1" "T"
if build "libsndfile" "$repo_version"; then
    download "https://github.com/libsndfile/libsndfile/releases/download/$repo_version/libsndfile-$repo_version.tar.xz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --enable-static \
                        --with-pic \
                        --with-pkgconfigdir="$workspace/lib/pkgconfig"
    execute make "-j$cpu_threads"
    execute make install
    build_done "libsndfile" "$repo_version"
fi

git_caller "https://gitlab.freedesktop.org/pulseaudio/pulseaudio.git" "pulseaudio-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    fix_pulse_meson_build_file
    extracmds=("-D"{daemon,doxygen,ipv6,man,tests}"=false")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                               "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    libpulse_fix_libs "${version//\$ /}"
    build_done "$repo_name" "$version"
fi
CONFIGURE_OPTIONS+=("--enable-libpulse")

find_git_repo "xiph/ogg" "1" "T"
if build "libogg" "$repo_version"; then
    download "https://github.com/xiph/ogg/archive/refs/tags/v$repo_version.tar.gz" "libogg-$repo_version.tar.gz"
    execute autoreconf -fi
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DBUILD_TESTING=OFF \
                  -DCPACK_BINARY_DEB=OFF \
                  -DCPACK_SOURCE_ZIP=OFF \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "libogg" "$repo_version"
fi

find_git_repo "xiph/flac" "1" "T"
if build "libflac" "$repo_version"; then
    download "https://github.com/xiph/flac/archive/refs/tags/$repo_version.tar.gz" "libflac-$repo_version.tar.gz"
    execute ./autogen.sh
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DINSTALL_CMAKE_CONFIG_MODULE=ON \
                  -DINSTALL_MANPAGES=OFF \
                  -DBUILD_CXXLIBS=ON \
                  -DBUILD_PROGRAMS=ON \
                  -DWITH_ASM=ON \
                  -DWITH_AVX=ON \
                  -DWITH_FORTIFY_SOURCE=ON \
                  -DWITH_STACK_PROTECTOR=ON \
                  -DWITH_OGG=ON \
                  -DENABLE_64_BIT_WORDS=ON \
                  -DBUILD_DOCS=OFF \
                  -DBUILD_EXAMPLES=OFF \
                  -DBUILD_TESTING=OFF \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "libflac" "$repo_version"
fi

if $NONFREE_AND_GPL; then
    find_git_repo "mstorsjo/fdk-aac" "1" "T"
    if build "libfdk-aac" "2.0.3"; then
        download "https://phoenixnap.dl.sourceforge.net/project/opencore-amr/fdk-aac/fdk-aac-2.0.3.tar.gz" "libfdk-aac-2.0.3.tar.gz"
        execute ./autogen.sh
        execute ./configure --prefix="$workspace" --disable-shared
        execute make "-j$cpu_threads"
        execute make install
        build_done "libfdk-aac" "2.0.3"
    fi
    CONFIGURE_OPTIONS+=("--enable-libfdk-aac")
fi

find_git_repo "xiph/vorbis" "1" "T"
if build "vorbis" "$repo_version"; then
    download "https://github.com/xiph/vorbis/archive/refs/tags/v$repo_version.tar.gz" "vorbis-$repo_version.tar.gz"
    execute ./autogen.sh
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DOGG_INCLUDE_DIR="$workspace/include" \
                  -DOGG_LIBRARY="$workspace/lib/libogg.so" \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "vorbis" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libvorbis")

find_git_repo "xiph/opus" "1" "T"
if build "opus" "$repo_version"; then
    download "https://github.com/xiph/opus/archive/refs/tags/v$repo_version.tar.gz" "opus-$repo_version.tar.gz"
    execute autoreconf -fis
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DCPACK_SOURCE_ZIP=OFF \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "opus" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libopus")

find_git_repo "hoene/libmysofa" "1" "T"
if build "libmysofa" "$repo_version"; then
    download "https://github.com/hoene/libmysofa/archive/refs/tags/v$repo_version.tar.gz" "libmysofa-$repo_version.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DBUILD_STATIC_LIBS=ON \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "libmysofa" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libmysofa")

find_git_repo "webmproject/libvpx" "1" "T"
if build "libvpx" "$repo_version"; then
    download "https://github.com/webmproject/libvpx/archive/refs/tags/v$repo_version.tar.gz" "libvpx-$repo_version.tar.gz"
    execute sed -i 's/#include "\.\/vpx_tpl\.h"/#include ".\/vpx\/vpx_tpl.h"/' "vpx/vpx_ext_ratectrl.h"
    execute ./configure --prefix="$workspace" \
                        --as=yasm \
                        --disable-unit-tests \
                        --disable-shared \
                        --disable-examples \
                        --enable-small \
                        --enable-multi-res-encoding \
                        --enable-webm-io \
                        --enable-libyuv \
                        --enable-vp8 \
                        --enable-vp9 \
                        --enable-postproc \
                        --enable-vp9-postproc \
                        --enable-better-hw-compatibility \
                        --enable-vp9-highbitdepth
    execute make "-j$cpu_threads"
    execute make install
    build_done "libvpx" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libvpx")

find_git_repo "8143" "6"
repo_version="${repo_version//debian\//}"
if build "opencore-amr" "$repo_version"; then
    download "https://salsa.debian.org/multimedia-team/opencore-amr/-/archive/debian/$repo_version/opencore-amr-debian-$repo_version.tar.bz2" "opencore-amr-$repo_version.tar.bz2"
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done "opencore-amr" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libopencore-"{amrnb,amrwb})

if build "liblame" "3.100"; then
    download "https://zenlayer.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz"
    execute ./configure --prefix="$workspace" \
                        --disable-shared \
                        --disable-gtktest \
                        --enable-nasm \
                        --with-libiconv-prefix=/usr
    execute make "-j$cpu_threads"
    execute make install
    build_done "liblame" "3.100"
fi
CONFIGURE_OPTIONS+=("--enable-libmp3lame")

find_git_repo "xiph/theora" "1" "T"
if build "libtheora" "1.1.1"; then
    download "https://github.com/xiph/theora/archive/refs/tags/v1.1.1.tar.gz" "libtheora-1.1.1.tar.gz"
    execute ./autogen.sh
    sed "s/-fforce-addr//g" "configure" > "configure.patched"
    chmod +x configure.patched
    execute mv configure.patched configure
    execute rm config.guess
    execute curl -fsSLo "config.guess" "https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess"
    chmod +x config.guess
    execute ./configure --prefix="$workspace" \
                        --disable-examples \
                        --disable-oggtest \
                        --disable-sdltest \
                        --disable-vorbistest \
                        --with-ogg="$workspace" \
                        --with-ogg-includes="$workspace/include" \
                        --with-ogg-libraries="$workspace/lib" \
                        --with-vorbis="$workspace" \
                        --with-vorbis-includes="$workspace/include" \
                        --with-vorbis-libraries="$workspace/lib" \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "libtheora" "1.1.1"
fi
CONFIGURE_OPTIONS+=("--enable-libtheora")

# Install video tools
echo
box_out_banner_video() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf "-"; done)
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

git_caller "https://aomedia.googlesource.com/aom" "av1-git" "av1"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DCONFIG_AV1_DECODER=1 \
                  -DCONFIG_AV1_ENCODER=1 \
                  -DCONFIG_AV1_HIGHBITDEPTH=1 \
                  -DCONFIG_AV1_TEMPORAL_DENOISING=1 \
                  -DCONFIG_DENOISE=1 \
                  -DCONFIG_DISABLE_FULL_PIXEL_SPLIT_8X8=1 \
                  -DENABLE_CCACHE=1 \
                  -DENABLE_EXAMPLES=0 \
                  -DENABLE_TESTS=0 \
                  -G Ninja \
                  "$packages/av1"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi
CONFIGURE_OPTIONS+=("--enable-libaom")

# Rav1e fails to build on Ubuntu Bionic and Debian 11 Bullseye
if [[ "$VER" != "18.04" ]] && [[ "$VER" != "11" ]]; then
    find_git_repo "xiph/rav1e" "1" "T" "enabled"
    if build "rav1e" "$repo_version"; then
        install_rustc
        check_and_install_cargo_c
        download "https://github.com/xiph/rav1e/archive/refs/tags/v$repo_version.tar.gz" "rav1e-$repo_version.tar.gz"
        rm -fr "$HOME/.cargo/registry/index/"* "$HOME/.cargo/.package-cache"
        execute cargo cinstall --prefix="$workspace" \
                               --library-type=staticlib \
                               --crt-static \
                               --release
        build_done "rav1e" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-librav1e")
fi

find_git_repo "AOMediaCodec/libavif" "1" "T"
if build "avif" "$repo_version"; then
    download "https://github.com/AOMediaCodec/libavif/archive/refs/tags/v$repo_version.tar.gz" "avif-$repo_version.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DAVIF_CODEC_AOM=ON \
                  -DAVIF_CODEC_AOM_DECODE=ON \
                  -DAVIF_CODEC_AOM_ENCODE=ON \
                  -DAVIF_ENABLE_GTEST=OFF \
                  -DAVIF_ENABLE_WERROR=OFF \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "avif" "$repo_version"
fi

git_caller "https://github.com/ultravideo/kvazaar.git" "kvazaar-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "$repo_name" "$version"
fi
CONFIGURE_OPTIONS+=("--enable-libkvazaar")

find_git_repo "76" "2" "T"
if build "libdvdread" "$repo_version"; then
    download "https://code.videolan.org/videolan/libdvdread/-/archive/$repo_version/libdvdread-$repo_version.tar.bz2"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-apidoc --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "libdvdread" "$repo_version"
fi

find_git_repo "363" "2" "T"
if build "udfread" "$repo_version"; then
    download "https://code.videolan.org/videolan/libudfread/-/archive/$repo_version/libudfread-$repo_version.tar.bz2"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "udfread" "$repo_version"
fi

if [[ "$OS" == "Arch" ]]; then
    apache_ant
else
    set_ant_path
    git_caller "https://github.com/apache/ant.git" "ant-git" "ant"
    if build "$repo_name" "${version//\$ /}"; then
        echo "Cloning \"$repo_name\" saving version \"$version\""
        git_clone "$git_url"
        chmod 777 -R "$workspace/ant"
        execute sh build.sh install-lite
        build_done "$repo_name" "$version"
    fi
fi

# Ubuntu Jammy gives an error so use the APT version instead
if [[ ! "$OS" == "Ubuntu" ]]; then
    find_git_repo "206" "2" "T"
    if build "libbluray" "$repo_version"; then
        download "https://code.videolan.org/videolan/libbluray/-/archive/$repo_version/$repo_version.tar.gz" "libbluray-$repo_version.tar.gz"
        execute autoreconf -fi
        execute ./configure --prefix="$workspace" \
                            --disable-doxygen-doc \
                            --disable-doxygen-dot \
                            --disable-doxygen-html \
                            --disable-doxygen-ps \
                            --disable-doxygen-pdf \
                            --disable-examples \
                            --disable-extra-warnings \
                            --disable-shared \
                            --without-libxml2
        execute make "-j$cpu_threads"
        execute make install
        build_done "libbluray" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-libbluray")
fi

find_git_repo "mediaarea/zenLib" "1" "T"
if build "zenlib" "$repo_version"; then
    download "https://github.com/MediaArea/ZenLib/archive/refs/tags/v$repo_version.tar.gz" "zenlib-$repo_version.tar.gz"
    cd Project/GNU/Library || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "zenlib" "$repo_version"
fi

find_git_repo "MediaArea/MediaInfoLib" "1" "T"
if build "mediainfo-lib" "$repo_version"; then
    download "https://github.com/MediaArea/MediaInfoLib/archive/refs/tags/v$repo_version.tar.gz" "mediainfo-lib-$repo_version.tar.gz"
    cd "Project/GNU/Library" || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "mediainfo-lib" "$repo_version"
fi

find_git_repo "MediaArea/MediaInfo" "1" "T"
if build "mediainfo-cli" "$repo_version"; then
    download "https://github.com/MediaArea/MediaInfo/archive/refs/tags/v$repo_version.tar.gz" "mediainfo-cli-$repo_version.tar.gz"
    cd Project/GNU/CLI || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-staticlibs --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    execute cp -f "$packages/mediainfo-cli-$repo_version/Project/GNU/CLI/mediainfo" /usr/local/bin/
    build_done "mediainfo-cli" "$repo_version"
fi

if $NONFREE_AND_GPL; then
    find_git_repo "georgmartius/vid.stab" "1" "T"
    if build "vid-stab" "$repo_version"; then
        download "https://github.com/georgmartius/vid.stab/archive/refs/tags/v$repo_version.tar.gz" "vid-stab-$repo_version.tar.gz"
        execute cmake -B build \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF \
                      -DUSE_OMP=ON \
                      -G Ninja
        execute ninja "-j$cpu_threads" -C build
        execute ninja -C build install
        build_done "vid-stab" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-libvidstab")
fi

if $NONFREE_AND_GPL; then
    find_git_repo "dyne/frei0r" "1" "T"
    if build "frei0r" "$repo_version"; then
        download "https://github.com/dyne/frei0r/archive/refs/tags/v$repo_version.tar.gz" "frei0r-$repo_version.tar.gz"
        execute cmake -B build \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF \
                      -DWITHOUT_OPENCV=OFF \
                      -G Ninja
        execute ninja "-j$cpu_threads" -C build
        execute ninja -C build install
        build_done "frei0r" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-frei0r")
fi

if [[ "$OS" == "Arch" ]]; then
    find_git_repo "gpac/gpac" "1" "T"
    if build "gpac" "$repo_version"; then
        pacman -Sq --needed --noconfirm gpac
        build_done "gpac" "$repo_version"
    fi
else
    git_caller "https://github.com/gpac/gpac.git" "gpac-git"
    if build "$repo_name" "${version//\$ /}"; then
        echo "Cloning \"$repo_name\" saving version \"$version\""
        git_clone "$git_url"
        execute ./configure --prefix="$workspace" \
                            --static-bin \
                            --static-modules \
                            --use-a52=local \
                            --use-faad=local \
                            --use-freetype=local \
                            --use-mad=local \
                            --sdl-cfg="$workspace/include/SDL3"
        execute make "-j$cpu_threads"
        execute make install
        execute cp -f bin/gcc/MP4Box /usr/local/
        build_done "$repo_name" "$version"
    fi
fi

find_git_repo "24327400" "3" "T"
if build "svt-av1" "1.8.0"; then
    download "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v1.8.0/SVT-AV1-v1.8.0.tar.bz2" "svt-av1-1.8.0.tar.bz2"
    execute cmake -S . \
                  -B Build/linux \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DBUILD_APPS=OFF \
                  -DBUILD_DEC=ON \
                  -DBUILD_ENC=ON \
                  -DBUILD_TESTING=OFF \
                  -DENABLE_AVX512=OFF \
                  -DENABLE_NASM=ON \
                  -DNATIVE=ON \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C Build/linux
    execute ninja "-j$cpu_threads" -C Build/linux install
    cp -f "Build/linux/SvtAv1Enc.pc" "$workspace/lib/pkgconfig"
    cp -f "Build/linux/SvtAv1Dec.pc" "$workspace/lib/pkgconfig"
    build_done "svt-av1" "1.8.0"
fi
CONFIGURE_OPTIONS+=("--enable-libsvtav1")

if $NONFREE_AND_GPL; then
    find_git_repo "536" "2" "B"
    if build "x264" "$repo_short_version_1"; then
        download "https://code.videolan.org/videolan/x264/-/archive/$repo_version_1/x264-$repo_version_1.tar.bz2" "x264-$repo_short_version_1.tar.bz2"
        execute ./configure --prefix="$workspace" \
                            --bit-depth=all \
                            --chroma-format=all \
                            --enable-debug \
                            --enable-gprof \
                            --enable-lto \
                            --enable-pic \
                            --enable-static \
                            --enable-strip \
                            CFLAGS="$CFLAGS -fPIC" \
                            CXXFLAGS="$CXXFLAGS"
        execute make "-j$cpu_threads"
        execute make install
        execute make install-lib-static
        build_done "x264" "$repo_short_version_1"
    fi
    CONFIGURE_OPTIONS+=("--enable-libx264")
fi

if $NONFREE_AND_GPL; then
    if build "x265" "3.5"; then
        download "https://bitbucket.org/multicoreware/x265_git/downloads/x265_3.5.tar.gz" "x265-3.5.tar.gz"
        fix_libstd_libs
        cd build/linux || exit 1
        rm -fr {8,10,12}bit 2>/dev/null
        mkdir -p {8,10,12}bit
        cd 12bit || exit 1
        echo "$ making 12bit binaries"
        execute cmake ../../../source \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release \
                      -DENABLE_LIBVMAF=OFF \
                      -DENABLE_CLI=OFF \
                      -DENABLE_SHARED=OFF \
                      -DEXPORT_C_API=OFF \
                      -DHIGH_BIT_DEPTH=ON \
                      -DNATIVE_BUILD=ON \
                      -DMAIN12=ON \
                      -G Ninja -Wno-dev
        execute ninja "-j$cpu_threads"
        echo "$ making 10bit binaries"
        cd ../10bit || exit 1
        execute cmake ../../../source \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release \
                      -DENABLE_LIBVMAF=OFF \
                      -DENABLE_CLI=OFF \
                      -DENABLE_HDR10_PLUS=ON \
                      -DENABLE_SHARED=OFF \
                      -DEXPORT_C_API=OFF \
                      -DHIGH_BIT_DEPTH=ON \
                      -DNATIVE_BUILD=ON \
                      -DNUMA_ROOT_DIR=/usr \
                      -G Ninja -Wno-dev
        execute ninja "-j$cpu_threads"
        echo "$ making 8bit binaries"
        cd ../8bit || exit 1
        ln -sf "../10bit/libx265.a" "libx265_main10.a"
        ln -sf "../12bit/libx265.a" "libx265_main12.a"
        execute cmake ../../../source \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release \
                      -DENABLE_LIBVMAF=OFF \
                      -DENABLE_PIC=ON \
                      -DENABLE_SHARED=ON \
                      -DEXTRA_LIB="x265_main10.a;x265_main12.a" \
                      -DEXTRA_LINK_FLAGS="-L." \
                      -DHIGH_BIT_DEPTH=ON \
                      -DLINKED_10BIT=ON \
                      -DLINKED_12BIT=ON \
                      -DNATIVE_BUILD=ON \
                      -DNUMA_ROOT_DIR=/usr \
                      -G Ninja -Wno-dev
        execute ninja "-j$cpu_threads"

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

        # FIX THE x265 SHARED LIBRARY ISSUE
        fix_x265_libs

        build_done "x265" "3.5"
    fi
    CONFIGURE_OPTIONS+=("--enable-libx265")
fi

# Vaapi doesn"t work well with static links FFmpeg.
if [[ -z "$LDEXEFLAGS" ]]; then
    # If the libva development SDK is installed, enable vaapi.
    if library_exists "libva"; then
        if build "vaapi" "1"; then
            build_done "vaapi" "1"
        fi
        CONFIGURE_OPTIONS+=("--enable-vaapi")
    fi
fi

if $NONFREE_AND_GPL; then
    if [[ -n "$iscuda" ]]; then
        if build "nv-codec-headers" "12.1.14.0"; then
            download "https://github.com/FFmpeg/nv-codec-headers/releases/download/n12.1.14.0/nv-codec-headers-12.1.14.0.tar.gz"
            execute make "-j$cpu_threads"
            execute make PREFIX="$workspace" install
            build_done "nv-codec-headers" "12.1.14.0"
        fi

        CONFIGURE_OPTIONS+=("--enable-"{cuda-nvcc,cuda-llvm,cuvid,nvdec,nvenc,ffnvcodec})

        if [[ -n "$LDEXEFLAGS" ]]; then
            CONFIGURE_OPTIONS+=("--enable-libnpp")
        fi

        PATH+=":$cuda_path"
        export PATH

        # Get the Nvidia GPU architecture to build CUDA
        # https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards
        nvidia_architecture
        CONFIGURE_OPTIONS+=("--nvccflags=-gencode arch=$nvidia_arch_type")
    fi
fi

if $NONFREE_AND_GPL; then
    find_git_repo "Haivision/srt" "1" "T"
    if build "srt" "$repo_version"; then
        download "https://github.com/Haivision/srt/archive/refs/tags/v$repo_version.tar.gz" "srt-$repo_version.tar.gz"
        export OPENSSL_ROOT_DIR="$workspace"
        export OPENSSL_LIB_DIR="$workspace/lib"
        export OPENSSL_INCLUDE_DIR="$workspace/include"
        execute cmake -B build \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF \
                      -DENABLE_APPS=OFF \
                      -DENABLE_SHARED=OFF \
                      -DENABLE_STATIC=ON \
                      -DUSE_STATIC_LIBSTDCXX=ON \
                      -G Ninja
        execute ninja -C build "-j$cpu_threads"
        execute ninja -C build "-j$cpu_threads" install
        if [[ -n "$LDEXEFLAGS" ]]; then
            sed -i.backup "s/-lgcc_s/-lgcc_eh/g" "$workspace/lib/pkgconfig/srt.pc"
        fi
        build_done "srt" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-libsrt")
fi

if $NONFREE_AND_GPL; then
    find_git_repo "avisynth/avisynthplus" "1" "T"
    if build "avisynth" "$repo_version"; then
        download "https://github.com/AviSynth/AviSynthPlus/archive/refs/tags/v$repo_version.tar.gz" "avisynth-$repo_version.tar.gz"
        execute cmake -B build \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF \
                      -DHEADERS_ONLY=OFF
        execute make "-j$cpu_threads" -C build VersionGen install
        build_done "avisynth" "$repo_version"
    fi
    CONFIGURE_OPTIONS+=("--enable-avisynth")
fi

# find_git_repo "vapoursynth/vapoursynth" "1" "T"
if build "vapoursynth" "R65"; then
    download "https://github.com/vapoursynth/vapoursynth/archive/refs/tags/R65.tar.gz" "vapoursynth-R65.tar.gz"

    venv_path="$workspace/python_virtual_environment/vapoursynth"
    venv_packages=("Cython==0.29.36")
    setup_python_venv_and_install_packages "$venv_path" "${venv_packages[@]}"

    # Activate the virtual environment for the build process
    source "$venv_path/bin/activate" || fail "Failed to re-activate virtual environment"

    # Explicitly set the PYTHON environment variable to the virtual environment's Python
    export PYTHON="$venv_path/bin/python"

    # Assuming autogen, configure, make, and install steps for VapourSynth
    execute ./autogen.sh || fail "Failed to execute autogen.sh"
    execute ./configure --prefix="$workspace" --disable-shared || fail "Failed to configure"
    execute make -j"$cpu_threads" || fail "Failed to make"
    execute make install || fail "Failed to make install"

    # Deactivate the virtual environment after the build
    deactivate

    build_done "vapoursynth" "R65"
fi
CONFIGURE_OPTIONS+=("--enable-vapoursynth")

git_caller "https://chromium.googlesource.com/codecs/libgav1" "libgav1-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url"
    execute git clone -q -b "20220623.1" --depth 1 "https://github.com/abseil/abseil-cpp.git" "third_party/abseil-cpp"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DABSL_ENABLE_INSTALL=ON \
                  -DABSL_PROPAGATE_CXX_STD=ON \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
                  -DCMAKE_INSTALL_SBINDIR=sbin \
                  -DLIBGAV1_ENABLE_TESTS=OFF \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi
git_caller "https://chromium.googlesource.com/codecs/libgav1" "libgav1-git"

if $NONFREE_AND_GPL; then
    find_git_repo "8268" "6"
    repo_version="${repo_version//debian\/2%/}"
    if build "xvidcore" "$repo_version"; then
        download "https://salsa.debian.org/multimedia-team/xvidcore/-/archive/debian/2%25$repo_version/xvidcore-debian-2%25$repo_version.tar.bz2" "xvidcore-$repo_version.tar.bz2"
        cd "build/generic" || exit 1
        execute ./bootstrap.sh
        execute ./configure --prefix="$workspace"
        execute make "-j$cpu_threads"
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
    line=$(for i in $(seq 0 $input_char); do printf "-"; done)
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
    CFLAGS="-g -O3 -fno-lto -pipe -march=native"
    CXXFLAGS="-g -O3 -fno-lto -pipe -march=native"
    export CFLAGS CXXFLAGS
    libde265_libs=$(find /usr/ -type f -name 'libde265.s*')
    if [[ -f "$libde265_libs" ]] && [[ ! -e "/usr/lib/x86_64-linux-gnu/libde265.so" ]]; then
        ln -sf "$libde265_libs" "/usr/lib/x86_64-linux-gnu/libde265.so"
        chmod 755 "/usr/lib/x86_64-linux-gnu/libde265.so"
    fi

    case "$VER" in
        20.04) pixbuf_switch=OFF ;;
        *)     pixbuf_switch=ON ;;
    esac

    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DAOM_INCLUDE_DIR="$workspace/include" \
                  -DAOM_LIBRARY="$workspace/lib/libaom.a" \
                  -DLIBDE265_INCLUDE_DIR="$workspace/include" \
                  -DLIBDE265_LIBRARY="/usr/lib/x86_64-linux-gnu/libde265.so" \
                  -DLIBSHARPYUV_INCLUDE_DIR="$workspace/include/webp" \
                  -DLIBSHARPYUV_LIBRARY="$workspace/lib/libsharpyuv.so" \
                  -DWITH_AOM_DECODER=ON \
                  -DWITH_AOM_ENCODER=ON \
                  -DWITH_DAV1D=OFF \
                  -DWITH_EXAMPLES=OFF \
                  -DWITH_GDK_PIXBUF="$pixbuf_switch" \
                  -DWITH_LIBDE265=ON \
                  -DWITH_X265=OFF \
                  -DWITH_LIBSHARPYUV=ON \
                  -DWITH_REDUCED_VISIBILITY=OFF \
                  -DWITH_SvtEnc=OFF \
                  -DWITH_SvtEnc_PLUGIN=OFF \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    source_compiler_flags
    build_done "libheif" "$repo_version"
fi

find_git_repo "uclouvain/openjpeg" "1" "T"
if build "openjpeg" "$repo_version"; then
    download "https://codeload.github.com/uclouvain/openjpeg/tar.gz/refs/tags/v$repo_version" "openjpeg-$repo_version.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DBUILD_TESTING=OFF \
                  -DBUILD_THIRDPARTY=ON \
                  -G Ninja
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "openjpeg" "$repo_version"
fi
CONFIGURE_OPTIONS+=("--enable-libopenjpeg")

# Build FFmpeg
echo
box_out_banner_ffmpeg() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf "-"; done)
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

if [[ "$OS" == "Arch" ]]; then
    ladspa_switch="--disable-ladspa"
else
    ladspa_switch="--enable-ladspa"
fi

# Get DXVA2 and other essential windows header files
get_wsl_version
if [[ "$wsl_flag=" == "yes_wsl" ]]; then
    install_windows_hardware_acceleration
fi

# Check the last build version of ffmpeg if it exists to determine if an update has occured
if [[ -f "$packages/ffmpeg-git.done" ]]; then
    # Define a function to read the file content
    read_file_contents() {
        local file_path="$1"
        if [ -f "$file_path" ]; then
            # Read the content of the file into a variable
            local content=$(cat "$file_path")
            echo "$content"
        fi
    }

    file_path="$packages/ffmpeg-git.done"
    ffmpeg_current_version=$(read_file_contents "$file_path")
fi

# Get the latest FFmpeg version by parsing its repository
ffmpeg_latest_version=$(check_ffmpeg_version "https://github.com/FFmpeg/FFmpeg.git")

if [[ -z "$ffmpeg_current_version" ]]; then
    ffmpeg_current_version="Not installed"
fi

echo
log_update "The current installed version of FFmpeg: $ffmpeg_current_version"
log_update "The latest release version of FFmpeg: $ffmpeg_latest_version"

# Clean the compilter flags before building FFmpeg
source_compiler_flags

# Build FFmpeg from source using the latest git clone
git_caller "https://git.ffmpeg.org/ffmpeg.git" "ffmpeg-git" "ffmpeg"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    git_clone "$git_url" "ffmpeg-git" "ffmpeg"

    [[ "$OS" == "Arch" ]] && patch_ffmpeg

    mkdir build; cd build
    ../configure --prefix=/usr/local \
                 --arch=$(uname -m) \
                 --cc="$CC" \
                 --cxx="$CXX" \
                 --disable-debug \
                 --disable-doc \
                 --disable-large-tests \
                 --disable-shared \
                 "$ladspa_switch" \
                 "${CONFIGURE_OPTIONS[@]}" \
                 --enable-chromaprint \
                 --enable-libbs2b \
                 --enable-libcaca \
                 --enable-libgme \
                 --enable-libmodplug \
                 --enable-libshine \
                 --enable-libsnappy \
                 --enable-libsoxr \
                 --enable-libspeex \
                 --enable-libssh \
                 --enable-libtwolame \
                 --enable-libv4l2 \
                 --enable-libvo-amrwbenc \
                 --enable-libzvbi \
                 --enable-lto \
                 --enable-opengl \
                 --enable-pic \
                 --enable-pthreads \
                 --enable-small \
                 --enable-static \
                 --enable-version3 \
                 --extra-cflags="$CFLAGS" \
                 --extra-cxxflags="$CXXFLAGS" \
                 --extra-libs="$EXTRALIBS" \
                 --extra-ldflags="-pie" \
                 --pkg-config-flags="--static" \
                 --pkg-config="$workspace/bin/pkg-config" \
                 --pkgconfigdir="$workspace/lib/pkgconfig" \
                 --strip=$(type -P strip)
    execute make "-j$cpu_threads"
    execute make install
    build_done "$repo_name" "$version"
fi

# Execute the ldconfig command to ensure that all library changes are detected by ffmpeg
ldconfig 2>/dev/null

# Display the version of each of the programs
prompt_ffmpeg_versions

# Prompt the user to clean up the build files
cleanup

# Show exit message
exit_fn
