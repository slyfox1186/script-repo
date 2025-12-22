#!/usr/bin/env bash
# shellcheck disable=SC2034
set -o pipefail

# Script Version: 1.1.5
# Updated: 12.2.25
# GitHub: https://github.com/slyfox1186/imagemagick-build-script
# Purpose: Build ImageMagick 7 from the source code obtained from ImageMagick's official GitHub repository
# Supported OS: Debian (12|13) | Ubuntu (20|22|24).04

# Check if sudo is available for commands that need root
if ! command -v sudo &>/dev/null && [[ "$EUID" -ne 0 ]]; then
    echo "Warning: sudo is not available and you are not root. Some operations may fail."
fi

# SET GLOBAL VARIABLES
script_ver=1.1.5
cwd="$PWD/magick-build-script"
packages="$cwd/packages"
workspace="$cwd/workspace"
regex_string='(Rc|rc|rC|RC|alpha|beta|master|pre)+[0-9]*$'
debug=OFF

# Pre-defined color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ANNOUNCE THE BUILD HAS BEGUN
box_out_banner_header() {
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
box_out_banner_header "ImageMagick Build Script v$script_ver"

# CREATE OUTPUT DIRECTORIES
[[ ! -d "$packages" ]] && mkdir -p "$packages"
[[ ! -d "$workspace" ]] && mkdir -p "$workspace"

# SET THE COMPILERS TO USE AND THE COMPILER OPTIMIZATION FLAGS
CC="gcc"
CXX="g++"
CFLAGS="-O2 -fPIC -pipe -march=native -fstack-protector-strong"
CXXFLAGS="$CFLAGS"
CPPFLAGS="-I$workspace/include -I/usr/local/include -I/usr/include -D_FORTIFY_SOURCE=2"
LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,-rpath,/usr/local/lib64:/usr/local/lib"
export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS

# SET THE AVAILABLE CPU COUNT FOR PARALLEL PROCESSING (SPEEDS UP THE BUILD PROCESS)
if [[ -f /proc/cpuinfo ]]; then
    cpu_threads=$(grep -c ^processor /proc/cpuinfo)
else
    cpu_threads=$(nproc --all 2>/dev/null || true)
fi
[[ -z "$cpu_threads" || "$cpu_threads" -lt 1 ]] && cpu_threads=2

# Set the path variable
PATH="/usr/lib/ccache:$workspace/bin:$PATH"
export PATH

# Set the pkg_config_path variable
PKG_CONFIG_PATH="\
$workspace/lib64/pkgconfig:\
$workspace/lib/x86_64-linux-gnu/pkgconfig:\
$workspace/lib/pkgconfig:\
$workspace/share/pkgconfig:\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig\
"
export PKG_CONFIG_PATH

exit_fn() {
    echo
    echo -e "${GREEN}[INFO]${NC} Make sure to ${YELLOW}star${NC} this repository to show your support!"
    echo -e "${GREEN}[INFO]${NC} https://github.com/slyfox1186/script-repo"
    echo
    exit 0
}

fail() {
    echo
    echo -e "${RED}[ERROR]${NC} $1\n"
    echo -e "${GREEN}[INFO]${NC} For help or to report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    echo
    exit 1
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

use_root() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    elif command -v sudo &>/dev/null; then
        sudo "$@"
    else
        fail "sudo is not available and you are not root. Cannot run: $*"
    fi
}

safe_rm_rf() {
    local target="$1"

    [[ -z "$target" || "$target" == "/" ]] && fail "Refusing to remove unsafe path: \"$target\""
    [[ -e "$target" ]] || return 0

    case "$target" in
        "$cwd"|"$cwd"/*) ;;
        *) fail "Refusing to remove path outside build root: \"$target\"" ;;
    esac

    use_root rm -rf -- "$target"
}

cleanup() {
    local choice

    echo
    echo "========================================================"
    echo "       Would you like to clean up the build files?      "
    echo "========================================================"
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo

    read -rp "Your choices are (1 or 2): " choice

    case "${choice,,}" in
        1|y|yes) safe_rm_rf "$cwd" ;;
        2|n|no) ;;
        *) unset choice; cleanup ;;
    esac
}

execute() {
    echo "$ $*"
    local output

    if [[ "$debug" == "ON" ]]; then
        if ! output=$("$@"); then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail "Failed to execute: $*"
        fi
    else
        if ! output=$("$@" 2>&1); then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            echo "$output" >&2
            fail "Failed to execute: $*. Line: ${LINENO}"
        fi
    fi
}

build() {
    echo
    echo -e "${GREEN}Building ${YELLOW}$1${NC} - ${GREEN}version ${YELLOW}$2${NC}"
    echo "=========================================="

    if [[ -f "$packages/$1.done" ]]; then
        if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        fi
    fi
    return 0
}

build_done() {
    echo "$2" > "$packages/$1.done"
}

download() {
    local archive url output_dir target_file target_dir
    url="$1"
    archive="${2:-${url##*/}}"
    output_dir="$3"
    target_file="$packages/$archive"
    target_dir="$packages/${output_dir:-${archive%.tar*}}"

    if [[ ! -f "$target_file" ]]; then
        log "Downloading \"$url\" saving as \"$archive\""
        if ! curl -fLSso "$target_file" "$url"; then
            fail "Failed to download \"$archive\". Line: ${LINENO}"
        fi
    else
        log "The file \"$archive\" is already downloaded."
    fi

    [[ -d "$target_dir" ]] && safe_rm_rf "$target_dir"
    [[ ! -d "$target_dir" ]] && mkdir -p "$target_dir"

    if [[ -n "$output_dir" ]]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null; then
            rm "$target_file"
            fail "Failed to extract \"$archive\". Line: ${LINENO}"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components=1 2>/dev/null; then
            rm "$target_file"
            fail "Failed to extract \"$archive\". Line: ${LINENO}"
        fi
    fi

    log "File extracted: $archive"
    cd "$target_dir" || fail "Unable to change the working directory to \"$target_dir\" Line: ${LINENO}"
}

