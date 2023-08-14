#!/bin/bash
# shellcheck disable=SC2046,SC2068,SC2119,SC2162

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
if [ "$EUID" -ne '0' ]; then
    exec sudo bash "$0" "$@"
fi

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

# find the latest version by querying github's api
github_api_fn()
{
    # scrape github website for latest repo version
    net_timeout='5'
    github_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" -Ls "https://api.github.com/repos/$github_repo/releases?per_page=1"); then
        github_ver=$(echo "$curl_cmd" | jq -r '.[].name')
        github_ver=${github_ver#v}
    fi
}

# call the github_api_fn function to get the latest version of imagemagick
github_api_fn 'ImageMagick/ImageMagick' 2>/dev/null

# set variables
progname='ImageMagick'
script_ver='2.2'
png_ver='1.2.59'
magick_ver="$github_ver"
packages="$PWD"/packages

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

    output=$("$@" 2>&1)

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
    fname="$(basename "$0")"
    if which 'jq' &>/dev/null; then
        printf "%s\n\n%s\n\n" \
        "The latest version of ImageMagick is: $magick_ver" \
        "To install execute: sudo bash $fname --build"
        exit 0
    else
        printf "%s\n\n%s\n\n%s\n%s\n\n" \
        'The required package "jq" must be installed for this command to work.' \
        'Excute one of the following commands to install.' \
        'sudo apt install jq' \
        "sudo bash $fname"
        exit 1
    fi
}

make_dir()
{
    remove_dir "$1"
    if ! mkdir "$1"; then
        printf "\nFailed to create dir %s" "$1"
        echo
        exit 1
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

## failed download/extraction
extract_fail_fn()
{
    clear
    printf "%s\n\n%s\n\n%s\n\n" 'The tar command failed to extract any files.' 'Please create a support ticket at the address below' 'https://github.com/slyfox1186/script-repo/issues'
    echo
    exit 1
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
        curl -Lso "$dl_path/$dl_file" "$1"

        exit_code="$?"
        if [ "$exit_code" -ne '0' ]; then
            echo
            echo "Failed to download $1. Exitcode $exit_code. Retrying in 10 seconds"
            echo
            read -t 10 -p 'Press enter to skip waiting.'
            echo
            curl -Lso "$dl_path/$dl_file" "$1"
        fi

        exit_code="$?"
        if [ "$exit_code" -ne '0' ]; then
            echo
            echo "Failed to download: $1. Exitcode $exit_code"
            echo
            exit 1
        fi

        echo 'Download Complete...'
        echo
    else
        echo "$dl_file is already downloaded."
    fi

    make_dir "$dl_path/$target_dir"

    if [[ "$dl_file" == *'patch'* ]]; then
        return
    fi

    if [ -n "$3" ]; then
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" &>/dev/null; then
            echo "Failed to extract: $dl_file"
            echo
            exit 1
        fi
    else
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" --strip-components 1 &>/dev/null; then
            echo "Failed to extract: $dl_file"
            echo
            exit 1
        fi
    fi

    echo "Extracted $dl_file"

    cd "$dl_path/$target_dir" || (
        echo "Error: Unable to change the working directory to: $target_dir"
        echo
        exit 1
    )

}

## determine if a package is installed or not
installed() { return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

## required imagemagick developement packages
magick_packages_fn()
{
    pkgs=(autoconf automake build-essential google-perftools jq libc-devtools libcpu-features-dev \
          libcrypto++-dev libdmalloc-dev libdmalloc5 libgc-dev libgc1 libgl2ps-dev libglib2.0-dev \
          libgoogle-perftools-dev libgoogle-perftools4 libheif-dev libjemalloc-dev libjemalloc2 libjpeg-dev \
          libmagickcore-6.q16hdri-dev libopenjp2-7-dev libpng++-dev libpng-dev libpng-tools libpng16-16 \
          libpstoedit-dev libraw-dev librust-bzip2-dev librust-jpeg-decoder+default-dev librust-malloc-buf-dev \
          libtcmalloc-minimal4 libtiff-dev libtool libvmmalloc-dev libvmmalloc1 libwebp-dev libzip-dev pstoedit)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "${missing_pkgs-}" ]; then
        for i in "$missing_pkgs"
        do
            apt -y install $i
        done
        printf "\n%s\n\n%s\n\n" \
            'The required packages were successfully installed.' \
            'Please execute the script again to finish installing ImageMagick.'
        exit 0
    else
        echo 'The required packages are already installed.'
    fi
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
            usage
            echo
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

clear
echo
echo 'Starting the build process...'
echo
echo "ImageMagick Build Script v$script_ver"
echo '=========================================='
echo

echo "This script will use ($cpus cpu cores) for parallel processing to accelerate the build speed."
echo

# Required + extra functionality packages for imagemagick
echo 'Installing required packages'
echo '=========================================='
echo
magick_packages_fn

# Export the pkg-config paths to enable support during the build
PKG_CONFIG_PATH="\
/usr/lib/i386-linux-gnu/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig:\
"
export PKG_CONFIG_PATH

# Create the packages directory
mkdir -p "$packages"

##
## Begin libpng12 build
##

if build 'libpng12' "$png_ver"; then
    download "https://github.com/glennrp/libpng/archive/refs/tags/v$png_ver.tar.gz" "libpng-$png_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix='/usr/local'
    execute make install
    build_done 'libpng12' "$png_ver"
fi

##
## Begin imagemagick build
##

if build 'ImageMagick' "$magick_ver"; then
    download "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/$magick_ver.tar.gz" "ImageMagick-$magick_ver.tar.gz"
    execute ./configure \
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
        --with-quantum-depth=16
    execute make "-j$cpus"
    execute make install
    build_done 'ImageMagick' "$magick_ver"
fi

# ldconfig must be run next in order to update file changes or the magick command will not work
echo
ldconfig /usr/local/lib 2>/dev/null

# show the newly installed magick version
if ! magick -version 2>/dev/null; then
    clear
    echo 'Error: The script failed to execute the command "magick -version"'
    echo
    echo 'Try running the command manually and if needed create a support ticket'
    echo 'https://github.com/slyfox1186/script-repo/issues'
    echo
    exit 1
fi

# prompt the user to cleanup the build files
cleanup_fn
