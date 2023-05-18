#!/bin/bash
# shellcheck disable=SC2046,SC2066,SC2068,SC2086,SC2119,SC2162

#############################################################################
##
## GitHub: https://github.com/slyfox1186
##
## Purpose: Builds ImageMagick 7 from source code obtained
##          from the official ImageMagick GitHub repository.
##
## Function: ImageMagick is the leading open source command line
##           image processor. It can blur, sharpen, warp, reduce
##           file size, ect... The possibilities are vast and wide.
##
## Method: The script will search GitHub for the latest released version
##         and upon execution, will import the info into the script for use
##
## Updated: 05.17.23
##
#############################################################################

# set variables
progname="${0:2}"
script_ver='5.0'
cwd="$PWD"
packages="$cwd"/packages
workspace="$cwd"/workspace
install_dir='/usr/bin'
CFLAGS="-I$workspace/include"
LDFLAGS="-L$workspace"/lib
CXX_NAT='-O3 -march=native -mtune=native'
CXX_ZEN='-O3 -march=znver4 -mtune=znver4'
png_ver='1.2.59'
g_ver="$github_ver"
packages="$PWD"/packages
export GCC_ZEN='-O3 -march=znver4 -mtune=znver4'
export GCC_NAT='-O3 -march=native -mtune=native'

# Create the packages directory
mkdir -p "$packages" "$workspace"

##
## Set the available cpu count for parallel processing (speeds up the build process)
##

if [ -f '/proc/cpuinfo' ]; then
    cpus="$(grep -c processor '/proc/cpuinfo')"
else
    cpus="$(nproc --all)"
fi

##
## Create Functions
##

# general failure function
fail_fn()
{
    printf "\n\n%s\n\n%s\n\n%s\n\n" \
        "$1" \
        'Please create a support ticket at the address below' \
        'https://github.com/slyfox1186/script-repo/issues'
    exit 1
}

# PULL THE LATEST VERSIONS OF EACH PACKAGE FROM THE WEBSITE API
curl_timeout='10'
git_token=''

git_1_fn()
{
    local github_repo github_url

    # SCRAPE GITHUB WEBSITE FOR LATEST REPO VERSION
    github_repo="$1"
    github_url="$2"
    if curl_cmd="$(curl \
                         -m "$curl_timeout" \
                        --request GET \
                        --url "https://api.github.com/slyfox1186" \
                        --header "Authorization: Bearer $git_token" \
                        --header "X-GitHub-Api-Version: 2022-11-28" \
                        -sSL https://api.github.com/repos/$github_repo/$github_url)"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_ver1="$(echo "$curl_cmd" | jq -r '.[1].name' 2>/dev/null)"
        g_ver3="$(echo "$curl_cmd" | jq -r '.[3].name' 2>/dev/null)"
        g_ver="${g_ver#OpenJPEG }"
        g_ver="${g_ver#OpenSSL }"
        g_ver="${g_ver#pkgconf-}"
        g_ver="${g_ver#release-}"
        g_ver="${g_ver#lcms}"
        g_ver="${g_ver#ver-}"
        g_ver="${g_ver#PCRE2-}"
        g_ver="${g_ver#FAAC }"
        g_ver="${g_ver#v}"
        g_ver1="${g_ver1#v}"
        g_ver3="${g_ver3#v}"
        g_url="$(echo "$curl_cmd" | jq -r '.[0].tarball_url')"
    fi

    echo "${github_repo%/*}-$g_ver" >> "$ver_file_tmp"
    awk '!NF || !seen[$0]++' "$latest_txt_tmp" > "$ver_file"
}