git_latest_version() {
    local repo_url="$1"
    local tag_list="" latest="" head_info=""

    if ! tag_list=$(git ls-remote --tags "$repo_url" 2>/dev/null); then
        return 1
    fi

    latest=$(printf '%s\n' "$tag_list" |
        awk -F'/' '/\/v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9]+)?(\^\{\})?$/ {
            tag = $3;
            sub(/^v/, "", tag);
            print tag
        }' |
        grep -v '\^{}' |
        sort -rV |
        head -n1
    )

    if [[ -z "$latest" ]]; then
        if ! head_info=$(git ls-remote "$repo_url" 2>/dev/null); then
            return 1
        fi
        latest=$(printf '%s\n' "$head_info" | awk '/HEAD/ {print substr($1,1,7)}')
    fi

    [[ -z "$latest" ]] && latest="unknown"
    printf '%s' "$latest"
}

git_caller() {
    git_url="$1"
    repo_name="$2"
    recurse_flag=0

    [[ "$3" == "recurse" ]] && recurse_flag=1

    version=$(git_latest_version "$git_url") || fail "Failed to determine latest version for \"$git_url\". Line: ${LINENO}"
}

git_clone() {
    local repo_url repo_name target_directory version store_prior_version recurse_opt
    local recurse="${3:-0}"
    local version_arg="${4:-}"

    repo_url="$1"
    repo_name="${2:-"${1##*/}"}"
    repo_name="${repo_name//\./-}"
    target_directory="$packages/$repo_name"

    if [[ -n "$version_arg" ]]; then
        version="$version_arg"
    else
        version=$(git_latest_version "$repo_url") || fail "Failed to determine latest version for \"$repo_url\". Line: ${LINENO}"
    fi

    [[ -f "$packages/$repo_name.done" ]] && store_prior_version=$(<"$packages/$repo_name.done")

    if [[ ! "$version" == "$store_prior_version" ]]; then
        [[ "$recurse" -eq 1 ]] && recurse_opt="--recursive"
        [[ -d "$target_directory" ]] && safe_rm_rf "$target_directory"
        # Clone the repository
        if ! git clone --depth 1 ${recurse_opt:+"$recurse_opt"} -q "$repo_url" "$target_directory"; then
            echo
            echo -e "${RED}[ERROR]${NC} Failed to clone \"$target_directory\". Second attempt in 10 seconds..."
            echo
            sleep 10
            if ! git clone --depth 1 ${recurse_opt:+"$recurse_opt"} -q "$repo_url" "$target_directory"; then
                fail "Failed to clone \"$target_directory\". Exiting script. Line: ${LINENO}"
            fi
        fi
        cd "$target_directory" || fail "Failed to cd into \"$target_directory\". Line: ${LINENO}"
    fi

    log "Cloning completed: $version"
    return 0
}

show_version() {
    echo
    log "ImageMagick's new version is:"
    echo
    magick -version 2>/dev/null || fail "Failure to execute the command: magick -version. Line: ${LINENO}"
}

# Parse each git repository to find the latest release version number for each program
gnu_repo() {
    local url="$1"
    version=$(curl -fsS "$url" | grep -oP '[a-z]+-\K(([0-9\.]*[0-9]+)){2,}' | sort -rV | head -n1)
}

github_repo() {
    local count git_repo git_url
    git_repo="$1"
    git_url="$2"
    count=1
    version=""

    # Fetch GitHub tags page
    while [[ $count -le 10 ]]; do
        # Apply case-insensitive matching for RC versions to exclude them
        version=$(curl -fsSL "https://github.com/$git_repo/$git_url" |
                grep -oP 'href="[^"]*/tags/[^"]*\.tar\.gz"' |
                grep -oP '\/tags\/\K(v?[\w.-]+?)(?=\.tar\.gz)' |
                grep -iPv '(rc)[0-9]*' | head -n1 | sed 's/^v//')

        # Check if a non-RC version was found
        if [[ -n "$version" ]]; then
            break
        else
            ((count++))
        fi
    done
    # Handle cases where only release candidate versions are found after the script reaches the maximum attempts
    [[ -z "$version" ]] && fail "No matching version found without RC/rc suffix. Line: ${LINENO}"
}

gitlab_freedesktop_repo() {
    local count repo curl_results
    repo="$1"
    count=0
    version=""

    while true; do
        if curl_results=$(curl -fsSL "https://gitlab.freedesktop.org/api/v4/projects/$repo/repository/tags"); then
            version=$(echo "$curl_results" | jq -r ".[$count].name")
            version="${version#v}"

            # Check if the version contains "RC" and skip it
            if [[ $version =~ $regex_string ]]; then
                ((count++))
            else
                break # Exit the loop when a non-RC version is found
            fi
        else
            fail "Failed to fetch data from GitLab API. Line: ${LINENO}"
        fi
    done
}

gitlab_gnome_repo() {
    local count repo url curl_results
    repo="$1"
    url="$2"
    count=0
    version=""

    [[ -z "$repo" ]] && fail "Repository name is required. Line: ${LINENO}"

    if curl_results=$(curl -fsSL "https://gitlab.gnome.org/api/v4/projects/$repo/repository/$url"); then
        version=$(echo "$curl_results" | jq -r '.[0].name')
        version="${version#v}"
    fi

    # Deny installing a release candidate
    while [[ $version =~ $regex_string ]]; do
        if curl_results=$(curl -fsSL "https://gitlab.gnome.org/api/v4/projects/$repo/repository/$url"); then
            version=$(echo "$curl_results" | jq -r ".[$count].name" | sed 's/^v//')
        fi
        ((count++))
    done
}

find_git_repo() {
    local url="$1"
    local git_repo_type="$2"
    local url_action="$3"
    local set_repo set_action

    case "$git_repo_type" in
        1) set_repo="github_repo" ;;
        2) set_repo="gitlab_freedesktop_repo" ;;
        3) set_repo="gitlab_gnome_repo" ;;
        *) fail "Error: Could not detect the variable \"\$git_repo_type\" in the function \"find_git_repo\". Line: ${LINENO}"
    esac

    case "$url_action" in
        T) set_action="tags" ;;
        *) set_action="$3" ;;
    esac

    "$set_repo" "$url" "$set_action" 2>/dev/null
}

