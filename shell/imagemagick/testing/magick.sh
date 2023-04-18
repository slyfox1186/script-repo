#!/bin/bash
# shellcheck disable=SC2016,SC2046,SC2066,SC2068,SC2086,SC2162,SC2317

#################################################################################
##
##  GitHub: https://github.com/slyfox1186/script-repo
##
##  Forked: https://github.com/markus-perl/ffmpeg-build-script/
##
##  Supported Distros: Debian-based ( Debian, Ubuntu, etc. )
##
##  Supported architecture: x86_x64
##
##  Purpose: Build FFmpeg from source code with addon development
##           libraries also compiled from source code to ensure the
##           latest in extra functionality
##
##  Cuda:    If the cuda libraries are not installed (for geforce cards only)
##           the user will be prompted by the script to install them so that
##           hardware acceleration is enabled when compiling FFmpeg
##
##  Updated: 03.23.23
##
##  Version: 3.2
##
#################################################################################

##
## define variables
##

script_ver='3.2'
progname="${0:2}"
ffmpeg_ver='n5.0.3'
cuda_ver='12.1'
packages="$PWD"/packages
workspace="$PWD"/workspace
install_dir='/usr/bin'
CFLAGS="-I$workspace"/include
LDFLAGS="-L$workspace"/lib
nonfree='false'
latest='false'

##
## set the available cpu thread and core count for parallel processing (speeds up the build process)
##

if [ -f '/proc/cpuinfo' ]; then
    cpu_threads="$(grep -c ^processor '/proc/cpuinfo')"
else
    cpu_threads="$(nproc --all)"
fi
cpu_cores="$(grep ^cpu\\scores '/proc/cpuinfo' | uniq | awk '{print $4}')"

##
## define functions
##

exit_fn()
{
    echo
    echo 'Make sure to star this repository to show your support!'
    echo
    echo 'https://github.com/slyfox1186/script-repo/'
    echo
    exit 0
}

fail_fn()
{
    echo
    echo "$1"
    echo
    echo 'Please create a support ticket'
    echo
    echo 'https://github.com/slyfox1186/script-repo/issues'
    echo
    exit_fn
}

fail_pkg_fn()
{
    echo
    echo "The '$1' package is not installed. It is required for this script to run."
    echo
    exit 1
}

cleanup_fn()
{
    echo '=========================================='
    echo ' Do you want to clean up the build files? '
    echo '=========================================='
    echo
    echo '[1] Yes'
    echo '[2] No'
    echo
    read -p 'Your choices are (1 or 2): ' cleanup_ans

    if [ "$cleanup_ans" -eq '1' ]; then
        remove_dir "$packages"
        remove_dir "$workspace"
        remove_file "$0"
        echo 'cleanup finished.'
        exit_fn
    elif [ "$cleanup_ans" -eq '2' ]; then
        exit_fn
    else
        echo 'Bad user input'
        echo
        read -p 'Press enter to try again.'
        echo
        cleanup_fn
    fi
}

make_dir()
{
    remove_dir "$1"
    if ! mkdir "$1"; then
        printf "\n Failed to create dir %s" "$1"
        echo
        exit 1
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
            echo
            echo "The script failed to download \"$1\" and will try again in 10 seconds"
            sleep 10
            echo
            if ! curl -Lso "$dl_path/$dl_file" "$1"; then
                echo
                echo "The script failed to download \"$1\" two times and will exit the build"
                echo
                fail_fn
            fi
        fi
        echo 'Download Completed'
        echo
    else
        echo "$dl_file is already downloaded"
    fi

    make_dir "$dl_path/$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" &>/dev/null; then
            fail_fn "Failed to extract $dl_file"
        fi
    else
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" --strip-components 1 &>/dev/null; then
            fail_fn "Failed to extract $dl_file"
        fi
    fi

    echo "File extracted: $dl_file"

    cd "$dl_path/$target_dir" || fail_fn "Unable to change the working directory to $target_dir"
}

