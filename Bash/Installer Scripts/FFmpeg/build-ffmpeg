#!/usr/bin/env bash
# shellcheck disable=SC2068,SC2162,SC2317 source=/dev/null

#############################################################################################################################
##
##  GitHub: https://github.com/slyfox1186/ffmpeg-build-script
##
##  Script version: 3.4.7
##
##  Updated: 02.10.24
##
##  Purpose:
##
##    - build ffmpeg from source code with addon development libraries also compiled from
##      source to help ensure the latest functionality
##
##  Supported Distro:
##
##    - arch linux
##    - debian 11|12
##    - ubuntu (20|22|23).04 & 23.10
##
##  Supported architecture: x86_64
##
##  Arch Linux:
##
##    - required pacman packages for archlinux
##    - updated the source code libraries to compile successfully using a partial mix of aur (arch user repository)
##    - removed the aur install of libbluray as it was not needed and can be done with the github repository
##
##  GeForce CUDA SDK Toolkit:
##
##    - updated to version 12.3.2 (01.08.2024)
##
##  Updated:
##
##    - ffmpeg to retrieve the latest release version
##
##  Added:
##
##    - a check to skip compiling libbluray if the OS is Ubuntu Jammy due to compile issues. Use the APT version instead.
##    - code to get the latest OpenSSL version 3.1.X
##    - ubuntu 23.10 (manic) support
##    - set the x265 libs to be built with clang because it gives better fps output than when built with gcc
##
##  Removed:
##
##    - let APT manage libdav1d
##    - unnecessary compiler flags
##    - python3 build code that became useless
##    - removed support for debian 10 (Buster)
##    - removed support for Ubuntu 18.04 (bionic)
##
##  Fixed:
##
##    - python pip virtual environment build errors
##    - Regex parsing error for libencode
##    - Fixed an error output caused by a missing Cuda JSON file
##    - libvpx has a bug in their code in file vpx_ext_ratectrl.h and I used the sed command to edit the code and fix it.
##    - libant would not build unexpectedly so I edited APT to download Java v8 which works for some unknown reason.
##    - a missing library related to libc6 for x265 to compile on windows wsl
##
#############################################################################################################################

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root/sudo"
    exit 1
fi

#
# DEFINE GLOBAL VARIABLES
#

script_name="${0}"
script_ver=3.4.7
cuda_pin_url=https://developer.download.nvidia.com/compute/cuda/repos
cwd="$PWD/ffmpeg-build-script"
packages="$cwd/packages"
workspace="$cwd/workspace"
install_dir=/usr/local
pc_type=x86_64-linux-gnu
web_repo=https://github.com/slyfox1186/script-repo
LDEXEFLAGS=""
ffmpeg_libraries=()
latest=false
regex_str='(rc|RC|master)+[0-9]*$' # SET THE REGEX VARIABLE TO CHECK FOR RELEASE CANDIDATES
debug=OFF

#
# SET THE AVAILABLE CPU THREAD AND CORE COUNT FOR PARALLEL PROCESSING (SPEEDS UP THE BUILD PROCESS)
#

if [[ -f /proc/cpuinfo ]]; then
    cpu_threads=$(grep --count ^processor /proc/cpuinfo)
else
    cpu_threads=$(nproc --all)
fi
MAKEFLAGS="-j$cpu_threads"
export MAKEFLAGS

#
# CREATE THE OUTPUT DIRECTORIES
#

mkdir -p "$packages/nvidia-cuda"

#
# PRINT SCRIPT BANNER
#

echo
box_out_banner1() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
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
box_out_banner1 "FFmpeg Build Script - v$script_ver"
printf "\n%s\n\n" "Utilizing $cpu_threads CPU threads"

#
# SET THE CC/CPP COMPILERS + CUSTOMIZED COMPILER OPTIMIZATION FLAGS
#

source_flags_fn() {
    CC=gcc
    CXX=g++
    CFLAGS="-g -O3 -march=native"
    CXXFLAGS="$CFLAGS -std=c++20"
    EXTRALIBS="-lm -lpthread -lz -lstdc++ -lgcc_s -lrt -ldl -lnuma"
    export CC CFLAGS CPPFLAGS CXX CXXFLAGS
}
source_flags_fn

exit_fn() {
    printf "\n%s\n%s\n\n" "Make sure to star this repository to show your support!" "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n%s\n\n%s\n\n" "$1" "For help or to report a bug create an issue at: $web_repo/issues"
    exit 1
}

cleanup_fn() {
    local choice

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        "========================================================" \
        "        Do you want to clean up the build files?        " \
        "========================================================" \
        "[1] Yes" \
        "[2] No"
    read -p "Your choices are (1 or 2): " choice

    case "$choice" in
        1)      rm -fr "$cwd" ;;
        2)      return ;;
        *)      unset choice
                cleanup_fn
                ;;
    esac
}

ff_ver_fn() {
    printf "\n%s\n%s\n%s\n\n" \
        "========================================================" \
        "                     FFmpeg Version                     " \
        "========================================================"
    "$install_dir/bin/ffmpeg" -version
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
        echo "$dl_file is already downloaded."
    else
        echo "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! curl -LsSo "$target_file" "$dl_url"; then
            printf "\n%s\n\n" "Error: Failed to download \"$dl_file\". Second attempt in 10 seconds..."
            sleep 10
            if ! curl -LsSo "$target_file" "$dl_url"; then
                fail_fn "Error: Failed to download \"$dl_file\". Exiting... (Line: $LINENO)"
            fi
        fi
        echo "Download Completed"
    fi

    if [[ -d "$target_dir" ]]; then
        rm -fr "$target_dir"
    fi
    mkdir -p "$target_dir"

    if [[ -n "$3" ]]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            rm "$target_file"
            fail_fn "Error: Failed to extract the tarball \"$dl_file\" and was deleted. Re-run the script to try again. (Line: $LINENO)"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            rm "$target_file"
            fail_fn "Error: Failed to extract the tarball \"$dl_file\" and was deleted. Re-run the script to try again. (Line: $LINENO)"
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail_fn "Error: Failed to cd into \"$target_dir\". (Line: $LINENO)"
}

# Function to check if cargo-c is installed and install it if not
check_and_install_cargo_c() {
    if [ -z "$(ls "$HOME/.cargo/bin" | grep -Eo '^(cargo-(cbuild|cinstall))')" ] && [ -z "$(command -v cargo-cinstall)" ]; then
        echo "cargo-c could not be found, installing..."
        # Remove any stale locks on cargo
        if ps aux | grep -E 'cargo|rustc' | grep -v grep &>/dev/null; then
            cargo clean
            find $HOME/.cargo/registry/index -type f -name ".cargo-lock" -delete
        fi
        if ! execute cargo install cargo-c; then
            echo "\$ The command \"cargo install cargo-c\" failed as well. The script will now exit."
            exit 1
        fi
        echo "cargo-c installation completed."
    else
        echo "cargo-c is already installed."
    fi
}

install_rustc_fn() {
    get_rustc_ver=$(rustc --version | grep -Eo '[0-9 \.]+' | head -n1)
    if [ "$get_rustc_ver" != "1.75.0" ]; then
        echo "Installing RustUp"
        curl -sS --proto "=https" --tlsv1.2 "https://sh.rustup.rs" | sh -s -- -y &>/dev/null
        source "$HOME/.cargo/env"
        if [[ -f "$HOME/.zshrc" ]]; then
            source "$HOME/.zshrc"
        else
            source "$HOME/.bashrc"
        fi
    fi
}

git_call_fn() {
    git_url="$1"
    repo_name="$2"
    recurse_flag=""
    if [[ "$3" == "recurse" ]]; then
        recurse_flag=1
    elif [[ "$3" == "ant" ]]; then
        version=$(download_git "$git_url" "$repo_name" "ant")
    else
        version=$(download_git "$git_url" "$repo_name")
    fi
    version="${version//Cloning completed: /}"
}

