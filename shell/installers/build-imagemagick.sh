#!/bin/bash

#################################################################
##
## github: https://github.com/slyfox1186
##
## purpose: builds imagemagick 7 from source code that is
##          obtained from the official imagemagick github page.
##
## function: imagemagick is the leading open source command line
##           image processor. it can blur, sharpen, warp, reduce
##           file size, ect... it is fantastic.
##
## updated: 03.18.23
##
#################################################################

# verify the script does not have root access before continuing
if [ "${EUID}" -ne '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exec sudo bash "${0}" "${@}"
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
    github_repo="${1}"
    curl_cmd=$(curl -m "${net_timeout}" -Ls "https://api.github.com/repos/${github_repo}/releases?per_page=1")
    if [ "${?}" -eq '0' ]; then
        github_ver=$(echo "${curl_cmd}" | jq -r '.[].name')
        github_ver=${github_ver#v}
    fi
}

# call the github_api_fn function to get the latest version of imagemagick
github_api_fn 'ImageMagick/ImageMagick' 2>/dev/null

# set variables
progname='ImageMagick'
script_ver='2.00'
png_ver='1.2.59'
magick_ver="${github_ver}"
packages="${PWD}"/packages

exit_fn()
{
    clear

    # show the newly installed magick version
    if ! magick -version 2>/dev/null; then
        clear
        echo '$ error the script failed to execute the command "magick -version"'
        echo
        echo '$ Try running the command manually first and if needed create a support ticket by visiting:'
        echo '$ https://github.com/slyfox1186/script-repo/issues'
        echo
        exit 1
    fi

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
    echo "$ ${*}"

    output=$("${@}" 2>&1)

    # shellcheck disable=SC2181
    if [ "${?}" -ne '0' ]; then
        echo "${output}"
        echo
        echo "Failed to Execute ${*}" >&2
        echo
        exit 1
    fi
}

build()
{
    echo
    echo "building ${1} - version ${2}"
    echo '========================================'

    if [ -f "${packages}/${1}.done" ]; then
        if grep -Fx "${2}" "${packages}/${1}.done" >/dev/null; then
            echo "${1} version ${2} already built. Remove ${packages}/${1}.done lockfile to rebuild it."
            return 1
        elif ${latest}; then
            echo "${1} is outdated and will be rebuilt using version ${2}"
            return 0
        else
            echo "${1} is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove ${packages}/${1}.done lockfile."
            return 1
        fi
    fi

    return 0
}

build_done() { echo "${2}" > "${packages}/${1}.done"; }

cleanup_fn()
{
 
    # prompt user to clean up build files
    clear
    echo '$ Do you want to remove the build files?'
    echo
    echo '[1] Yes'
    echo '[2] No'
    echo
    read -p 'Your choices are (1 or 2): ' cleanup_choice
    clear

    if [[ "${cleanup_choice}" -eq '1' ]]; then
        remove_dir "${packages}"
        remove_file "${0}"
        exit_fn
    elif [[ "${1}" -eq '2' ]]; then
        exit_fn
    else
        echo 'Bad user input'
        echo
        read -p 'Press enter to try again.'
        clear
        cleanup_fn
    fi
}

download()
{

    dl_path="${packages}"
    dl_file="${2:-"${1##*/}"}"

    if [[ "${dl_file}" =~ tar. ]]; then
        tdir="${dl_file%.*}"
        tdir="${3:-"${tdir%.*}"}"
    else
        tdir="${3:-"${dl_file%.*}"}"
    fi

    if [ ! -f "${dl_path}/${dl_file}" ]; then
        echo "Downloading ${1} as ${dl_file}"
        curl -Lso "${dl_path}/${dl_file}" "${1}"

        ec="${?}"
        if [ "${ec}" -ne '0' ]; then
            echo
            echo "Failed to download ${1}. Exitcode ${ec}. Retrying in 10 seconds"
            echo
            read -t 10 -p 'Press enter to skip waiting.'
            echo
            curl -Lso "${dl_path}/${dl_file}" "${1}"
        fi

        ec="${?}"
        if [ "${ec}" -ne '0' ]; then
            echo
            echo "Failed to download ${1}. Exitcode ${ec}"
            echo
            exit 1
        fi

        echo 'Download Complete...'
        echo
    else
        echo "${dl_file} is already downloaded."
    fi

    make_dir "${dl_path}/${tdir}"

    if [[ "${dl_file}" == *'patch'* ]]; then
        return
    fi

    if [ -n "${3}" ]; then
        if ! tar -xf "${dl_path}/${dl_file}" -C "${dl_path}/${tdir}" &>/dev/null; then
            echo "Failed to extract ${dl_file}"
            echo
            exit 1
        fi
    else
        if ! tar -xf "${dl_path}/${dl_file}" -C "${dl_path}/${tdir}" --strip-components 1 &>/dev/null; then
            echo "Failed to extract ${dl_file}"
            echo
            exit 1
        fi
    fi

    echo "Extracted ${dl_file}"

    cd "${dl_path}/${tdir}" || (
        echo 'Script error!'
        echo
        echo "Unable to change the working directory to ${tdir}"
        echo
        exit 1
    )

}

make_dir()
{
    remove_dir "${1}"
    if ! mkdir "${1}"; then
        printf "\n Failed to create dir %s" "${1}"
        echo
        exit 1
    fi
}

remove_file()
{
    if [ -f "${1}" ]; then
        rm -f "${1}"
    fi
}

remove_dir()
{
    if [ -d "${1}" ]; then
        rm -fr "${1}"
    fi
}

## determine if a package is installed or not
installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

## failed download/extraction
extract_fail_fn()
{
    clear
    echo 'Error: The tar command failed to extract any files'
    echo
    echo 'To create a support ticket visit: https://github.com/slyfox1186/script-repo/issues'
    echo
    exit 1
}

## required imagemagick developement packages
magick_packages_fn()
{

    pkgs='autoconf automake build-essential google-perftools jq libc-devtools libcpu-features-dev libcrypto++-dev libdmalloc-dev libdmalloc5 libgc-dev libgc1 libgl2ps-dev libglib2.0-dev libgoogle-perftools-dev libgoogle-perftools4 libheif-dev libjemalloc-dev libjemalloc2 libjpeg-dev libmagickcore-6.q16hdri-dev libmimalloc-dev libmimalloc2.0 libopenjp2-7-dev libpng++-dev libpng-dev libpng-tools libpng16-16 libpstoedit-dev libraw-dev librust-bzip2-dev librust-jpeg-decoder+default-dev libtcmalloc-minimal4 libtiff-dev libtool libwebp-dev libzip-dev pstoedit'

    for pkg in ${pkgs[@]}
    do
        if ! installed "${pkg}"; then
            missing_pkgs+=" ${pkg}"
        fi
    done

    if [ -n "${missing_pkgs-}" ]; then
        for i in "${missing_pkgs}"
        do
            apt -y install ${i}
        done
        echo '$ The required packages were successfully installed'
        echo
    else
        echo '$ The required packages are already installed'
        echo
    fi
}

# PRINT THE OPTIONS AVAILABLE WHEN MANUALLY RUNNING THE SCRIPT
usage()
{
    echo "Usage: ${progname} [options]"
    echo
    echo 'Options:'
    echo '    -h, --help                                           Display usage information'
    echo '            --version                                    Display version information'
    echo '    -b, --build                                          Starts the build process'
    echo '    -c, --cleanup                                        Remove all working dirs'
    echo
}

echo "imagemagick-build-script v${script_ver}"
echo '======================================'
echo

while ((${#} > 0)); do
    case ${1} in
    -h | --help)
        usage
        exit 0
        ;;
    --version)
        echo current magick version: "${magick_ver}"
        echo
        exit 0
        ;;
    -*)
        if [[ "${1}" == '--build' || "${1}" =~ '-b' ]]; then
            bflag='-b'
        fi
        if [[ "${1}" == '--cleanup' || "${1}" =~ '-c' && ! "${1}" =~ '--' ]]; then
            cflag='-c'
            cleanup_fn
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

echo "This script will utilize ${cpus} cpu cores for parallel processing to accelerate the build speed."
echo

if [ -z "${bflag}" ]; then
    if [ -z "${cflag}" ]; then
        usage
        echo
        exit 1
    fi
    exit 0
fi

echo '$ installing required packages'
echo '======================================'

# required + extra functionality packages for imagemagick
magick_packages_fn

mkdir -p "${packages}"

# export the pkg config paths to enable support during the build
PKG_CONFIG_PATH="\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig:\
"
export PKG_CONFIG_PATH

##
## start libpng12 build
##

if build 'libpng12' "${png_ver}"; then
    download "https://sourceforge.net/projects/libpng/files/libpng12/${png_ver}/libpng-${png_ver}.tar.xz/download" "libpng-${png_ver}.tar.xz"
    # parellel building not available for this library
    execute ./autogen.sh
    execute ./configure --prefix='/usr/local'
    execute make install
    build_done 'libpng12' "${png_ver}"
fi

##
## start imagemagick build
##

if build 'imagemagick' "${magick_ver}"; then
    download "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${magick_ver}.tar.gz" "ImageMagick-${magick_ver}.tar.gz"
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
    execute make "-j${cpus}"
    execute make install
    build_done 'imagemagick' "${magick_ver}"
fi

# ldconfig must be run next in order to update file changes or the magick command will not work
ldconfig /usr/local/lib 2>/dev/null

# prompt the user to cleanup the build files
cleanup_fn
