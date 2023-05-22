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
## Updated: 04.10.23
##
#############################################################################

# verify the script does not have root access before continuing
if [ "$EUID" -eq '0' ]; then
    echo 'This script must be run WITHOUT root/sudo'
    echo
    exit 1
fi

# Set variables
progname="${0:2}"
script_ver='5.0'
cwd="$PWD"
packages="$cwd"/packages
workspace="$cwd"/workspace
png_ver='1.2.59'

##
## Set the available cpu count for parallel processing (speeds up the build process)
##

if [ -f '/proc/cpuinfo' ]; then
    cpu_threads="$(grep -c processor '/proc/cpuinfo')"
else
    cpu_threads="$(nproc --all)"
fi

PATH="\
/usr/lib/ccache:\
$workspace/bin:\
/usr/local/bin:\
/usr/bin:\
/usr/share/sensible-utils/bin:\
/usr/share/cargo/registry/cc-1.0.71/src/bin:\
/usr/lib/klibc/bin:\
/usr/lib/jvm/java-11-openjdk-amd64/bin:\
/usr/lib/initramfs-tools/bin:\
/usr/lib/github-desktop/resources/app/git/bin\
$PATH\
"
export PATH

# Export the pkg-config paths to enable support during the build
PKG_CONFIG_PATH="\
$workspace/lib/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/share/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig\
"
export PKG_CONFIG_PATH

LD_LIBRARY_PATH="\
$workspace/lib:\
$workspace/lib64:\
$workspace/src/lib:\
$workspace/share/ghostscript/10.01.1/lib:\
$packages/imagemagick-7.1.1-9/Magick++/lib:\
$packages/imagemagick-7.1.1-9/PerlMagick/blib/lib:\
$packages/jpeg-turbo-git/CMakeFiles/Export/lib:\
$packages/ghostscript-10.01.1/openjpeg/src/lib:\
$packages/ghostscript-10.01.1/contrib/pcl3/lib:\
$packages/ghostscript-10.01.1/lib:\
/usr/share/texinfo/lib:\
/usr/share/ghostscript/9.55.0/lib:\
/usr/lib/jvm/java-11-openjdk-amd64/lib:\
/usr/local/lib:\
/usr/lib64:\
/usr/lib\
"
export LD_LIBRARY_PATH

##
## Create Functions
##

# general failure function
fail_fn()
{
    printf "\n\n%s\n\n%s\n\n%s\n\n" \
        "$1" \
        'Please create a support ticket at the address below' \
        'https://github.com/slyfox1186/build-imagemagick/issues'
    exit 1
}

exit_fn()
{
    clear
    echo
    echo 'The script has completed'
    echo
    echo 'Make sure to star this repository to show your support!'
    echo 'https://github.com/slyfox1186/script-repo'
    echo
    exit 0
}

execute()
{
    echo "$ $*"
# 2>&1
    output=$("$@")

    # shellcheck disable=SC2181
    if [ "$?" -ne '0' ]; then
        echo "$output"
        echo
        echo "Failed to Execute $*" >&2
        echo
        exit 1
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
    echo
    echo 'Do you want to remove the build files?'
    echo
    echo '[1] Yes'
    echo '[2] No'
    echo
    read -p 'Your choices are (1 or 2): ' cleanup_choice
    clear

    if [[ "$cleanup_choice" -eq '1' ]]; then
        remove_dir "$packages"
        remove_file "$0"
        exit_fn
    elif [[ "$cleanup_choice" -eq '2' ]]; then
        exit_fn
    else
        echo 'Bad user input...'
        echo
        read -p 'Press enter to try again.'
        clear
        cleanup_fn
    fi
}

get_version_fn()
{
    scipt_name="$(basename "$0")";
    echo "$scipt_name"
}

make_dir()
{
    if ! remove_dir "$1"; then
        fail_fn "Failed to remove the directory: $PWD/$1"
    fi
    if ! mkdir "$1"; then
        fail_fn "Failed to create the directory: $PWD/$1"
    fi
}

remove_file()
{
    if [ -f "$1" ]; then
        rm -f "$1"
    fi
}