download_git() {
    local repo_url="$1"
    local repo_name="${2:-"${1##*/}"}"
    local repo_name="${repo_name//\./-}"
    local repo_flag="$3"
    local target_dir="$packages/$repo_name"
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
            version=$(git ls-remote "$repo_url" | grep HEAD | awk '{print substr($1,1,7)}')
            if [[ -z "$version" ]]; then
                version="unknown"
            fi
        fi
    fi

    [[ -f "$packages/${repo_name}.done" ]] && store_prior_version=$(cat "$packages/${repo_name}.done")

    if [[ ! "$version" == "$store_prior_version" ]]; then
        if [[ "$recurse_flag" -eq 1 ]]; then
            recurse="--recursive"
        elif [[ -n "$3" ]]; then
            output_dir="$dl_path/$3"
            target_dir="$output_dir"
        fi
        [[ -d "$target_dir" ]] && rm -fr "$target_dir"
        # Clone the repository
        if ! git clone --depth 1 $recurse -q "$repo_url" "$target_dir"; then
            printf "\n%s\n\n" "Error: Failed to clone \"$target_dir\". Second attempt in 10 seconds..."
            sleep 10
            if ! git clone --depth 1 $recurse -q "$repo_url" "$target_dir"; then
                fail_fn "Error: Failed to clone \"$target_dir\". Exiting script. (Line: $LINENO)"
            fi
        fi
        cd "$target_dir" || fail_fn "Error: Failed to cd into \"$target_dir\". (Line: $LINENO)"
    fi

    echo "Cloning completed: $version"
    return 0
}

# LOCATE GITHUB RELEASE VERSION NUMBERS USING GIT CLONE
ffmpeg_version_check_fn() {
    local ffmpeg_repo="$1"

    ffmpeg_ver_check=$(git ls-remote --tags "$ffmpeg_repo" |
                    awk -F'/' '/n[0-9]+(\.[0-9]+)*(-dev)?$/ {print $3}' |
                    grep -Ev '\-dev' |
                    sort -rV |
                    head -n1)
}

# LOCATE GITHUB RELEASE VERSION NUMBERS
github_repo() {
    local repo="$1"
    local url="$2"
    local url_flag="$3"
    g_ver=""

    local count=1
    local max_attempts=10
    local github_regex_string='[v]*(\d+[\._]\d+(?:[\._]\d*){0,2})\.tar\.gz'

    if [[ -z "$repo" || -z "$url" ]]; then
        echo "Error: Git repository and URL are required."
        return 1
    fi

    [ -n "$url_flag" ] && url_flag=1

    while [ $count -le $max_attempts ]
    do
        if [[ "$url_flag" -eq 1 ]]; then
            curl_cmd=$(curl -LSs "https://github.com/xiph/rav1e/tags" | grep -Eo 'href="[^"]*v?[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz"' | head -n1)
        else
            curl_cmd=$(curl -LSs "https://github.com/$repo/$url" | grep -o 'href="[^"]*\.tar\.gz"')
        fi

        # Extract the specific line
        line=$(echo "$curl_cmd" | grep -o 'href="[^"]*\.tar\.gz"' | sed -n "${count}p")

        # Check if the line matches the pattern (version without 'RC'/'rc')
        if echo "$line" | grep -qP "$github_regex_string"; then
            # Extract and print the version number
            g_ver=$(echo "$line" | grep -oP '(\d+[\._]\d+(?:[\._]\d+){0,2})')
            break
        else
            # Increment the count if no match is found
            ((count++))
        fi
    done

    # DENY INSTALLING A RELEASE CANDIDATE
    while [[ $g_ver =~ $regex_str ]]
    do
        curl_cmd=$(curl -LSs "https://github.com/$repo/$url" | grep -o 'href="[^"]*\.tar\.gz"')

        # Extract the specific line
        line=$(echo "$curl_cmd" | grep -o 'href="[^"]*\.tar\.gz"' | sed -n "${count}p")

        # Check if the line matches the pattern (version without 'RC'/'rc')
        if echo "$line" | grep -qP "$github_regex_string"; then
            # Extract and print the version number
            g_ver=$(echo "$line" | grep -oP '(\d+[\._]\d+(?:[\._]\d+){0,2})')
            break
        else
            # Increment the count if no match is found
            ((count++))
        fi
    done
}

videolan_repo() {
    local repo="$1"
    local url="$2"
    local count=0
    g_ver=""

    if [[ -z "$repo" || -z "$url" ]]; then
        echo "Error: Repository and URL are required."
        return 1
    fi

    if curl_cmd=$(curl -sS "https://code.videolan.org/api/v4/projects/$repo/repository/$url"); then
        g_ver=$(echo "$curl_cmd" | jq -r ".[0].commit.id")
        g_sver=$(echo "$curl_cmd" | jq -r ".[0].commit.short_id")
        g_sver=${g_sver::7}
        g_ver1=$(echo "$curl_cmd" | jq -r ".[0].name")
        g_ver1=${g_ver1#v}
    fi

    # DENY INSTALLING A RELEASE CANDIDATE
    while [[ $g_ver =~ $regex_str ]]
    do
        if curl_cmd=$(curl -sS "https://code.videolan.org/api/v4/projects/$repo/repository/$url"); then
            g_ver=$(echo "$curl_cmd" | jq -r ".[$count].name")
            g_ver="${g_ver#v}"
        fi
        ((count++))
    done
}

gitlab_repo() {
    local repo="$1"
    local url="$2"
    local count=0
    g_ver=""
    g_ver1=""
    g_sver1=""

    if curl_cmd=$(curl -sS "https://gitlab.com/api/v4/projects/$repo/repository/$url"); then
        g_ver=$(echo "$curl_cmd" | jq -r ".[0].name")
        g_ver="${g_ver#v}"
        g_ver1=$(echo "$curl_cmd" | jq -r ".[0].commit.id")
        g_ver1="${g_ver1#v}"
        g_sver1=$(echo "$curl_cmd" | jq -r ".[0].commit.short_id")
        g_ver="${g_ver#VTM-}"
    fi

    # DENY INSTALLING A RELEASE CANDIDATE
    while [[ $g_ver =~ $regex_str ]]
    do
        if curl_cmd=$(curl -sS "https://gitlab.com/api/v4/projects/$repo/repository/$url"); then
            g_ver=$(echo "$curl_cmd" | jq -r ".[$count].name")
            g_ver="${g_ver#v}"
        fi
        ((count++))
    done
}

gitlab_freedesktop_repo() {
    local repo="$1"
    local count=0
    g_ver=""

    while true
    do
        if curl_cmd=$(curl -sS "https://gitlab.freedesktop.org/api/v4/projects/$repo/repository/tags"); then
            g_ver=$(echo "$curl_cmd" | jq -r ".[$count].name")
            g_ver="${g_ver#v}"

            # Check if g_ver contains "RC" and skip it
            if [[ $g_ver =~ $regex_str ]]; then
                ((count++))
            else
                break  # Exit the loop when a non-RC version is found
            fi
        else
            echo "Error: Failed to fetch data from GitLab API."
            return 1
        fi
    done
}

gitlab_gnome_repo() {
    local repo="$1"
    local count=0
    g_ver=""

    if [[ -z "$repo" ]]; then
        echo "Error: Repository name is required."
        return 1
    fi

    if curl_cmd=$(curl -sS "https://gitlab.gnome.org/api/v4/projects/$repo/repository/tags"); then
        g_ver=$(echo "$curl_cmd" | jq -r ".[0].name")
        g_ver="${g_ver#v}"
    fi

    # DENY INSTALLING A RELEASE CANDIDATE
    while [[ $g_ver =~ $regex_str ]]; do
        if curl_cmd=$(curl -sS "https://gitlab.gnome.org/api/v4/projects/$repo/repository/tags"); then
            g_ver=$(echo "$curl_cmd" | jq -r ".[$count].name")
            g_ver="${g_ver#v}"
        fi
        ((count++))
    done
}

debian_salsa_repo() {
    local repo="$1"
    local count=0
    g_ver=""

    if [[ -z "$repo" ]]; then
        echo "Error: Repository name is required."
        return 1
    fi

    if curl_cmd=$(curl -sS "https://salsa.debian.org/api/v4/projects/$repo/repository/tags"); then
        g_ver=$(echo "$curl_cmd" | jq -r ".[0].name")
        g_ver="${g_ver#v}"
    fi

    # DENY INSTALLING A RELEASE CANDIDATE
    while [[ $g_ver =~ $regex_str ]]
    do
        if curl_cmd=$(curl -sS "https://salsa.debian.org/api/v4/projects/$repo/repository/tags"); then
            g_ver=$(echo "$curl_cmd" | jq -r ".[$count].name")
            g_ver="${g_ver#v}"
        fi
        ((count++))
    done
}

find_git_repo() {
    local url="$1"
    local git_repo_type="$2"
    local url_action="$3"

    case "$git_repo_type" in
        1) set_repo="github_repo" ;;
        2) set_repo="videolan_repo" ;;
        3) set_repo="gitlab_repo" ;;
        4) set_repo="gitlab_freedesktop_repo" ;;
        5) set_repo="gitlab_gnome_repo" ;;
        6) set_repo="debian_salsa_repo" ;;
        *) fail_fn "Error: Could not detect the variable \"\$git_repo_type\" in the function \"find_git_repo\". (Line: $LINENO)"
    esac

    case "$url_action" in
        B) set_action="branches" ;;
        L) set_action="releases/latest" ;;
        R) set_action="releases" ;;
        T) set_action="tags" ;;
        *) set_action="$3" ;;
    esac

    "$set_repo" "$url" "$set_action" 2>/dev/null
}

execute() {
    echo "$ $*"

    if [[ "$debug" = "ON" ]]; then
        if ! output=$("$@"); then
            notify-send -t 5000 "Failed to execute $*" 2>/dev/null
            fail_fn "Error: Failed to execute $*"
        fi
    else
        if ! output=$("$@" 2>/dev/null >/dev/null); then
            notify-send -t 5000 "Failed to execute $*" 2>/dev/null
            fail_fn "Error: Failed to execute $*"
        fi
    fi
}

build() {
    printf "\n%s\n%s\n" \
        "Building $1 - version $2" \
        "========================================================"
    if [[ -f "$packages/$1.done" ]]; then
        if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        elif $latest; then
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
    if ! [[ -x $(pkg-config --exists --print-errors "$1" 2>/dev/null >/dev/null >/dev/null) ]]; then
        return 1
    fi
    return 0
}

# Function to setup Python virtual environment and install packages
setup_python_venv_and_install_packages() {
    local parse_path="$1"
    shift
    local parse_package=("$@")

    echo "Creating a Python virtual environment at $parse_path..."
    python3 -m venv "$parse_path" || fail_fn "Failed to create virtual environment"

    echo "Activating the virtual environment..."
    source "$parse_path/bin/activate" || fail_fn "Failed to activate virtual environment"

    echo "Installing Python packages: ${parse_package[*]}..."
    pip install "${parse_package[@]}" || fail_fn "Failed to install packages"

    echo "Deactivating the virtual environment..."
    deactivate

    echo "Python virtual environment setup and package installation completed."
}

find_cuda_json_file() {
    locate_cuda_json_file=$(find /usr/local/cuda/ -type f -name 'version.json' 2>/dev/null)
    locate_cuda_json_file=$(find /opt/cuda/ -type f -name 'version.json' 2>/dev/null)
    echo "$locate_cuda_json_file"
}

# PRINT THE SCRIPT OPTIONS
usage() {
    clear
    echo "Usage: ./script [options]"
    echo
    echo "Options:"
    echo "    -h, --help                                       Display usage information"
    echo "        --version                                    Display version information"
    echo "    -c, --cleanup                                    Remove all working dirs"
    echo "    -b, --build                                      Starts the build process"
    echo "    -l, --latest                                     Force the script to build the latest version of dependencies if newer version is available"
    echo
    echo "Example: ./script --build --latest"
}

while (("$#" > 0))
do
    case "$1" in
        -h | --help) usage
                     echo
                     exit 0
                     ;;
        --version)   printf "%s\n\n" "The script version is: $script_ver"
                     exit 0
                     ;;
        -*)          if [[ "$1" == "--build" || "$1" =~ "-b" ]]; then
                         bflag="-b"
                     fi
                     if [[ "$1" == "--cleanup" || "$1" =~ "-c" && ! "$1" =~ "--" ]]; then
                         cflag="-c"
                         cleanup_fn
                     fi
                     if [[ "$1" == "--full-static" ]]; then
                         LDEXEFLAGS="-static"
                      fi
                     if [[ "$2" == "--latest" || "$2" =~ "-l" ]]; then
                         latest=true
                     fi
                     shift
                     ;;
             *)      usage
                     echo
                     exit 1
                     ;;
    esac
done

if [[ -z "$bflag" ]]; then
    if [[ -z "$cflag" ]]; then
        usage
        echo
        exit 1
    fi
    exit 0
fi

if [[ -n "$LDEXEFLAGS" ]]; then
    printf "%s\n\n" "The script has been configured to run in full static mode."
fi

#
# SET THE PATH VARIABLE
#

if find /usr/local -maxdepth 1 -name "cuda" &>/dev/null | head -n1; then
    cuda_bin_path=$(find /usr/local -maxdepth 1 -name "cuda" &>/dev/null | head -n1)
    cuda_bin_path+="/bin"
elif find /opt -maxdepth 1 -name "cuda" &>/dev/null | head -n1; then
    cuda_bin_path=$(find /opt -maxdepth 1 -name "cuda" &>/dev/null | head -n1)
    cuda_bin_path+="/bin"
fi

if [[ -d /usr/lib/ccache/bin ]]; then
    set_ccache_dir="/usr/lib/ccache/bin"
else
    set_ccache_dir="/usr/lib/ccache"
fi

path_fn() {
    PATH=""
    PATH="\
$set_ccache_dir:\
$cuda_bin_path:\
$workspace/bin:\
$HOME/.local/bin:\
/usr/local/ant/bin:\
/usr/local/sbin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"
export PATH
}
path_fn

path_clean_fn() {
    PATH=""
    PATH="\
$set_ccache_dir:\
$cuda_bin_path:\
$HOME/.local/bin:\
/usr/local/ant/bin:\
/usr/local/sbin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"
export PATH
}

#
# SET THE PKG_CONFIG_PATH VARIABLE
#

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

check_nvidia_gpu() {
    cuda_version_test=$(cat "/usr/local/cuda/version.json" 2>/dev/null | jq -r '.cuda.version' 2>/dev/null)
}

check_amd_gpu() {
    if lshw -C display 2>&1 | grep -qEio 'AMD|amdgpu'; then
        echo "AMD GPU detected"
    elif dpkg -l 2>&1 | grep -qi 'amdgpu'; then
        echo "AMD GPU detected"
    elif lspci 2>&1 | grep -i 'AMD'; then
        echo "AMD GPU detected"
    else
        echo "No AMD GPU detected"
    fi
}

fetch_and_parse_cuda_version() {
    local url="https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html"

    # Use curl to fetch the HTML content of the page
    local content=$(curl -sS "$url")

    # Parse the version directly from the fetched content
    if [[ $content =~ CUDA\ ([0-9]+\.[0-9]+)(\ Update\ ([0-9]+))? ]]; then
        local base_version=${BASH_REMATCH[1]}
        local update_version=${BASH_REMATCH[3]}
        cuda_latest_ver="$base_version"

        # Append the update number if present
        if [[ -n "$update_version" ]]; then
          cuda_latest_ver+=".$update_version"
        fi
    fi
}