download_fonts() {
    local -a font_urls=(
        "https://github.com/dejavu-fonts/dejavu-fonts.git"
        "https://github.com/adobe-fonts/source-code-pro.git"
        "https://github.com/adobe-fonts/source-sans-pro.git"
        "https://github.com/adobe-fonts/source-serif-pro.git"
        "https://github.com/googlefonts/roboto.git"
        "https://github.com/mozilla/Fira.git"
    )
    local font_url repo_name
    for font_url in "${font_urls[@]}"; do
        repo_name="${font_url##*/}"
        repo_name="${repo_name%.git}"
        git_caller "$font_url" "$repo_name"
        if build "$repo_name" "$version"; then
            git_clone "$git_url" "$repo_name" "$recurse_flag" "$version"
            execute use_root cp -fr . "/usr/share/fonts/truetype/"
            build_done "$repo_name" "$version"
        fi
    done
}

find_ghostscript_version() {
    version="$1"
    formatted_version=$(
                        echo "$version" |
                        sed -E 's/gs([0-9]{2})([0-9]{2})([0-9])/\1.\2.\3/'
                    )
    gscript_url="https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/${version}/ghostscript-${formatted_version}.tar.xz"
}

apt_pkgs() {
    local pkg
    local -a pkgs=() extra_pkgs=("$@")
    local -a missing_packages=() available_packages=() unavailable_packages=()

    pkgs=(
        "${extra_pkgs[@]}" alien autoconf autoconf-archive
        binutils bison build-essential cmake curl dbus-x11
        flex fontforge git gperf intltool jq libc6
        libx11-dev libxext-dev libxt-dev
        libcpu-features-dev libdmalloc-dev libdmalloc5
        libfont-ttf-perl libgc-dev libgc1 libgegl-common
        libgl2ps-dev libglib2.0-dev libgs-dev libheif-dev
        libhwy-dev libjxl-dev libnotify-bin librust-jpeg-decoder-dev
        librust-malloc-buf-dev libsharp-dev libticonv-dev
        libtool libtool-bin libyuv-dev libyuv-utils libyuv0
        lsb-release lzip m4 meson nasm ninja-build php-dev
        pkg-config python3-dev yasm zlib1g-dev
    )

    [[ "$OS" == "Debian" ]] && pkgs+=(libjpeg62-turbo libjpeg62-turbo-dev)
    [[ "$OS" == "Ubuntu" ]] && pkgs+=(libjpeg62 libjpeg62-dev)

    log "Checking package installation status..."

    # Loop through the array to find missing packages
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    # Check the availability of missing packages and categorize them
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
        use_root apt update || fail "apt update failed. Line: ${LINENO}"
        use_root apt install -y "${available_packages[@]}" || fail "apt install failed. Line: ${LINENO}"
        use_root apt -y autoremove || warn "apt autoremove failed, continuing..."
        echo
    else
        log "No missing packages to install or all missing packages are unavailable."
    fi
}