remove_dir()
{
    if [ -d "$1" ]; then
        rm -fr "$1"
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
            echo 'Download Completed'
        fi
    else
        echo 'File already downloaded.'
    fi

    if [ -d "$dl_path/$target_dir" ]; then
        sudo rm -fr "$dl_path/$target_dir"
    fi

    make_dir "$dl_path/$target_dir"

    if [[ "$dl_file" == *'patch'* ]]; then
        return
    fi

    if [ -n "$3" ]; then
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" &>/dev/null; then
            fail_fn "Failed to extract: $dl_file"
        fi
    else
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" --strip-components 1 &>/dev/null; then
            fail_fn "Failed to extract: $dl_file"
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
    pkgs=(autoconf automake bison build-essential curl flex google-perftools jq libc-devtools libcpu-features-dev \
          libcrypto++-dev libdmalloc-dev libdmalloc5 libgc-dev libgc1 libgl2ps-dev libglib2.0-dev libgoogle-perftools-dev \
          libgoogle-perftools4 libheif-dev libjemalloc-dev libjemalloc2 libjpeg-dev libmagickcore-6.q16hdri-dev \
          libmimalloc-dev libmimalloc2.0 libopenjp2-7-dev libpng++-dev libpng-dev libpng-tools libpng16-16 \
          libpstoedit-dev libraw-dev librust-bzip2-dev librust-jpeg-decoder+default-dev libtcmalloc-minimal4 \
          libtiff-dev libtool libwebp-dev libzip-dev pstoedit libsdl2-dev meson ninja-build)

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
    else
        echo 'The required packages are already installed.'
    fi
}