gpu_arch_fn() {
    local gpu_name gpu_type
    cuda_compile_flag=""

    if [ -n $(find_cuda_json_file) ]; then
        cuda_compile_flag=1
        gpu_name=$(nvidia-smi --query-gpu=gpu_name --format=csv | sort -rV | head -n 1)
        if [[ "$gpu_name" == "name" ]]; then
            gpu_name=$(nvidia-smi --query-gpu=gpu_name --format=csv | sort -V | head -n 1)
        fi

        case "$gpu_name" in
            "Quadro P2000")                 gpu_type=1 ;;
            "NVIDIA GeForce GT 1010")       gpu_type=1 ;;
            "NVIDIA GeForce GTX 1030")      gpu_type=1 ;;
            "NVIDIA GeForce GTX 1050")      gpu_type=1 ;;
            "NVIDIA GeForce GTX 1060")      gpu_type=1 ;;
            "NVIDIA GeForce GTX 1070")      gpu_type=1 ;;
            "NVIDIA GeForce GTX 1080")      gpu_type=1 ;;
            "NVIDIA TITAN Xp")              gpu_type=1 ;;
            "NVIDIA Tesla P40")             gpu_type=1 ;;
            "NVIDIA Tesla P4")              gpu_type=1 ;;
            "NVIDIA GeForce GTX 1180")      gpu_type=2 ;;
            "NVIDIA GeForce GTX Titan V")   gpu_type=2 ;;
            "Quadro GV100")                 gpu_type=2 ;;
            "NVIDIA Tesla V100")            gpu_type=2 ;;
            "NVIDIA GeForce GTX 1660 Ti")   gpu_type=3 ;;
            "NVIDIA GeForce RTX 2060")      gpu_type=3 ;;
            "NVIDIA GeForce RTX 2070")      gpu_type=3 ;;
            "NVIDIA GeForce RTX 2080")      gpu_type=3 ;;
            "Quadro 4000")                  gpu_type=3 ;;
            "Quadro 5000")                  gpu_type=3 ;;
            "Quadro 6000")                  gpu_type=3 ;;
            "Quadro 8000")                  gpu_type=3 ;;
            "NVIDIA T1000")                 gpu_type=3 ;;
            "NVIDIA T2000")                 gpu_type=3 ;;
            "NVIDIA Tesla T4")              gpu_type=3 ;;
            "NVIDIA GeForce RTX 3050")      gpu_type=4 ;;
            "NVIDIA GeForce RTX 3060")      gpu_type=4 ;;
            "NVIDIA GeForce RTX 3070")      gpu_type=4 ;;
            "NVIDIA GeForce RTX 3080")      gpu_type=4 ;;
            "NVIDIA GeForce RTX 3080 Ti")   gpu_type=4 ;;
            "NVIDIA GeForce RTX 3090")      gpu_type=4 ;;
            "NVIDIA RTX A2000")             gpu_type=4 ;;
            "NVIDIA RTX A3000")             gpu_type=4 ;;
            "NVIDIA RTX A4000")             gpu_type=4 ;;
            "NVIDIA RTX A5000")             gpu_type=4 ;;
            "NVIDIA RTX A6000")             gpu_type=4 ;;
            "NVIDIA GeForce RTX 4080")      gpu_type=5 ;;
            "NVIDIA GeForce RTX 4090")      gpu_type=5 ;;
            "NVIDIA H100")                  gpu_type=6 ;;
            *)                              fail_fn "Error: Unable to define \"\$gpu_name\" in the function \"gpu_arch_fn\". (Line: $LINENO)" ;;
        esac

        if [[ -n "$gpu_type" ]]; then
            case "$gpu_type" in
                1)      gpu_arch="compute_61,code=sm_61" ;;
                2)      gpu_arch="compute_70,code=sm_70" ;;
                3)      gpu_arch="compute_75,code=sm_75" ;;
                4)      gpu_arch="compute_86,code=sm_86" ;;
                5)      gpu_arch="compute_89,code=sm_89" ;;
                6)      gpu_arch="compute_90,code=sm_90" ;;
                *)      fail_fn "Error: Unable to define \"\$gpu_arch\" in the function \"gpu_arch_fn\". (Line: $LINENO)" ;;
            esac
        else
            fail_fn "Error: Failed to define \"\$gpu_type\". (Line: $LINENO)"
        fi
    else
        return 1
    fi
}

cuda_download_fn() {
    local choice

    printf "\n%s\n\n%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n" \
        "Pick your Linux distro from the list below:" \
        "Supported architecture: x86_64" \
        "[1] Debian 10" \
        "[2] Debian 11" \
        "[3] Debian 12" \
        "[4] Ubuntu 20.04" \
        "[5] Ubuntu 22.04" \
        "[6] Ubuntu WSL" \
        "[7] Arch Linux" \
        "[8] Exit"
    read -p "Your choices are (1 to 8): " choice

    printf "\n%s\n%s\n\n" \
        "Downloading CUDA SDK Toolkit - version $cuda_latest_ver" \
        "===================================================="

    local cuda_url="https://developer.download.nvidia.com/compute/cuda/$cuda_latest_ver"

    case "$choice" in
        1)
            wget --show progress -cqO "$packages/nvidia-cuda/cuda-buster-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-debian10-12-3-local_12.3.2-545.23.08-1_amd64.deb"
            dpkg -i "$packages/nvidia-cuda/cuda-buster-$cuda_latest_ver.deb"
            cp -f /var/cuda-repo-debian10-12-3-local/cuda-*-keyring.gpg /usr/share/keyrings/
            add-apt-repository -y contrib
            ;;
        2)
            wget --show progress -cqO "$packages/nvidia-cuda/cuda-bullseye-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-debian11-12-3-local_12.3.2-545.23.08-1_amd64.deb"
            dpkg -i "$packages/nvidia-cuda/cuda-bullseye-$cuda_latest_ver.deb"
            cp -f /var/cuda-repo-debian11-12-3-local/cuda-*-keyring.gpg /usr/share/keyrings/
            add-apt-repository -y contrib
            ;;
        3)
            wget --show progress -cqO "$packages/nvidia-cuda/cuda-bookworm-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-debian12-12-3-local_12.3.2-545.23.08-1_amd64.deb"
            dpkg -i "$packages/nvidia-cuda/cuda-bookworm-$cuda_latest_ver.deb"
            cp -f /var/cuda-repo-debian12-12-3-local/cuda-*-keyring.gpg /usr/share/keyrings/
            add-apt-repository -y contrib
            ;;
        4)
            wget --show progress -cqO "$packages/nvidia-cuda/cuda-ubuntu2004.pin" "$cuda_pin_url/ubuntu2004/x86_64/cuda-ubuntu2004.pin"
            mv "$packages/nvidia-cuda/cuda-ubuntu2004.pin" /etc/apt/preferences.d/cuda-repository-pin-600
            wget --show progress -cqO "$packages/nvidia-cuda/cuda-focal-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-ubuntu2004-12-3-local_12.3.2-545.23.08-1_amd64.deb"
            dpkg -i "$packages/nvidia-cuda/cuda-focal-$cuda_latest_ver.deb"
            cp -f /var/cuda-repo-ubuntu2004-12-3-local/cuda-*-keyring.gpg /usr/share/keyrings/
            ;;
        5)
            wget --show progress -cqO "$packages/nvidia-cuda/cuda-ubuntu2204.pin" "$cuda_pin_url/ubuntu2204/x86_64/cuda-ubuntu2204.pin"
            mv "$packages/nvidia-cuda/cuda-ubuntu2204.pin" /etc/apt/preferences.d/cuda-repository-pin-600
            wget --show progress -cqO "$packages/nvidia-cuda/cuda-jammy-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-ubuntu2204-12-3-local_12.3.2-545.23.08-1_amd64.deb"
            dpkg -i "$packages/nvidia-cuda/cuda-jammy-$cuda_latest_ver.deb"
            cp -f /var/cuda-repo-ubuntu2204-12-3-local/cuda-*-keyring.gpg /usr/share/keyrings/
            ;;
        6)
            wget --show progress -cqO "$packages/nvidia-cuda/cuda-wsl-ubuntu.pin" "$cuda_pin_url/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin"
            mv "$packages/nvidia-cuda/cuda-wsl-ubuntu.pin" /etc/apt/preferences.d/cuda-repository-pin-600
            wget --show progress -cqO "$packages/nvidia-cuda/cuda-wsl-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-wsl-ubuntu-12-3-local_12.3.2-1_amd64.deb"
            dpkg -i "$packages/nvidia-cuda/cuda-wsl-$cuda_latest_ver.deb"
            cp -f /var/cuda-repo-wsl-ubuntu-12-3-local/cuda-*-keyring.gpg /usr/share/keyrings/
            ;;
    7)
            git clone -q "https://gitlab.archlinux.org/archlinux/packaging/packages/cuda.git"
            cd cuda || exit 1
            makepkg -sif -C --needed --noconfirm
            ;;
    8)      exit_fn ;;
    *)
            unset choice
            cuda_download_fn
            ;;
    esac

    # UPDATE THE APT PACKAGES THEN INSTALL THE CUDA-SDK-TOOLKIT
    apt update
    apt install cuda-toolkit-12-3
}

# Function to detect the environment and check for an NVIDIA GPU
nvidia_gpu_check_fn() {
    # Check for NVIDIA GPU in native Linux
    if ! grep -qi microsoft /proc/version; then
        if lspci | grep -i nvidia > /dev/null; then
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
                    gpu_info=$("$dir/Windows/System32/cmd.exe" /c "wmic path win32_VideoController get name | findstr /i nvidia" 2>/dev/null)
                    
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

# REQUIRED GEFORCE CUDA DEVELOPMENT PACKAGES
install_cuda_fn() {
    local choice

    nvidia_gpu_check_fn
    fetch_and_parse_cuda_version

    echo "Checking GPU Status"
    echo "========================================================"

    amd_gpu_test=$(check_amd_gpu)
    echo "$amd_gpu_test"

    nvidia_gpu_status="$is_nvidia_gpu_present"
    nvidia_cuda_test="$cuda_version_test"

    # Determine if the PC has an Nvidia GPU available
    if [[ "$nvidia_gpu_status" == "NVIDIA GPU detected" ]]; then
        echo "Nvidia GPU detected"
        echo "Determining if CUDA is installed..."
        # Determine the installed CUDA version if any
        if [ -n "$nvidia_cuda_test" ]; then
            echo "The installed CUDA version is: $nvidia_cuda_test"
        else
            echo "CUDA is not installed"
        fi
        echo "The latest CUDA version available is: $cuda_latest_ver"
    else
        echo "Nvidia GPU not detected"
    fi

    if [[ "$amd_gpu_test" == "AMD GPU detected" ]] || [[ ! "$nvidia_cuda_test" == "$cuda_latest_ver" ]]; then
        if [[ -n "$nvidia_gpu_status" ]] || [[ -n "$(grep -i Microsoft /proc/version)" ]]; then
            get_os_version_1
            if [[ "$OS" == "Arch" ]]; then
                find_nvcc=$(find /opt/ -type f -name 'nvcc')
                cuda_ver_test=$($find_nvcc --version | sed -n 's/^.*release \([0-9]\+\.[0-9]\+\).*$/\1/p')
                cuda_ver_test+=".2"
            else
                cuda_ver_test="$nvidia_gpu_status"
            fi
            cuda_ver="$cuda_ver_test"

            if [[ -n "$cuda_ver_test" ]]; then
                printf "\n%s\n\n%s\n%s\n\n" \
                    "Do you want to update/reinstall CUDA?" \
                    "[1] Yes" \
                    "[2] No"
                read -p "Your choices are (1 or 2): " choice

                case "$choice" in
                    1)
                            cuda_download_fn
                            PATH="$PATH:$cuda_path"
                            export PATH
                            ;;
                    2)
                            PATH="$PATH:$cuda_path"
                            export PATH
                            ;;
                    *)
                            unset choice
                            install_cuda_fn
                            ;;
                esac
            else
                printf "\n%s\n%s\n\n%s\n%s\n\n" \
                    "The CUDA SDK Toolkit was not detected and the latest version is: $cuda_latest_ver" \
                    "=========================================================================" \
                    "[1] Install the CUDA SDK Toolkit and add it to your PATH." \
                    "[2] Continue without installing. (Hardware acceleration will be turned off)"
                read -p "Your choices are (1 or 2): " choice

                case "$choice" in
                    1)      cuda_download_fn ;;
                    2)      return ;;
                    *)
                            unset choice
                            install_cuda_fn
                            ;;
                esac
            fi

            if [[ "$OS" == "Arch" ]]; then
                find_nvcc=$(find /opt/ -type f -name "nvcc")
                cuda_ver_test=$($find_nvcc --version | sed -n "s/^.*release \([0-9]\+\.[0-9]\+\).*$/\1/p")
                cuda_ver_test+=".1"
            else
                cuda_ver_test=$(cat '/usr/local/cuda/version.json' 2>&1 | jq -r '.cuda.version')
            fi
            cuda_ver="$cuda_ver_test"

            if [[ -z "$cuda_ver" ]]; then
                fail_fn "Error: Unable to locate \"/usr/local/cuda/version.json\". (Line: $LINENO)"
            else
                export PATH="$PATH:$cuda_path"
            fi
        fi
    else
        gpu_flag=1
    fi
}

