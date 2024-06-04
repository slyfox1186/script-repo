#!/usr/bin/env bash
# Shellcheck disable=sc1091,sc2000,sc2034,sc2046,sc2066,sc2068,sc2086,sc2162,sc2317

#############################################################################################################
##
##  Github: https://github.com/slyfox1186/script-repo
##
##  Script version
##
##    - 3.1.3
##
##  Updated on
##
##    - 11.08.23
##
##  Purpose:
##
##    - build FFmpeg from source code with addon development libraries also compiled from
##      Source to help ensure the latest functionality
##
##  Supported Distro:
##
##    - arch Linux
##    - debian (11|12)
##    - ubuntu (20|22|23).04
##
##  Supported architecture:
##
##    - x86_64
##
##  Arch Linux notes
##
##    - required pacman packages for ArchLinux
##    - updated the source code libraries to compile successfully using a partial mix of AUR (Arch User Repository)
##    - removed the AUR install of libbluray as it was not needed and can be done with the GitHub repository
##
##  Geforce CUDA SDK Toolkit notes
##
##    - updated to version 12.3.0
##    - reverted the nv-codec-headers to version n12.0.16.1 due to a 20% decrease in fps using x265 with nvenc cuda
##    - if the cuda libraries are not installed (for Geforce graphics cards only) the user will be prompted
##      By the script to install them so that hardware acceleration is enabled during the build
##
##  Updated
##
##    - abseil library
##    - aom/av1 library
##    - libvpx library
##    - rav1e library to version p20231024 (10.21.23)
##    - x265 library
##
##  Added
##
##    - set the x265 libs to be built with clang because it gives better FPS output than when built with gcc
##    - cunit support library for libmysofa
##    - cyanrip software
##    - cyanrip libcurl support library for
##    - debian 11 (Bullseye) support
##    - debian 12 (Bookworm) support
##    - opencl and libpulse support libraries
##    - ubuntu 23.04 (Lunar) support
##    - vapoursynth library support
##    - windows WSL2 support
##    - ndi SDK for Linux Support
##    - vulkan Support
##
##  Removed
##
##    - python3 build code that became useless
##    - removed support for Debian 10 (Buster)
##    - removed support for Ubuntu 18.04 (Bionic)
##
##  Fixed
##
##    - gpac was missing a required .so file from libjpeg-turbo
##    - the nvidia-smi command not being installed for Debian OS versions
##    - gpac build issue due to the sdl2 library not being found in the workspace folder
##    - libheif not building the specified plugins
##    - the code that prompts the user to install the CUDA SDK ToolKit
##    - a broken download url for the WSL version of the CUDA SDK ToolKit
##    - apt package errors for Debian 11 Bullseye
##
#############################################################################################################

# Define global variables

script_name="${0}"
script_ver=3.1.3
# Ffmpeg_ver=e531abaf3c41953618573bef9a2568f7644626b6
# Ffmpeg_sver="${ffmpeg_ver::7}"
# Ffmpeg_archive=ffmpeg-"${ffmpeg_sver}".tar.gz
# Ffmpeg_url=https://git.ffmpeg.org/gitweb/ffmpeg.git/snapshot/"${ffmpeg_ver}".tar.gz
###############################################################################
# Snapshot
# Ffmpeg_ver=963937e408fc68b5925f938a253cfff1d506f784
# Ffmpeg_sver="${ffmpeg_ver::7}"
# Ffmpeg_archive=ffmpeg-"${ffmpeg_sver}".tar.gz
# Ffmpeg_url=https://git.ffmpeg.org/gitweb/ffmpeg.git/snapshot/"${ffmpeg_ver}".tar.gz
# Stable
# Ffmpeg_sver=5.1.3
# Ffmpeg_archive=https://www.ffmpeg.org/releases/ffmpeg-"${ffmpeg_sver}".tar.gz
###############################################################################
cuda_latest_ver=12.3.0
cuda_url="https://developer.download.nvidia.com/compute/cuda/$cuda_latest_ver"
cuda_pin_url='https://developer.download.nvidia.com/compute/cuda/repos'
cwd="$PWD"/ffmpeg-build-script
packages="$cwd"/packages
workspace="$cwd"/workspace
install_dir=/usr/local
pc_type=$(gcc -dumpmachine)
LDEXEFLAGS=''
ffmpeg_libraries=()
latest=false
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
web_repo=https://github.com/slyfox1186/script-repo
curl_timeout=10
debug=OFF # Change THE DEBUG VARIABLE TO "ON" FOR HELP TROUBLESHOOTING ISSUES

# Set the available cpu thread and core count for parallel processing (speeds up the build process)

if [ -f '/proc/cpuinfo' ]; then
    cpu_threads="$(grep --count ^processor '/proc/cpuinfo')"
else
    cpu_threads="$(nproc --all)"
fi
export MAKEFLAGS="-j$(nproc --all)"

# Print script banner

clear
box_out_banner1()
{
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner1 "FFmpeg Build Script - v${script_ver}"
printf "\n%s\n\n" "The script will utilize (${cpu_threads}) CPU threads for parallel processing to accelerate the build speed."

# Set the c & c++ compilers to the highest version installed

export CC=gcc CXX=g++

# Set compiler optimization flags

source_flags_fn()
{
    EXTRALIBS="-ldl -lpthread -lm -lz -L/usr/lib/x86_64-linux-gnu -lcurl -lvulkan -L$workspace/lib -llcms2 -llcms2_threaded"
    EXTRALIBS+=" -lhwy -lbrotlidec -lbrotlienc -ltesseract -L/usr/local/cuda/targets/x86_64-linux/lib -lOpenCL"
    CXXFLAGS='-g -O2 -pipe -march=native -DHWY_COMPILE_ONLY_SCALAR'
    CFLAGS="-I$workspace/include -I$workspace/include/jxl -I$workspace/include/CL -I/usr/local/include -I/usr/include"
    CFLAGS+='-I/usr/include/x86_64-linux-gnu -I/usr/include/SDL2 -I/usr/lib/x86_64-linux-gnu/pulseaudio -I/usr/include/openjpeg-2.5'
    CFLAGS+=" -I/usr/include/vk_video -I/usr/include/vulkan ${CXXFLAGS}"
    CPPFLAGS="-I$workspace/include -I/usr/local/include -I/usr/include -I/usr/include/openjpeg-2.5 -I/usr/include/flite"
    LDFLAGS="-L$workspace/lib64 -L$workspace/lib -L$workspace/lib/x86_64-linux-gnu -L/usr/local/lib64"
    LDFLAGS+=' -L/usr/local/lib -L/usr/lib/x86_64-linux-gnu -L/usr/lib64 -L/usr/lib -L/lib64 -L/lib'
    export CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
}
source_flags_fn

# Create the output directories

mkdir -p "$packages"/nvidia-cuda "$workspace"/logs

# Define functions

exit_fn()
{
    printf "\n%s\n%s\n\n"                                         \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

fail_fn()
{
    printf "\n%s\n\n%s\n\n" \
        "$1"              \
        "To report a bug create an issue at: $web_repo/issues"
    exit 1
}

cleanup_fn()
{
    local answer

    printf "\n%s\n%s\n%s\n\n%s\n%s\n"                  \
        '============================================' \
        '  Do you want to clean up the build files?  ' \
        '============================================' \
        '[1] Yes'                                      \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer

    case "${answer}" in
        1)      sudo rm -fr "$cwd";;
        2)      echo;;
        *)
                unset answer
                clear
                cleanup_fn
                ;;
    esac
}

ff_ver_fn()
{
    printf "\n%s\n%s\n%s\n\n"                          \
        '============================================' \
        '               FFmpeg Version               ' \
        '============================================'
    ffmpeg -version
    sleep 2
}

download()
{
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

    if [ -f "${target_file}" ]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"${dl_url}\" saving as \"$dl_file\""
        if ! wget -U "$user_agent" -cqO "${target_file}" "${dl_url}"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! wget -U "$user_agent" -cqO "${target_file}" "${dl_url}"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit. Line: ${LINENO}"
            fi
        fi
        echo 'Download Completed'
    fi

    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    fi
    mkdir -p "$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "${target_file}" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "${target_file}"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: ${LINENO}"
        fi
    else
        if ! tar -xf "${target_file}" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "${target_file}"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: ${LINENO}"
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: ${LINENO}"
}

download_git()
{
    local dl_path dl_url dl_file target_dir

    dl_path="$packages"
    dl_url="$1"
    dl_file="${2:-"${1##*/}"}"
    dl_file="${dl_file//\./-}"
    target_dir="$dl_path/$dl_file"

    if [ -n "$3" ]; then
        output_dir="$dl_path/$3"
        target_dir="$output_dir"
    fi

    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    fi

    echo "Downloading ${dl_url} as $dl_file"

    if ! git clone -q "${dl_url}" "$target_dir"; then
        printf "\n%s\n\n" "The script failed to clone the directory \"$target_dir\" and will try again in 10 seconds..."
        sleep 10
        if ! git clone -q "${dl_url}" "$target_dir"; then
            fail_fn "The script failed to clone the directory \"$target_dir\" twice and will now exit the buildLine: ${LINENO}"
        fi
    else
        printf "%s\n\n" "Successfully cloned: $target_dir"
    fi

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: ${LINENO}"
}

# Create txt files to store version numbers to avoid unnecessary api calls
ver_file_tmp="$workspace"/latest-versions-tmp.txt
ver_file="$workspace"/latest-versions.txt

sed -i -e '/null-/d' -e '/null /d' -e '/-null/d' -e '/-$/d' "$ver_file_tmp" "${ver_file}" 2>/dev/null

if [ ! -f "$ver_file_tmp" ] || [ ! -f "${ver_file}" ]; then
    touch "$ver_file_tmp" "${ver_file}" 2>/dev/null
fi

# Pull the latest versions of each package from the website api

git_1_fn()
{
    local curl_cmd github_repo github_url git_token

# Scrape github website for the latest repo version
    github_repo="$1"
    github_url="$2"

    if curl_cmd="$(curl -A "$user_agent" -m "${curl_timeout}" -sSL "https://api.github.com/repos/${github_repo}/${github_url}")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_ver1="$(echo "$curl_cmd" | jq -r '.[1].name' 2>/dev/null)"
        g_ver2="$(echo "$curl_cmd" | jq -r '.[0].tag_name' 2>/dev/null)"
        g_ver="${g_ver#Cares-}"
        g_ver="${g_ver#FAAC }"
        g_ver="${g_ver#Lcms}"
        g_ver="${g_ver#OpenJPEG }"
        g_ver="${g_ver#OpenSSL }"
        g_ver="${g_ver#Pcre}"
        g_ver="${g_ver#Pkgconf-}"
        g_ver="${g_ver#Release-}"
        g_ver="${g_ver#Rust }"
        g_ver="${g_ver//-snapshot/}"
        g_ver="${g_ver#Ver-}"
        g_ver="${g_ver#V}"
        g_ver1="${g_ver1#Nasm-}"
        g_ver1="${g_ver1#V}"
        g_ver2="${g_ver2#V}"
    fi

    echo "${github_repo%/*}-$g_ver" >> "$ver_file_tmp"
    awk '!NF || !seen[$0]++' "${latest_txt_tmp}" > "${ver_file}"
}

git_2_fn()
{
    repo="$1"
    url="$2"
    if curl_cmd="$(curl -A "$user_agent" -m "${curl_timeout}" -sSL "https://code.videolan.org/api/v4/projects/${repo}/repository/${url}")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].commit.id')"
        g_sver="$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')"
        g_sver="${g_sver::7}"
        g_ver1="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver1="${g_ver1#V}"
    fi
}

git_3_fn()
{
    repo="$1"
    url="$2"
    if curl_cmd="$(curl -A "$user_agent" -m "${curl_timeout}" -sSL "https://gitlab.com/api/v4/projects/${repo}/repository/${url}")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#V}"
        g_ver1="$(echo "$curl_cmd" | jq -r '.[0].commit.id')"
        g_ver1="${g_ver1#V}"
        g_sver1="$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')"
        g_ver="${g_ver#VTM-}"
    fi
}

git_4_fn()
{
    repo="$1"
    if curl_cmd="$(curl -A "$user_agent" -m "${curl_timeout}" -sSL "https://gitlab.freedesktop.org/api/v4/projects/${repo}/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#Pkg-config-}"
        g_ver="${g_ver#VER-}"
        g_ver="${g_ver#V}"
    fi
}

git_5_fn()
{
    repo="$1"
    if curl_cmd="$(curl -A "$user_agent" -m "${curl_timeout}" -sSL "https://gitlab.gnome.org/api/v4/projects/${repo}/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#V}"
    fi
}

git_6_fn()
{
    repo="$1"
    if curl_cmd="$(curl -A "$user_agent" -m "${curl_timeout}" -sSL "https://salsa.debian.org/api/v4/projects/${repo}/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#V}"
    fi
}

git_ver_fn()
{
    local t_flag u_flag v_flag v_tag v_url

    v_url="$1"
    v_tag="$2"

    if [ -n "$3" ]; then
        v_flag="$3"
        case "${v_flag}" in
                B)      t_flag=branches;;
                R)      t_flag=releases;;
                T)      t_flag=tags;;
        esac
    fi

    case "${v_tag}" in
            1)      u_flag=git_1_fn;;
            2)      u_flag=git_2_fn;;
            3)      u_flag=git_3_fn;;
            4)      u_flag=git_4_fn;;
            5)      u_flag=git_5_fn;;
            6)      u_flag=git_6_fn;;
            *)      fail_fn "Could not detect the variable \"v_tag\" in the function \"git_ver_fn\". Line: ${LINENO}"
    esac

    "${u_flag}" "${v_url}" "${t_flag}" 2>/dev/null
}