download_git()
{
    dl_path="$packages"
    dl_url="$1"
    dl_file="$2"
    dl_args="$3"
    target_dir="$dl_path/$dl_file"

    if [ -n "$dl_args" ]; then
        dl_url+=" $dl_args"
        dl_full="git clone -q $dl_url $target_dir"
    else
        dl_full="git clone -q $dl_url $target_dir"
    fi

    # first download attempt
    if [ ! -d "$target_dir" ]; then
        echo "Downloading $dl_file"
        if ! $dl_full; then
            echo
            echo "The script failed to download \"$dl_file\" and will try again in 10 seconds"
            sleep 10
            echo
            if ! $dl_full; then
                echo
                echo "The script failed to download \"$dl_file\" two times and will exit the build"
                fail_fn
            fi
        fi
        echo 'Download Complete'
        echo
    else
        echo "$dl_file is already downloaded"
    fi

    cd "$target_dir" || (
        echo 'Script error!'
        echo
        echo "Unable to change the working directory to $target_dir"
        fail_fn
    )
}

execute()
{
    echo "$ $*"

    if ! output=$("$@" 2>&1); then
        fail_fn "Failed to Execute $*" 
    fi
}

build()
{
    echo
    echo "building $1 - version $2"
    echo '===================================='

    if [ -f "$packages/$1.done" ]; then
        if grep -Fx "$2" "$packages/$1.done" 2>/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        elif $latest; then
            echo "$1 is outdated and will be rebuilt using version $2"
            return 0
        else
            echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $packages/$1.done lockfile."
            return 1
        fi
    fi

    return 0
}

command_exists()
{
    if ! [[ -x $(command -v "$1") ]]; then
        return 1
    fi

    return 0
}

library_exists()
{

    if ! [[ -x "$(pkg-config --exists --print-errors "$1" 2>&1 >/dev/null)" ]]; then
        return 1
    fi

    return 0
}

jxl_install_fn()
{
    for i in *.deb
    do
        sudo apt-get -y install ./"$i" >/dev/null
    done
}

build_done() { echo "$2" > "$packages/$1.done"; }

installed() { return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }


# PRINT THE OPTIONS AVAILABLE WHEN MANUALLY RUNNING THE SCRIPT
usage()
{
    echo "Usage: $progname [OPTIONS]"
    echo
    echo 'Options:'
    echo '    -h, --help                                         Display usage information'
    echo '            --version                                    Display version information'
    echo '    -b, --build                                        Starts the build process'
    echo '            --enable-gpl-and-non-free    Enable GPL and non-free codecs    - https://ffmpeg.org/legal.html'
    echo '    -c, --cleanup                                    Remove all working dirs'
    echo '            --latest                                     Build latest version of dependencies if newer available'
    echo '            --full-static                            Build a full static FFmpeg binary (eg. glibc, pthreads, etc...) **only Linux**'
    echo '                                                                 Note: Because of the NSS (Name Service Switch), glibc does not recommend static links.'
    echo
}

clear
echo "ffmpeg-build-script v$script_ver"
echo '======================================'

echo
echo "The script will utilize $cpu_threads CPU cores for parallel processing to accelerate the build speed."

while (($# > 0)); do
    case $1 in
    -h | --help)
        usage
        exit 0
        ;;
    --version)
        echo "$script_ver"
        exit 0
        ;;
    -*)
        if [[ "$1" == '--build' || "$1" =~ '-b' ]]; then
            bflag='-b'
        fi
        if [[ "$1" == '--enable-gpl-and-non-free' ]]; then
            cnf_ops+=('--enable-nonfree')
            cnf_ops+=('--enable-gpl')
            nonfree='true'
        fi
        if [[ "$1" == '--cleanup' || "$1" =~ '-c' && ! "$1" =~ '--' ]]; then
            cflag='-c'
            cleanup_fn
        fi
        if [[ "$1" == '--full-static' ]]; then
            LDEXEFLAGS='-static'
        fi
        if [[ "$1" == '--latest' ]]; then
            latest='true'
        fi
        shift
        ;;
    *)
        usage
        echo
        fail_fn
        ;;
    esac