#
# REQUIRED BUILD PACKAGES
#

pkgs_fn() {
    local missing_pkg missing_packages pkg pkgs available_packages unavailable_packages

    openjdk_pkg=$(apt search --names-only '^openjdk-[0-9]+-jdk$' 2>/dev/null | grep -oP '^openjdk-\d+-jdk/' | sed 's|/||' | sort -rV | head -n1)
    libcpp_pkg=$(apt list libc++* 2>/dev/null | grep -Eo 'libc\+\+-[0-9\-]+-dev' | uniq | sort -rV | head -n1)
    libcppabi_pkg=$(apt list libc++abi* 2>/dev/null | grep -Eo 'libc\+\+abi-[0-9]+-dev' | uniq | sort -rV | head -n1)
    libunwind_pkg=$(apt list libunwind* 2>/dev/null | grep -Eo 'libunwind-[0-9]+-dev' | uniq | sort -rV | head -n1)

    # Define an array of apt package names
    pkgs=(
        $1 $libcppabi_pkg $libcpp_pkg $libunwind_pkg $openjdk_pkg ant apt asciidoc autoconf
        autoconf-archive automake autopoint binutils bison build-essential cargo cargo-c
        ccache checkinstall cmake curl doxygen fcitx-libs-dev flex flite1-dev freeglut3-dev
        frei0r-plugins-dev gawk gettext gimp-data git gnome-desktop-testing gnustep-gui-runtime
        google-perftools gperf gtk-doc-tools guile-3.0-dev help2man jq junit ladspa-sdk
        lib32stdc++6 libamd2 libasound2-dev libass-dev libaudio-dev libavfilter-dev libbabl-0.1-0
        libbluray-dev libbpf-dev libbs2b-dev libbz2-dev libc6 libc6-dev libcaca-dev libcairo2-dev
        libcamd2 libccolamd2 libcdio-dev libcdio-paranoia-dev libcdparanoia-dev libcholmod3 libdav1d-dev
        libchromaprint-dev libcjson-dev libcodec2-dev libcolamd2 libcrypto++-dev libcurl4-openssl-dev
        libdbus-1-dev libde265-dev libdevil-dev libdmalloc-dev libdrm-dev libdvbpsi-dev libebml-dev
        libegl1-mesa-dev libffi-dev libgbm-dev libgdbm-dev libgegl-0.4-0 libgegl-common libgimp2.0
        libgl1-mesa-dev libgles2-mesa-dev libglib2.0-dev libgme-dev libgmock-dev libgnutls28-dev
        libgnutls30 libgoogle-perftools-dev libgoogle-perftools4 libgsm1-dev libgtest-dev libgvc6
        libibus-1.0-dev libiconv-hook-dev libintl-perl libjack-dev libjemalloc-dev  libjxl-dev
        libladspa-ocaml-dev libleptonica-dev liblz-dev liblzma-dev liblzo2-dev libmathic-dev
        libmatroska-dev libmbedtls-dev libmetis5 libmfx-dev libmodplug-dev libmp3lame-dev
        libmusicbrainz5-dev libmysofa-dev libnuma-dev libopencore-amrnb-dev libopencore-amrwb-dev
        libopencv-dev libopenmpt-dev libopus-dev libpango1.0-dev libperl-dev
        libpstoedit-dev libpulse-dev librabbitmq-dev libraqm-dev libraw-dev librsvg2-dev librubberband-dev
        librust-gstreamer-base-sys-dev libshine-dev libsmbclient-dev libsnappy-dev libsndfile1-dev
        libsndio-dev libsoxr-dev libspeex-dev libsqlite3-dev libssh-dev libssl-dev libsuitesparseconfig5
        libsystemd-dev libtalloc-dev libtheora-dev libticonv-dev libtool libtool-bin libtwolame-dev
        libudev-dev libumfpack5 libv4l-dev libva-dev libvdpau-dev libvidstab-dev libvlccore-dev
        libvo-amrwbenc-dev libvpx-dev libx11-dev libxcursor-dev libxext-dev libxfixes-dev libxi-dev
        libxkbcommon-dev libxrandr-dev libxss-dev libxvidcore-dev libzimg-dev libzmq3-dev libzstd-dev
        libzvbi-dev libzzip-dev llvm lshw lzma-dev m4 mesa-utils meson nasm ninja-build pandoc python3
        python3-pip python3-venv ragel re2c scons texi2html texinfo tk-dev unzip valgrind wget xmlto
        zlib1g-dev
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
    if [[ "${#unavailable_packages[@]}" -gt 0 ]]; then
        echo "Unavailable packages: ${unavailable_packages[*]}"
    fi

    # Install available missing packages
    if [[ "${#available_packages[@]}" -gt 0 ]]; then
        echo "Installing available missing packages: ${available_packages[*]}"
        apt install "${available_packages[@]}"
        echo
    else
        printf "%s\n\n" "No missing packages to install or all missing packages are unavailable."
    fi
}

fix_missing_x265_lib() {
    if [[ ! -f "/usr/lib/x86_64-linux-gnu/libstdc++.so" ]] && [[ -f "/usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.30" ]]; then
        echo "$ ln -sf /usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.30 /usr/lib/x86_64-linux-gnu/libstdc++.so"
        ln -sf "/usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.30" "/usr/lib/x86_64-linux-gnu/libstdc++.so"
    fi
}

x265_fix_libs_fn() {
    local x265_libs x265_libs_trim
fix_
    x265_libs=$(find "$workspace/lib/" -type f -name 'libx265.so.*')
    x265_libs_trim=$(echo "$x265_libs" | sed "s:.*/::" | head -n1)

    case "$OS" in
        Arch)
                    cp -f "$x265_libs" "/usr/lib"
                    ln -sf "/usr/lib/$x265_libs_trim" "/usr/lib/libx265.so"
                    ;;
        *)
                    cp -f "$x265_libs" "/usr/lib/x86_64-linux-gnu"
                    ln -sf "/usr/lib/x86_64-linux-gnu/$x265_libs_trim" "/usr/lib/x86_64-linux-gnu/libx265.so"
                    ;;
    esac
}

fix_pulse_meson_build_file() {
    FILE_PATH="meson.build"

    # Replace the original pa_version_minor and pa_version_micro blocks
    sed -i "/pa_version_major = version_split\[0\].split('v')\[0\]/a \\
if version_split.length() > 1\\n  pa_version_minor = version_split[1]\\nelse\\n  pa_version_minor = '0'\\nendif" "$FILE_PATH"

    sed -i "/pa_version_minor = '0'/a \\
\\nif version_split.length() > 2\\n  pa_version_micro = version_split[2]\\nelse\\n  pa_version_micro = '0'\\nendif" "$FILE_PATH"

    # Remove the original pa_version_minor and pa_version_micro lines
    sed -i '/pa_version_minor = version_split\[1\]/d' "$FILE_PATH"
    sed -i '/pa_version_micro = version_split\[2\]/d' "$FILE_PATH"
}

libpulse_fix_libs_fn() {
    local pulse_version="$1"
    local libpulse_lib=$(find "$workspace/lib/" -type f -name 'libpulsecommon-*.so' | head -n1)
    local libpulse_trim=$(echo "$libpulse_lib" | sed 's:.*/::' | head -n1)

    if [[ "$OS" == "Arch" ]]; then
        if [[ ! -d "/usr/lib/pulseaudio" ]]; then
            mkdir -p "/usr/lib/pulseaudio"
        fi
    else
        if [[ ! -d "/usr/lib/x86_64-linux-gnu/pulseaudio" ]]; then
            mkdir -p "/usr/lib/x86_64-linux-gnu/pulseaudio"
        fi
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

ffmpeg_install_test() {
    local binaries i

binaries=("ffmpeg" "ffplay" "ffprobe")

    for i in ${binaries[@]}
    do
        if [[ ! -f "$install_dir/bin/$i" ]]; then
            printf "\n%s\n%s\n\n" \
                "Warning: Unable to locate the binary file: $install_dir/bin/$i" \
                "I have read online that this is a bug of some sort and people are unsure why it happens."
            read -p "You can press enter to continue, however, please be aware that it is missing."
            echo
        fi
    done
}

find_latest_nasm_version() {
    # URL of the NASM stable releases directory
    local url="https://www.nasm.us/pub/nasm/stable/"
    
    # Fetch the HTML, extract links, sort them, and get the last one
    local latest_version=$(curl -s $url | grep -oP 'nasm-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.xz)' | sort -V | tail -n 1)
    
    if [ -z "$latest_version" ]; then
        echo "Failed to find the latest NASM version."
        return 1
    fi

    # Print the version and download link without additional messages
    echo "$latest_version"
}

# To use the function and store its result in a variable:
latest_nasm_version=$(find_latest_nasm_version)

get_openssl_version() {
    g_ver="$(curl -s "https://www.openssl.org/source/" | grep -oP 'openssl-3.1.[0-9]+.tar.gz' | sort -V | tail -1 | grep -oP '3.1.[0-9]+')"
}

# PATCH FUNCTIONS
patch_ffmpeg_fn() {
    execute curl -LsSo "mathops.patch" "https://raw.githubusercontent.com/slyfox1186/ffmpeg-build-script/main/patches/mathops.patch"
    execute patch -d "libavcodec/x86" -i "../../mathops.patch"
}

# ARCHLINUX FUNCTION SECTION
apache_ant_fn() {
    if build "apache-ant" "git"; then
        download_git "https://aur.archlinux.org/apache-ant-contrib.git" "apache-ant-AUR"
        execute makepkg -sif --cleanbuild --noconfirm --needed
        build_done "apache-ant" "git"
    fi
}

librist_arch_fn() {
    if build "librist" "git"; then
        download_git "https://aur.archlinux.org/librist.git" "librist-AUR"
        execute makepkg -sif --cleanbuild --noconfirm --needed
        build_done "librist" "git"
    fi
}

arch_os_ver_fn() {
    local arch_pkgs pkg

    arch_pkgs=(
        av1an bluez-libs clang cmake dav1d devil docbook5-xml flite gdb gettext git gperf
        gperftools jdk17-openjdk ladspa jq libde265 libjpeg-turbo libjxl libjpeg6-turbo libmusicbrainz5
        libnghttp2 libwebp libyuv meson nasm ninja numactl opencv pd perl-datetime texlive-basic
        texlive-binextra tk valgrind webp-pixbuf-loader xterm yasm
    )

    # Check for Pacman lock file and if Pacman is running
    if [[ -f "/var/lib/pacman/db.lck" ]]; then
        echo "Pacman lock file found. Checking if Pacman is running..."
        while pgrep -x pacman > /dev/null; do
            echo "Pacman is currently running. Waiting for it to finish..."
            sleep 5
        done
        
        if ! pgrep -x pacman > /dev/null; then
            echo "Pacman is not running. Removing stale lock file..."
            sudo rm "/var/lib/pacman/db.lck"
        fi
    fi

    for pkg in "${arch_pkgs[@]}"
    do
        echo "Installing $pkg..."
        sudo pacman -Sq --needed --noconfirm $pkg 2>&1
    done

    # Set the path for the Python virtual environment
    local venv_path="$workspace/python_virtual_environment/arch_os"

    # Python packages to install
    local python_packages=("DateTime" "Sphinx" "wheel")

    # Call the function to setup Python venv and install packages
    setup_python_venv_and_install_packages "$venv_path" "${python_packages[@]}"
}


debian_os_ver_fn() {
    if [[ "$2" = "yes_wsl" ]]; then
        VER="msft"
        debian_wsl_pkgs="$1"
    fi

    debian_pkgs="cppcheck libnvidia-encode1 libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev libyuv-utils libyuv0 libhwy-dev libsrt-gnutls-dev libyuv-dev"
    debian_pkgs+=" libsharp-dev libdmalloc5 libumfpack5 libsuitesparseconfig5 libcolamd2 libcholmod3 libccolamd2 libcamd2 libamd2"

    case "$VER" in
        msft)               pkgs_fn $debian_wsl_pkgs $debian_pkgs librist-dev ;;
        12|trixie|sid)      pkgs_fn $1 $debian_pkgs librist-dev ;;
        11)                 pkgs_fn $1 $debian_pkgs ;;
        *)                  fail_fn "Error: Could not detect the Debian release version. (Line: $LINENO)" ;;
    esac
}