check_version()
{
    github_repo="$1"
    latest_txt_tmp="$ver_file_tmp"
    latest_txt="${ver_file}"

    awk '!NF || !seen[$0]++' "${latest_txt_tmp}" > "${latest_txt}"
    check_ver="$(grep -Eo "${github_repo#*/}-[0-9\.]+$" "${latest_txt}" | sort | head -n1)"

    if [ -n "${check_ver}" ]; then
        g_nocheck=0
    else
        g_nocheck=1
    fi
}

pre_check_ver()
{
    github_repo="$1"
    git_ver="$2"
    git_url_type="$3"

    check_version "${github_repo}"
    if [ "${g_nocheck}" -eq '1' ]; then
        git_ver_fn "${github_repo}" "${git_ver}" "${git_url_type}"
        g_ver="${g_ver##-*}"
        g_ver2="${g_ver2##-*}"
    else
        g_ver="${check_ver#*-}"
    fi
}

execute()
{
    echo "$ ${*}"

    if [ "${debug}" = 'ON' ]; then
        if ! output=$("$@"); then
            notify-send -t 5000 "Failed to execute: ${*}" 2>/dev/null
            fail_fn "Failed to execute: ${*}"
        fi
    else
        if ! output=$("$@" 2>&1); then
            notify-send -t 5000 "Failed to execute: ${*}" 2>/dev/null
            fail_fn "Failed to execute: ${*}"
        fi
    fi
}

build()
{
    printf "\n%s\n%s\n"                \
        "Building $1 - version $2" \
        '===================================='

    if [ -f "$packages/$1.done" ]; then
        if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        elif "${latest}"; then
            echo "$1 is outdated and will be rebuilt using version $2"
            return 0
        else
            echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $packages/$1.done lockfile."
            return 1
        fi
    fi
    return 0
}

build_done() { echo "$2" > "$packages/$1.done"; }

installed() { return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

library_exists()
{
    if ! [[ -x "$(pkg-config --exists --print-errors "$1" 2>&1 >/dev/null)" ]]; then
        return 1
    fi
    return 0
}

gpu_arch_fn()
{
    local is_wsl gpu_name gpu_type

    gpu_name="$(nvidia-smi --query-gpu=gpu_name --format=csv | sort -r | head -n 1)"
    if [ "${gpu_name}" = 'name' ]; then
        gpu_name="$(nvidia-smi --query-gpu=gpu_name --format=csv | sort | head -n 1)"
    fi

    case "${gpu_name}" in
        'Quadro P2000')                 gpu_type=1;;
        'NVIDIA GeForce GT 1010')       gpu_type=1;;
        'NVIDIA GeForce GTX 1030')      gpu_type=1;;
        'NVIDIA GeForce GTX 1050')      gpu_type=1;;
        'NVIDIA GeForce GTX 1060')      gpu_type=1;;
        'NVIDIA GeForce GTX 1070')      gpu_type=1;;
        'NVIDIA GeForce GTX 1080')      gpu_type=1;;
        'NVIDIA TITAN Xp')              gpu_type=1;;
        'NVIDIA Tesla P40')             gpu_type=1;;
        'NVIDIA Tesla P4')              gpu_type=1;;
        'NVIDIA GeForce GTX 1180')      gpu_type=2;;
        'NVIDIA GeForce GTX Titan V')   gpu_type=2;;
        'Quadro GV100')                 gpu_type=2;;
        'NVIDIA Tesla V100')            gpu_type=2;;
        'NVIDIA GeForce GTX 1660 Ti')   gpu_type=3;;
        'NVIDIA GeForce RTX 2060')      gpu_type=3;;
        'NVIDIA GeForce RTX 2070')      gpu_type=3;;
        'NVIDIA GeForce RTX 2080')      gpu_type=3;;
        'Quadro 4000')                  gpu_type=3;;
        'Quadro 5000')                  gpu_type=3;;
        'Quadro 6000')                  gpu_type=3;;
        'Quadro 8000')                  gpu_type=3;;
        'NVIDIA T1000')                 gpu_type=3;;
        'NVIDIA T2000')                 gpu_type=3;;
        'NVIDIA Tesla T4')              gpu_type=3;;
        'NVIDIA GeForce RTX 3050')      gpu_type=4;;
        'NVIDIA GeForce RTX 3060')      gpu_type=4;;
        'NVIDIA GeForce RTX 3070')      gpu_type=4;;
        'NVIDIA GeForce RTX 3080')      gpu_type=4;;
        'NVIDIA GeForce RTX 3080 Ti')   gpu_type=4;;
        'NVIDIA GeForce RTX 3090')      gpu_type=4;;
        'NVIDIA RTX A2000')             gpu_type=4;;
        'NVIDIA RTX A3000')             gpu_type=4;;
        'NVIDIA RTX A4000')             gpu_type=4;;
        'NVIDIA RTX A5000')             gpu_type=4;;
        'NVIDIA RTX A6000')             gpu_type=4;;
        'NVIDIA GeForce RTX 4080')      gpu_type=5;;
        'NVIDIA GeForce RTX 4090')      gpu_type=5;;
        'NVIDIA H100')                  gpu_type=6;;
        *)                              fail_fn "Unable to define the variable \"gpu_name\" in the function \"gpu_arch_fn\". Line: ${LINENO}";;
    esac

    if [ -n "${gpu_type}" ]; then
        case "${gpu_type}" in
            1)      gpu_arch='compute_61,code=sm_61';;
            2)      gpu_arch='compute_70,code=sm_70';;
            3)      gpu_arch='compute_75,code=sm_75';;
            4)      gpu_arch='compute_86,code=sm_86';;
            5)      gpu_arch='compute_89,code=sm_89';;
            6)      gpu_arch='compute_90,code=sm_90';;
            *)      fail_fn "Unable to define the variable \"gpu_arch\" in the function \"gpu_arch_fn\". Line: ${LINENO}";;
        esac
    else
        fail_fn "Failed to find the variable: gpu_type Line: ${LINENO}"
    fi
}

# Print the options available when manually running the script
usage()
{
    printf "%s\n\n" "Usage: ${script_name} [OPTIONS]"
    echo 'Options:'
    echo '    -h, --help                                       Display usage information'
    echo '        --version                                    Display version information'
    echo '    -b, --build                                      Starts the build process'
    echo '    -c, --cleanup                                    Remove all working dirs'
    echo '        --latest                                     Build latest version of dependencies if newer available'
    echo
}

while ((${#} > 0))
do
    case "$1" in
        -h | --help)
                usage
                echo
                exit 0
                ;;
        --version)
                printf "%s\n\n" "The script version is: ${script_ver}"
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
                if [[ "$1" == '--full-static' ]]; then
                    LDEXEFLAGS='-static'
                fi
                if [[ "$1" == '--latest' ]]; then
                    latest=true
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

if [ -z "${bflag}" ]; then
    if [ -z "${cflag}" ]; then
        usage
        echo
        exit 1
    fi
    exit 0
fi

if [ -n "${LDEXEFLAGS}" ]; then
    printf "%s\n\n" 'The script has been configured to run in full static mode.'
fi

# Set the path variable

cuda_bin_path="$(sudo find /usr/local/ -type d -name 'cuda' | head -n1)"
cuda_bin_path="$(sudo find /opt/ -type d -name 'cuda' | head -n1)"
cuda_bin_path+='/bin'

path_fn()
{
PATH="\
/usr/lib/ccache/bin:\
/usr/lib/ccache:\
${cuda_bin_path}:\
$workspace/bin:\
${HOME}/.local/bin:\
/usr/local/sbin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin:\
/usr/local/ant/bin\
"
export PATH
}
path_fn

path_clean_fn()
{
PATH="\
/usr/lib/ccache/bin:\
/usr/lib/ccache:\
${cuda_bin_path}:\
${HOME}/.local/bin:\
/usr/local/sbin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin:\
/usr/local/ant/bin\
"
export PATH
}

# Set the pkg_config_path variable

PKG_CONFIG_PATH="\
$workspace/usr/lib/pkgconfig:\
$workspace/lib64/pkgconfig:\
$workspace/lib/pkgconfig:\
$workspace/lib/x86_64-linux-gnu/pkgconfig:\
$workspace/share/pkgconfig:\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/open-coarrays/openmpi/pkgconfig:\
/usr/lib/x86_64-linux-gnu/openmpi/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig:\
/lib64/pkgconfig:\
/lib/pkgconfig:\
/lib/x86_64-linux-gnu/pkgconfig\
"
export PKG_CONFIG_PATH

cuda_download_fn()
{
    local choice
    clear

    printf "%s\n\n%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n" \
        'Pick your Linux distro from the list below:'       \
        'Supported architecture: x86_64'                    \
        '[1] Debian 10'                                     \
        '[2] Debian 11'                                     \
        '[3] Debian 12'                                     \
        '[4] Ubuntu 20.04'                                  \
        '[5] Ubuntu 22.04'                                  \
        '[6] Ubuntu WSL'                                    \
        '[7] Arch Linux'                                    \
        '[8] Exit'
    read -p 'Your choices are (1 to 8): ' choice
    clear

    printf "%s\n%s\n\n"                                             \
        "Downloading CUDA SDK Toolkit - version $cuda_latest_ver" \
        '===================================================='

    case "${choice}" in
        1)
            wget --show progress -U "$user_agent" -cqO "$packages/nvidia-cuda/cuda-buster-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-debian10-12-3-local_12.3.0-545.23.06-1_amd64.deb"
            sudo dpkg -i "$packages/nvidia-cuda/cuda-buster-$cuda_latest_ver.deb"
            sudo cp -f /var/cuda-repo-debian10-12-3-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            sudo add-apt-repository -y contrib
            ;;
        2)
            wget --show progress -U "$user_agent" -cqO "$packages/nvidia-cuda/cuda-bullseye-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-debian11-12-3-local_12.3.0-545.23.06-1_amd64.deb"
            sudo dpkg -i "$packages/nvidia-cuda/cuda-bullseye-$cuda_latest_ver.deb"
            sudo cp -f /var/cuda-repo-debian11-12-3-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            sudo add-apt-repository -y contrib
            ;;
        3)
            wget --show progress -U "$user_agent" -cqO "$packages/nvidia-cuda/cuda-bookworm-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-debian12-12-3-local_12.3.0-545.23.06-1_amd64.deb"
            sudo dpkg -i "$packages/nvidia-cuda/cuda-bookworm-$cuda_latest_ver.deb"
            sudo cp /var/cuda-repo-debian12-12-3-local/cuda-*-keyring.gpg /usr/share/keyrings/
            sudo add-apt-repository -y contrib
            ;;
        4)
            wget --show progress -U "$user_agent" -cqO "$packages/nvidia-cuda/cuda-ubuntu2004.pin" "${cuda_pin_url}/ubuntu2004/x86_64/cuda-ubuntu2004.pin"
            sudo mv "$packages/nvidia-cuda/cuda-ubuntu2004.pin" '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -U "$user_agent" -cqO "$packages/nvidia-cuda/cuda-focal-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-ubuntu2004-12-3-local_12.3.0-545.23.06-1_amd64.deb"
            sudo dpkg -i "$packages/nvidia-cuda/cuda-focal-$cuda_latest_ver.deb"
            sudo cp -f /var/cuda-repo-ubuntu2004-12-3-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        5)
            wget --show progress -U "$user_agent" -cqO "$packages/nvidia-cuda/cuda-ubuntu2204.pin" "${cuda_pin_url}/ubuntu2204/x86_64/cuda-ubuntu2204.pin"
            sudo mv "$packages/nvidia-cuda/cuda-ubuntu2204.pin" '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -U "$user_agent" -cqO "$packages/nvidia-cuda/cuda-jammy-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-ubuntu2204-12-3-local_12.3.0-545.23.06-1_amd64.deb"
            sudo dpkg -i "$packages/nvidia-cuda/cuda-jammy-$cuda_latest_ver.deb"
            sudo cp /var/cuda-repo-ubuntu2204-12-3-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        6)
            wget --show progress -U "$user_agent" -cqO "$packages/nvidia-cuda/cuda-wsl-ubuntu.pin" "${cuda_pin_url}/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin"
            sudo mv "$packages/nvidia-cuda/cuda-wsl-ubuntu.pin" '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -U "$user_agent" -cqO "$packages/nvidia-cuda/cuda-wsl-$cuda_latest_ver.deb" "$cuda_url/local_installers/cuda-repo-wsl-ubuntu-12-3-local_12.3.0-1_amd64.deb"
            sudo dpkg -i "$packages/nvidia-cuda/cuda-wsl-$cuda_latest_ver.deb"
            sudo cp -f /var/cuda-repo-wsl-ubuntu-12-3-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
    7)
            git clone -q 'https://gitlab.archlinux.org/archlinux/packaging/packages/cuda.git'
            cd cuda || exit 1
            makepkg -sif --cleanbuild --noconfirm --needed
            return 0
            ;;
    8)
            clear
            exit_fn
            ;;
    *)
            unset choice
            cuda_download_fn
            ;;
    esac

# Update the apt packages then install the cuda-sdk-toolkit
    sudo apt update
    sudo apt install cuda-toolkit-12-3
    clear
}

# Required geforce cuda development packages