done

if [ -z "$bflag" ]; then
    if [ -z "$cflag" ]; then
        usage
    fi
    exit 0
fi

##
## required build packages
##

build_pkgs_fn()
{
    echo
    echo 'Installing required development packages'
    echo '=========================================='

    pkgs=(autoconf automake build-essential google-perftools jq libc-devtools libcpu-features-dev libcrypto++-dev \
          libdmalloc-dev libdmalloc5 libgc-dev libgc1 libgl2ps-dev libglib2.0-dev libgoogle-perftools-dev \
          libgoogle-perftools4 libheif-dev libjemalloc-dev libjemalloc2 libjpeg-dev libmagickcore-6.q16hdri-dev \
          libmimalloc-dev libmimalloc2.0 libopenjp2-7-dev libpng++-dev libpng-dev libpng-tools libpng16-16 \
          libpstoedit-dev libraw-dev librust-bzip2-dev librust-jpeg-decoder+default-dev libtcmalloc-minimal4 \
          libtiff-dev libtool libwebp-dev libzip-dev lld perlmagick pstoedit)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        for pkg in "$missing_pkgs"
        do
            if sudo apt -y install $pkg; then
                echo
                echo 'The required development packages were installed.'
                echo
            else
                fail_fn 'The required development packages failed to install'
            fi
        done
        echo 'The required development packages are already installed.'
    fi
}

# install required apt packages
build_pkgs_fn

# PULL THE LATEST VERSIONS OF EACH PACKAGE FROM THE WEBSITE API
curl_timeout='5'