deb_files_fn()
{
    local deb

    mkdir -p "$packages"/deb-files

    if ! curl -Lso "$packages"/deb-files/autotrace_0.40.0.deb 'https://github.com/autotrace/autotrace/releases/download/travis-20200219.65/autotrace_0.40.0-20200219_all.deb'; then
        fail_fn 'Failed to download the required debian files.'
    fi

    if [ ! -f "$packages"/jpegb-xl.tar.gz ]; then
        if [ "$os_test" = '23.04' ] || [ "$os_test" = '22.10' ] || [ "$os_test" = '22.04' ]; then
            if ! curl -Lso "$packages"/jpegb-xl.tar.gz 'https://github.com/libjxl/libjxl/releases/download/v0.8.1/jxl-debs-amd64-ubuntu-22.04-v0.8.1.tar.gz'; then
                fail_fn 'Failed to download the required debian files.'
            fi
        elif [ "$os_test" = '20.04' ]; then
            if ! curl -Lso "$packages"/jpegb-xl.tar.gz 'https://github.com/libjxl/libjxl/releases/download/v0.8.1/jxl-debs-amd64-ubuntu-20.04-v0.8.1.tar.gz'; then
                fail_fn 'Failed to download the required debian files.'
            fi
        elif [ "$os_test" = '18.04' ]; then
            if ! curl -Lso "$packages"/jpegb-xl.tar.gz 'https://github.com/libjxl/libjxl/releases/download/v0.8.1/jxl-debs-amd64-ubuntu-18.04-v0.8.1.tar.gz'; then
                fail_fn 'Failed to download the required debian files.'
            fi
        fi

        if ! tar -zxf "$packages"/jpegb-xl.tar.gz -C "$packages"/deb-files --strip-components 1; then
            fail_fn 'Could not extract the debian files.'
        fi

        printf "%s\n%s\n" \
            'Installing deb files.' \
            '================================'
        for deb in "$packages"/deb-files/*.deb; do
            sudo dpkg -i "$deb" >/dev/null
        done
    fi

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
        g_url="$(echo "$curl_cmd" | jq -r '.[0].zipball_url' 2>/dev/null)"
        g_ver="${g_ver#OpenJPEG }"
        g_ver="${g_ver#OpenSSL }"
        g_ver="${g_ver#pkgconf-}"
        g_ver="${g_ver#release-}"
        g_ver="${g_ver#lcms}"
        g_ver="${g_ver#ver-}"
        g_ver="${g_ver#PCRE2-}"
        g_ver="${g_ver#FAAC }"
        #g_ver="${g_ver%t}"
        g_ver="${g_ver#v}"
        g_ver1="${g_ver1#v}"
        g_ver3="${g_ver3#v}"
    fi
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
    -h | --help)
        clear
        usage
        echo
        exit 0
        ;;
    -*)
        if [[ "$1" == '--build' || "$1" =~ '-b' ]]; then
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
        echo
        exit 1
        ;;
    esac
done

if [ -z "$bflag" ]; then
    if [ -z "$cflag" ]; then
        if [ -z "$vflag" ]; then
            clear
            usage
            echo
            exit 1
        fi
    fi
    exit 0
fi

#
# Begin compiling source code
#

printf "%s\n\n%s\n%s\n\n%s\n\n" \
    'Starting the build process...' \
    "ImageMagick Build Script v$script_ver" \
    '==========================================' \
    "This script will use ($cpu_threads cpu cores) for parallel processing to accelerate the build speed."
# sleep 3

printf "%s\n%s\n\n" \
    'Installing required packages' \
    '=========================================='

#
# Install extra libraries for imagemagick
#

os_test="$(lsb_release -r 2>/dev/null | grep -Eo '[0-9\.]+$')"
if [ "$os_test" = '23.04' ]; then
    librust_pkg='librust-jpeg-decoder-dev'
    pkgs_fn "$librust_pkg"
else
    pkgs_fn
fi

#
# Install required debian files
#

deb_files_fn

#
# Create the packages directory
#

mkdir -p "$packages" "$workspace"

git_ver_fn 'pkgconf/pkgconf' '1' 'T'
if build 'pkg-config' "$g_ver"; then
    download "https://codeload.github.com/pkgconf/pkgconf/tar.gz/refs/tags/pkgconf-$g_ver" "pkg-config-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --silent --prefix="$workspace" --enable-static --disable-shared CXXFLAGS='-g -O3 -march=native' 
    execute make "-j$cpu_threads"
    execute make install
    build_done 'pkg-config' "$g_ver"
fi

git_ver_fn 'netwide-assembler/nasm' '1' 'T'
if build 'nasm' "$g_ver1"; then
    download "https://codeload.github.com/netwide-assembler/nasm/tar.gz/refs/tags/nasm-$g_ver1" "nasm-$g_ver1.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-ccache --disable-pedantic CXXFLAGS='-g -O3 -march=native'
    execute make "-j$cpu_threads" everything
    execute make strip
    execute make install
    build_done 'nasm' "$g_ver1"
fi

if build 'autoconf' 'git'; then
    download_git 'https://git.savannah.gnu.org/git/autoconf.git' 'autoconf-git'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" CXXFLAGS='-g -O3 -march=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'autoconf' 'git'
fi

if build 'automake' 'git'; then
    download_git 'https://git.savannah.gnu.org/git/automake.git' 'automake-git'
    execute ./bootstrap
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" CXXFLAGS='-g -O3 -march=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'automake' 'git'
fi

if build 'libtool' '2.4.7'; then
    download 'https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz' 'libtool-2.4.7.tar.xz'
    execute ./configure --prefix="$workspace" --enable-static --disable-shared --with-pic CXXFLAGS="-g -O3 -march=native -fPIC"
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libtool' '2.4.7'
fi

git_ver_fn 'kitware/cmake' '1' 'T'
if build 'cmake' "$g_ver"; then
    download "https://codeload.github.com/Kitware/CMake/tar.gz/refs/tags/v$g_ver" "cmake-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --parallel="$cpu_threads" --enable-ccache -- -DCMAKE_USE_OPENSSL='OFF'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'cmake' "$g_ver"
fi

git_ver_fn 'adobe-fonts/source-code-pro' '1' 'T'
g_ver3="$(echo "$g_ver3" | sed 's:/.*::' | sed 's/-u//g')"
if build 'adobe-fonts' "$g_ver3"; then
    download "https://github.com/adobe-fonts/source-code-pro/archive/refs/tags/2.042R-u/1.062R-i/1.026R-vf.tar.gz" "adobe-fonts-$g_ver3.tar.gz"
    sudo mkdir -p '/usr/share/fonts/adobe-pro'
    sudo cp -fr 'OTF' '/usr/share/fonts/adobe-pro'
    sudo cp -fr 'TTF' '/usr/share/fonts/adobe-pro'
    sudo cp -fr 'VF' '/usr/share/fonts/adobe-pro'
    sudo cp -fr 'WOFF' '/usr/share/fonts/adobe-pro'
    sudo cp -fr 'WOFF2' '/usr/share/fonts/adobe-pro'
    build_done 'adobe-fonts' "$g_ver3"
fi

git_ver_fn 'libsdl-org/libtiff' '1' 'T'
if build 'tiff' "$g_ver"; then
    download "https://codeload.github.com/libsdl-org/libtiff/tar.gz/refs/tags/v$g_ver" "tiff-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-shared --enable-cxx CXXFLAGS='-g -O3 -march=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'tiff' "$g_ver"
fi

if build 'jpeg-turbo' 'git'; then
    download_git 'https://github.com/ImageMagick/jpeg-turbo.git' 'jpeg-turbo-git'
    make_dir 'build'
    execute cmake -S . -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE='Release' -DENABLE_SHARED='ON' -DENABLE_STATIC='ON' -G 'Ninja'
    execute ninja "-j$cpu_threads"
    execute ninja "-j$cpu_threads" install
    build_done 'jpeg-turbo' 'git'
fi

git_ver_fn 'flif-hub/flif' '1' 'T'
if build 'flif' "$g_ver"; then
    download_git 'https://github.com/FLIF-hub/FLIF.git' 'flif-git'
    execute make flif
    execute sudo make install PREFIX='/usr/local'
    build_done 'flif' 'git'
fi

if build 'fpx' 'git'; then
    download_git 'https://github.com/ImageMagick/libfpx.git' 'libfpx-git'
    execute autoreconf -fi
    execute ./configure --prefix='/usr/local'
    execute make -j "$cpu_threads"
    execute sudo make install
    build_done 'fpx' 'git'
fi

if build 'ghostscript' '10.01.1'; then
    download 'https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10011/ghostscript-10.01.1.tar.gz' 'ghostscript-10.01.1.tar.gz'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"
    execute make "-j$cpu_threads"
    execute make install
    build_done 'ghostscript' '10.01.1'
fi

if build 'png12' "$png_ver"; then
    download "https://github.com/glennrp/libpng/archive/refs/tags/v$png_ver.tar.gz" "libpng-$png_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"
    execute make "-j$cpu_threads"
    execute make install
    build_done 'png12' "$png_ver"
fi

if build 'webp' 'git'; then
    download_git 'https://chromium.googlesource.com/webm/libwebp' 'webp-git'
    execute autoreconf -fi
    make_dir 'build'
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_BUILD_TYPE='Release' -DBUILD_SHARED_LIBS='ON' \
        -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG" -DWEBP_BUILD_EXTRAS='OFF' -DWEBP_BUILD_LIBWEBPMUX='OFF' \
        -DCMAKE_INSTALL_INCLUDEDIR="include" -DWEBP_LINK_STATIC='OFF' -DWEBP_BUILD_GIF2WEBP='OFF' -DWEBP_BUILD_IMG2WEBP='OFF' \
        -DWEBP_BUILD_DWEBP='ON' -DWEBP_BUILD_CWEBP='ON' -DWEBP_BUILD_ANIM_UTILS='OFF' -DWEBP_BUILD_WEBPMUX='OFF' \
        -DWEBP_ENABLE_SWAP_16BIT_CSP='OFF' -DWEBP_BUILD_WEBPINFO='OFF' -DZLIB_INCLUDE_DIR='/usr/include' -DWEBP_BUILD_VWEBP='OFF' \
        -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'webp' 'git'
fi

if build 'c2man' 'git'; then
    download_git 'https://github.com/fribidi/c2man.git' 'c2man-git'
    execute ./Configure -desO -D prefix="$workspace" -D bin="$workspace"/bin -D bash='/bin/bash' -D cc='/usr/bin/cc' \
        -D d_gnu='/usr/lib/x86_64-linux-gnu' -D find='/usr/bin/find' -D gcc="$CC" -D gzip='/usr/bin/gzip' \
        -D installmansrc="$workspace"/share/man -D ldflags="-L$workspace/lib" -D less='/usr/bin/less' \
        -D libpth="$workspace/lib /usr/local/lib /lib /usr/lib" \
        -D locincpth="$workspace/include /usr/local/include /opt/local/include /usr/gnu/include /opt/gnu/include /usr/GNU/include /opt/GNU/include" \
        -D yacc='/usr/bin/yacc' -D loclibpth="$workspace/lib /usr/local/lib /opt/local/lib /usr/gnu/lib /opt/gnu/lib /usr/GNU/lib /opt/GNU/lib" \
        -D make='/usr/bin/make' -D more='/usr/bin/more' -D osname='Ubuntu' -D perl='/usr/bin/perl' -D privlib="$workspace"/lib/c2man \
        -D privlibexp="$workspace"/lib/c2man -D sleep='/usr/bin/sleep' -D tail='/usr/bin/tail' -D tar='/usr/bin/tar' -D uuname='Linux' \
        -D vi='/usr/bin/vi' -D zip='/usr/bin/zip'
    execute make depend
    execute make "-j$cpu_threads"
    execute sudo make install
    build_done 'c2man' 'git'
fi

git_ver_fn 'fribidi/fribidi' '1' 'T'
if build 'fribidi' "$g_ver"; then
    download "https://codeload.github.com/fribidi/fribidi/tar.gz/refs/tags/v$g_ver" "fribidi-$g_ver.tar.gz"
    execute meson setup 'build' --prefix="$workspace" --buildtype='release' --default-library='static' --strip
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'fribidi' "$g_ver"
fi

git_ver_fn 'HOST-Oman/libraqm' '1' 'T'
if build 'raqm' "$g_ver"; then
    download "https://codeload.github.com/HOST-Oman/libraqm/tar.gz/refs/tags/v$g_ver" "raqm-$g_ver.tar.gz"
    execute meson setup 'build' --prefix='/usr/local' --buildtype='release' --default-library='static' --strip
    execute ninja "-j$cpu_threads" -C 'build'
    execute sudo ninja "-j$cpu_threads" -C 'build' install
    build_done 'raqm' "$g_ver"
fi

##
## Begin imagemagick build
##

if [ -f "$packages/ImageMagick.done" ]; then
    rm -f "$packages/ImageMagick.done"
fi

git_ver_fn 'imagemagick/imagemagick' '1' 'T'
if [ -d "$packages/imagemagick-$g_ver" ]; then
    rm -fr "$packages/imagemagick-$g_ver"
fi

if build 'ImageMagick' "$g_ver"; then
    rm -fr "imagemagick-$g_ver.tar.gz"
    download "$g_url" "imagemagick-$g_ver.tar.gz"
    ./configure \
        --prefix='/usr/local' \
        --enable-ccmalloc \
        --enable-legacy-support \
        --with-autotrace \
        --with-dmalloc \
        --with-flif \
        --with-gslib \
        --with-heic \
        --with-jemalloc \
        --with-modules \
        --with-perl \
        --with-tcmalloc \
        --with-quantum-depth=16 \
        CFLAGS="-I/usr/include" \
        LDFLAGS="-L$workspace/lib"
    execute make "-j$cpu_threads"
    sudo make install
    build_done 'ImageMagick' "$g_ver"
fi

# ldconfig must be run next in order to update file changes or the magick command will not work
echo
sudo ldconfig /usr/local/lib 2>/dev/null

# show the newly installed magick version
if ! magick -version 2>/dev/null; then
    clear
    printf "%s\n%s\n\n%s\n\n%s\n\n" \
        'Script error!' \
        '    - Failure to execute the command: magick -version' \
        'If help is required or to report bugs please create a support ticket' \
        'https://github.com/slyfox1186/build-imagemagick/issues'
    exit 1
fi

# prompt the user to cleanup the build files
cleanup_fn