install_cuda_fn()
{
    local choice
    clear

    if [[ "${OS}" == 'Arch' ]]; then
        cuda_ver_test="$(nvcc --version | sed -n 's/^.*release \([0-9]\+\.[0-9]\+\).*$/\1/p')"
        cuda_ver_test+='.0'
    else
        cuda_ver_test="$(cat '/usr/local/cuda/version.json' 2>/dev/null | jq -r '.cuda.version')"
    fi
    cuda_ver="${cuda_ver_test}"

    if [ -n "${cuda_ver_test}" ]; then
        printf "%s\n%s\n%s\n%s\n\n%s\n%s\n\n"                             \
            "The installed CUDA SDK Toolkit version is: ${cuda_ver_test}" \
            "The latest version available is: $cuda_latest_ver"         \
            '====================================================='       \
            'Do you want to update/reinstall it?'                         \
            '[1] Yes'                                                     \
            '[2] No'
        read -p 'Your choices are (1 or 2): ' choice
        clear

        case "${choice}" in
            1)      cuda_download_fn;;
            2)
                    PATH="${PATH}:${cuda_path}"
                    export PATH
                    ;;
            *)
                    unset choice
                    install_cuda_fn
                    ;;
        esac
    else
        printf "%s\n%s\n\n%s\n\n%s\n%s\n\n" \
            "The CUDA SDK Toolkit was not detected and the latest version is: $cuda_latest_ver" \
            '========================================================================='           \
            'Choose an option'                                                                    \
            '[1] Install the CUDA SDK Toolkit and add it to your PATH'                            \
            '[2] Continue without installing (hardware acceleration will be turned off)'
        read -p 'Your choices are (1 or 2): ' choice
        clear

        case "${choice}" in
            1)      cuda_download_fn;;
            2)      echo;;
            *)
                    unset choice
                    install_cuda_fn
                    ;;
        esac
    fi

    cuda_ver="$(cat '/usr/local/cuda/version.json' 2>/dev/null | jq -r '.cuda.version')"

    if [ -z "${cuda_ver}" ]; then
        fail_fn "Unable to locate the file: /usr/local/cuda/version.json. Line: ${LINENO}"
    else
        export PATH="${PATH}:${cuda_path}"
    fi
}

# Required build packages

pkgs_fn()
{
    local pkg pkgs missing_pkgs

    printf "%s\n%s\n"                          \
        'Installing the required APT packages' \
        '=============================================='

    pkgs=("$1" ant apt asciidoc autoconf autoconf-archive automake autopoint binutils bison build-essential
          cargo ccache checkinstall clang clang-tools cmake curl default-jdk-headless doxygen fcitx-libs-dev
          flex flite1-dev freeglut3-dev frei0r-plugins-dev gawk gettext gimp-data git gnome-desktop-testing
          gnustep-gui-runtime google-perftools gperf gtk-doc-tools guile-3.0-dev help2man jq junit ladspa-sdk
          libamd2 libasound2-dev libass-dev libaudio-dev libavfilter-dev libbabl-0.1-0 libbluray-dev libbs2b-dev
          libbz2-dev libc6 libc6-dev libcaca-dev libcairo2-dev libcamd2 libccolamd2 libcdio-dev libcdio-paranoia-dev
          libcdparanoia-dev libcholmod3 libchromaprint-dev libcjson-dev libcodec2-dev libcolamd2 libcrypto++-dev
          libcurl4-openssl-dev libdbus-1-dev libde265-dev libdevil-dev libdmalloc-dev libdrm-dev libdvbpsi-dev
          libebml-dev libegl1-mesa-dev libffi-dev libgbm-dev libgdbm-dev libgegl-0.4-0 libgegl-common libgimp2.0
          libgl1-mesa-dev libgles2-mesa-dev libglib2.0-dev libgme-dev libgnutls28-dev libgnutls30 libgoogle-perftools4
          libgoogle-perftools-dev libgsm1-dev libgtest-dev libgvc6 libhwy-dev libibus-1.0-dev libiconv-hook-dev
          libintl-perl libjack-dev libjemalloc-dev libladspa-ocaml-dev libleptonica-dev liblz-dev liblzma-dev
          liblzo2-dev libmathic-dev libmatroska-dev libmbedtls-dev libmetis5 libmfx-dev libmodplug-dev libmp3lame-dev
          libmusicbrainz5-dev libmysofa-dev libnuma1 libnuma-dev libopencore-amrnb-dev libopencore-amrwb-dev libopencv-dev
          libopenjp2-7-dev libopenmpt-dev libopus-dev libperl-dev libpstoedit-dev libpulse-dev librabbitmq-dev libraqm-dev
          libraw-dev librsvg2-dev librubberband-dev librust-gstreamer-base-sys-dev libshine-dev libsmbclient-dev libsnappy-dev
          libsndfile1-dev libsndio-dev libsoxr-dev libspeex-dev libsqlite3-dev libsrt-gnutls-dev libssh-dev libssl-dev
          libsuitesparseconfig5 libtalloc-dev libtheora-dev libticonv-dev libtool libtool-bin libtwolame-dev libudev-dev
          libumfpack5 libunwind-dev libv4l-dev libva-dev libvdpau-dev libvidstab-dev libvlccore-dev libvo-amrwbenc-dev
          libvpx-dev libx11-dev libx264-dev libxcursor-dev libxext-dev libxfixes-dev libxi-dev libxkbcommon-dev libxrandr-dev
          libxss-dev libxvidcore-dev libyuv-dev libzmq3-dev libzstd-dev libzvbi-dev libzzip-dev lshw lzma-dev m4 meson nasm
          ninja-build pandoc python3 python3-pip ragel re2c scons sudo texi2html texinfo tk-dev unzip valgrind wget xmlto zlib1g-dev)

    for pkg in ${pkgs[@]}
    do
        if ! installed "${pkg}"; then
            missing_pkgs+=" ${pkg}"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        if sudo apt install $missing_pkgs; then
            sudo apt -y autoremove
            clear
            echo 'The required APT packages were installed.'
        else
            fail_fn "These required APT packages failed to install: $missing_pkgs. Line: ${LINENO}"
        fi
    else
        echo 'The required APT packages are already installed.'
    fi
}

x265_fix_libs_fn()
{
    x265_libs_208="$(find /usr/local/lib/ -type f -name 'libx265.so.208' -print | head -n1)"
    x265_libs_199="$(find "$workspace"/lib/ -type f -name 'libx265.so.199' -print  | head -n1)"

    case "${OS}" in
        Arch)       sudo cp -f "${x265_libs_208}" '/usr/lib';;
        *)          sudo cp -f "${x265_libs_208}" '/usr/lib/x86_64-linux-gnu';;
    esac

    if [ ! -f "${x265_libs_199}" ]; then
        if ! curl -A "$user_agent" -m 10 -Lso "$workspace/lib/libx265.so.199" 'https://github.com/slyfox1186/script-repo/raw/main/library-files/libx265.so.199'; then
            fail_fn "The script was unable to download the required library file \"$workspace/lib/libx265.so.199\". Line: ${LINENO}"
        fi
    fi

    case "${OS}" in
        Arch)
                sudo cp -f "$workspace/lib/libx265.so.199" '/usr/lib'
                sudo ln -sf '/usr/lib/libx265.so.199' '/usr/lib/libx265.so'
                ;;
        *)      sudo cp -f "$workspace/lib/libx265.so.199" '/usr/lib/x86_64-linux-gnu'
                sudo ln -sf '/usr/lib/x86_64-linux-gnu/libx265.so.199' '/usr/lib/x86_64-linux-gnu/libx265.so'
                ;;
    esac
}

libpulse_fix_libs_fn()
{
    local libpulse_lib libpulse_trim

    libpulse_lib="$(find "$workspace"/lib/ -type f -name 'libpulsecommon-*.so')"
    libpulse_trim="$(echo "$libpulse_lib" | sed 's:.*/::' | head -n1)"

    if [[ "${OS}" == 'Arch' ]]; then
        if [ ! -d '/usr/lib/pulseaudio' ]; then
            sudo mkdir -p '/usr/lib/pulseaudio'
        fi
    else
        if [ ! -d '/usr/lib/x86_64-linux-gnu/pulseaudio' ]; then
            sudo mkdir -p '/usr/lib/x86_64-linux-gnu/pulseaudio'
        fi
    fi

    if [ -n "$libpulse_lib" ]; then
        if [[ "${OS}" == 'Arch' ]]; then
            execute sudo cp -f "$libpulse_lib" '/usr/lib/pulseaudio'
            execute sudo ln -sf "/usr/lib/pulseaudio/$libpulse_trim" '/usr/lib'
        else
            execute sudo cp -f "$libpulse_lib" '/usr/lib/x86_64-linux-gnu/pulseaudio'
            execute sudo ln -sf "/usr/lib/x86_64-linux-gnu/pulseaudio/$libpulse_trim" '/usr/lib/x86_64-linux-gnu'
        fi
    fi
}

ffmpeg_install_test()
{
    local binaries i

    binaries=(ffmpeg ffplay ffprobe)

    for i in ${binaries[@]}
    do
        if [ ! -f "$install_dir/bin/${i}" ]; then
            printf "\n%s\n%s\n\n"                                                \
                "Warning: Unable to locate the binary file: $install_dir/bin/${i}" \
                'I have read online that this is a bug of some sort and people are unsure why it happens.'
            read -p 'You can press enter to continue, however, please be aware that it is missing.'
            echo
        fi
    done
}

install_libjxl_fn()
{
    local i

    cd "$packages"/deb-files || exit 1

# Install the main debian file first before installing the others
    printf "%s\n" '$ sudo dpkg -i libjxl_0.8.2_amd64.deb'
    if sudo dpkg -i 'libjxl_0.8.2_amd64.deb' &>/dev/null; then
        sudo rm 'libjxl_0.8.2_amd64.deb' &>/dev/null
    fi

# Install the remaining debian files
    for i in *.deb
    do
        printf "%s\n" "\$ sudo dpkg -i ${i}"
        sudo dpkg -i ./"${i}" &>/dev/null
    done
}

dl_libjxl_fn()
{
    local url_base url_suffix

    url_base=https://github.com/libjxl/libjxl/releases/download/v0.8.2/jxl-debs-amd64
    url_suffix=v0.8.2.tar.gz

    if [ ! -f "$packages"/libjxl.tar.gz ]; then
        case "${VER}" in
            '10')
                        libjxl_download="${url_base}-debian-buster-${url_suffix}"
                        libjxl_name='debian-buster'
                        ;;
            '11')
                        libjxl_download="${url_base}-debian-bullseye-${url_suffix}"
                        libjxl_name='debian-bullseye'
                        ;;
            '12')
                        libjxl_download="${url_base}-debian-bookworm-${url_suffix}"
                        libjxl_name='debian-bookworm'
                        ;;
            '18.04')
                        libjxl_download="${url_base}-ubuntu-18.04-${url_suffix}"
                        libjxl_name='ubuntu-18.04'
                        ;;
            '20.04')
                        libjxl_download="${url_base}-ubuntu-20.04-${url_suffix}"
                        libjxl_name='ubuntu-20.04'
                        ;;
            '22.04')
                        libjxl_download="${url_base}-ubuntu-22.04-${url_suffix}"
                        libjxl_name='ubuntu-22.04'
                        ;;           
            *)          echo;;
        esac

        if ! curl -A "$user_agent" -Lso "$packages/${libjxl_name}.tar.gz" "${libjxl_download}"; then
            fail_fn "Failed to download the libjxl archive: $packages/${libjxl_name}.tar.gz. Line: ${LINENO}"
        fi

        if [ ! -d "$packages"/deb-files ]; then
            mkdir -p "$packages"/deb-files
        fi
        if ! tar -zxf "$packages/${libjxl_name}.tar.gz" -C "$packages"/deb-files --strip-components 1; then
            fail_fn "Could not extract the libjxl archive $packages/${libjxl_name}.tar.gz. Line: ${LINENO}"
        fi

# Install the downloaded libjxl debian packages
        install_libjxl_fn "${libjxl_name}"
    fi
}

# Patch functions

patch_ffmpeg_fn()
{
    execute curl -A "$user_agent" -Lso 'mathops.patch' 'https://raw.githubusercontent.com/slyfox1186/ffmpeg-build-script/main/patches/mathops.patch'
    execute patch -d 'libavcodec/x86' -i '../../mathops.patch'
}

# Archlinux function section

ffmpeg_ndi_fn()
{
    cd "$packages" || exit 1
    if build 'FFMPEG-NDI-git' 'git'; then
        download_git 'https://github.com/lplassman/FFMPEG-NDI.git'
    fi
    ffmpeg_libraries+=('--enable-libndi_newtek')
}

apache_ant_fn()
{
    if build 'apache-ant' 'git'; then
        download_git 'https://aur.archlinux.org/apache-ant-contrib.git' 'apache-ant-AUR'
        execute makepkg -sif --cleanbuild --noconfirm --needed
        build_done 'apache-ant' 'git'
    fi
}

librist_arch_fn()
{
    if build 'librist' 'git'; then
        download_git 'https://aur.archlinux.org/librist.git' 'librist-AUR'
        execute makepkg -sif --cleanbuild --noconfirm --needed
        build_done 'librist' 'git'
    fi
}

wsl2_os_ver_fn()
{
    wsl_common_pkgs="$1 libnvidia-encode1"
    pkgs_fn "nvidia-smi cppcheck libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev libyuv-utils libyuv0 libsharp-dev libdmalloc5"
}