git_1_fn()
{
    # SCRAPE GITHUB WEBSITE FOR LATEST REPO VERSION
    github_repo="$1"
    github_url="$2"

    if curl_cmd="$(curl \
        -m "$curl_timeout" \
        --request GET \
        --url "https://api.github.com/slyfox1186" \
        --header "Authorization: Bearer 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" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        -sSL "https://api.github.com/repos/$github_repo/$github_url")"; then

        g_ver=$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)
        g_ver=${g_ver#v}
        g_ver_lcsm2="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_ver_lcsm2="${g_ver_lcsm2#Little CMS }"
        g_ver_ssl="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_ver_ssl="${g_ver_ssl#OpenSSL }"
        g_ver_pkg="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_ver_pkg="${g_ver_pkg#pkg-config-}"
        g_ver_zimg="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_ver_zimg="${g_ver_zimg#release-}"
        g_ver_libva="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_ver_libva="${g_ver_libva#Libva }"
        g_ver_llvm="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_ver_llvm="${g_ver_llvm#LLVM }"
        g_ver_gpdl="${g_ver#Ghostscript/GhostPDL }"
        g_url_gpdl="$(echo "$curl_cmd" | jq -r '.[0].assets[3].browser_download_url' 2>/dev/null)"
        g_url_gs="$(echo "$curl_cmd" | jq -r '.[0].assets[5].browser_download_url' 2>/dev/null)"
        g_url="$(echo "$curl_cmd" | jq -r '.[0].tarball_url')"
    fi
}

git_2_fn()
{
    github_repo="$1"
    github_url="$2"
    if curl_cmd=$(curl -m "$curl_timeout" -sSL "https://code.videolan.org/api/v4/projects/$videolan_repo/repository/$github_url"); then
        v_ver=$(echo "$curl_cmd" | jq -r '.[0].commit.id')
        v_sver1=$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')
        v_sver2=$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)
        v_sver2=${v_sver2#v}
    fi
}

git_3_fn()
{
    gitlab_repo="$1"

    if curl_cmd=$(curl -m "$curl_timeout" -sSL "https://gitlab.com/api/v4/projects/$gitlab_repo/repository/branches"); then
        gitlab_ver0=$(echo "$curl_cmd" | jq -r '.[0].commit.id')
        gitlab_ver0=${gitlab_ver0#v}
        gitlab_sver0=$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')
        gitlab_ver3=$(echo "$curl_cmd" | jq -r '.[3].commit.id')
        gitlab_ver3=${gitlab_ver3#v}
        gitlab_sver3=$(echo "$curl_cmd" | jq -r '.[3].commit.short_id')
    fi
}

git_4_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$curl_timeout" -sSL "https://gitlab.com/api/v4/projects/$gitlab_repo/repository/tags"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)
        gitlab_ver=${gitlab_ver#v}
        gitlab_sver=$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')
    fi
}

git_5_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$curl_timeout" -sSL "https://gitlab.freedesktop.org/api/v4/projects/$gitlab_repo/repository/tags"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)
    fi
}

git_6_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL 'https://bitbucket.org/!api/2.0/repositories/multicoreware/x265_git/effective-branching-model')"; then
        gitlab_ver=$(echo "$curl_cmd" | jq '.development.branch.target' | grep -Eo '[0-9a-z][0-9a-z]+' | sort | head -n 1)
    fi
}

git_7_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$curl_timeout" -sSL "https://gitlab.gnome.org/api/v4/projects/$gitlab_repo/repository/tags"); then
        g_ver=$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)
        g_ver=${g_ver#v}
    fi
}

git_8_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$curl_timeout" -sSL "https://git.archive.org/api/v4/projects/$gitlab_repo/repository/tags"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)
        gitlab_ver=${gitlab_ver#v}
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

    if [  "$v_flag" = 'T' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn' gv_url='tags'
    elif [ "$v_flag" = 'T' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn' gv_url='tags'
    fi

    if [  "$v_flag" = 'R' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn'; gv_url='releases'
    fi

    case "$v_tag" in
        2)          url_tag='git_2_fn';;
        3)          url_tag='git_3_fn';;
        4)          url_tag='git_4_fn';;
        5)          url_tag='git_5_fn';;
        6)          url_tag='git_6_fn';;
        7)          url_tag='git_7_fn';;
        8)          url_tag='git_8_fn';;
    esac

    "$url_tag" "$v_url" "$gv_url" 2>/dev/null
}

dmalloc_alias_fn()
{
    local dmalArray my_shell test_bourne_shell

    dmalArray=('.bashrc' '.zshrc' '.kshrc')
    for shell in ${dmalArray[@]}
    do
        case $shell in
            '.bashrc')           my_shell='1';;
             '.zshrc')           my_shell='2';;
             '.kshrc')           my_shell='3';;
                    *)           fail_fn 'Bad user input';;
        esac
    done


    if [ "$my_shell" -eq '1' ]; then execute echo 'function dmalloc { eval `command dmalloc -b $*`; }' | tee -a "$HOME"/.bashrc; fi
    if [ "$my_shell" -eq '2' ]; then execute echo 'function dmalloc { eval `command dmalloc -b $*`; }' | tee -a "$HOME"/.zshrc; fi
    if [ "$my_shell" -eq '3' ]; then execute echo 'function dmalloc { eval `command dmalloc -b $*`; }' | tee -a "$HOME"/.kshrc; fi
}

git_ver_fn 'freedesktop/pkg-config' '1' 'T'
# set the pkg-config path
PKG_CONFIG_PATH="\
$packages/pkg-config-$g_ver_pkg:\
$workspace/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/i386-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig\
"
export PKG_CONFIG_PATH