git_ver_fn()
{
    local v_flag v_tag url_tag

    v_url="$1"
    v_tag="$2"

    if [ -n "$3" ]; then
        v_flag="$3"
    fi

    if [ "$v_flag" = 'T' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn' gv_url='tags'
    fi

    if [ "$v_flag" = 'R' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases'
    fi

    "$url_tag" "$v_url" "$gv_url" 2>/dev/null
}

exit_fn()
{
    clear
    printf "%s\n\n%s\n%s\n\n" \
        'The script has completed' \
        'Make sure to star this repository to show your support!' \
        'https://github.com/slyfox1186/script-repo'
    exit 0
}

execute()
{
    echo "$ $*"
# 2>&1
    if ! output=$("$@"); then
        echo
        read -p 'Failure! Press enter to exit.'
        exit_fn "Failed to Execute $*"
    fi
}

build()
{
    echo
    echo "Building $1 - version $2"
    echo '=========================================='

    if [ -f "$packages/$1.done" ]; then
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

build_done() { echo "$2" > "$packages/$1.done"; }

cleanup_fn()
{
    local cchoice

        printf "\n%s\n\n%s\n%s\n%s\n\n" \
            'The script has completed' \
            'Do you want to remove the build files?' \
            '[1] Yes' \
            '[2] No'
        read -p 'Your choices are (1 or 2): ' cchoice
        clear

    case "$cchoice" in
        1)
            remove_dir "$packages"
            remove_file "$0"
            exit_fn
            ;;
        2)  exit_fn;;

        *)
            echo 'Bad user input.'
            echo
            read -p 'Press enter to try again.'
            clear
            cleanup_fn
            ;;
    esac
}

get_version_fn()
{
    scipt_name="$(basename "$0")"
    if which 'jq' &>/dev/null; then
        printf "%s\n\n%s\n\n" \
            "The latest version of ImageMagick is: $g_ver" \
            "To install execute: bash $scipt_name --build"
        exit 0
    else
        printf "%s\n\n%s\n\n%s\n\n%s\n\n" \
            'The required package "jq" must be installed for this command to work.' \
            'Excute one of the following commands to install.' \
            'apt install jq' \
            "bash $scipt_name"
        exit 1
    fi
}

make_dir()
{
    if ! remove_dir "$1"; then
        printf "%s\n" \
            fail_fn "Failed to remove the directory: $PWD/$1"
    fi
    if ! mkdir -p "$1"; then
        printf "%s\n" \
            fail_fn "Failed to create the directory: $PWD/$1"
    fi
}

remove_file()
{
    if [ -f "$1" ]; then
        sudo rm -f "$1"
    fi
}

remove_dir()
{
    if [ -d "$1" ]; then
        sudo rm -fr "$1"
    fi
}