arch_os_ver_fn()
{
    local arch_pkgs i
    clear

    arch_pkgs=(av1an bluez-libs clang cmake dav1d devil docbook5-xml flite gdb gettext git gperf
               gperftools jdk17-openjdk ladspa jq libde265 libjpeg-turbo libjxl libjpeg6-turbo libmusicbrainz5
               libnghttp2 libwebp libyuv meson nasm ninja numactl opencv pd perl-datetime sudo texlive-basic
               texlive-binextra tk valgrind webp-pixbuf-loader xterm yasm)

# Remove any locks on pacman
    if [ -f '/var/lib/pacman/db.lck' ]; then
        sudo rm '/var/lib/pacman/db.lck'
    fi
 
    for i in "${arch_pkgs[@]}"
    do
        sudo pacman -Sq --needed --noconfirm ${i} 2>&1
    done

# Install required pip modules
    sudo pip install DateTime Sphinx wheel
    clear
}

debian_os_ver_fn()
{
    if [[ "$2" = 'yes_wsl' ]]; then
        VER=msft
        debian_wsl_pkgs="$1"
    fi

    debian_pkgs="$1 cppcheck libnvidia-encode1 libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev"
    debian_pkgs+=' libyuv-utils libyuv0 libsharp-dev libdmalloc5'

    case "${VER}" in
        12|trixie|sid)      pkgs_fn "${debian_pkgs} librist-dev";;
        11)                 pkgs_fn "${debian_pkgs}";;
        msft)               pkgs_fn "${debian_wsl_pkgs} ${debian_pkgs} librist-dev";;
        *)                  fail_fn "Could not detect the Debian version. Line: ${LINENO}";;
    esac
}

ubuntu_os_ver_fn()
{
    if [[ "$2" = 'yes_wsl' ]]; then
        VER=msft
        ubuntu_wsl_pkgs="$1"
    fi

    ubuntu_common_pkgs=' libsvtav1dec-dev libsvtav1-dev libsvtav1enc-dev cppcheck'
    focal_pkgs='libvmmalloc1 libvmmalloc-dev libdmalloc5 libcunit1-dev nvidia-utils-535'
    focal_pkgs+=' librust-jemalloc-sys-dev librust-malloc-buf-dev libsrt-doc libreadline-dev libcunit1 libcunit1-doc'
    jammy_pkgs='libmimalloc-dev libtbbmalloc2 librust-jemalloc-sys-dev librust-malloc-buf-dev'
    jammy_pkgs+=' libsrt-doc libreadline-dev libpipewire-0.3-dev libwayland-dev libdecor-0-dev nvidia-utils-545'
    lunar_kenetic_pkgs='librist-dev libjxl-dev nvidia-utils-545'

    case "${VER}" in
        23.04|22.10)        pkgs_fn "${ubuntu_common_pkgs} ${lunar_kenetic_pkgs} ${jammy_pkgs}";;
        22.04|msft)         pkgs_fn "${ubuntu_common_pkgs} ${ubuntu_wsl_pkgs} ${jammy_pkgs}";;
        20.04|msft)         pkgs_fn "${ubuntu_common_pkgs} ${ubuntu_wsl_pkgs} ${focal_pkgs}";;
        *)                  fail_fn "Could not detect the Ubuntu version. Line: ${LINENO}";;
    esac
}

# Test the os and its version

find_lsb_release="$(sudo find /usr/bin/ -type f -name 'lsb_release')"

if [ -f '/etc/os-release' ]; then
    source '/etc/os-release'
    OS_TMP="$NAME"
    VER_TMP="$VERSION_ID"
    CODENAME="$VERSION_CODENAME"
    OS="$(echo "${OS_TMP}" | awk '{print $1}')"
    VER="$(echo "${VER_TMP}" | awk '{print $1}')"
elif [ -n "${find_lsb_release}" ]; then
    OS="$(lsb_release -d | awk '{print $2}')"
    VER="$(lsb_release -r | awk '{print $2}')"
else
    fail_fn "Failed to define the \$OS and/or \$VER variables. Line: ${LINENO}"
fi

nvidia_utils_var="$(sudo apt list nvidia-utils-* 2>&1 | grep -Eo '^nvidia-utils-5[34]+5' | sort -r | head -n1)"
nvidia_encode_var="$(sudo apt list libnvidia-encode* 2>&1 | grep -Eo 'libnvidia-encode[1-]+[0-9]*$' | sort -r | head -n1)"

# Check if running windows wsl2

if [ "$(grep -i 'microsoft' '/proc/version')" ]; then
    wsl_switch='yes_wsl'
fi

if [ "${wsl_switch}" = 'yes_wsl' ]; then
    OS=WSL2
fi

# Install required apt packages

case "${OS}" in
    'Arch')             arch_os_ver_fn;;
    'Debian'|'n/a')     debian_os_ver_fn "${nvidia_encode_var} ${nvidia_utils_var}";;
    'Ubuntu')           ubuntu_os_ver_fn "${nvidia_encode_var} ${nvidia_utils_var}";;
    'WSL2')             
                        case "${OS}" in
                            'Debian'|'n/a')     debian_os_ver_fn "${nvidia_encode_var} ${nvidia_utils_var}" "${wsl_switch}";;
                            'Ubuntu')           ubuntu_os_ver_fn "${nvidia_encode_var} ${nvidia_utils_var}" "${wsl_switch}";;
                        esac
                        ;;
esac

# Set java variables

path_fn
find_java="$(sudo find /usr/lib/jvm/ -type d -name 'java-*-openjdk*' | rev | sort | rev | head -n1)"
java_config="$(sudo find /usr/lib/ -type f -name 'jni.h'  | rev | sort -r | rev | head -n1 | sed 's/\(^.*\)\/.*$/\1/')"
export CPPFLAGS+=" -I${java_config}"
export JDK_HOME="${find_java}"
export JAVA_HOME="${find_java}"
export PATH="${PATH}:${JAVA_HOME}/bin"

ant_path_fn()
{
    export ANT_HOME="$install_dir/ant"
    if [ ! -d "$install_dir/ant/bin" ] || [ ! -d "$install_dir/ant/lib" ]; then
        sudo mkdir -p "$install_dir/ant/bin" "$install_dir/ant/lib" 2>/dev/null
    fi
}

# Check if the cuda folder exists to determine installation status

case "${OS}" in
    'Arch')
            iscuda="$(sudo find /opt/cuda* -type f -name 'nvcc' 2>/dev/null)"
            cuda_path="$(sudo find /opt/cuda* -type f -name 'nvcc' 2>/dev/null | grep -Eo '^.*/bin?')"
            ;;
    *)
            iscuda="$(sudo find /usr/local/cuda* -type f -name 'nvcc' 2>/dev/null)"
            cuda_path="$(sudo find /usr/local/cuda* -type f -name 'nvcc' 2>/dev/null | grep -Eo '^.*/bin?')"
            ;;
esac

# Prompt the user to install the geforce cuda sdk-toolkit

install_cuda_fn

# Install the global tools

clear
box_out_banner_global()
{
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner_global 'Installing Global Tools'

if build 'm4' 'latest'; then
    download 'https://ftp.gnu.org/gnu/m4/m4-latest.tar.xz'
    execute ./configure --prefix=$install_dir            \
                        --{build,host,target}="${pc_type}" \
                        --disable-nls                      \
                        --enable-c++
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'm4' 'latest'
fi

if build 'autoconf' 'latest'; then
    download 'http://ftp.gnu.org/gnu/autoconf/autoconf-latest.tar.xz'
    execute autoreconf -fi
    execute ./configure --prefix=$install_dir     \
                        --{build,host}="${pc_type}" \
                        M4=/usr/local/bin/m4
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'autoconf' 'latest'
fi

if [[ "${OS}" == 'Arch' ]]; then
    if build 'libtool' "${lt_ver}"; then
        sudo pacman -S --noconfirm libtool
        build_done 'libtool' "${lt_ver}"
    fi
else
    case "${VER}" in
        12|23.04)       lt_ver=2.4.7;;
        *)              lt_ver=2.4.6;;
    esac
    if build 'libtool' "${lt_ver}"; then
        download "https://ftp.gnu.org/gnu/libtool/libtool-${lt_ver}.tar.xz"
        execute ./configure --prefix=$install_dir        \
                            --{build,host}="${pc_type}" \
                            --with-pic                  \
                            M4=/usr/local/bin/m4
        execute make "-j${cpu_threads}"
        execute sudo make install
        build_done 'libtool' "${lt_ver}"
    fi
fi

if build 'pkg-config' '0.29.2'; then
    download "https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
    execute ./configure --prefix=$install_dir\
                        --with-pc-path="${PKG_CONFIG_PATH}"
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'pkg-config' '0.29.2'
fi

if [[ "${OS}" == 'Arch' ]]; then
    librist_arch_fn
else
    if build 'librist' 'git'; then
        download_git 'https://code.videolan.org/rist/librist.git'
        execute meson setup build --prefix="$workspace"  \
                                  --buildtype=release      \
                                  --default-library=static \
                                  --strip                  \
                                  -Dstatic_analyze=true    \
                                  -Dtest=false
        execute ninja "-j${cpu_threads}" -C build
        execute ninja "-j${cpu_threads}" -C build install
        build_done 'librist' 'git'
    fi
fi

pre_check_ver 'madler/zlib' '1' 'T'
if build 'zlib' "$g_ver"; then
    download "https://github.com/madler/zlib/releases/download/v$g_ver/zlib-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace"
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'zlib' "$g_ver"
fi

if build 'openssl' '3.1.4'; then
    download 'https://www.openssl.org/source/openssl-3.1.4.tar.gz'
    execute ./Configure --prefix="$workspace"                    \
                        enable-egd                                 \
                        enable-fips                                \
                        enable-md2                                 \
                        enable-rc5                                 \
                        enable-trace                               \
                        threads zlib                               \
                        --with-rand-seed=os                        \
                        --with-zlib-include="$workspace"/include \
                        --with-zlib-lib="$workspace"/lib
    execute make "-j${cpu_threads}"
    execute sudo make install_sw
    execute sudo make install_fips
    build_done 'openssl' '3.1.4'
fi
ffmpeg_libraries+=('--enable-openssl')

pre_check_ver 'yasm/yasm' '1' 'T'
if build 'yasm' "$g_ver"; then
    download "https://github.com/yasm/yasm/archive/refs/tags/v$g_ver.tar.gz" "yasm-$g_ver.tar.gz"
    execute autoreconf -fi
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'yasm' "$g_ver"
fi

if build 'nasm' '2.16.01'; then
    download 'https://www.nasm.us/pub/nasm/stable/nasm-2.16.01.tar.xz'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"            \
                        --{build,host,target}="${pc_type}" \
                        --disable-pedantic                 \
                        --enable-ccache
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'nasm' '2.16.01'
fi

if build 'giflib' '5.2.1'; then
    download 'https://cfhcable.dl.sourceforge.net/project/giflib/giflib-5.2.1.tar.gz'
# Parellel building not available for this library
    execute make
    execute make PREFIX="$workspace" install
    build_done 'giflib' '5.2.1'
fi

# Ubuntu bionic fails to build xml2
if [ "${VER}" != '18.04' ]; then
    git_ver_fn '1665' '5' 'T'
    if build 'xml2' "$g_ver"; then
        download "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$g_ver/libxml2-v$g_ver.tar.bz2" "xml2-$g_ver.tar.bz2"
        CFLAGS+=' -DNOLIBTOOL'
        execute ./autogen.sh
        execute cmake -B build                              \
                      -DCMAKE_INSTALL_PREFIX="$workspace" \
                      -DCMAKE_BUILD_TYPE=Release            \
                      -DBUILD_SHARED_LIBS=OFF               \
                      -G Ninja -Wno-dev
        execute ninja "-j${cpu_threads}" -C build
        execute ninja "-j${cpu_threads}" -C build install
        build_done 'xml2' "$g_ver"
    fi
    ffmpeg_libraries+=('--enable-libxml2')
fi

# Manually update this from time to time ($g_ver returns = 1.7.0beta88)
if build 'libpng' '1.6.40'; then
    download 'https://github.com/glennrp/libpng/archive/refs/tags/v1.6.40.tar.gz' 'libpng-1.6.40.tar.gz'
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$workspace"             \
                        --enable-hardware-optimizations=yes \
                        --with-pic
    execute make "-j${cpu_threads}"
    execute make install-header-links
    execute make install-library-links
    execute make install
    build_done 'libpng' '1.6.40'
fi

git_ver_fn '4720790' '3' 'T'
if build 'libtiff' "$g_ver"; then
    download "https://gitlab.com/libtiff/libtiff/-/archive/v$g_ver/libtiff-v$g_ver.tar.bz2" "libtiff-$g_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix=$install_dir        \
                        --{build,host}="${pc_type}" \
                        --disable-docs              \
                        --disable-sphinx            \
                        --disable-tests             \
                        --enable-cxx                \
                        --with-pic
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'libtiff' "$g_ver"
fi

pre_check_ver 'nkoriyama/aribb24' '1' 'T'
if build 'aribb24' "$g_ver"; then
    download "https://github.com/nkoriyama/aribb24/archive/refs/tags/v$g_ver.tar.gz" "aribb24-$g_ver.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --disable-shared        \
                        --with-pic
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'aribb24' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libaribb24')

git_ver_fn '7950' '4'
g_ver1="${g_ver//-/.}"
if build 'freetype' "$g_ver1"; then
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/VER-$g_ver/freetype-VER-$g_ver.tar.bz2" "freetype-$g_ver1.tar.bz2"
    extracmds=('-D'{harfbuzz,png,bzip2,brotli,zlib,tests}'=disabled')
    execute ./autogen.sh
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                              "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'freetype' "$g_ver1"
fi
ffmpeg_libraries+=('--enable-libfreetype')