LD_LIBRARY_PATH="\
$workspace/lib:\
$workspace/share/ghostscript/10.01.1/lib:\
/usr/lib:\
/usr/x86_64-linux-gnux32/lib:\
/usr/local/lib:\
/usr/local/lib/x86_64-linux-gnu:\
/usr/src/linux-hwe-5.19-headers-5.19.0-38/lib:\
/usr/share/git-gui/lib:\
/usr/share/gitk/lib:\
/usr/share/lintian/lib:\
/usr/share/texinfo/lib:\
/usr/lib/x86_64-linux-gnu/lib\
"
export LD_LIBRARY_PATH

##
## make output directories
##

if [ ! -d "$workspace" ] || [ ! -d "$packages" ]; then
    mkdir -p "$packages" "$workspace" 2>/dev/null
fi

##
## start source code building
##

git_ver_fn 'Kitware/CMake' '1' 'T'
if build 'cmake' "$g_ver" "$packages/$1.done"; then
    download "$g_url" "cmake-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --parallel="$cpu_threads" -- -DCMAKE_USE_OPENSSL='OFF'
    execute make -j "$cpu_threads"
    execute make install
    build_done 'cmake' "$g_ver"
fi

git_ver_fn 'google/brotli' '1' 'R'
if build 'brotli' "$g_ver"; then
    download "$g_url" "brotli-$g_ver.tar.gz"
    make_dir 'out'
    cd 'out' || exit 1
    execute cmake -DCMAKE_BUILD_TYPE='Release' -DCMAKE_INSTALL_PREFIX="$workspace" ..
    execute cmake --build . --config Release --target install
    build_done 'brotli' "$g_ver"
fi

git_ver_fn 'mm2/Little-CMS' '1' 'R'
if build 'lcms2' "$g_ver_lcsm2"; then
    download "$g_url" "lcms2-$g_ver_lcsm2"
    execute ./autogen.sh
    execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
    execute ninja -C build
    execute ninja -C build install
    build_done 'lcms2' "$g_ver_lcsm2"
fi

export CC='gcc' CXX='g++'

git_ver_fn 'libjxl/libjxl' '1' 'R'
if build 'libjxl' "$g_ver"; then
    download "https://github.com/libjxl/libjxl/releases/download/v0.8.1/jxl-debs-amd64-ubuntu-22.04-v0.8.1.tar.gz" "libjxl-$g_ver.tar.gz"
    jxl_install_fn
    build_done 'libjxl' "$g_ver"
fi

git_ver_fn 'j256/dmalloc' '1' 'R'
if build 'dmalloc' "$g_ver"; then
    download "$g_url" "dmalloc-$g_ver.tar.gz"
    execute sh ./configure --prefix="$workspace" --disable-cxx --enable-threads --disable-option-checking
    execute make -j "$cpu_threads"
    execute make threads -j "$cpu_threads"
    execute make install
    execute make installth
    # for dmalloc to work as intended you MUST create an alias in one of your startup shell config files
    #    such as $HOME/.bashrc file. You must log out and log back in for the changes to take effect or you
    #    can source the file like this: source $HOME/.bashrc  .... then you must run the command `dmalloc runtime`
    #    and if you see any output with DMALLOC_OPTIONS in it then the alias did not take effect.
    #    DMALLOC_OPTIONS in it then the alias did not take effect.
    dmalloc_alias_fn
    build_done 'dmalloc' "$g_ver"
fi

git_ver_fn 'libsdl-org/SDL' '1' 'R'
if build 'libsdl' "$g_ver"; then
    download "$g_url" "libsdl-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libsdl' "$g_ver"
fi

if command_exists 'python3'; then
    # dav1d needs meson and ninja along with nasm to be built
    if command_exists 'pip3'; then
        # meson and ninja can be installed via pip3
        if ! pip3 show setuptools; then
                execute pip3 install pip setuptools --quiet --upgrade --no-cache-dir --disable-pip-version-check
        fi
        for r in meson ninja ninja-syntax
        do
            if ! command_exists $r; then
                execute pip3 install $r --quiet --upgrade --no-cache-dir --disable-pip-version-check
            fi
            export PATH="$PATH:$HOME/Library/Python/3.9/bin"
        done
    fi