ubuntu_os_ver_fn() {
    if [[ "$2" = "yes_wsl" ]]; then
        VER="msft"
        ubuntu_wsl_pkgs="$1"
    fi

    ubuntu_common_pkgs="cppcheck libumfpack5 libsuitesparseconfig5 libcolamd2 libcholmod3 libccolamd2 libcamd2 libamd2"
    focal_pkgs="libvmmalloc1 libvmmalloc-dev libdmalloc5 libcunit1-dev nvidia-utils-535 librust-jemalloc-sys-dev"
    focal_pkgs+=" librust-malloc-buf-dev libsrt-doc libreadline-dev libcunit1 libcunit1-doc libhwy-dev libsrt-gnutls-dev libyuv-dev"
    jammy_pkgs="libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev libmimalloc-dev libtbbmalloc2 librust-jemalloc-sys-dev librust-malloc-buf-dev"
    jammy_pkgs+=" liblz4-dev libsrt-doc libreadline-dev libpipewire-0.3-dev libwayland-dev libdecor-0-dev libpsl-dev libacl1-dev"
    lunar_kenetic_pkgs="libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev librist-dev libjxl-dev libhwy-dev libsrt-gnutls-dev libyuv-dev"
    mantic_pkgs="libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev libhwy-dev libsrt-gnutls-dev libyuv-dev"

    case "$VER" in
        23.10)          pkgs_fn $1 $mantic_pkgs $lunar_kenetic_pkgs $jammy_pkgs $focal_pkgs ;;
        23.04|22.10)    pkgs_fn $1 $ubuntu_common_pkgs $lunar_kenetic_pkgs $jammy_pkgs ;;
        22.04|msft)     pkgs_fn $1 $ubuntu_common_pkgs $ubuntu_wsl_pkgs $jammy_pkgs ;;
        20.04)          pkgs_fn $1 $ubuntu_common_pkgs $ubuntu_wsl_pkgs $focal_pkgs ;;
        *)              fail_fn "Error: Could not detect the Ubuntu release version. (Line: $LINENO)" ;;
    esac
}

#
# TEST THE OS AND ITS VERSION
#

find_lsb_release=$(find /usr/bin/ -type f -name 'lsb_release')

get_os_version_1() {
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
        fail_fn "Error: Failed to define \"\$OS\" and/or \"\$VER\". (Line: $LINENO)"
    fi

    nvidia_utils_ver=$(apt list nvidia-utils-* 2>/dev/null | grep -Eo '^nvidia-utils-[0-9]{3}' | sort -rV | uniq | head -n1)
    nvidia_encode_var=$(apt list libnvidia-encode* 2>&1 | grep -Eo 'libnvidia-encode-[0-9]{3}' | sort -rV | head -n1)
}
get_os_version_1

#
# CHECK IF RUNNING WINDOWS WSL2
#

get_os_version_2() {
    if [[ $(grep -i "Microsoft" /proc/version) ]]; then
        wsl_flag="yes_wsl"
        OS="WSL2"
        wsl_common_pkgs="cppcheck libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev libyuv-utils libyuv0 libsharp-dev libdmalloc5 libnvidia-encode1 nvidia-smi"
    fi
}
get_os_version_2

#
# INSTALL REQUIRED APT PACKAGES
#

printf "%s\n%s\n%s\n" \
    "Installing the required APT packages" \
    "========================================================" \
    "Checking installation status of each package..."

case "$OS" in
    Arch)           arch_os_ver_fn ;;
    Debian|n/a)     debian_os_ver_fn "$nvidia_encode_var $nvidia_utils_ver" ;;
    Ubuntu)         ubuntu_os_ver_fn "$nvidia_encode_var $nvidia_utils_ver" ;;
    WSL2)           get_os_version_1
                    case "$OS" in
                        Debian|n/a)     debian_os_ver_fn "$nvidia_encode_var $nvidia_utils_ver $wsl_common_pkgs" "$wsl_flag" ;;
                        Ubuntu)         ubuntu_os_ver_fn "$nvidia_encode_var $nvidia_utils_ver $wsl_common_pkgs" "$wsl_flag" ;;
                    esac
                    ;;
esac

# SET THE JAVA VARIABLES
path_fn
locate_java=$(find /usr/lib/jvm/ -type d -name 'java-*-openjdk*' | sort -rV | head -n1)
java_include=$(find /usr/lib/jvm/ -type f -name 'javac' | sort -rV | head -n1 | xargs dirname | sed 's/bin/include/')
CPPFLAGS+=" -I$java_include"
export CPPFLAGS
export JDK_HOME="$locate_java"
export JAVA_HOME="$locate_java"
export PATH="$PATH:$JAVA_HOME/bin"

ant_path_fn() {
    export ANT_HOME="$workspace/ant"
    if [[ ! -d "$workspace/ant/bin" ]] || [[ ! -d "$workspace/ant/lib" ]]; then
        mkdir -p "$workspace/ant/bin" "$workspace/ant/lib" 2>/dev/null
    fi
}

# Check if the cuda folder exists to determine installation status
case "$OS" in
    Arch)   iscuda=$(find /opt/cuda* -type f -name 'nvcc' 2>/dev/null)
            cuda_path=$(find /opt/cuda* -type f -name 'nvcc' 2>/dev/null | grep -Eo '^.*/bin?')
            ;;
    *)      iscuda=$(find /usr/local/cuda* -type f -name 'nvcc' 2>/dev/null)
            cuda_path=$(find /usr/local/cuda* -type f -name 'nvcc' 2>/dev/null | grep -Eo '^.*/bin?')
            ;;
esac

# Prompt the user to install the geforce cuda sdk-toolkit
install_cuda_fn

# Update the ld linker search paths
ldconfig

# INSTALL THE GLOBAL TOOLS
echo
box_out_banner_global() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
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

# Alert the user that an amd gpu was found without a geforce gpu present
if [[ "$gpu_flag" -eq 1 ]]; then
    printf "\n%s\n" "AMD GPU detected without a GeForce GPU present."
fi

if build "m4" "latest"; then
    download "https://ftp.gnu.org/gnu/m4/m4-latest.tar.xz"
    execute ./configure --prefix="$workspace" \
                        --{build,host,target}="$pc_type" \
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
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        M4="$workspace/bin/m4"
    execute make "-j$cpu_threads"
    execute make install
    build_done "autoconf" "latest"
fi

if [[ "$OS" == "Arch" ]]; then
    if build "libtool" "$lt_ver"; then
        pacman -Sq --needed --noconfirm libtool
        build_done "libtool" "$lt_ver"
    fi
else
    get_os_version_2
    if [[ "$VER" = "WSL2" ]]; then
        lt_ver=2.4.6
    else
        get_os_version_1
        case "$VER" in
            12|23.10|23.04)     lt_ver=2.4.7 ;;
            *)                  lt_ver=2.4.6 ;;
        esac
    fi
    if build "libtool" "$lt_ver"; then
        download "https://ftp.gnu.org/gnu/libtool/libtool-$lt_ver.tar.xz"
        execute ./configure --prefix="$workspace" \
                            --{build,host}="$pc_type" \
                            --with-pic \
                            M4="$workspace/bin/m4"
        execute make "-j$cpu_threads"
        execute make install
        build_done "libtool" "$lt_ver"
    fi
fi

if build "pkg-config" "0.29.2"; then
    download "https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
    execute autoconf
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --enable-silent-rules \
                        --with-pc-path="$PKG_CONFIG_PATH"
    execute make "-j$cpu_threads"
    execute make install
    build_done "pkg-config" "0.29.2"
fi

find_git_repo "mesonbuild/meson" "1" "T"
if build "meson" "$g_ver"; then
    download "https://github.com/mesonbuild/meson/archive/refs/tags/$g_ver.tar.gz" "meson-$g_ver.tar.gz"
    execute python3 setup.py build
    execute python3 setup.py install --prefix="$workspace"
    build_done "meson" "$g_ver"
fi

if [[ "$OS" == "Arch" ]]; then
    librist_arch_fn
else
    find_git_repo "816" "2" "T"
    if build "librist" "$g_ver1"; then
        download "https://code.videolan.org/rist/librist/-/archive/v$g_ver1/librist-v$g_ver1.tar.bz2" "librist-$g_ver1.tar.bz2"
        execute meson setup build --prefix="$workspace" \
                                  --buildtype=release \
                                  --default-library=static \
                                  --strip \
                                  -Dstatic_analyze=false \
                                  -Dtest=false
        execute ninja "-j$cpu_threads" -C build
        execute ninja -C build install
        build_done "librist" "$g_ver1"
    fi
fi

find_git_repo "madler/zlib" "1" "T"
if build "zlib" "$g_ver"; then
    download "https://github.com/madler/zlib/releases/download/v$g_ver/zlib-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace"
    execute make "-j$cpu_threads"
    execute make install
    build_done "zlib" "$g_ver"
fi

get_openssl_version
if build "openssl" "$g_ver"; then
    download "https://www.openssl.org/source/openssl-$g_ver.tar.gz"
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
    execute make install_sw
    execute make install_fips
    build_done "openssl" "$g_ver"
fi
ffmpeg_libraries+=("--enable-openssl")

find_git_repo "yasm/yasm" "1" "T"
if build "yasm" "$g_ver"; then
    download "https://github.com/yasm/yasm/archive/refs/tags/v$g_ver.tar.gz" "yasm-$g_ver.tar.gz"
    execute autoreconf -fi
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "yasm" "$g_ver"
fi

if build "nasm" "$latest_nasm_version"; then
    find_latest_nasm_version
    download "https://www.nasm.us/pub/nasm/stable/nasm-$latest_nasm_version.tar.xz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host,target}="$pc_type" \
                        --disable-pedantic \
                        --enable-ccache
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
    if build "libxml2" "$g_ver"; then
        download "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$g_ver/libxml2-v$g_ver.tar.bz2" "libxml2-$g_ver.tar.bz2"
        CFLAGS+=" -DNOLIBTOOL"
        execute ./autogen.sh
        execute cmake -B build \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release \
                      -DBUILD_SHARED_LIBS=OFF \
                      -G Ninja -Wno-dev
        execute ninja "-j$cpu_threads" -C build
        execute ninja -C build install
        build_done "libxml2" "$g_ver"
    fi
    ffmpeg_libraries+=("--enable-libxml2")
fi

find_git_repo "/glennrp/libpng" "1" "T"
if build "libpng" "$g_ver"; then
    download "https://github.com/glennrp/libpng/archive/refs/tags/v$g_ver.tar.gz" "libpng-$g_ver.tar.gz"
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --enable-hardware-optimizations=yes \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install-header-links install-library-links install
    build_done "libpng" "$g_ver"
fi

find_git_repo "4720790" "3" "T"
if build "libtiff" "$g_ver"; then
    download "https://gitlab.com/libtiff/libtiff/-/archive/v$g_ver/libtiff-v$g_ver.tar.bz2" "libtiff-$g_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-docs \
                        --disable-sphinx \
                        --disable-tests \
                        --enable-cxx \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "libtiff" "$g_ver"
fi

find_git_repo "nkoriyama/aribb24" "1" "T"
if build "aribb24" "$g_ver"; then
    download "https://github.com/nkoriyama/aribb24/archive/refs/tags/v$g_ver.tar.gz" "aribb24-$g_ver.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-shared \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "aribb24" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libaribb24")

find_git_repo "7950" "4"
g_ver="${g_ver#VER-}"
g_ver1="${g_ver//-/.}"
if build "freetype" "$g_ver1"; then
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/VER-$g_ver/freetype-VER-$g_ver.tar.bz2" "freetype-$g_ver1.tar.bz2"
    extracmds=("-D"{harfbuzz,png,bzip2,brotli,zlib,tests}"=disabled")
    execute ./autogen.sh
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "freetype" "$g_ver1"
fi
ffmpeg_libraries+=("--enable-libfreetype")