# Install APT packages
    echo
    echo "Installing required APT packages"
    echo "=========================================="

debian_version() {
    case "$VER_MAJOR" in
        11) apt_pkgs libvmmalloc1 libvmmalloc-dev libgegl-0.4-0 libcamd2 ;;
        12) apt_pkgs libgegl-0.4-0 libcamd2 ;;
        13) apt_pkgs libgegl-0.4-0t64 libcamd3 ;;
        *)  fail "Could not detect the Debian version '$VER'. Supported: 11, 12, 13. Line: ${LINENO}" ;;
    esac
}

get_os_version() {
    if command -v lsb_release &>/dev/null; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            debian) OS="Debian" ;;
            ubuntu) OS="Ubuntu" ;;
            arch) OS="Arch" ;;
            *) OS="${NAME:-$ID}" ;;
        esac
        VER="$VERSION_ID"
    else
        fail "Failed to define the \$OS and/or \$VER variables. Line: ${LINENO}"
    fi
}

# GET THE OS NAME
get_os_version
VER_MAJOR="${VER%%.*}"

# DISCOVER WHAT VERSION OF LINUX WE ARE RUNNING (DEBIAN OR UBUNTU)
case "$OS" in
    Arch) ;;
    Debian) debian_version ;;
    Ubuntu) apt_pkgs ;;
    *) fail "Could not detect the OS architecture. Line: ${LINENO}" ;;