git_ver_fn '890' '4'
if build 'fontconfig' "$g_ver"; then
    download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$g_ver/fontconfig-$g_ver.tar.bz2"
    extracmds=('--disable-'{docbook,docs,nls,shared})
    LDFLAGS+=' -DLIBXML_STATIC'
    sed -i 's|Cflags:|& -DLIBXML_STATIC|' 'fontconfig.pc.in'
    execute ./autogen.sh --noconf
    execute autoupdate
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        "${extracmds[@]}"           \
                        --enable-iconv              \
                        --enable-static             \
                        --with-arch="$(uname -m)"   \
                        --with-libiconv-prefix=/usr
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'fontconfig' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libfontconfig')

# Ubuntu bionic fails to build xml2
if [ "${VER}" != '18.04' ]; then
    pre_check_ver 'harfbuzz/harfbuzz' '1' 'R'
    if build 'harfbuzz' "$g_ver"; then
        download "https://github.com/harfbuzz/harfbuzz/archive/refs/tags/$g_ver.tar.gz" "harfbuzz-$g_ver.tar.gz"
        extracmds=('-D'{benchmark,cairo,docs,glib,gobject,icu,introspection,tests}'=disabled')
        execute ./autogen.sh
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                              "${extracmds[@]}"
        execute ninja "-j${cpu_threads}" -C build
        execute ninja "-j${cpu_threads}" -C build install
        build_done 'harfbuzz' "$g_ver"
    fi
fi

if build 'c2man' 'git'; then
    download_git 'https://github.com/fribidi/c2man.git'
    execute ./Configure -desO                                                               \
                        -D bash="$(type -P bash)"                                           \
                        -D bin="$workspace"/bin                                           \
                        -D cc=/usr/bin/cc                                                   \
                        -D d_gnu=/usr/lib/x86_64-linux-gnu                                  \
                        -D find="$(type -P find)"                                           \
                        -D gcc=/usr/bin/gcc                                                 \
                        -D gzip="$(type -P gzip)"                                           \
                        -D installmansrc="$workspace"/share/man                           \
                        -D ldflags="${LDFLAGS}"                                             \
                        -D less="$(type -P less)"                                           \
                        -D libpth='/usr/lib64 /usr/lib /lib64 /lib'                         \
                        -D locincpth="$workspace/include /usr/local/include /usr/include" \
                        -D loclibpth="$workspace/lib /usr/local/lib64 /usr/local/lib"     \
                        -D make="$(type -P make)"                                           \
                        -D more="$(type -P more)"                                           \
                        -D osname="${OS}"                                                   \
                        -D perl="$(type -P perl)"                                           \
                        -D prefix="$workspace"                                            \
                        -D privlib="$workspace"/lib/c2man                                 \
                        -D privlibexp="$workspace"/lib/c2man                              \
                        -D sleep="$(type -P sleep)"                                         \
                        -D tail="$(type -P tail)"                                           \
                        -D tar="$(type -P tar)"                                             \
                        -D tr="$(type -P tr)"                                               \
                        -D troff="$(type -P troff)"                                         \
                        -D uniq="$(type -P uniq)"                                           \
                        -D uuname="$(uname -s)"                                             \
                        -D vi="$(type -P vi)"                                               \
                        -D yacc="$(type -P yacc)"
    execute make depend
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'c2man' 'git'
fi

pre_check_ver 'fribidi/fribidi' '1' 'T'
if build 'fribidi' "$g_ver"; then
    download "https://github.com/fribidi/fribidi/archive/refs/tags/v$g_ver.tar.gz" "fribidi-$g_ver.tar.gz"
    extracmds=('-D'{docs,tests}'=false')
    execute autoreconf -fi
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                              "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'fribidi' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libfribidi')

pre_check_ver 'libass/libass' '1' 'T'
if build 'libass' "$g_ver"; then
    download "https://github.com/libass/libass/archive/refs/tags/$g_ver.tar.gz" "libass-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'libass' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libass')

pre_check_ver 'FreeGLUTProject/freeglut' '1' 'T'
if build 'freeglut' "$g_ver"; then
    download "https://github.com/freeglutproject/freeglut/archive/refs/tags/v$g_ver.tar.gz" "freeglut-$g_ver.tar.gz"
    CFLAGS+=' -DFREEGLUT_STATIC'
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DFREEGLUT_BUILD_SHARED_LIBS=OFF      \
                  -DFREEGLUT_BUILD_STATIC_LIBS=ON       \
                  -DFREEGLUT_PRINT_ERRORS=OFF           \
                  -DFREEGLUT_PRINT_WARNINGS=OFF         \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'freeglut' "$g_ver"
fi

if build 'libwebp' 'git'; then
    download_git 'https://chromium.googlesource.com/webm/libwebp' 'libwebp-git'
    execute autoreconf -fi
    execute cmake -B build                                  \
                  -DCMAKE_INSTALL_PREFIX=/usr/local         \
                  -DCMAKE_BUILD_TYPE=Release                \
                  -DBUILD_SHARED_LIBS=ON                    \
                  -DZLIB_INCLUDE_DIR="$workspace"/include \
                  -DWEBP_BUILD_ANIM_UTILS=OFF               \
                  -DWEBP_BUILD_CWEBP=ON                     \
                  -DWEBP_BUILD_DWEBP=ON                     \
                  -DWEBP_BUILD_EXTRAS=OFF                   \
                  -DWEBP_BUILD_VWEBP=OFF                    \
                  -DWEBP_ENABLE_SWAP_16BIT_CSP=OFF          \
                  -DWEBP_LINK_STATIC=ON                     \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute sudo ninja "-j${cpu_threads}" -C build install
    build_done 'libwebp' 'git'
fi
ffmpeg_libraries+=('--enable-libwebp')

pre_check_ver 'google/highway' '1' 'R'
if build 'libhwy' "$g_ver"; then
    download "https://github.com/google/highway/archive/refs/tags/$g_ver.tar.gz" "libhwy-$g_ver.tar.gz"
    CFLAGS+=' -DHWY_COMPILE_ALL_ATTAINABLE'
    CXXFLAGS+=' -DHWY_COMPILE_ALL_ATTAINABLE'
    execute cmake -B build                                   \
                  -DCMAKE_INSTALL_PREFIX="$install_prefix" \
                  -DCMAKE_BUILD_TYPE=Release                 \
                  -DHWY_ENABLE_TESTS=OFF                     \
                  -DBUILD_TESTING=OFF                        \
                  -DHWY_ENABLE_EXAMPLES=OFF                  \
                  -DHWY_FORCE_STATIC_LIBS=ON                 \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute sudo ninja "-j${cpu_threads}" -C build install
    build_done 'libhwy' "$g_ver"
fi

pre_check_ver 'google/brotli' '1' 'T'
if build 'brotli' "$g_ver"; then
    download "https://github.com/google/brotli/archive/refs/tags/v$g_ver.tar.gz" "brotli-$g_ver.tar.gz"
    execute cmake -B build                          \
                  -DCMAKE_INSTALL_PREFIX=/usr/local \
                  -DCMAKE_BUILD_TYPE=Release        \
                  -DBUILD_SHARED_LIBS=ON            \
                  -DBUILD_TESTING=OFF               \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute sudo ninja "-j${cpu_threads}" -C build install
    build_done 'brotli' "$g_ver"
fi

pre_check_ver 'mm2/Little-CMS' '1' 'T'
if build 'lcms2' "$g_ver"; then
    download "https://github.com/mm2/Little-CMS/archive/refs/tags/lcms$g_ver.tar.gz" "lcms2-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-shared            \
                        --with-threaded
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'lcms2' "$g_ver"
fi
ffmpeg_libraries+=('--enable-lcms2')

pre_check_ver 'gflags/gflags' '1' 'T'
if build 'gflags' "$g_ver"; then
    download "https://github.com/gflags/gflags/archive/refs/tags/v$g_ver.tar.gz" "gflags-$g_ver.tar.gz"
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_gflags_LIB=ON                 \
                  -DBUILD_STATIC_LIBS=ON                \
                  -DINSTALL_HEADERS=ON                  \
                  -DREGISTER_BUILD_DIR=ON               \
                  -DREGISTER_INSTALL_PREFIX=ON          \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'gflags' "$g_ver"
fi

if [[ "${OS}" == 'Arch' ]]; then
    echo
else
    if build 'libjxl' '0.8.2'; then
        dl_libjxl_fn
        build_done 'libjxl' '0.8.2'
    fi
fi
# Libjxl has a bug in the decoder bit decoding and must be disabled on arch linux
if [[ "${OS}" == 'Arch' ]]; then
    ffmpeg_libraries+=('--disable-libjxl')
else
    ffmpeg_libraries+=('--enable-libjxl')
fi

pre_check_ver 'khronosgroup/opencl-headers' '1' 'T'
if build 'opencl-headers' "$g_ver"; then
    download "https://github.com/KhronosGroup/OpenCL-Headers/archive/refs/tags/v$g_ver.tar.gz" "opencl-headers-$g_ver.tar.gz"
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DOPENCL_HEADERS_BUILD_CXX_TESTS=OFF  \
                  -DBUILD_TESTING=OFF                   \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'opencl-headers' "$g_ver"
fi
ffmpeg_libraries+=('--enable-opencl')

pre_check_ver 'DanBloomberg/leptonica' '1' 'T'
if build 'leptonica' '1.83.1'; then
    download 'https://github.com/DanBloomberg/leptonica/archive/refs/tags/1.83.1.tar.gz' "leptonica-1.83.1.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix=$install_dir        \
                        --{build,host}="${pc_type}" \
                        --with-pic
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'leptonica' '1.83.1'
fi

pre_check_ver 'tesseract-ocr/tesseract' '1' 'T'
if build 'tesseract' '5.3.2'; then
    download 'https://github.com/tesseract-ocr/tesseract/archive/refs/tags/5.3.2.tar.gz' 'tesseract-5.3.2.tar.gz'
    execute ./autogen.sh
    execute ./configure --prefix=$install_dir                         \
                        --{build,host}="${pc_type}"                  \
                        --disable-doc                                \
                        --with-extra-includes="$workspace"/include \
                        --with-extra-libraries="$workspace"/lib    \
                        --with-pic
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'tesseract' '5.3.2'
fi
ffmpeg_libraries+=('--enable-libtesseract')

if build 'jpeg-turbo' 'git'; then
    download_git 'https://github.com/imageMagick/jpeg-turbo.git'
    execute cmake -S .                              \
                  -DCMAKE_INSTALL_PREFIX=/usr/local \
                  -DCMAKE_BUILD_TYPE=Release        \
                  -DENABLE_SHARED=ON                \
                  -DENABLE_STATIC=ON                \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}"
    execute sudo ninja "-j${cpu_threads}" install
    build_done 'jpeg-turbo' 'git'
fi

if build 'rubberband' 'git'; then
    download_git 'https://github.com/m-ab-s/rubberband.git'
    execute make "-j${cpu_threads}" PREFIX="$workspace" install-static
    build_done 'rubberband' 'git'
fi
ffmpeg_libraries+=('--enable-librubberband')

pre_check_ver 'sekrit-twc/zimg' '1' 'T'
if build 'zimg' "$g_ver"; then
    download "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-$g_ver.tar.gz" "zimg-$g_ver.tar.gz"
    execute libtoolize -fiq
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'zimg' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libzimg')

pre_check_ver 'c-ares/c-ares' '1' 'R'
g_ver="${g_ver//ares-/}"
g_tag="${g_ver//\./_}"
if build 'c-ares' "$g_ver"; then
    download "https://github.com/c-ares/c-ares/archive/refs/tags/cares-${g_tag}.tar.gz" "c-ares-$g_ver.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix=$install_dir        \
                        --{build,host}="${pc_type}" \
                        --disable-debug             \
                        --disable-warnings          \
                        --with-pic
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'c-ares' "$g_ver"
fi

if build 'lv2' 'git'; then
    download_git 'https://github.com/lv2/lv2.git'
    extracmds=('-D'{docs,tests}'=disabled')
    case "${VER}" in
        10|11)      pswitch=enabled;;
        *)          pswitch=disabled;;
    esac
    rm_pip_lock="$(sudo find /usr/lib/python3* -type f -name 'EXTERNALLY-MANAGED')"
    if [ -n "${rm_pip_lock}" ]; then
        sudo rm "${rm_pip_lock}"
    fi
    execute pip install lxml Markdown Pygments rdflib
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                              -Dplugins="${pswitch}"   \
                              "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'lv2' 'git'
fi

git_ver_fn '7131569' '3' 'T'
g_ver="${g_ver//waf-/}"
if build 'waflib' "$g_ver"; then
    download "https://gitlab.com/ita1024/waf/-/archive/waf-$g_ver/waf-waf-$g_ver.tar.bz2" "waflib-$g_ver.tar.bz2"
    build_done 'waflib' "$g_ver"
fi

git_ver_fn '5048975' '3' 'T'
if build 'serd' "$g_ver"; then
    download "https://gitlab.com/drobilla/serd/-/archive/v$g_ver/serd-v$g_ver.tar.bz2" "serd-$g_ver.tar.bz2"
    extracmds=('-D'{docs,tests}'=disabled')
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                              -Dstatic=true            \
                              "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'serd' "$g_ver"
fi

pre_check_ver 'pcre2project/pcre2' '1' 'T'
if build 'pcre2' "$g_ver"; then
    download "https://github.com/PCRE2Project/pcre2/archive/refs/tags/pcre$g_ver.tar.gz" "pcre2-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --enable-jit            \
                        --enable-valgrind       \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'pcre2' "$g_ver"
fi