fi

png_ver='1.2.59'
if build 'libpng12' "$png_ver"; then
    download "https://github.com/glennrp/libpng/archive/refs/tags/v$png_ver.tar.gz" "libpng-$png_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make install
    build_done 'libpng12' "$png_ver"
fi

CC='clang' CXX='clang++'
export CC CXX

git_ver_fn 'llvm/llvm-project' '1' 'R'
if build 'llvm' "$g_ver_llvm"; then
    download "$g_url" "llvm-$g_ver_llvm.tar.gz"
    execute cmake -S llvm -B build -G 'Ninja' -DCMAKE_INSTALL_PREFIX="$workspace" \
        -DCMAKE_BUILD_TYPE='Release' -DLLVM_ENABLE_ASSERTIONS='OFF' -DLLVM_USE_LINKER='lld' \
        -DLLVM_PARALLEL_{COMPILE,LINK}_JOBS="$cpu_threads"
    ninja -C build install
    build_done 'llvm' "$g_ver_llvm"
fi

CC='gcc-12' CXX='g++-12'
export CC CXX

if build 'm4' '1.4.19'; then
    download 'https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-static --disable-shared  --enable-c++ --with-dmalloc
    execute make -j "$cpu_threads"
    execute make install
    build_done 'm4' '1.4.19'
fi

if build 'libtool' '2.4.7'; then
    download 'https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz'
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libtool' '2.4.7'
fi
CFLAGS+=" -I$workspace/include/libltdl"

git_ver_fn '1665' '7'
if build 'libxml' "$g_ver"; then
    download "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$g_ver/libxml2-v$g_ver.tar.bz2" "libxml-$g_ver.tar.bz2"
    execute ./autogen.sh --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libxml' "$g_ver"
fi

git_ver_fn 'madler/zlib' '1' 'T'
if build 'zlib' "$g_ver"; then
    download "$g_url" "zlib-$g_ver"
    execute ./configure --prefix="$workspace" --static 
    execute make -j "$cpu_threads"
    execute make install
    build_done 'zlib' "$g_ver"
fi

if build 'flif' 'git'; then
    download_git 'https://github.com/ImageMagick/flif.git' 'flif-git'
    execute make flif -j "$cpu_threads"
    execute sudo make install
    build_done 'flif' 'git'
fi

if build 'libfpx' 'git'; then
    download_git 'https://github.com/ImageMagick/libfpx.git' 'libfpx-git'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libfpx' 'git'
fi

git_ver_fn '890' '5'
if build 'fontconfig' "$gitlab_ver"; then
    download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$gitlab_ver/fontconfig-$gitlab_ver.tar.bz2" "fontconfig-$gitlab_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --sysconfdir="$workspace"/etc/ --mandir="$workspace"/share/man/ --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'fontconfig' "$gitlab_ver"
fi

git_ver_fn '7950' '5'
if build 'freetype' "$gitlab_ver"; then
    extracommands=(-D{harfbuzz,png,bzip2,brotli,zlib,tests}"=disabled")
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/$gitlab_ver/freetype-$gitlab_ver.tar.bz2" "freetype-$gitlab_ver.tar.bz2"
    execute ./autogen.sh
    execute cmake -S . -B 'build/release-static' -DCMAKE_INSTALL_PREFIX="$workspace" \
        -DVVDEC_ENABLE_LINK_TIME_OPT='OFF' -DCMAKE_VERBOSE_MAKEFILE='OFF' -DCMAKE_BUILD_TYPE='Release' "${extracommands[@]}"
    execute cmake --build 'build/release-static' -j
    build_done 'freetype' "$gitlab_ver"
fi

if build 'djvu' '3.5.28'; then
    download 'http://downloads.sourceforge.net/djvu/djvulibre-3.5.28.tar.gz' 'djvu-3.5.28'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-desktopfiles='no' --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'djvu' '3.5.28'