esac

# INSTALL OFFICIAL IMAGEMAGICK LIBS (optional - skip if version not available)
find_git_repo "imagemagick/imagemagick" "1" "T"
if build "magick-libs" "$version"; then
    [[ ! -d "$packages/deb-files" ]] && mkdir -p "$packages/deb-files"
    cd "$packages/deb-files" || exit 1
    if curl -LSso "magick-libs-$version.rpm" "https://imagemagick.org/archive/linux/CentOS/x86_64/ImageMagick-libs-$version.x86_64.rpm" 2>/dev/null; then
        execute use_root alien -d ./*.rpm || warn "alien conversion failed, continuing..."
        execute use_root dpkg --force-overwrite -i ./*.deb || warn "dpkg install failed, continuing..."
        build_done "magick-libs" "$version"
    else
        warn "magick-libs $version not available for download, skipping (will build from source)"
    fi
fi

# INSTALL COMPOSER TO COMPILE GRAPHVIZ
if [[ ! -f "/usr/bin/composer" ]]; then
    composer_tmp=$(mktemp -d)
    cd "$composer_tmp" || fail "Failed to cd to temp directory"
    EXPECTED_CHECKSUM=$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_CHECKSUM=$(php -r "echo hash_file('sha384', 'composer-setup.php');")

    if [[ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
        warn "Composer checksum mismatch, skipping composer installation"
        rm -f "composer-setup.php"
        rm -rf "$composer_tmp"
    else
        if ! use_root php composer-setup.php --install-dir=/usr/bin --filename=composer --quiet; then
            warn "Failed to install composer, continuing without it"
        fi
        rm -rf "$composer_tmp" composer-setup.php
    fi
    cd "$cwd" || exit 1
fi

case "$OS:$VER_MAJOR" in
    Ubuntu:22) version=2.4.6 ;;
    Ubuntu:24) version=2.4.7 ;;
    Debian:11) version=2.4.6 ;;
    Debian:12|Debian:13) version=2.4.7 ;;
    *) fail "Unsupported OS version for libtool: $OS $VER. Line: ${LINENO}" ;;
esac
if build "libtool" "$version"; then
    download "https://ftp.gnu.org/gnu/libtool/libtool-$version.tar.xz"
    execute sh ./configure --prefix="$workspace" \
                        --with-pic \
                        M4="$workspace/bin/m4"
    execute make "-j$cpu_threads"
    execute make install
    build_done "libtool" "$version"
fi

gnu_repo "https://pkgconfig.freedesktop.org/releases/"
if build "pkg-config" "$version"; then
    download "https://pkgconfig.freedesktop.org/releases/pkg-config-$version.tar.gz"
    execute autoconf
    execute sh ./configure --prefix="$workspace" \
                        --with-internal-glib \
                        --with-pc-path="$PKG_CONFIG_PATH" \
                        CFLAGS="-I$workspace/include" \
                        LDFLAGS="-L$workspace/lib64 -L$workspace/lib"
    execute make "-j$cpu_threads"
    execute make install
    build_done "pkg-config" "$version"
fi

find_git_repo "libsdl-org/libtiff" "1" "T"
if build "libtiff" "$version"; then
    download "https://codeload.github.com/libsdl-org/libtiff/tar.gz/refs/tags/v$version" "libtiff-$version.tar.gz"
    execute autoreconf -fi
    execute sh ./configure --prefix="$workspace" \
                        --enable-cxx \
                        --disable-docs \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "libtiff" "$version"
fi

find_git_repo "gperftools/gperftools" "1" "T"
version="${version#gperftools-}"
if build "gperftools" "$version"; then
    download "https://github.com/gperftools/gperftools/releases/download/gperftools-$version/gperftools-$version.tar.gz" "gperftools-$version.tar.bz2"
    gperftools_cflags="$CFLAGS -DNOLIBTOOL"
    execute autoreconf -fi
    [[ ! -d build ]] && mkdir build
    cd build || exit 1
    execute sh ../configure --prefix="$workspace" \
                         --with-pic \
                         --with-tcmalloc-pagesize=256 \
                         CFLAGS="$gperftools_cflags"
    execute make "-j$cpu_threads"
    execute make install
    build_done "gperftools" "$version"
fi

git_caller "https://github.com/libjpeg-turbo/libjpeg-turbo.git" "jpeg-turbo-git"
if build "$repo_name" "${version//\$ /}"; then
    git_clone "$git_url" "$repo_name" "$recurse_flag" "$version"
    execute cmake -S . \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DENABLE_STATIC=ON \
                  -DENABLE_SHARED=OFF \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads"
    execute ninja install
    build_done "$repo_name" "$version"
fi

git_caller "https://github.com/imageMagick/libfpx.git" "libfpx-git"
if build "$repo_name" "$version"; then
    git_clone "$git_url" "$repo_name" "$recurse_flag" "$version"
    execute autoreconf -fi
    execute sh ./configure --prefix="$workspace" --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "$repo_name" "$version"
fi

find_git_repo "ArtifexSoftware/ghostpdl-downloads" "1" "T"
find_ghostscript_version "$version"
if build "ghostscript" "$version"; then
    download "$gscript_url" "ghostscript-$version.tar.xz"
    execute sh ./autogen.sh
    execute sh ./configure --prefix="$workspace" \
                        --with-libiconv=native
    execute make "-j$cpu_threads"
    execute make install
    build_done "ghostscript" "$version"
fi

find_git_repo "pnggroup/libpng" "1" "T"
if build "libpng" "$version"; then
    download "https://github.com/pnggroup/libpng/archive/refs/tags/v$version.tar.gz" "libpng-$version.tar.gz"
    execute autoreconf -fi
    execute sh ./configure --prefix="$workspace" \
                        --enable-hardware-optimizations=yes \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done "libpng" "$version"
fi

if [[ "$OS" == "Ubuntu" ]]; then
    version="1.2.59"
    if build "libpng12" "$version"; then
        download "https://github.com/pnggroup/libpng/archive/refs/tags/v$version.tar.gz" "libpng12-$version.tar.gz"
        execute autoreconf -fi
        execute sh ./configure --prefix="$workspace" --with-pic
        execute make "-j$cpu_threads"
        execute make install
        execute rm "$workspace/include/png.h"
        build_done "libpng12" "$version"
    fi
fi

git_caller "https://chromium.googlesource.com/webm/libwebp" "libwebp-git"
if build "$repo_name" "${version//\$ /}"; then
    git_clone "$git_url" "$repo_name" "$recurse_flag" "$version"
    execute autoreconf -fi
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DZLIB_INCLUDE_DIR="$workspace/include" \
                  -DWEBP_BUILD_{CWEBP,DWEBP}=ON \
                  -DWEBP_BUILD_{ANIM_UTILS,EXTRAS,VWEBP}=OFF \
                  -DWEBP_ENABLE_SWAP_16BIT_CSP=OFF \
                  -DWEBP_LINK_STATIC=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "$repo_name" "$version"
fi

find_git_repo "7950" "2"
version="${version#VER-}"
version1="${version//-/.}"
if build "freetype" "$version1"; then
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/VER-$version/freetype-VER-$version.tar.bz2" "freetype-$version1.tar.bz2"
    extracmds=("-D"{harfbuzz,png,bzip2,brotli,zlib,tests}"=disabled")
    execute sh ./autogen.sh
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "freetype" "$version1"
fi

find_git_repo "1665" "3" "T"
if build "libxml2" "$version"; then
    download "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$version/libxml2-v$version.tar.bz2" "libxml2-$version.tar.bz2"
    if command -v python3.11-config &>/dev/null; then
        PYTHON_CFLAGS=$(python3.11-config --cflags)
        PYTHON_LIBS=$(python3.11-config --ldflags)
    else
        PYTHON_CFLAGS=$(python3.12-config --cflags)
        PYTHON_LIBS=$(python3.12-config --ldflags)
    fi
    export PYTHON_CFLAGS PYTHON_LIBS
    execute sh ./autogen.sh
    execute cmake -B build -DCMAKE_INSTALL_PREFIX="$workspace" \
                           -DCMAKE_BUILD_TYPE=Release \
                           -DBUILD_SHARED_LIBS=OFF \
                           -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "libxml2" "$version"
fi

find_git_repo "890" "2"
if build "fontconfig" "$version"; then
    download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$version/fontconfig-$version.tar.bz2"
    
    # Explicitly add paths for zlib and lzma, and link them
    fontconfig_ldflags="$LDFLAGS -DLIBXML_STATIC -L/usr/lib/x86_64-linux-gnu -lz -llzma"
    fontconfig_cflags="$CFLAGS -I/usr/include -I/usr/include/libxml2"

    # Update the pkg-config file to include LIBXML_STATIC
    sed -i "s|Cflags:|& -DLIBXML_STATIC|" "fontconfig.pc.in"
    
    execute sh ./autogen.sh --noconf
    execute sh ./configure --prefix="$workspace" \
                        --disable-docbook \
                        --disable-docs \
                        --disable-shared \
                        --disable-nls \
                        --enable-iconv \
                        --enable-libxml2 \
                        --enable-static \
                        --with-arch="$(uname -m)" \
                        --with-libiconv-prefix=/usr \
                        --with-pic \
                        CFLAGS="$fontconfig_cflags" \
                        LDFLAGS="$fontconfig_ldflags"
    
    execute make "-j$cpu_threads"
    execute make install
    build_done "fontconfig" "$version"
fi

# c2man is optional - it's an old tool for generating man pages from C comments
# Skip it as it has compatibility issues with modern systems
if command -v c2man &>/dev/null; then
    log "c2man already available, skipping build"
else
    warn "c2man not available, skipping (optional - used for man page generation)"
fi

find_git_repo "fribidi/fribidi" "1" "T"
if build "fribidi" "$version"; then
    download "https://github.com/fribidi/fribidi/archive/refs/tags/v$version.tar.gz" "fribidi-$version.tar.gz"
    extracmds=("-D"{docs,tests}"=false")
    execute autoreconf -fi
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "fribidi" "$version"
fi

find_git_repo "harfbuzz/harfbuzz" "1" "T"
if build "harfbuzz" "$version"; then
    download "https://github.com/harfbuzz/harfbuzz/archive/refs/tags/$version.tar.gz" "harfbuzz-$version.tar.gz"
    extracmds=("-D"{benchmark,cairo,docs,glib,gobject,icu,introspection,tests}"=disabled")
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "harfbuzz" "$version"
fi

find_git_repo "host-oman/libraqm" "1" "T"
if build "raqm" "$version"; then
    download "https://codeload.github.com/host-oman/libraqm/tar.gz/refs/tags/v$version" "raqm-$version.tar.gz"
    execute meson setup build --prefix="$workspace" \
                              --includedir="$workspace/include" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              -Ddocs=false
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "raqm" "$version"
fi

find_git_repo "jemalloc/jemalloc" "1" "T"
if build "jemalloc" "$version"; then
    download "https://github.com/jemalloc/jemalloc/archive/refs/tags/$version.tar.gz" "jemalloc-$version.tar.gz"
    execute sh ./autogen.sh
    execute sh ./configure --prefix="$workspace" \
                        --disable-debug \
                        --disable-doc \
                        --disable-fill \
                        --disable-log \
                        --disable-prof \
                        --disable-stats \
                        --enable-autogen \
                        --enable-static \
                        --enable-xmalloc \
                        CFLAGS="$CFLAGS"
    execute make "-j$cpu_threads"
    execute make install
    build_done "jemalloc" "$version"
fi

git_caller "https://github.com/KhronosGroup/OpenCL-SDK.git" "opencl-sdk-git" "recurse"
if build "$repo_name" "${version//\$ /}"; then
    git_clone "$git_url" "$repo_name" "$recurse_flag" "$version"
    execute cmake \
            -S . \
            -B build \
            -DCMAKE_INSTALL_PREFIX="$workspace" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_POSITION_INDEPENDENT_CODE=true \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_{DOCS,EXAMPLES,TESTING}=OFF \
            -DOPENCL_SDK_{BUILD_SAMPLES,TEST_SAMPLES}=OFF \
            -DCMAKE_C_FLAGS="$CFLAGS" \
            -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DOPENCL_HEADERS_BUILD_CXX_TESTS=OFF \
            -DOPENCL_ICD_LOADER_BUILD_SHARED_LIBS=OFF \
            -DOPENCL_SDK_BUILD_{OPENGL_SAMPLES,SAMPLES}=OFF \
            -DOPENCL_SDK_TEST_SAMPLES=OFF \
            -DTHREADS_PREFER_PTHREAD_FLAG=ON \
            -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    execute mv "$workspace/lib/pkgconfig/libpng.pc" "$workspace/lib/pkgconfig/libpng-12.pc"
    build_done "$repo_name" "$version"
fi

find_git_repo "uclouvain/openjpeg" "1" "T"
if build "openjpeg" "$version"; then
    download "https://codeload.github.com/uclouvain/openjpeg/tar.gz/refs/tags/v$version" "openjpeg-$version.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DCMAKE_POSITION_INDEPENDENT_CODE=true \
                  -DBUILD_{SHARED_LIBS,TESTING}=OFF \
                  -DBUILD_THIRDPARTY=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done "openjpeg" "$version"
fi

find_git_repo "mm2/Little-CMS" "1" "T"
version="${version//lcms/}"
if build "lcms2" "$version"; then
    download "https://github.com/mm2/Little-CMS/archive/refs/tags/lcms$version.tar.gz" "lcms2-$version.tar.gz"
    execute sh ./autogen.sh
    execute sh ./configure --prefix="$workspace" --with-pic --with-threaded
    execute make "-j$cpu_threads"
    execute make install
    build_done "lcms2" "$version"
fi

# Download and install fonts
download_fonts

echo
box_out_banner_magick() {
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
box_out_banner_magick "Build ImageMagick"

find_git_repo "ImageMagick/ImageMagick" "1" "T"
if build "imagemagick" "$version"; then
    download "https://imagemagick.org/archive/releases/ImageMagick-$version.tar.lz" "imagemagick-$version.tar.lz"
    execute autoreconf -fi
    [[ ! -d build ]] && mkdir build
    cd build || exit 1
    execute sh ../configure --prefix=/usr/local \
                         --enable-ccmalloc \
                         --enable-delegate-build \
                         --enable-hdri \
                         --enable-hugepages \
                         --enable-legacy-support \
                         --enable-opencl \
                         --with-dmalloc \
                         --with-fontpath=/usr/share/fonts/truetype \
                         --with-dejavu-font-dir=/usr/share/fonts/truetype/dejavu \
                         --with-gs-font-dir=/usr/share/fonts/ghostscript \
                         --with-urw-base35-font-dir=/usr/share/fonts/type1/urw-base35 \
                         --with-fpx \
                         --with-gslib \
                         --with-gvc \
                         --with-heic \
                         --with-jemalloc \
                         --with-modules \
                         --with-perl \
                         --with-pic \
                         --with-pkgconfigdir="$workspace/lib/pkgconfig" \
                         --with-png \
                         --with-quantum-depth=16 \
                         --with-rsvg \
                         --with-tcmalloc \
                         --with-utilities \
                         --without-autotrace \
                         CFLAGS="$CFLAGS -DCL_TARGET_OPENCL_VERSION=300" \
                         CXXFLAGS="$CFLAGS" \
                         CPPFLAGS="$CPPFLAGS -I$workspace/include/CL" \
                         PKG_CONFIG="$workspace/bin/pkg-config"
    execute make "-j$cpu_threads"
    execute use_root make install
fi

# LDCONFIG MUST BE RUN NEXT TO UPDATE FILE CHANGES OR THE MAGICK COMMAND WILL NOT WORK
use_root ldconfig

# SHOW THE NEWLY INSTALLED MAGICK VERSION
show_version

# PROMPT THE USER TO CLEAN UP THE BUILD FILES
cleanup

# SHOW EXIT MESSAGE
exit_fn