git_ver_fn '14889806' '3' 'B'
if build 'zix' '0.4.0'; then
    download 'https://gitlab.com/drobilla/zix/-/archive/v0.4.0/zix-v0.4.0.tar.bz2' 'zix-0.4.0.tar.bz2'
    extracmds=('-D'{benchmarks,docs,singlehtml,tests,tests_cpp}'=disabled')
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                              "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'zix' '0.4.0'
fi

git_ver_fn '11853362' '3' 'B'
if build 'sord' "${g_sver1}"; then
    CFLAGS+=" -I$workspace/include/serd-0"
    download "https://gitlab.com/drobilla/sord/-/archive/$g_ver1/sord-$g_ver1.tar.bz2" "sord-${g_sver1}.tar.bz2"
    extracmds=('-D'{docs,tests}'=disabled')
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                              "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'sord' "${g_sver1}"
fi

git_ver_fn '11853194' '3' 'T'
if build 'sratom' "$g_ver"; then
    download "https://gitlab.com/lv2/sratom/-/archive/v$g_ver/sratom-v$g_ver.tar.bz2" "sratom-$g_ver.tar.bz2"
    extracmds=('-D'{docs,tests}'=disabled')
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                              "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'sratom' "$g_ver"
fi

git_ver_fn '11853176' '3' 'T'
if build 'lilv' "$g_ver"; then
    download "https://gitlab.com/lv2/lilv/-/archive/v$g_ver/lilv-v$g_ver.tar.bz2" "lilv-$g_ver.tar.bz2"
    extracmds=('-D'{docs,tests}'=disabled')
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                              "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'lilv' "$g_ver"
fi
CFLAGS+=" -I$workspace/include/lilv-0"
ffmpeg_libraries+=('--enable-lv2')

if build 'libmpg123' 'git'; then
    download_git 'https://github.com/gypified/libmpg123.git'
    execute rm -fr aclocal.m4
    execute aclocal --force -I m4
    execute autoconf -f -W all,no-obsolete
    execute autoheader -f -W all
    execute automake -a -c -f -W all,no-portability
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --enable-static         \
                        --with-cpu=x86-64
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'libmpg123' 'git'
fi

pre_check_ver 'akheron/jansson' '1' 'T'
if build 'jansson' "$g_ver"; then
    download "https://github.com/akheron/jansson/archive/refs/tags/v$g_ver.tar.gz" "jansson-$g_ver.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace"
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'jansson' "$g_ver"
fi

pre_check_ver 'jemalloc/jemalloc' '1' 'T'
if build 'jemalloc' "$g_ver"; then
    download "https://github.com/jemalloc/jemalloc/archive/refs/tags/$g_ver.tar.gz" "jemalloc-$g_ver.tar.gz"
    extracmds1=('--disable-'{debug,doc,fill,log,shared,prof,stats})
    extracmds2=('--enable-'{autogen,static,xmalloc})
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        "${extracmds1[@]}"      \
                        "${extracmds2[@]}"
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'jemalloc' "$g_ver"
fi

if build 'cunit' 'git'; then
    download_git 'https://github.com/jacklicn/cunit.git'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'cunit' 'git'
fi

# Install audio tools