find_git_repo "890" "4"
if build "fontconfig" "$g_ver"; then
    download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$g_ver/fontconfig-$g_ver.tar.bz2"
    extracmds=("--disable-"{docbook,docs,nls,shared})
    LDFLAGS+=" -DLIBXML_STATIC"
    sed -i "s|Cflags:|& -DLIBXML_STATIC|" "fontconfig.pc.in"
    execute ./autogen.sh --noconf
    execute autoupdate
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        "${extracmds[@]}" \
                        --enable-iconv \
                        --enable-static \
                        --with-arch=$(uname -m) \
                        --with-libiconv-prefix=/usr
    execute make "-j$cpu_threads"
    execute make install
    build_done "fontconfig" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libfontconfig")

# UBUNTU BIONIC FAILS TO BUILD XML2
if [[ "$VER" != "18.04" ]]; then
    find_git_repo "harfbuzz/harfbuzz" "1" "T"
    if build "harfbuzz" "$g_ver"; then
        download "https://github.com/harfbuzz/harfbuzz/archive/refs/tags/$g_ver.tar.gz" "harfbuzz-$g_ver.tar.gz"
        extracmds=("-D"{benchmark,cairo,docs,glib,gobject,icu,introspection,tests}"=disabled")
        execute ./autogen.sh
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
        execute ninja "-j$cpu_threads" -C build
        execute ninja -C build install
        build_done "harfbuzz" "$g_ver"
    fi
fi

git_call_fn "https://github.com/fribidi/c2man.git" "c2man-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
    execute ./Configure -desO \
                        -D bash=$(type -P bash) \
                        -D bin="$workspace/bin" \
                        -D cc="/usr/bin/cc" \
                        -D d_gnu="/usr/lib/x86_64-linux-gnu" \
                        -D find=$(type -P find) \
                        -D gcc="/usr/bin/gcc" \
                        -D gzip=$(type -P gzip) \
                        -D installmansrc="$workspace/share/man" \
                        -D ldflags="$LDFLAGS" \
                        -D less=$(type -P less) \
                        -D libpth="/usr/lib64 /usr/lib /lib64 /lib" \
                        -D locincpth="$workspace/include /usr/local/include /usr/include" \
                        -D loclibpth="$workspace/lib /usr/local/lib64 /usr/local/lib" \
                        -D make=$(type -P make) \
                        -D more=$(type -P more) \
                        -D osname="$OS" \
                        -D perl=$(type -P perl) \
                        -D prefix="$workspace" \
                        -D privlib="$workspace/lib/c2man" \
                        -D privlibexp="$workspace/lib/c2man" \
                        -D sleep=$(type -P sleep) \
                        -D tail=$(type -P tail) \
                        -D tar=$(type -P tar) \
                        -D tr=$(type -P tr) \
                        -D troff=$(type -P troff) \
                        -D uniq=$(type -P uniq) \
                        -D uuname=$(uname -s) \
                        -D vi=$(type -P vi) \
                        -D yacc=$(type -P yacc)
    execute make depend
    execute make "-j$cpu_threads"
    execute make install
    build_done "$repo_name" "$version"
fi

find_git_repo "fribidi/fribidi" "1" "T"
if build "fribidi" "$g_ver"; then
    download "https://github.com/fribidi/fribidi/archive/refs/tags/v$g_ver.tar.gz" "fribidi-$g_ver.tar.gz"
    extracmds=("-D"{docs,tests}"=false")
    execute autoreconf -fi
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "fribidi" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libfribidi")

find_git_repo "libass/libass" "1" "T"
if build "libass" "$g_ver"; then
    download "https://github.com/libass/libass/archive/refs/tags/$g_ver.tar.gz" "libass-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "libass" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libass")

find_git_repo "freeglut/freeglut" "1" "T"
if build "freeglut" "$g_ver"; then
    download "https://github.com/freeglut/freeglut/releases/download/v$g_ver/freeglut-$g_ver.tar.gz"
    CFLAGS+=" -DFREEGLUT_STATIC"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DFREEGLUT_BUILD_SHARED_LIBS=OFF \
                  -DFREEGLUT_BUILD_STATIC_LIBS=ON \
                  -DFREEGLUT_PRINT_ERRORS=OFF \
                  -DFREEGLUT_PRINT_WARNINGS=OFF \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "freeglut" "$g_ver"
fi

git_call_fn "https://chromium.googlesource.com/webm/libwebp" "libwebp-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
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
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi
ffmpeg_libraries+=("--enable-libwebp")

find_git_repo "google/highway" "1" "T"
if build "libhwy" "$g_ver"; then
    download "https://github.com/google/highway/archive/refs/tags/$g_ver.tar.gz" "libhwy-$g_ver.tar.gz"
    CFLAGS+=" -DHWY_COMPILE_ALL_ATTAINABLE"
    CXXFLAGS+=" -DHWY_COMPILE_ALL_ATTAINABLE"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DHWY_ENABLE_TESTS=OFF \
                  -DBUILD_TESTING=OFF \
                  -DHWY_ENABLE_EXAMPLES=OFF \
                  -DHWY_FORCE_STATIC_LIBS=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "libhwy" "$g_ver"
fi

find_git_repo "google/brotli" "1" "T"
if build "brotli" "$g_ver"; then
    download "https://github.com/google/brotli/archive/refs/tags/v$g_ver.tar.gz" "brotli-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DBUILD_TESTING=OFF \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "brotli" "$g_ver"
fi

find_git_repo "mm2/Little-CMS" "1" "T"
if build "lcms2" "$g_ver"; then
    download "https://github.com/mm2/Little-CMS/archive/refs/tags/lcms$g_ver.tar.gz" "lcms2-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --with-pic \
                        --with-threaded
    execute make "-j$cpu_threads"
    execute make install
    build_done "lcms2" "$g_ver"
fi
ffmpeg_libraries+=("--enable-lcms2")

find_git_repo "gflags/gflags" "1" "T"
if build "gflags" "$g_ver"; then
    download "https://github.com/gflags/gflags/archive/refs/tags/v$g_ver.tar.gz" "gflags-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_gflags_LIB=ON \
                  -DBUILD_STATIC_LIBS=ON \
                  -DINSTALL_HEADERS=ON \
                  -DREGISTER_BUILD_DIR=ON \
                  -DREGISTER_INSTALL_PREFIX=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "gflags" "$g_ver"
fi

git_call_fn "https://github.com/KhronosGroup/OpenCL-SDK.git" "opencl-sdk-git" "recurse"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
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
            -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi

find_git_repo "DanBloomberg/leptonica" "1" "T"
g_ver="${g_ver//Leptonica version /}"
if build "leptonica" "$g_ver"; then
    download "https://github.com/DanBloomberg/leptonica/archive/refs/tags/$g_ver.tar.gz" "leptonica-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "leptonica" "$g_ver"
fi

find_git_repo "tesseract-ocr/tesseract" "1" "T"
if build "tesseract" "$g_ver"; then
    download "https://github.com/tesseract-ocr/tesseract/archive/refs/tags/$g_ver.tar.gz" "tesseract-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-doc \
                        --with-extra-includes="$workspace/include" \
                        --with-extra-libraries="$workspace/lib" \
                        --with-pic \
                        --without-archive \
                        --without-curl
    execute make "-j$cpu_threads"
    execute make install
    build_done "tesseract" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libtesseract")

git_call_fn "https://github.com/imageMagick/jpeg-turbo.git" "jpeg-turbo-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
    execute cmake -S . \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DENABLE_SHARED=ON \
                  -DENABLE_STATIC=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads"
    execute ninja "-j$cpu_threads" install
    save_version=build_done "$repo_name" "$version"
    build_done "$repo_name" "$version"
fi

git_call_fn "https://github.com/m-ab-s/rubberband.git" "rubberband-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
    execute make "-j$cpu_threads" PREFIX="$workspace" install-static
    build_done "$repo_name" "$version"
fi
ffmpeg_libraries+=("--enable-librubberband")

find_git_repo "c-ares/c-ares" "1" "T"
g_ver="${g_ver//c-ares-/}"
g_tag="${g_ver//_/\.}"
if build "c-ares" "$g_tag"; then
    download "https://github.com/c-ares/c-ares/archive/refs/tags/cares-$g_ver.tar.gz" "c-ares-$g_ver.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-debug \
                        --disable-warnings \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "c-ares" "$g_tag"
fi

git_call_fn "https://github.com/lv2/lv2.git" "lv2-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
    extracmds=("-D"{docs,tests}"=disabled")
    case "$VER" in
        10|11)      lv2_switch=enabled ;;
        *)          lv2_switch=disabled ;;
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
                              -Dplugins="$lv2_switch" \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi

find_git_repo "7131569" "3" "T"
g_ver="${g_ver//waf-/}"
if build "waflib" "$g_ver"; then
    download "https://gitlab.com/ita1024/waf/-/archive/waf-$g_ver/waf-waf-$g_ver.tar.bz2" "waflib-$g_ver.tar.bz2"
    build_done "waflib" "$g_ver"
fi

find_git_repo "5048975" "3" "T"
if build "serd" "$g_ver"; then
    download "https://gitlab.com/drobilla/serd/-/archive/v$g_ver/serd-v$g_ver.tar.bz2" "serd-$g_ver.tar.bz2"
    extracmds=("-D"{docs,tests}"=disabled")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              -Dstatic=true \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "serd" "$g_ver"
fi

find_git_repo "pcre2project/pcre2" "1" "T"
g_ver="${g_ver//2-/}"
target_url="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$tag_urls/pcre2-$tag_urls.tar.gz"
if build "pcre2" "$g_ver"; then
    download "https://github.com/PCRE2Project/pcre2/archive/refs/tags/pcre2-$g_ver.tar.gz" "pcre2-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --enable-jit \
                        --enable-valgrind \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "pcre2" "$g_ver"
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
if build "sord" "$g_sver1"; then
    CFLAGS+=" -I$workspace/include/serd-0"
    download "https://gitlab.com/drobilla/sord/-/archive/$g_ver1/sord-$g_ver1.tar.bz2" "sord-$g_sver1.tar.bz2"
    extracmds=("-D"{docs,tests}"=disabled")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "sord" "$g_sver1"
fi

find_git_repo "11853194" "3" "T"
if build "sratom" "$g_ver"; then
    download "https://gitlab.com/lv2/sratom/-/archive/v$g_ver/sratom-v$g_ver.tar.bz2" "sratom-$g_ver.tar.bz2"
    extracmds=("-D"{docs,tests}"=disabled")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "sratom" "$g_ver"
fi

find_git_repo "11853176" "3" "T"
if build "lilv" "$g_ver"; then
    download "https://gitlab.com/lv2/lilv/-/archive/v$g_ver/lilv-v$g_ver.tar.bz2" "lilv-$g_ver.tar.bz2"
    extracmds=("-D"{docs,tests}"=disabled")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "lilv" "$g_ver"
fi
# CFLAGS+=" -I$workspace/include/lilv-0"
ffmpeg_libraries+=("--enable-lv2")

git_call_fn "https://github.com/gypified/libmpg123.git" "libmpg123-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
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
if build "jansson" "$g_ver"; then
    download "https://github.com/akheron/jansson/archive/refs/tags/v$g_ver.tar.gz" "jansson-$g_ver.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "jansson" "$g_ver"
fi

find_git_repo "jemalloc/jemalloc" "1" "T"
if build "jemalloc" "$g_ver"; then
    download "https://github.com/jemalloc/jemalloc/archive/refs/tags/$g_ver.tar.gz" "jemalloc-$g_ver.tar.gz"
    extracmds1=("--disable-"{debug,doc,fill,log,shared,prof,stats})
    extracmds2=("--enable-"{autogen,static,xmalloc})
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        "${extracmds1[@]}" \
                        "${extracmds2[@]}"
    execute make "-j$cpu_threads"
    execute make install
    build_done "jemalloc" "$g_ver"
fi

git_call_fn "https://github.com/jacklicn/cunit.git" "cunit-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "$repo_name" "$version"
fi

#
# INSTALL AUDIO TOOLS
#

echo
box_out_banner_audio() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
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