fi

if build 'bzlib' 'git'; then
    download_git 'https://github.com/ImageMagick/bzlib.git' 'bzlib-git'
    execute make -j "$cpu_threads"
    execute make install PREFIX="$workspace"
    build_done 'bzlib' 'git'
fi

git_ver_fn 'ArtifexSoftware/ghostpdl-downloads' '1' 'R'
if build 'GhostPDL' "$g_ver_gpdl"; then
    download "$g_url_gpdl" "GhostPDL-$g_ver_gpdl.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'GhostPDL' "$g_ver_gpdl"
fi

git_ver_fn 'ArtifexSoftware/ghostpdl-downloads' '1' 'R'
if build 'ghostscript' "$g_ver_gpdl"; then
    download "$g_url_gs" "ghostscript-$g_ver_gpdl.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'ghostscript' "$g_ver_gpdl"
fi

# REMOVE ANY FILES FROM PRIOR RUNS
if [ -d "$packages/ImageMagick-$g_ver" ]; then
    rm -fr "$packages/ImageMagick-$g_ver"
fi

# REMOVE ANY LOCKFILES FROM PRIOR RUNS
if [ -f "$packages/ImageMagick.done" ]; then
    rm -fr "$packages/ImageMagick.done"
fi

git_ver_fn 'ImageMagick/ImageMagick' '1' 'T'
if build 'ImageMagick' "$g_ver"; then
    download "https://imagemagick.org/archive/releases/ImageMagick-$g_ver.tar.xz" "ImageMagick-$g_ver.tar.xz"
    ./configure \
        --prefix="$workspace" \
        --disable-docs \
        --disable-shared \
        --enable-ccmalloc \
        --enable-hdri \
        --enable-legacy-support \
        --enable-static \
        --with-autotrace \
        --with-bzlib \
        --with-djvu \
        --with-dmalloc \
        --with-flif \
        --with-fontconfig \
        --with-fpx \
        --with-freetype \
        --with-gnu-ld \
        --with-gs-font-dir='/usr/share/ghostscript/fonts' \
        --with-gslib \
        --with-gvc \
        --with-heic \
        --with-jbig \
        --with-jemalloc \
        --with-jpeg \
        --with-lcms \
        --with-lqr \
        --with-magick-plus-plus \
        --with-modules \
        --with-openexr \
        --with-perl \
        --with-png \
        --with-quantum-depth=16 \
        --with-tcmalloc \
        --with-tiff \
        --with-windows-font-dir \
        --with-wmf \
        --with-x \
        --with-xml \
        --with-zlib \
        --disable-silent-rules \
        --without-dps \
        CFLAGS="$CFLAGS -fopenmp -Wall -g -O2 -mtune=amdfam10 -fexceptions -pthread" \
        LIBS='-llcms2 -lfreetype -lraqm -lfreetype -llqr-1 -lglib-2.0 -lxml2 -lfontconfig -lfreetype -lXext -lSM -lICE -lX11 -lXt -lbz2 -lz -lzip -lltdl -lm -ljemalloc -lpthread -ltcmalloc_minimal'
    build_done 'ImageMagick' "$g_ver"
fi

sudo make -j "$cpu_threads"
sudo make install

# ldconfig must be run next in order to update file changes or the magick command will not work
sudo ldconfig /usr/local/lib 2>/dev/nullldconfig '/usr/local/lib' 2>/dev/null

# show the newly installed magick version
if ! magick -version 2>/dev/null; then
    printf "\n%s\n%s\n\n%s\n\n%s\n\n" \
        'Script error!' \
        '    - Failure to execute the command: magick -version' \
        'If help is required or to report bugs please create a support ticket' \
        'https://github.com/slyfox1186/build-imagemagick/issues'
    fail_fn
fi

# prompt the user to cleanup the build files
cleanup_fn