echo
box_out_banner_audio()
{
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner_audio 'Installing Audio Tools'

if build 'sdl2' 'git'; then
    download_git 'https://github.com/libsdl-org/SDL.git' 'sdl2-git'
    execute cmake -S . -B build                              \
                       -DCMAKE_INSTALL_PREFIX="$workspace" \
                       -DCMAKE_BUILD_TYPE=Release            \
                       -DBUILD_SHARED_LIBS=OFF               \
                       -DSDL_ALSA_SHARED=OFF                 \
                       -DSDL_DISABLE_INSTALL_DOCS=ON         \
                       -DSDL_CCACHE=ON                       \
                       -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'sdl2' 'git'
fi

git_ver_fn '810' '4'
if build 'libpulse' "$g_ver"; then
    download_git 'https://gitlab.freedesktop.org/pulseaudio/pulseaudio.git' "libpulse-$g_ver.tar.gz"
    extracmds=('-D'{daemon,doxygen,ipv6,man,tests}'=false')
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                               "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute sudo ninja "-j${cpu_threads}" -C build install
    libpulse_fix_libs_fn
    build_done 'libpulse' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libpulse')

pre_check_ver 'xiph/ogg' '1' 'T'
if build 'libogg' "$g_ver"; then
    download "https://github.com/xiph/ogg/archive/refs/tags/v$g_ver.tar.gz" "libogg-$g_ver.tar.gz"
    execute autoreconf -fi
    execute cmake -B build                          \
                  -DCMAKE_INSTALL_PREFIX=/usr/local \
                  -DCMAKE_BUILD_TYPE=Release        \
                  -DBUILD_SHARED_LIBS=ON            \
                  -DBUILD_TESTING=OFF               \
                  -DCPACK_BINARY_DEB=OFF            \
                  -DCPACK_SOURCE_ZIP=OFF            \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute sudo ninja "-j${cpu_threads}" -C build install
    build_done 'libogg' "$g_ver"
fi

pre_check_ver 'xiph/flac' '1' 'T'
if build 'libflac' "$g_ver"; then
    download "https://github.com/xiph/flac/archive/refs/tags/$g_ver.tar.gz" "libflac-$g_ver.tar.gz"
    execute ./autogen.sh
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -DINSTALL_CMAKE_CONFIG_MODULE=ON      \
                  -DINSTALL_MANPAGES=OFF                \
                  -DBUILD_CXXLIBS=ON                    \
                  -DBUILD_PROGRAMS=ON                   \
                  -DWITH_ASM=ON                         \
                  -DWITH_AVX=ON                         \
                  -DWITH_FORTIFY_SOURCE=ON              \
                  -DWITH_STACK_PROTECTOR=ON             \
                  -DWITH_OGG=ON                         \
                  -DENABLE_64_BIT_WORDS=ON              \
                  -DBUILD_DOCS=OFF                      \
                  -DBUILD_EXAMPLES=OFF                  \
                  -DBUILD_TESTING=OFF                   \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'libflac' "$g_ver"
fi

pre_check_ver 'mstorsjo/fdk-aac' '1' 'T'
if build 'libfdk-aac' '2.0.2'; then
    download 'https://master.dl.sourceforge.net/project/opencore-amr/fdk-aac/fdk-aac-2.0.2.tar.gz?viasf=1' 'libfdk-aac-2.0.2.tar.gz'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --disable-shared        \
                        --enable-static
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'libfdk-aac' '2.0.2'
fi
ffmpeg_libraries+=('--enable-libfdk-aac')

pre_check_ver 'xiph/vorbis' '1' 'T'
if build 'vorbis' "$g_ver"; then
    download "https://github.com/xiph/vorbis/archive/refs/tags/v$g_ver.tar.gz" "vorbis-$g_ver.tar.gz"
    execute ./autogen.sh
    execute cmake -B build                                   \
                  -DCMAKE_INSTALL_PREFIX=/usr/local          \
                  -DCMAKE_BUILD_TYPE=Release                 \
                  -DBUILD_SHARED_LIBS=ON                     \
                  -DOGG_INCLUDE_DIR=/usr/local/include   \
                  -DOGG_LIBRARY=/usr/local/lib/libogg.so \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute sudo ninja "-j${cpu_threads}" -C build install
    build_done 'vorbis' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libvorbis')

pre_check_ver 'xiph/opus' '1' 'T'
if build 'opus' "$g_ver"; then
    download "https://github.com/xiph/opus/archive/refs/tags/v$g_ver.tar.gz" "opus-$g_ver.tar.gz"
    execute autoreconf -fis
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -DCPACK_SOURCE_ZIP=OFF                \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'opus' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libopus')

pre_check_ver 'hoene/libmysofa' '1' 'T'
if build 'libmysofa' "$g_ver"; then
    download "https://github.com/hoene/libmysofa/archive/refs/tags/v$g_ver.tar.gz" "libmysofa-$g_ver.tar.gz"
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -DBUILD_STATIC_LIBS=ON                \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'libmysofa' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libmysofa')

pre_check_ver 'webmproject/libvpx' '1' 'T'
if build 'vpx' "$g_ver"; then
    download "https://github.com/webmproject/libvpx/archive/refs/tags/v$g_ver.tar.gz" "libvpx-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" \
                        --as=yasm               \
                        --disable-unit-tests    \
                        --disable-shared        \
                        --disable-examples      \
                        --enable-vp9-highbitdepth
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'vpx' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libvpx')

git_ver_fn '8143' '6'
g_ver="${g_ver//debian\//}"
if build 'opencore-amr' "$g_ver"; then
    download "https://salsa.debian.org/multimedia-team/opencore-amr/-/archive/debian/$g_ver/opencore-amr-debian-$g_ver.tar.bz2" "opencore-amr-$g_ver.tar.bz2"
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'opencore-amr' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libopencore-amrnb' '--enable-libopencore-amrwb')

if build 'liblame' '3.100'; then
    download 'https://zenlayer.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz'
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-shared            \
                        --disable-gtktest           \
                        --enable-nasm               \
                        --with-libiconv-prefix=/usr
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'liblame' '3.100'
fi
ffmpeg_libraries+=('--enable-libmp3lame')

pre_check_ver 'xiph/theora' '1' 'T'
if build 'libtheora' "$g_ver1"; then
    download "https://github.com/xiph/theora/archive/refs/tags/v$g_ver1.tar.gz" "libtheora-$g_ver1.tar.gz"
    execute ./autogen.sh
    sed 's/-fforce-addr//g' configure > configure.patched
    chmod +x configure.patched
    execute mv configure.patched configure
    execute rm config.guess
    execute curl -A "$user_agent" -Lso config.guess https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess
    chmod +x config.guess
    execute ./configure --prefix=$install_dir                          \
                        --{build,host,target}="${pc_type}"            \
                        --disable-examples                            \
                        --disable-oggtest                             \
                        --disable-sdltest                             \
                        --disable-vorbistest                          \
                        --with-ogg="$workspace"                     \
                        --with-ogg-includes="$workspace"/include    \
                        --with-ogg-libraries="$workspace"/lib       \
                        --with-vorbis="$workspace"                  \
                        --with-vorbis-includes="$workspace"/include \
                        --with-vorbis-libraries="$workspace"/lib    \
                        --with-pic
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'libtheora' "$g_ver1"
fi
ffmpeg_libraries+=('--enable-libtheora')

# Install video tools

echo
box_out_banner_video()
{
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner_video 'Installing Video Tools'

if build 'vulkan-headers' 'git'; then
    download_git 'https://github.com/KhronosGroup/Vulkan-Headers.git' 'vulkan-headers-git'
    execute cmake -B build                                     \
                  -DCMAKE_INSTALL_PREFIX="$workspace"        \
                  -DCMAKE_BUILD_TYPE=Release                   \
                  -DBUILD_TESTS=OFF                            \
                  -DCMAKE_C_FLAGS='-g -O2 -pipe -march=native' \
                  -DCMAKE_STRIP="$(type -P strip)"             \
                  -G Ninja -Wno-devCMAKE_CXX_COMPILE
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'vulkan-headers' 'git'
fi
ffmpeg_libraries+=('--enable-libkvazaar')

if build 'decklink' '12.8'; then
    download "https://github.com/slyfox1186/ffmpeg-build-script/raw/main/headers/blackmagic-deckLink-sdk-12.8.tar.gz" 'decklink-12.8.tar.xz'
    for files in *.{h,cpp}
    do
        mv "${files}" "$workspace"/include
    done
    build_done 'decklink' '12.8'
fi
ffmpeg_libraries+=('--enable-decklink')

# Need to update this repo from time to time manually
aom_ver=6054fae218eda6e53e1e3b4f7ef0fff4877c7bf1
# Aom_ver=4783bb8b4ca42e15078225e3f58d246e13a93c28
aom_sver="${aom_ver::7}"
if build 'av1' "${aom_sver}"; then
    download "https://aomedia.googlesource.com/aom/+archive/${aom_ver}.tar.gz" "av1-${aom_sver}.tar.gz" 'av1'
    mkdir -p "$packages/aom_build"
    cd "$packages/aom_build" || exit 1
    execute cmake -B build                                \
                  -DCMAKE_INSTALL_PREFIX="$workspace"   \
                  -DCMAKE_BUILD_TYPE=Release              \
                  -DBUILD_SHARED_LIBS=OFF                 \
                  -DCONFIG_AV1_DECODER=1                  \
                  -DCONFIG_AV1_ENCODER=1                  \
                  -DCONFIG_AV1_HIGHBITDEPTH=1             \
                  -DCONFIG_AV1_TEMPORAL_DENOISING=1       \
                  -DCONFIG_DENOISE=1                      \
                  -DCONFIG_DISABLE_FULL_PIXEL_SPLIT_8X8=1 \
                  -DENABLE_CCACHE=1                       \
                  -DENABLE_EXAMPLES=0                     \
                  -DENABLE_TESTS=0                        \
                  -G Ninja -Wno-dev                       \
                  "$packages"/av1
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'av1' "${aom_sver}"
fi
ffmpeg_libraries+=('--enable-libaom')

pre_check_ver '198' '2' 'T'
if build 'dav1d' "$g_ver1"; then
    download "https://code.videolan.org/videolan/dav1d/-/archive/$g_ver1/dav1d-$g_ver1.tar.bz2"
    extracmds=('-D'{enable_tests,logging}'=false')
    execute meson setup build --prefix="$workspace"  \
                              --buildtype=release      \
                              --default-library=static \
                              --strip                  \
                               "${extracmds[@]}"
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'dav1d' "$g_ver1"
fi
ffmpeg_libraries+=('--enable-libdav1d')

# Rav1e fails to build on ubuntu bionic and debian 11 bullseye
if [ "${VER}" != '18.04' ] && [ "${VER}" != '11' ]; then
    pre_check_ver 'xiph/rav1e' '1' 'T'
    if build 'rav1e' 'p20231024'; then
        get_rustc_ver="$(rustc --version | grep -Eo '[0-9\.]+' | head -n1)"
        if [ "${get_rustc_ver}" != '1.73.0' ]; then
            echo '$ Installing RustUp'
            curl -A "$user_agent" -sSf --proto '=https' --tlsv1.2 'https://sh.rustup.rs' | sh -s -- -y &>/dev/null
            source "${HOME}"/.cargo/env
            if [ -f "${HOME}"/.zshrc ]; then
                source "${HOME}"/.zshrc
            else
                source "${HOME}"/.bashrc
            fi
            rm -fr "${HOME}"/.cargo/registry/index/* "${HOME}"/.cargo/.package-cache
        fi
        execute cargo install cargo-c
        download 'https://github.com/xiph/rav1e/archive/refs/tags/p20231024.tar.gz' 'rav1e-p20231024.tar.gz'
        execute cargo cinstall --prefix="$workspace"  \
                               --library-type=staticlib \
                               --crt-static             \
                               --release
        build_done 'rav1e' 'p20231024'
    fi
    ffmpeg_libraries+=('--enable-librav1e')
fi

pre_check_ver 'AOMediaCodec/libavif' '1' 'T'
if build 'avif' "$g_ver"; then
    download "https://github.com/AOMediaCodec/libavif/archive/refs/tags/v$g_ver.tar.gz" "avif-$g_ver.tar.gz"
    execute cmake -B build                          \
                  -DCMAKE_INSTALL_PREFIX=/usr/local \
                  -DCMAKE_BUILD_TYPE=Release        \
                  -DBUILD_SHARED_LIBS=ON            \
                  -DAVIF_CODEC_AOM=ON               \
                  -DAVIF_CODEC_AOM_DECODE=ON        \
                  -DAVIF_CODEC_AOM_ENCODE=ON        \
                  -DAVIF_ENABLE_GTEST=OFF           \
                  -DAVIF_ENABLE_WERROR=OFF          \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute sudo ninja "-j${cpu_threads}" -C build install
    build_done 'avif' "$g_ver"
fi

pre_check_ver 'ultravideo/kvazaar' '1' 'T'
if build 'kvazaar' "$g_ver"; then
    download_git 'https://github.com/ultravideo/kvazaar.git'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'kvazaar' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libkvazaar')

git_ver_fn '76' '2' 'T'
if build 'libdvdread' "$g_ver1"; then
    download "https://code.videolan.org/videolan/libdvdread/-/archive/$g_ver1/libdvdread-$g_ver1.tar.bz2"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-apidoc            \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'libdvdread' "$g_ver1"
fi

git_ver_fn '363' '2' 'T'
if build 'udfread' "$g_ver1"; then
    download "https://code.videolan.org/videolan/libudfread/-/archive/$g_ver1/libudfread-$g_ver1.tar.bz2"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'udfread' "$g_ver1"
fi

ant_path_fn
if build 'ant' 'git'; then
    download_git 'https://github.com/apache/ant.git'
    sudo chmod 777 -R /usr/local/ant
    execute sh build.sh install-lite
    build_done 'ant' 'git'
fi

if [[ "${OS}" == 'Arch' ]]; then
    apache_ant_fn
fi

git_ver_fn '206' '2' 'T'
if build 'libbluray' "$g_ver1"; then
    download "https://code.videolan.org/videolan/libbluray/-/archive/$g_ver1/$g_ver1.tar.gz" "libbluray-$g_ver1.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-examples          \
                        --disable-extra-warnings    \
                        --disable-shared            \
                        --without-libxml2
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'libbluray' "$g_ver1"
fi
ffmpeg_libraries+=('--enable-libbluray')

pre_check_ver 'mediaarea/zenLib' '1' 'T'
if build 'zenlib' "$g_ver"; then
    download "https://github.com/MediaArea/ZenLib/archive/refs/tags/v$g_ver.tar.gz" "zenlib-$g_ver.tar.gz"
    cd Project/GNU/Library || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'zenlib' "$g_ver"
fi

pre_check_ver 'MediaArea/MediaInfoLib' '1' 'T'
if build 'mediainfolib' "$g_ver"; then
    download "https://github.com/MediaArea/MediaInfoLib/archive/refs/tags/v$g_ver.tar.gz" "mediainfolib-$g_ver.tar.gz"
    cd Project/GNU/Library || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'mediainfolib' "$g_ver"
fi

pre_check_ver 'MediaArea/MediaInfo' '1' 'T'
if build 'mediainfo-cli' "$g_ver"; then
    download "https://github.com/MediaArea/MediaInfo/archive/refs/tags/v$g_ver.tar.gz" "mediainfo-cli-$g_ver.tar.gz"
    cd Project/GNU/CLI || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"     \
                        --{build,host}="${pc_type}" \
                        --enable-staticlibs         \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'mediainfo-cli' "$g_ver"
fi

pre_check_ver 'georgmartius/vid.stab' '1' 'T'
if build 'vid-stab' "$g_ver"; then
    download "https://github.com/georgmartius/vid.stab/archive/refs/tags/v$g_ver.tar.gz" "vid-stab-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -DUSE_OMP=ON                          \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'vid-stab' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libvidstab')

pre_check_ver 'dyne/frei0r' '1' 'T'
if build 'frei0r' "$g_ver"; then
    download "https://github.com/dyne/frei0r/archive/refs/tags/v$g_ver.tar.gz" "frei0r-$g_ver.tar.gz"
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -DWITHOUT_OPENCV=OFF                  \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'frei0r' "$g_ver"
fi
ffmpeg_libraries+=('--enable-frei0r')

pre_check_ver 'GPUOpen-LibrariesAndSDKs/AMF' '1' 'T'
g_sver="$(echo "$g_ver" | sed -E 's/^\.//g')"
if build 'amf' "${g_sver}"; then
    download "https://github.com/GPUOpen-LibrariesAndSDKs/AMF/archive/refs/tags/v$g_ver.tar.gz" "amf-${g_sver}.tar.gz"
    execute rm -fr "$workspace"/include/AMF
    execute mkdir -p "$workspace"/include/AMF
    execute cp -fr "$packages"/amf-"${g_sver}"/amf/public/include/* "$workspace"/include/AMF
    build_done 'amf' "${g_sver}"
fi
ffmpeg_libraries+=('--enable-amf')

if [[ "${OS}" == 'Arch' ]]; then
    pre_check_ver 'gpac/gpac' '1' 'T'
    if build 'gpac' "$g_ver"; then
        sudo pacman --noconfirm gpac
        build_done 'gpac' "$g_ver"
    fi
else
    pre_check_ver 'gpac/gpac' '1' 'T'
    if build 'gpac' "$g_ver"; then
        download_git 'https://github.com/gpac/gpac.git'
        execute sudo ./configure --prefix=$install_dir                  \
                                 --static-bin                          \
                                 --use-a52=local                       \
                                 --use-faad=local                      \
                                 --use-mad=local                       \
                                 --sdl-cfg="$workspace"/include/SDL3
        execute sudo make "-j${cpu_threads}"
        execute sudo make install
        build_done 'gpac' "$g_ver"
    fi
fi

# Versions >= 1.4.0 breaks ffmpeg during the build
git_ver_fn '24327400' '3' 'T'
if build 'svt-av1' '1.4.0'; then
    download 'https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v1.4.0/SVT-AV1-v1.4.0.tar.bz2' 'svt-av1-1.4.0.tar.bz2'
    execute cmake -S . -B Build/linux                        \
                       -DCMAKE_INSTALL_PREFIX="$workspace" \
                       -DCMAKE_BUILD_TYPE=Release            \
                       -DBUILD_SHARED_LIBS=OFF               \
                       -DBUILD_APPS=OFF                      \
                       -DBUILD_DEC=ON                        \
                       -DBUILD_ENC=ON                        \
                       -DBUILD_TESTING=OFF                   \
                       -DENABLE_AVX512=OFF                   \
                       -DENABLE_NASM=ON                      \
                       -DNATIVE=ON                           \
                       -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C Build/linux
    execute ninja "-j${cpu_threads}" -C Build/linux install
    cp -f 'Build/linux/SvtAv1Enc.pc' "$workspace"/lib/pkgconfig
    cp -f 'Build/linux/SvtAv1Dec.pc' "$workspace"/lib/pkgconfig
    build_done 'svt-av1' '1.4.0'
fi
ffmpeg_libraries+=('--enable-libsvtav1')

git_ver_fn '536' '2' 'B'
g_sver="${g_ver::8}"
if build 'x264' "${g_sver}"; then
    download "https://code.videolan.org/videolan/x264/-/archive/$g_ver/x264-$g_ver.tar.bz2" "x264-${g_sver}.tar.bz2"
    execute ./configure --prefix="$workspace" \
                        --bit-depth=all         \
                        --chroma-format=all     \
                        --enable-gprof          \
                        --enable-static         \
                        --enable-strip
    execute sudo make "-j${cpu_threads}"
    execute sudo make install
    execute sudo make install-lib-static
    build_done 'x264' "${g_sver}"
fi
ffmpeg_libraries+=('--enable-libx264')

# X265 gives better fps when built with clang
export CC=clang CXX=clang++
# Enter a snapshot id for x265
g_ver=8ee01d45b05cdbc9da89b884815257807a514bc8
g_sver="${g_ver::7}"
if build 'x265' "${g_sver}"; then
    download "https://bitbucket.org/multicoreware/x265_git/get/$g_ver.tar.bz2" "x265-${g_sver}.tar.bz2"
    cd build/linux || exit 1
    rm -fr {8,10,12}bit 2>/dev/null
    mkdir -p {8,10,12}bit
    cd 12bit || exit 1
    echo '$ making 12bit binaries'
    execute cmake ../../../source                   \
                  -DCMAKE_INSTALL_PREFIX=/usr/local \
                  -DCMAKE_BUILD_TYPE=Release        \
                  -DENABLE_CLI=OFF                  \
                  -DENABLE_SHARED=OFF               \
                  -DEXPORT_C_API=OFF                \
                  -DHIGH_BIT_DEPTH=ON               \
                  -DMAIN12=ON                       \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}"
    echo '$ making 10bit binaries'
    cd ../10bit || exit 1
    execute cmake ../../../source                   \
                  -DCMAKE_INSTALL_PREFIX=/usr/local \
                  -DCMAKE_BUILD_TYPE=Release        \
                  -DENABLE_CLI=OFF                  \
                  -DENABLE_HDR10_PLUS=ON            \
                  -DENABLE_SHARED=OFF               \
                  -DEXPORT_C_API=OFF                \
                  -DHIGH_BIT_DEPTH=ON               \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}"
    echo '$ making 8bit binaries'
    cd ../8bit || exit 1
    ln -sf ../10bit/libx265.a libx265_main10.a
    ln -sf ../12bit/libx265.a libx265_main12.a
    execute cmake ../../../source                           \
                  -DCMAKE_INSTALL_PREFIX=/usr/local         \
                  -DCMAKE_BUILD_TYPE=Release                \
                  -DENABLE_SHARED=ON                        \
                  -DENABLE_PIC=ON                           \
                  -DEXTRA_LIB='x265_main10.a;x265_main12.a' \
                  -DEXTRA_LINK_FLAGS=-L.                    \
                  -DLINKED_10BIT=ON                         \
                  -DLINKED_12BIT=ON                         \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}"

    mv 'libx265.a' 'libx265_main.a'

    execute ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF

    execute sudo ninja "-j${cpu_threads}" install

    if [ -n "${LDEXEFLAGS}" ]; then
        sed -i.backup 's/lgcc_s/lgcc_eh/g' '/usr/local/lib/pkgconfig/x265.pc'
    fi

# Fix x265 shared lib issues
    x265_fix_libs_fn

    build_done 'x265' "${g_sver}"
fi
ffmpeg_libraries+=('--enable-libx265')

# Change the compilers back to gcc for the rest of the build
export CC=gcc CXX=g++

# Vaapi doesn't work well with static links ffmpeg.
if [ -z "${LDEXEFLAGS}" ]; then
# If the libva development sdk is installed, enable vaapi.
    if library_exists 'libva'; then
        if build 'vaapi' '1'; then
            build_done 'vaapi' '1'
        fi
        ffmpeg_libraries+=('--enable-vaapi')
    fi
fi

if [ -n "${iscuda}" ]; then
    if build 'nv-codec-headers' '12.0.16.1'; then
        download 'https://github.com/FFmpeg/nv-codec-headers/releases/download/n12.0.16.1/nv-codec-headers-12.0.16.1.tar.gz'
        execute make "-j${cpu_threads}"
        execute make PREFIX="$workspace" install
        build_done 'nv-codec-headers' '12.0.16.1'
    fi

    if [[ "${OS}" == 'Arch' ]]; then
        export PATH+=':/opt/cuda/bin'
        CFLAGS+=' -I/opt/cuda/include -I/opt/cuda/targets/x86_64-linux/include'
        LDFLAGS+=' -L/opt/cuda/lib64 -L/opt/cuda/lib -L/opt/cuda/targets/x86_64-linux/lib'
    else
        CFLAGS+=' -I/usr/local/cuda/include'
        LDFLAGS+=' -L/usr/local/cuda/lib64'
    fi

    if [ "${OS}" != 'Arch' ]; then
        if ! sudo dpkg -l | grep -o nvidia-smi &>/dev/null; then
            sudo apt install nvidia-smi &>/dev/null
        fi
    fi

# Get the gpu architecture
# Https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards
    gpu_arch_fn

    ffmpeg_libraries+=('--enable-'{cuda-nvcc,cuda-llvm,cuvid,nvdec,nvenc,ffnvcodec})

    if [ -n "${LDEXEFLAGS}" ]; then
        ffmpeg_libraries+=('--enable-libnpp')
    fi
fi
ffmpeg_libraries+=("--nvccflags=-gencode arch=${gpu_arch}")

pre_check_ver 'Haivision/srt' '1' 'R'
if build 'srt' "$g_ver"; then
    download "https://github.com/Haivision/srt/archive/refs/tags/v$g_ver.tar.gz" "srt-$g_ver.tar.gz"
    export OPENSSL_ROOT_DIR="$workspace"
    export OPENSSL_LIB_DIR="$workspace"/lib
    export OPENSSL_INCLUDE_DIR="$workspace"/include
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -DENABLE_APPS=OFF                     \
                  -DENABLE_SHARED=OFF                   \
                  -DENABLE_STATIC=ON                    \
                  -DUSE_STATIC_LIBSTDCXX=ON             \
                  -G Ninja -Wno-dev
    execute ninja -C build "-j${cpu_threads}"
    execute ninja -C build "-j${cpu_threads}" install
    if [ -n "${LDEXEFLAGS}" ]; then
        sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$workspace"/lib/pkgconfig/srt.pc
    fi
    build_done 'srt' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libsrt')

pre_check_ver 'avisynth/avisynthplus' '1' 'T'
if build 'avisynth' "$g_ver"; then
    download "https://github.com/AviSynth/AviSynthPlus/archive/refs/tags/v$g_ver.tar.gz" "avisynth-$g_ver.tar.gz"
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -DHEADERS_ONLY=OFF
    execute make "-j${cpu_threads}" -C build VersionGen install
    build_done 'avisynth' "$g_ver"
fi
CFLAGS+=" -I$workspace/include/avisynth"
ffmpeg_libraries+=('--enable-avisynth')

pre_check_ver 'vapoursynth/vapoursynth' '1' 'R'
if build 'vapoursynth' "$g_ver"; then
    download "https://github.com/vapoursynth/vapoursynth/archive/refs/tags/$g_ver.tar.gz" "vapoursynth-$g_ver.tar.gz"
    execute pip install Cython==0.29.36
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --disable-shared
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'vapoursynth' "$g_ver"
fi
ffmpeg_libraries+=('--enable-vapoursynth')

if [ "${VER}" != '22.04' ]; then
    pre_check_ver 'cyanreg/cyanrip' '1' 'T'
    if build 'cyanrip' "$g_ver"; then
        download "https://github.com/cyanreg/cyanrip/archive/refs/tags/v$g_ver.tar.gz" "cyanrip-$g_ver.tar.gz"
        execute meson setup build --prefix="$workspace"  \
                                  --buildtype=release      \
                                  --default-library=static \
                                  --strip
        execute ninja -C build "-j${cpu_threads}"
        execute ninja -C build "-j${cpu_threads}" install
        build_done 'cyanrip' "$g_ver"
    fi
fi

if build 'libgav1' 'git'; then
    download_git 'https://chromium.googlesource.com/codecs/libgav1' 'libgav1-git'
    execute git clone -q -b '20220623.1' --depth 1 'https://github.com/abseil/abseil-cpp.git' 'third_party/abseil-cpp'
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DABSL_ENABLE_INSTALL=ON              \
                  -DABSL_PROPAGATE_CXX_STD=ON           \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON    \
                  -DCMAKE_INSTALL_SBINDIR=sbin          \
                  -DLIBGAV1_ENABLE_TESTS=OFF            \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'libgav1' 'git'
fi

git_ver_fn '8268' '6'
g_ver="${g_ver//debian\/2%/}"
if build 'xvidcore' "$g_ver"; then
    download "https://salsa.debian.org/multimedia-team/xvidcore/-/archive/debian/2%25$g_ver/xvidcore-debian-2%25$g_ver.tar.bz2" "xvidcore-$g_ver.tar.bz2"
    cd 'build/generic' || exit 1
    execute ./bootstrap.sh
    execute ./configure --prefix=$workspace \
                        --{build,host,target}="${pc_type}"
    execute make "-j${cpu_threads}"
    execute make install
    build_done 'xvidcore' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libxvid')

# Image libraries

echo
box_out_banner_images()
{
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner_images 'Installing Image Tools'

pre_check_ver 'strukturag/libheif' '1' 'T'
if build 'libheif' "$g_ver"; then
    download "https://github.com/strukturag/libheif/archive/refs/tags/v$g_ver.tar.gz" "libheif-$g_ver.tar.gz"
    export {CFLAGS,CXXFLAGS}='-g -O2 -fno-lto -pipe -march=native'
    libde265_libs="$(sudo find /usr -type f -name 'libde265.so')"
    if [ -f "${libde265_libs}" ] && [ ! -f '/usr/lib/x86_64-linux-gnu/libde265.so' ]; then
        sudo cp -f "${libde265_libs}" '/usr/lib/x86_64-linux-gnu'
        sudo chmod 755 '/usr/lib/x86_64-linux-gnu/libde265.so'
    fi
    if [ -f "$workspace/lib/libdav1d.a" ] && [ ! -f "$workspace/lib/x86_64-linux-gnu/libdav1d.a" ]; then
        if [ ! -d "$workspace/lib/x86_64-linux-gnu" ]; then
            mkdir -p "$workspace/lib/x86_64-linux-gnu"
        fi
        cp -f "$workspace/lib/libdav1d.a"  "$workspace/lib/x86_64-linux-gnu/libdav1d.a"
    fi
    case "${VER}" in
        18.04|20.04)    pixbuf_switch='OFF';;
        *)              pixbuf_switch='ON';;
    esac
    execute cmake -B build                                                       \
                  -DCMAKE_INSTALL_PREFIX="$workspace"                          \
                  -DCMAKE_BUILD_TYPE=Release                                     \
                  -DBUILD_SHARED_LIBS=OFF                                        \
                  -DAOM_INCLUDE_DIR="$workspace"/include                       \
                  -DAOM_LIBRARY="$workspace"/lib/libaom.a                      \
                  -DDAV1D_INCLUDE_DIR="$workspace"/include                     \
                  -DDAV1D_LIBRARY="$workspace"/lib/x86_64-linux-gnu/libdav1d.a \
                  -DLIBDE265_INCLUDE_DIR=/usr/local/include                      \
                  -DLIBDE265_LIBRARY=/usr/lib/x86_64-linux-gnu/libde265.so       \
                  -DLIBSHARPYUV_INCLUDE_DIR=/usr/local/include/webp              \
                  -DLIBSHARPYUV_LIBRARY=/usr/local/lib/libsharpyuv.so            \
                  -DWITH_AOM_DECODER=ON                                          \
                  -DWITH_AOM_ENCODER=ON                                          \
                  -DWITH_DAV1D=ON                                                \
                  -DWITH_EXAMPLES=OFF                                            \
                  -DWITH_GDK_PIXBUF="${pixbuf_switch}"                           \
                  -DWITH_LIBDE265=ON                                             \
                  -DWITH_LIBSHARPYUV=ON                                          \
                  -DWITH_REDUCED_VISIBILITY=OFF                                  \
                  -DWITH_SvtEnc=OFF                                              \
                  -DWITH_SvtEnc_PLUGIN=OFF                                       \
                  -DX265_INCLUDE_DIR=/usr/local/include                          \
                  -DX265_LIBRARY=/usr/local/lib/libx265.so                       \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    source_flags_fn
    build_done 'libheif' "$g_ver"
fi

pre_check_ver 'uclouvain/openjpeg' '1' 'R'
if build 'openjpeg' "$g_ver2"; then
    download "https://codeload.github.com/uclouvain/openjpeg/tar.gz/refs/tags/v$g_ver2" "openjpeg-$g_ver2.tar.gz"
    execute cmake -B build                          \
                  -DCMAKE_INSTALL_PREFIX=/usr/local \
                  -DCMAKE_BUILD_TYPE=Release        \
                  -DBUILD_SHARED_LIBS=ON            \
                  -DBUILD_TESTING=OFF               \
                  -G Ninja -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute sudo ninja "-j${cpu_threads}" -C build install
    build_done 'openjpeg' "$g_ver2"
fi
ffmpeg_libraries+=('--enable-libopenjpeg')

# Build ffmpeg

echo
box_out_banner_ffmpeg()
{
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner_ffmpeg 'Building FFmpeg'

if [ -n "${ffmpeg_archive}" ]; then
    ff_cmd="${ffmpeg_url} ${ffmpeg_archive}"
else
    ff_cmd="${ffmpeg_url}"
fi

if [[ "${OS}" == 'Arch' ]]; then
    ladspa_switch='--disable-ladspa'
else
    ladspa_switch='--enable-ladspa'
fi

curl -A "$user_agent" -Lso "$packages"/dxva2api.h 'https://download.videolan.org/pub/contrib/dxva2api.h'
sudo cp -f "$packages"/dxva2api.h /usr/include
curl -A "$user_agent" -Lso "$packages"/objbase.h 'https://raw.githubusercontent.com/wine-mirror/wine/master/include/objbase.h'
sudo cp -f "$packages"/objbase.h /usr/local

if build 'ffmpeg' 'git'; then
    download_git 'https://git.ffmpeg.org/ffmpeg.git'
    if [[ "${OS}" == 'Arch' ]]; then
        patch_ffmpeg_fn
    fi

    ffmpeg_ndi_fn
    cd "$packages/ffmpeg-git" || exit 1
    git checkout n5.1
    echo
    read -p 'Please enter your GitHub e-mail address: ' gh_email
    read -p 'Please enter your GitHub username: ' gh_uname
    echo
    git config user.email "${gh_email}"
    git config --global user.name "${gh_uname}"
    execute sudo git am "$packages"/FFMPEG-NDI-git/libndi.patch
    execute sudo cp "$packages"/FFMPEG-NDI-git/libavdevice/libndi_newtek_* libavdevice/
    execute sudo bash "$packages"/FFMPEG-NDI-git/preinstall.sh
    execute sed -i 's/FFMPEG-NDI/FFMPEG-NDI-git/g' "$packages/FFMPEG-NDI-git/install-ndi-x86_64.sh"
    execute sudo bash "$packages"/FFMPEG-NDI-git/install-ndi-x86_64.sh
    execute sed -i 's/    { VK_EXT_VIDEO_DECODE_H264_EXTENSION_NAME,                FF_VK_EXT_NO_FLAG                },//g' 'libavutil/hwcontext_vulkan.c'
    execute sed -i 's/    { VK_EXT_VIDEO_DECODE_H265_EXTENSION_NAME,                FF_VK_EXT_NO_FLAG                },//g' 'libavutil/hwcontext_vulkan.c'
    mkdir build
    cd build || exit 1
    ../configure --prefix=$install_dir                     \
                 --arch="$(uname -m)"                        \
                 --cpu="$((cpu_threads / 2))"                \
                 --cc="${CC}"                                \
                 --cxx="${CXX}"                              \
                 --disable-debug                             \
                 --disable-doc                               \
                 --disable-large-tests                       \
                 --disable-shared                            \
                 "${ladspa_switch}"                          \
                 "${ffmpeg_libraries[@]}"                    \
                 --enable-chromaprint                        \
                 --enable-gpl                                \
                 --enable-libbs2b                            \
                 --enable-libcaca                            \
                 --enable-libcdio                            \
                 --enable-libgme                             \
                 --enable-libmodplug                         \
                 --enable-libshine                           \
                 --enable-libsmbclient                       \
                 --enable-libsnappy                          \
                 --enable-libsoxr                            \
                 --enable-libspeex                           \
                 --enable-libssh                             \
                 --enable-libtwolame                         \
                 --enable-libv4l2                            \
                 --enable-libvo-amrwbenc                     \
                 --enable-libzvbi                            \
                 --enable-lto                                \
                 --enable-nonfree                            \
                 --enable-opengl                             \
                 --enable-pic                                \
                 --enable-pthreads                           \
                 --enable-small                              \
                 --enable-static                             \
                 --enable-vulkan                             \
                 --enable-version3                           \
                 --extra-cflags="${CFLAGS}"                  \
                 --extra-cxxflags="${CXXFLAGS}"              \
                 --extra-ldflags="${LDFLAGS}"                \
                 --extra-ldexeflags="${LDEXEFLAGS}"          \
                 --extra-libs="${EXTRALIBS}"                 \
                 --pkg-config-flags='--static'               \
                 --pkg-config=/usr/local/bin/pkg-config      \
                 --pkgconfigdir="$workspace"/lib/pkgconfig \
                 --strip="$(type -P strip)"
    execute make "-j${cpu_threads}"
    execute sudo make install
fi

# Make sure all of the files were compiled correctly
ffmpeg_install_test

# Execute the ldconfig command to ensure that all library changes are detected by ffmpeg
sudo ldconfig 2>/dev/null

# Display ffmpeg's version
if [ -f /usr/local/bin/ffmpeg ]; then
    ff_ver_fn
else
    fail_fn "Failed to find the binary file: $workspace/bin/ffmpeg. Line: ${LINENO}"
fi

# Prompt the user to clean up the build files
cleanup_fn

# Show exit message
exit_fn