git_call_fn "https://github.com/libsdl-org/SDL.git" "sdl2-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
    execute cmake -S . -B build \
                       -DCMAKE_INSTALL_PREFIX="$workspace" \
                       -DCMAKE_BUILD_TYPE=Release \
                       -DBUILD_SHARED_LIBS=OFF \
                       -DSDL_ALSA_SHARED=OFF \
                       -DSDL_DISABLE_INSTALL_DOCS=ON \
                       -DSDL_CCACHE=ON \
                       -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi

find_git_repo "libsndfile/libsndfile" "1" "T"
if build "libsndfile" "$g_ver"; then
    download "https://github.com/libsndfile/libsndfile/releases/download/$g_ver/libsndfile-$g_ver.tar.xz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --enable-static \
                        --with-pic \
                        --with-pkgconfigdir="$workspace/lib/pkgconfig"
    execute make "-j$cpu_threads"
    execute make install
    build_done "libsndfile" "$g_ver"
fi

# find_git_repo "810" "4"
git_call_fn "https://gitlab.freedesktop.org/pulseaudio/pulseaudio.git" "pulseaudio-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
    fix_pulse_meson_build_file
    extracmds=("-D"{daemon,doxygen,ipv6,man,tests}"=false")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                               "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    libpulse_fix_libs_fn "${version//\$ /}"
    build_done "$repo_name" "$version"
fi
ffmpeg_libraries+=("--enable-libpulse")

find_git_repo "xiph/ogg" "1" "T"
if build "libogg" "$g_ver"; then
    download "https://github.com/xiph/ogg/archive/refs/tags/v$g_ver.tar.gz" "libogg-$g_ver.tar.gz"
    execute autoreconf -fi
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DBUILD_TESTING=OFF \
                  -DCPACK_BINARY_DEB=OFF \
                  -DCPACK_SOURCE_ZIP=OFF \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "libogg" "$g_ver"
fi

find_git_repo "xiph/flac" "1" "T"
if build "libflac" "$g_ver"; then
    download "https://github.com/xiph/flac/archive/refs/tags/$g_ver.tar.gz" "libflac-$g_ver.tar.gz"
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
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "libflac" "$g_ver"
fi

find_git_repo "mstorsjo/fdk-aac" "1" "T"
if build "libfdk-aac" "2.0.3"; then
    download "https://phoenixnap.dl.sourceforge.net/project/opencore-amr/fdk-aac/fdk-aac-2.0.3.tar.gz" "libfdk-aac-2.0.3.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "libfdk-aac" "2.0.3"
fi
ffmpeg_libraries+=("--enable-libfdk-aac")

find_git_repo "xiph/vorbis" "1" "T"
if build "vorbis" "$g_ver"; then
    download "https://github.com/xiph/vorbis/archive/refs/tags/v$g_ver.tar.gz" "vorbis-$g_ver.tar.gz"
    execute ./autogen.sh
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DOGG_INCLUDE_DIR="$workspace/include" \
                  -DOGG_LIBRARY="$workspace/lib/libogg.so" \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "vorbis" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libvorbis")

find_git_repo "xiph/opus" "1" "T"
if build "opus" "$g_ver"; then
    download "https://github.com/xiph/opus/archive/refs/tags/v$g_ver.tar.gz" "opus-$g_ver.tar.gz"
    execute autoreconf -fis
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DCPACK_SOURCE_ZIP=OFF \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "opus" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libopus")

find_git_repo "hoene/libmysofa" "1" "T"
if build "libmysofa" "$g_ver"; then
    download "https://github.com/hoene/libmysofa/archive/refs/tags/v$g_ver.tar.gz" "libmysofa-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DBUILD_STATIC_LIBS=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "libmysofa" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libmysofa")

find_git_repo "webmproject/libvpx" "1" "T"
if build "libvpx" "$g_ver"; then
    download "https://github.com/webmproject/libvpx/archive/refs/tags/v$g_ver.tar.gz" "libvpx-$g_ver.tar.gz"
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
    build_done "libvpx" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libvpx")

find_git_repo "8143" "6"
g_ver="${g_ver//debian\//}"
if build "opencore-amr" "${g_ver}"; then
    download "https://salsa.debian.org/multimedia-team/opencore-amr/-/archive/debian/${g_ver}/opencore-amr-debian-${g_ver}.tar.bz2" "opencore-amr-${g_ver}.tar.bz2"
    execute ./configure --prefix="${workspace}" \
                        --{build,host}="${pc_type}" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done "opencore-amr" "${g_ver}"
fi
ffmpeg_libraries+=("--enable-libopencore-"{amrnb,amrwb})

if build "liblame" "3.100"; then
    download "https://zenlayer.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz"
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-shared \
                        --disable-gtktest \
                        --enable-nasm \
                        --with-libiconv-prefix=/usr
    execute make "-j$cpu_threads"
    execute make install
    build_done "liblame" "3.100"
fi
ffmpeg_libraries+=("--enable-libmp3lame")

find_git_repo "xiph/theora" "1" "T"
if build "libtheora" "1.1.1"; then
    download "https://github.com/xiph/theora/archive/refs/tags/v1.1.1.tar.gz" "libtheora-1.1.1.tar.gz"
    execute ./autogen.sh
    sed "s/-fforce-addr//g" "configure" > "configure.patched"
    chmod +x configure.patched
    execute mv configure.patched configure
    execute rm config.guess
    execute curl -LsSo "config.guess" "https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess"
    chmod +x config.guess
    execute ./configure --prefix="$workspace" \
                        --{build,host,target}="$pc_type" \
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
ffmpeg_libraries+=("--enable-libtheora")

#
# INSTALL VIDEO TOOLS
#

echo
box_out_banner_video() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
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

# NEED TO UPDATE THIS REPO FROM TIME TO TIME MANUALLY
aom_ver=8a3dfd53958db24f0e29ed43275fe3379acd164e
aom_sver="${aom_ver::7}"
if build "av1" "$aom_sver"; then
    download "https://aomedia.googlesource.com/aom/+archive/$aom_ver.tar.gz" "av1-$aom_sver.tar.gz" "av1"
    mkdir -p "$packages/aom_build"
    cd "$packages/aom_build" || exit 1
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
                  -G Ninja -Wno-dev \
                  "$packages/av1"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "av1" "$aom_sver"
fi
ffmpeg_libraries+=("--enable-libaom")

# RAV1E FAILS TO BUILD ON UBUNTU BIONIC AND DEBIAN 11 BULLSEYE
if [[ "$VER" != "18.04" ]] && [[ "$VER" != "11" ]]; then
    find_git_repo "xiph/rav1e" "1" "T" "enabled"
    if build "rav1e" "$g_ver"; then
        install_rustc_fn
        check_and_install_cargo_c
        download "https://github.com/xiph/rav1e/archive/refs/tags/v$g_ver.tar.gz" "rav1e-$g_ver.tar.gz"
        rm -fr "$HOME/.cargo/registry/index/"* "$HOME/.cargo/.package-cache"
        execute cargo cinstall --prefix="$workspace" \
                               --library-type=staticlib \
                               --crt-static \
                               --release
        build_done "rav1e" "$g_ver"
    fi
    ffmpeg_libraries+=("--enable-librav1e")
fi

find_git_repo "AOMediaCodec/libavif" "1" "T"
if build "avif" "$g_ver"; then
    download "https://github.com/AOMediaCodec/libavif/archive/refs/tags/v$g_ver.tar.gz" "avif-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DAVIF_CODEC_AOM=ON \
                  -DAVIF_CODEC_AOM_DECODE=ON \
                  -DAVIF_CODEC_AOM_ENCODE=ON \
                  -DAVIF_ENABLE_GTEST=OFF \
                  -DAVIF_ENABLE_WERROR=OFF \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "avif" "$g_ver"
fi

git_call_fn "https://github.com/ultravideo/kvazaar.git" "kvazaar-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "$repo_name" "$version"
fi
ffmpeg_libraries+=("--enable-libkvazaar")

find_git_repo "76" "2" "T"
if build "libdvdread" "$g_ver1"; then
    download "https://code.videolan.org/videolan/libdvdread/-/archive/$g_ver1/libdvdread-$g_ver1.tar.bz2"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-apidoc \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "libdvdread" "$g_ver1"
fi

find_git_repo "363" "2" "T"
if build "udfread" "$g_ver1"; then
    download "https://code.videolan.org/videolan/libudfread/-/archive/$g_ver1/libudfread-$g_ver1.tar.bz2"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "udfread" "$g_ver1"
fi

if [[ "$OS" == "Arch" ]]; then
    apache_ant_fn
else
    ant_path_fn
    git_call_fn "https://github.com/apache/ant.git" "ant-git" "ant"
    if build "$repo_name" "${version//\$ /}"; then
        echo "Cloning \"$repo_name\" saving version \"$version\""
        download_git "$git_url"
        chmod 777 -R "$workspace/ant"
        execute sh build.sh install-lite
        build_done "$repo_name" "$version"
    fi
fi

# Ubuntu Jammy gives an error so use the APT version instead
if [[ ! "$OS" == "Ubuntu" ]]; then
    find_git_repo "206" "2" "T"
    if build "libbluray" "$g_ver1"; then
        download "https://code.videolan.org/videolan/libbluray/-/archive/$g_ver1/$g_ver1.tar.gz" "libbluray-$g_ver1.tar.gz"
        execute autoreconf -fi
        execute ./configure --prefix="$workspace" \
                            --{build,host}="$pc_type" \
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
        build_done "libbluray" "$g_ver1"
    fi
    ffmpeg_libraries+=("--enable-libbluray")
fi

find_git_repo "mediaarea/zenLib" "1" "T"
if build "zenlib" "$g_ver"; then
    download "https://github.com/MediaArea/ZenLib/archive/refs/tags/v$g_ver.tar.gz" "zenlib-$g_ver.tar.gz"
    cd Project/GNU/Library || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "zenlib" "$g_ver"
fi

find_git_repo "MediaArea/MediaInfoLib" "1" "T"
if build "mediainfo-lib" "$g_ver"; then
    download "https://github.com/MediaArea/MediaInfoLib/archive/refs/tags/v$g_ver.tar.gz" "mediainfo-lib-$g_ver.tar.gz"
    cd "Project/GNU/Library" || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "mediainfo-lib" "$g_ver"
fi

find_git_repo "MediaArea/MediaInfo" "1" "T"
if build "mediainfo-cli" "$g_ver"; then
    download "https://github.com/MediaArea/MediaInfo/archive/refs/tags/v$g_ver.tar.gz" "mediainfo-cli-$g_ver.tar.gz"
    cd Project/GNU/CLI || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --{build,host}="$pc_type" \
                        --enable-staticlibs \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done "mediainfo-cli" "$g_ver"
fi

find_git_repo "georgmartius/vid.stab" "1" "T"
if build "vid-stab" "$g_ver"; then
    download "https://github.com/georgmartius/vid.stab/archive/refs/tags/v$g_ver.tar.gz" "vid-stab-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DUSE_OMP=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "vid-stab" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libvidstab")

find_git_repo "dyne/frei0r" "1" "T"
if build "frei0r" "$g_ver"; then
    download "https://github.com/dyne/frei0r/archive/refs/tags/v$g_ver.tar.gz" "frei0r-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DWITHOUT_OPENCV=OFF \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "frei0r" "$g_ver"
fi
ffmpeg_libraries+=("--enable-frei0r")

if [[ "$OS" == "Arch" ]]; then
    find_git_repo "gpac/gpac" "1" "T"
    if build "gpac" "$g_ver"; then
        pacman -Sq --needed --noconfirm gpac
        build_done "gpac" "$g_ver"
    fi
else
    git_call_fn "https://github.com/gpac/gpac.git" "gpac-git"
    if build "$repo_name" "${version//\$ /}"; then
        echo "Cloning \"$repo_name\" saving version \"$version\""
        download_git "$git_url"
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
        build_done "$repo_name" "$version"
    fi
fi

# VERSIONS >= 1.4.0 BREAKS FFMPEG DURING THE BUILD
find_git_repo "24327400" "3" "T"
if build "svt-av1" "1.8.0"; then
    download "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v1.8.0/SVT-AV1-v1.8.0.tar.bz2" "svt-av1-1.8.0.tar.bz2"
    execute cmake -S . -B Build/linux \
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
                       -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C Build/linux
    execute ninja "-j$cpu_threads" -C Build/linux install
    cp -f "Build/linux/SvtAv1Enc.pc" "$workspace/lib/pkgconfig"
    cp -f "Build/linux/SvtAv1Dec.pc" "$workspace/lib/pkgconfig"
    build_done "svt-av1" "1.8.0"