download()
{
    dl_path="$packages"
    dl_file="${2:-"${1##*/}"}"

    if [[ "$dl_file" =~ tar. ]]; then
        target_dir="${dl_file%.*}"
        target_dir="${3:-"${target_dir%.*}"}"
    else
        target_dir="${3:-"${dl_file%.*}"}"
    fi

    if [ ! -f "$dl_path/$dl_file" ]; then
        echo "Downloading $1 as $dl_file"
        if ! curl -Lso "$dl_path/$dl_file" "$1"; then
            printf "\n%s\n\n%s" \
                "Failed to download: $1" \
                'Retrying in 5 seconds'
                sleep 5
            if ! curl -Lso "$dl_path/$dl_file" "$1"; then
               fail_fn "Failed to download: $1"
            fi
        fi
        echo 'Download Completed'
        echo
    fi

    make_dir "$dl_path/$target_dir"

    if [[ "$dl_file" == *'patch'* ]]; then
        return
    fi

    if [ -n "$3" ]; then
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" &>/dev/null; then
            fail_fn "Failed to download: $dl_file"
        fi
    else
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" --strip-components 1 &>/dev/null; then
            fail_fn "Failed to download: $dl_file"
        fi
    fi

    echo "Extracted $dl_file"

    cd "$dl_path/$target_dir" || fail_fn "Unable to change the working directory to: $target_dir"
}

download_git()
{
    dl_path="$packages"
    dl_url="$1"
    dl_file="$2"
    target_dir="$dl_path/$dl_file"

    if [ -d "$target_dir" ]; then
        remove_dir "$target_dir"
    fi

        echo "Downloading $dl_url as $dl_file"
        if ! git clone -q "$dl_url" "$target_dir"; then
            printf "\n%s\n\n%s\n\n" \
                "The script failed to clone the git repository: $target_dir" \
                'Sleeping for 5 seconds before trying again.'
            sleep 5
            if ! git clone -q "$dl_url" "$target_dir"; then
                fail_fn "The script failed to clone \"$target_dir\" twice and will now exit the build."
            fi
        fi
        echo -e "Succesfully cloned the directory: $target_dir\\n"

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir"
}

## determine if a package is installed or not
installed() { return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

## required imagemagick developement packages
pkgs_fn()
{
    rust_pkg="$1"
    pkgs=(autopoint build-essential ccache gcc g++ google-perftools gtk-doc-tools help2man intltool jq libc-devtools libcpu-features-dev \
          libcrypto++-dev libdmalloc-dev libdmalloc5 libgc-dev libgc1 libgl2ps-dev libglib2.0-dev libgoogle-perftools-dev \
          libgoogle-perftools4 libheif-dev libjemalloc-dev libjemalloc2 libjpeg-dev libmagickcore-6.q16hdri-dev \
          libmimalloc-dev libmimalloc2.0 libopenjp2-7-dev libpng++-dev libpng-dev libpng-tools libpng16-16 \
          libstdc++-13-dev libpstoedit-dev libraw-dev librust-bzip2-dev "$rust_pkg" libtcmalloc-minimal4 \
          libyuv-dev libzip-dev make ninja-build pstoedit texinfo)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "${missing_pkgs-}" ]; then
        for i in "$missing_pkgs"
        do
            sudo apt -y install $i
        done
        printf "\n%s\n\n" \
            'The required packages were successfully installed.'
    else
        echo -e "The required packages were already installed.\\n"
    fi
}

os_test="$(lsb_release -a | grep -Eo '[0-9\.]+' | uniq)"
if [ "$os_test" = '23.04' ]; then
    librust_pkg='librust-jpeg-decoder-dev'
fi

# Required + extra functionality packages for imagemagick
echo 'Installing required packages'

pkgs_fn "$lirust_pkg"

# PRINT THE OPTIONS AVAILABLE WHEN MANUALLY RUNNING THE SCRIPT
usage()
{
    clear
    echo "Usage: $progname [options]"
    echo
    echo 'Options:'
    echo '    -h, --help                                           Display this usage information'
    echo '    -v, --version                                        Display version information'
    echo '    -b, --build                                          Start the build process'
    echo '    -c, --cleanup                                        Remove all working directories'
}

while (($# > 0)); do
    case $1 in
    -h|--help)
            clear
            usage
            exit 0
            ;;
    -*)
            if [[ "$1" == '--build' || "$1" =~ '-b' && ! "$1" =~ '--' ]]; then
                bflag='-b'
            fi
            if [[ "$1" == '--cleanup' || "$1" =~ '-c' && ! "$1" =~ '--' ]]; then
                cflag='-c'
                cleanup_fn
            fi
            if [[ "$1" == '--version' || "$1" =~ '-v' && ! "$1" =~ '--' ]]; then
                vflag='-v'
                clear
                get_version_fn
            fi
            shift
            ;;
    *)
            usage
            exit 1
            ;;
    esac
done

if [ -z "$bflag" ]; then
    if [ -z "$cflag" ]; then
        if [ -z "$vflag" ]; then
            clear
            usage
            exit 1
        fi
    fi
    exit 0
fi

PATH="\
/usr/lib/ccache:\
$workspace/bin:\
$PATH\
"
export PATH

# Export the pkg-config paths to enable support during the build
PKG_CONFIG_PATH="\
$workspace/lib/pkgconfig:\
$workspace/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/i386-linux-gnu/pkgconfig:\
/usr/lib/x86_64-linux-gnu/open-coarrays/openmpi/pkgconfig:\
/usr/lib/x86_64-linux-gnu/openmpi/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/share/pkgconfig\
"
export PKG_CONFIG_PATH

LD_LIBRARY_PATH="\
$workspace/lib:\
$workspace/lib64:\
$workspace/src/lib:\
/usr/local/lib:\
/usr/lib:\
/usr/lib/llvm-14/lib:\
/usr/lib/usrmerge/lib:\
/usr/share/ant/lib:\
/usr/share/git-gui/lib:\
/usr/share/gitk/lib:\
/usr/share/gnulib/lib:\
/usr/share/lintian/lib:\
/usr/share/texinfo/lib:\
/usr/x86_64-linux-gnu/lib\
"
export LD_LIBRARY_PATH

##
## FIGURE OUT WHICH COMPILER TO USE
##

if which gcc-13 &>/dev/null; then
    export CC=gcc-13 CXX=g++-12
elif which gcc-12 &>/dev/null; then
    export CC=gcc-12 CXX=g++-12
elif which gcc-11 &>/dev/null; then
    export CC=gcc-11 CXX=g++-11