fi
ffmpeg_libraries+=("--enable-libsvtav1")

find_git_repo "536" "2" "B"
g_sver="${g_ver::8}"
if build "x264" "$g_sver"; then
    download "https://code.videolan.org/videolan/x264/-/archive/$g_ver/x264-$g_ver.tar.bz2" "x264-$g_sver.tar.bz2"
    execute ./configure --prefix="$workspace" \
                        --host="$pc_type" \
                        --bit-depth="all" \
                        --chroma-format="all" \
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
    build_done "x264" "$g_sver"
fi
ffmpeg_libraries+=("--enable-libx264")

if build "x265" "3.5"; then
    fix_missing_x265_lib
    download "https://bitbucket.org/multicoreware/x265_git/downloads/x265_3.5.tar.gz" "x265-3.5.tar.gz"
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

    if [[ -n "$LDEXEFLAGS" ]]; then
        sed -i.backup "s/lgcc_s/lgcc_eh/g" "$workspace/lib/pkgconfig/x265.pc"
    fi

    # FIX THE x265 SHARED LIBRARY ISSUE
    x265_fix_libs_fn

    build_done "x265" "3.5"
fi
ffmpeg_libraries+=("--enable-libx265")

# Vaapi doesn"t work well with static links FFmpeg.
if [[ -z "$LDEXEFLAGS" ]]; then
    # If the libva development SDK is installed, enable vaapi.
    if library_exists "libva"; then
        if build "vaapi" "1"; then
            build_done "vaapi" "1"
        fi
        ffmpeg_libraries+=("--enable-vaapi")
    fi
fi

# GET THE NVIDIA GPU ARCHITECTURE TO BUILD CUDA
# https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards
[[ -n "$cuda_version_test" ]] || [[ "$wsl_flag" == "yes_wsl" ]] && gpu_arch_fn

if [[ "$cuda_compile_flag" -eq 1 ]]; then
    if [[ -n "$iscuda" ]]; then
        if build "nv-codec-headers" "12.1.14.0"; then
            download "https://github.com/FFmpeg/nv-codec-headers/releases/download/n12.1.14.0/nv-codec-headers-12.1.14.0.tar.gz"
            execute make "-j$cpu_threads"
            execute make PREFIX="$workspace" install
            build_done "nv-codec-headers" "12.1.14.0"
        fi

        get_os_version_1

        if [[ "$OS" == "Arch" ]]; then
            PATH+=":/opt/cuda/bin"
            export PATH
            CFLAGS+=" -I/opt/cuda/include -I/opt/cuda/targets/x86_64-linux/include"
            LDFLAGS+=" -L/opt/cuda/lib64 -L/opt/cuda/lib -L/opt/cuda/targets/x86_64-linux/lib"
        else
            CFLAGS+=" -I/usr/local/cuda/include"
            LDFLAGS+=" -L/usr/local/cuda/lib64"
        fi

        ffmpeg_libraries+=("--enable-"{cuda-nvcc,cuda-llvm,cuvid,nvdec,nvenc,ffnvcodec})

        if [[ -n "$LDEXEFLAGS" ]]; then
            ffmpeg_libraries+=("--enable-libnpp")
        fi
        ffmpeg_libraries+=("--nvccflags=-gencode arch=$gpu_arch")
    fi
else
    echo "The Active GPU is made by AMD and the Geforce CUDA SDK Toolkit will not be enabled."
fi

find_git_repo "Haivision/srt" "1" "T"
if build "srt" "$g_ver"; then
    download "https://github.com/Haivision/srt/archive/refs/tags/v$g_ver.tar.gz" "srt-$g_ver.tar.gz"
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
                  -G Ninja -Wno-dev
    execute ninja -C build "-j$cpu_threads"
    execute ninja -C build "-j$cpu_threads" install
    if [[ -n "$LDEXEFLAGS" ]]; then
        sed -i.backup "s/-lgcc_s/-lgcc_eh/g" "$workspace/lib/pkgconfig/srt.pc"
    fi
    build_done "srt" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libsrt")

find_git_repo "avisynth/avisynthplus" "1" "T"
if build "avisynth" "$g_ver"; then
    download "https://github.com/AviSynth/AviSynthPlus/archive/refs/tags/v$g_ver.tar.gz" "avisynth-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DHEADERS_ONLY=OFF
    execute make "-j$cpu_threads" -C build VersionGen install
    build_done "avisynth" "$g_ver"
fi
ffmpeg_libraries+=("--enable-avisynth")

# find_git_repo "vapoursynth/vapoursynth" "1" "T"
if build "vapoursynth" "R65"; then
    download "https://github.com/vapoursynth/vapoursynth/archive/refs/tags/R65.tar.gz" "vapoursynth-R65.tar.gz"

    venv_path="$workspace/python_virtual_environment/vapoursynth"
    venv_packages=("Cython==0.29.36")
    setup_python_venv_and_install_packages "$venv_path" "${venv_packages[@]}"

    # Activate the virtual environment for the build process
    source "$venv_path/bin/activate" || fail_fn "Failed to re-activate virtual environment"

    # Explicitly set the PYTHON environment variable to the virtual environment's Python
    export PYTHON="$venv_path/bin/python"

    # Assuming autogen, configure, make, and install steps for VapourSynth
    execute ./autogen.sh || fail_fn "Failed to execute autogen.sh"
    execute ./configure --prefix="$workspace" --disable-shared || fail_fn "Failed to configure"
    execute make -j"$cpu_threads" || fail_fn "Failed to make"
    execute make install || fail_fn "Failed to make install"
    
    # Deactivate the virtual environment after the build
    deactivate

    build_done "vapoursynth" "R65"
fi
ffmpeg_libraries+=("--enable-vapoursynth")

git_call_fn "https://chromium.googlesource.com/codecs/libgav1" "libgav1-git"
if build "$repo_name" "${version//\$ /}"; then
    echo "Cloning \"$repo_name\" saving version \"$version\""
    download_git "$git_url"
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
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi

find_git_repo "8268" "6"
g_ver="${g_ver//debian\/2%/}"
if build "xvidcore" "$g_ver"; then
    download "https://salsa.debian.org/multimedia-team/xvidcore/-/archive/debian/2%25$g_ver/xvidcore-debian-2%25$g_ver.tar.bz2" "xvidcore-$g_ver.tar.bz2"
    cd "build/generic" || exit 1
    execute ./bootstrap.sh
    execute ./configure --prefix="$workspace" --{build,host,target}="$pc_type"
    execute make "-j$cpu_threads"
    [[ -f "$workspace/lib/libxvidcore.so" ]] && rm "$workspace/lib/libxvidcore.so" "$workspace/lib/libxvidcore.so.4"
    execute make install
    build_done "xvidcore" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libxvid")

#
# IMAGE LIBRARIES
#

echo
box_out_banner_images() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
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
if build "libheif" "$g_ver"; then
    download "https://github.com/strukturag/libheif/archive/refs/tags/v$g_ver.tar.gz" "libheif-$g_ver.tar.gz"
    source_flags_fn
    CFLAGS="-g -O3 -fno-lto -pipe -march=native"
    CXXFLAGS="-g -O3 -fno-lto -pipe -march=native"
    export CFLAGS CXXFLAGS
    libde265_libs=$(find /usr/ -type f -name "libde265.so")
    if [[ -f "$libde265_libs" ]] && [[ ! -f "/usr/lib/x86_64-linux-gnu/libde265.so" ]]; then
        cp -f "$libde265_libs" "/usr/lib/x86_64-linux-gnu"
        chmod 755 "/usr/lib/x86_64-linux-gnu/libde265.so"
    fi
    case "$VER" in
        18.04|20.04)    pixbuf_switch="OFF" ;;
        *)              pixbuf_switch="ON" ;;
    esac
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DAOM_INCLUDE_DIR="$workspace/include" \
                  -DAOM_LIBRARY="$workspace/lib/libaom.a" \
                  -DLIBDE265_INCLUDE_DIR="$workspace/include" \
                  -DLIBDE265_LIBRARY=/usr/lib/x86_64-linux-gnu/libde265.so \
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
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    source_flags_fn
    build_done "libheif" "$g_ver"
fi

find_git_repo "uclouvain/openjpeg" "1" "T"
if build "openjpeg" "$g_ver"; then
    download "https://codeload.github.com/uclouvain/openjpeg/tar.gz/refs/tags/v$g_ver" "openjpeg-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DBUILD_TESTING=OFF \
                  -DBUILD_THIRDPARTY=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "openjpeg" "$g_ver"
fi
ffmpeg_libraries+=("--enable-libopenjpeg")

#
# BUILD FFMPEG
#

echo
box_out_banner_ffmpeg() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
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

curl -LsSo "$workspace/include/dxva2api.h" "https://download.videolan.org/pub/contrib/dxva2api.h"
cp -f "$workspace/include/dxva2api.h" "/usr/include"
curl -LsSo "$workspace/include/objbase.h" "https://raw.githubusercontent.com/wine-mirror/wine/master/include/objbase.h"
cp -f "$workspace/include/objbase.h" "$workspace"

if [[ -n "$ffmpeg_archive" ]]; then
    ff_cmd="ffmpeg-$ffmpeg_archive"
fi

# Get the latest FFmpeg version by parsing its repository
ffmpeg_version_check_fn "https://github.com/FFmpeg/FFmpeg.git" "3"
ffmpeg_ver="$ffmpeg_ver_check"
ffmpeg_archive="ffmpeg-$ffmpeg_ver.tar.gz"
ffmpeg_url="https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n6.1.1.tar.gz"

if [[ ! "$ffmpeg_ver_check" == "$ffmpeg_ver" ]]; then
    printf "\n%s\n%s\n%s\n" \
        "The FFmpeg version you are installing is: $ffmpeg_ver" \
        "The script detected a new version: $ffmpeg_ver_check" \
        "You can modify the variable \"ffmpeg_ver\" if desired to change versions."
fi

source_flags_fn

if build "ffmpeg" "$ffmpeg_ver"; then
    download $ffmpeg_url $ff_cmd
    if [[ "$OS" == "Arch" ]]; then
        patch_ffmpeg_fn
    fi

    mkdir build
    cd build || exit 1
    LDEXEFLAGS=-Wl,-rpath,\''$$ORIGIN/../lib'\' \
    LDSOFLAGS=-Wl,-rpath,\''$$$$ORIGIN'\' \
    ../configure --prefix="$install_dir" \
                 --arch=$(uname -m) \
                 --cc="$CC" \
                 --cxx="$CXX" \
                 --disable-debug \
                 --disable-doc \
                 --disable-large-tests \
                 --disable-shared \
                 "$ladspa_switch" \
                 "${ffmpeg_libraries[@]}" \
                 --enable-chromaprint \
                 --enable-gpl \
                 --enable-libbs2b \
                 --enable-libcaca \
                 --enable-libcdio \
                 --enable-libgme \
                 --enable-libmodplug \
                 --enable-libshine \
                 --enable-libsmbclient \
                 --enable-libsnappy \
                 --enable-libsoxr \
                 --enable-libspeex \
                 --enable-libssh \
                 --enable-libtwolame \
                 --enable-libv4l2 \
                 --enable-libvo-amrwbenc \
                 --enable-libzvbi \
                 --enable-lto \
                 --enable-nonfree \
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
fi

# MAKE SURE ALL OF THE FILES WERE COMPILED CORRECTLY
ffmpeg_install_test

# EXECUTE THE LDCONFIG COMMAND TO ENSURE THAT ALL LIBRARY CHANGES ARE DETECTED BY FFMPEG
ldconfig 2>/dev/null

# DISPLAY FFMPEG'S VERSION
if [[ -f "$install_dir/bin/ffmpeg" ]]; then
    ff_ver_fn
else
    fail_fn "Error: Failed to locate \"$install_dir/bin/ffmpeg\". (Line: $LINENO)"
fi

# PROMPT THE USER TO CLEAN UP THE BUILD FILES
cleanup_fn

# SHOW EXIT MESSAGE
exit_fn