elif which gcc &>/dev/null; then
    export CC=gcc CXX=g++
else
    fail_fn 'You must have gcc or some high version of it installed. Please do so and run the script again.'
fi

clear
echo "This script will utilize ( $cpus cpu cores ) for parallel processing to accelerate the building processes."
echo

##
## Begin building from source
##

git_ver_fn 'pkgconf/pkgconf' '1' 'T'
if build 'pkg-config' "$g_ver"; then
    download "https://codeload.github.com/pkgconf/pkgconf/tar.gz/refs/tags/pkgconf-$g_ver" "pkgconf-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --silent --prefix="$workspace" --with-pc-path="$workspace"/lib/pkgconfig --with-internal-glib --enable-static --disable-shared \
    	CXXFLAGS="$CXX_ZEN"
    execute make "-j$cpus"
    execute make install
    build_done 'pkg-config' "$g_ver"
fi

if build 'autoconf' 'git'; then
    download_git 'https://git.savannah.gnu.org/git/autoconf.git' 'autoconf-git'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-static --disable-shared CXXFLAGS="$CXX_ZEN"
    execute make "-j$cpus"
    execute make install
    read -p 'enter'
    build_done 'autoconf' 'git'
fi

if build 'automake' 'git'; then
    download_git 'https://git.savannah.gnu.org/git/automake.git' 'automake-git'
    execute ./bootstrap
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-static --disable-shared CXXFLAGS="$CXX_ZEN"
    execute make "-j$cpus"
    execute make install
    build_done 'automake' 'git'
fi

if build 'libtool' '2.4.7'; then
    download 'https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz' 'libtool-2.4.7.tar.xz'
    execute ./configure --prefix="$workspace" --enable-static --disable-shared --with-pic CXXFLAGS="$CXX_ZEN -fPIC"
    execute make "-j$cpus"
    execute make install
    build_done 'libtool' '2.4.7'
fi

git_ver_fn 'kitware/cmake' '1' 'T'
if build 'cmake' "$g_ver"; then
    download "https://codeload.github.com/Kitware/CMake/tar.gz/refs/tags/v$g_ver" "cmake-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --parallel="$cpus" --enable-ccache -- -DCMAKE_USE_OPENSSL='OFF' CXXFLAGS="$CXX_ZEN"
    execute make "-j$cpus"
    execute make install
    build_done 'cmake' "$g_ver"
fi

if build 'm4' '1.4.19'; then
    download 'https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz' 'm4-1.4.19.tar.xz'
    execute ./configure --prefix="$workspace" --enable-static --disable-shared --enable-c++ --with-dmalloc --enable-threads='posix' CXXFLAGS="$CXX_ZEN"
    execute make "-j$cpus"
    execute make install
    build_done 'm4' '1.4.19'
fi

git_ver_fn 'autotrace/autotrace' '1' 'T'
if build 'autotrace' "$g_ver"; then
    download "https://codeload.github.com/autotrace/autotrace/tar.gz/refs/tags/$g_ver" "autotrace-$png_ver.tar.gz"
    sed -in 's/AM_GLIB_GNU_GETTEXT//g' configure.ac
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make "-j$cpus"
    execute make install
    build_done 'autotrace' "$g_ver"
fi

if build 'libpng12' "$png_ver"; then
    download "https://github.com/glennrp/libpng/archive/refs/tags/v$png_ver.tar.gz" "libpng-$png_ver.tar.gz"
    sed -in 's/AM_GLIB_GNU_GETTEXT//g' configure.ac
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" CXXFLAGS="$CXX_NAT"
    execute make "-j$cpus"
    execute sudo make install
    build_done 'libpng12' "$png_ver"
fi

git_ver_fn 'uclouvain/openjpeg' '1' 'R'
if build 'openjpeg' "$g_ver"; then
    download "https://codeload.github.com/uclouvain/openjpeg/tar.gz/refs/tags/v$g_ver" "openjpeg-$g_ver.tar.gz"
    make_dir 'build'
    export CXXFLAGS="$CXX_ZEN"
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace"  -DCMAKE_BUILD_TYPE='Release' -DBUILD_TESTING='OFF' \
        -DCPACK_BINARY_FREEBSD='ON' -DBUILD_THIRDPARTY='ON' -DCPACK_SOURCE_RPM='ON' -DCPACK_SOURCE_ZIP='ON' \
        -DCPACK_BINARY_IFW='ON' -DBUILD_SHARED_LIBS='ON' -DCPACK_BINARY_DEB='ON' -DCPACK_BINARY_TBZ2='ON' \
        -DCPACK_BINARY_NSIS='ON' -DCPACK_BINARY_RPM='ON' -DCPACK_BINARY_TXZ='ON' -DCMAKE_EXPORT_COMPILE_COMMANDS='ON' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpus" -C 'build'
    execute ninja "-j$cpus" -C 'build' install
    build_done 'openjpeg' "$g_ver"
fi

git_ver_fn 'libsdl-org/libtiff' '1' 'T'
if build 'libtiff' "$g_ver"; then
    download "https://codeload.github.com/libsdl-org/libtiff/tar.gz/refs/tags/v$g_ver" "libtiff-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-shared --enable-cxx CXXFLAGS="$CXX_NAT"
    execute make "-j$cpus"
    execute make install
    build_done 'libtiff' "$g_ver"
fi

git_ver_fn 'libsdl-org/SDL' '1' 'T'
if build 'libsdl' "$g_ver"; then
    download "https://codeload.github.com/libsdl-org/SDL/tar.gz/refs/tags/release-$g_ver" "libsdl-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared CXXFLAGS="$CXX_ZEN"
    execute make "-j$cpus"
    execute make install
    build_done 'libsdl' "$g_ver"
fi

if build 'libwebp' 'git'; then
    download_git 'https://chromium.googlesource.com/webm/libwebp' 'libwebp-git'
    execute autoreconf -fi
    make_dir 'build'
    export CXXFLAGS="$CXX_ZEN"
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='ON' -DCMAKE_BUILD_TYPE='Release' \
        -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG" -DWEBP_BUILD_EXTRAS='OFF' -DWEBP_BUILD_LIBWEBPMUX='OFF' \
        -DCMAKE_INSTALL_INCLUDEDIR="include" -DWEBP_LINK_STATIC='OFF' -DWEBP_BUILD_GIF2WEBP='OFF' -DWEBP_BUILD_IMG2WEBP='OFF' \
        -DCMAKE_EXPORT_COMPILE_COMMANDS='OFF' -DWEBP_BUILD_DWEBP='OFF' -DWEBP_BUILD_CWEBP='ON' -DWEBP_BUILD_ANIM_UTILS='OFF' \
        -DWEBP_BUILD_WEBPMUX='OFF' -DWEBP_ENABLE_SWAP_16BIT_CSP='OFF' -DWEBP_BUILD_WEBPINFO='OFF' -DZLIB_INCLUDE_DIR="/usr/include" \
        -DWEBP_BUILD_VWEBP='OFF' -G 'Ninja'
    execute ninja "-j$cpus" -C 'build' all
    execute ninja "-j$cpus" -C 'build' install
    build_done 'libwebp' 'git'
fi

git_ver_fn 'imagemagick/imagemagick' '1' 'T'
if build 'ImageMagick' "$g_ver"; then
    download "https://codeload.github.com/ImageMagick/ImageMagick/tar.gz/refs/tags/$g_ver" "imagemagick-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --enable-shared --with-modules --enable-ccmalloc --enable-legacy-support --with-autotrace --with-dmalloc \
        --with-flif --with-gslib --with-heic --with-jemalloc --with-perl --with-tcmalloc --with-quantum-depth=16 \
        CXXFLAGS='-O3 -march=znver3 -mtune=znver3'
    execute make "-j$cpus"
    execute sudo make install
    build_done 'ImageMagick' "$g_ver"
fi

# ldconfig must be run next in order to update file changes or the magick command will not work
echo
sudo ldconfig /usr/local/lib 2>/dev/null
sudo ldconfig "$workspace"/lib 2>/dev/null

# show the newly installed magick version
if ! magick -version 2>/dev/null; then
    clear
    printf "%s\n%s\n\n%s\n\n%s\n\n" \
        'Script error!' \
        '- Failure to execute the command: magick -version' \
        'To notify the repo owner of a bug please create a support ticket at...' \
        'https://github.com/slyfox1186/script-repo/issues'
    exit 1
fi

# prompt the user to cleanup the build files
cleanup_fn
