#!/bin/bash
# shellcheck disable=SC2046,SC2066,SC2068,SC2086,SC2162,SC2317

#################################################################################
##
##  GitHub: https://github.com/slyfox1186/ffmpeg-build-script/
##
##  Supported Distros: Ubuntu 22.04.2
##
##  Supported architecture: x86_64
##
##  Purpose: Build FFmpeg from source code with addon development
##           libraries also compiled from source code to ensure the
##           latest in extra functionality
##
##  Cuda:    If the cuda libraries are not installed (for geforce cards only)
##           the user will be prompted by the script to install them so that
##           hardware acceleration is enabled when compiling FFmpeg
##
##  Updated: 05.13.23
##
##  Version: 5.6
##
#################################################################################

##
## define variables
##

# FFmpeg version: Whatever the latest Git pull from: https://git.ffmpeg.org/gitweb/ffmpeg.git
progname="${0:2}"
script_ver='5.6'
cuda_ver='12.1.1'
parent_dir="$PWD"
packages="$PWD"/packages
workspace="$PWD"/workspace
install_dir='/usr/bin'
CFLAGS="-I$workspace/include"
CXX_NAT

LDFLAGS="-L$workspace"/lib
LDEXEFLAGS=''
EXTRALIBS='-ldl -lpthread -lm -lz'
ffmpeg_libraries=()
nonfree_and_gpl='false'
latest='false'

# SET COMPILER COMMANDS
export CC='gcc-13'
export CXX='g++-12'

# create the output directories
mkdir -p "$packages" "$workspace"

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
    printf "\n%s\n\n%s\n\n" \
    'Make sure to star this repository to show your support!' \
    'https://github.com/slyfox1186/script-repo/'
    exit 0
}

fail_fn()
{
    echo
    echo 'Please create a support ticket'
    echo
    echo 'https://github.com/slyfox1186/script-repo/issues'
    echo
    exit 1
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

    if [[ "${cleanup_ans}" -eq '1' ]]; then
        sudo rm -fr  "$packages" "$workspace" "$0"
        echo 'Cleanup finished.'
        exit_fn
    elif [[ "${cleanup_ans}" -eq '2' ]]; then
        exit_fn
    else
        echo 'Bad user input'
        echo
        read -p 'Press enter to try again.'
        echo
        cleanup_fn
    fi
}

ff_ver_fn()
{
    echo
    echo '============================'
    echo '       FFmpeg Version       '
    echo '============================'
    echo
    ffmpeg -version
    echo
    cleanup_fn
}

make_dir()
{
    remove_dir "$*"
    if ! mkdir "$*"; then
        printf "\n Failed to create dir %s" "$*"
        echo
        exit 1
    fi
}

remove_file()
{
    if [ -f "$*" ]; then
        sudo rm -f "$*"
    fi
}

remove_dir()
{
    if [ -d "$*" ]; then
        sudo rm -fr "$*"
    fi
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

    if [ -f "$target_file" ]; then
        remove_file "$target_file"
    fi

    if [ -d "$target_dir" ]; then
        remove_dir "$target_dir"
    fi

    if [ -f "$target_file" ]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"$dl_url\" and saving as \"$dl_file\""
        if ! curl -Lso "$target_file" "$dl_url"; then
                        printf "\n%s\n\n%s\n\n" \
                "The script failed to download \"$dl_file\" and will try again in 5 seconds." \
                'Sleeping for 5 seconds before trying again.'
            sleep 5
            if ! curl -Lso "$target_file" "$dl_url"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit the build."
            fi
        fi
        echo 'Download Completed'
    fi

    if [ -d "$output_dir" ]; then
        remove_dir "$output_dir"
    fi

    make_dir "$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            fail_fn "Failed to extract: $dl_file"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            fail_fn "Failed to extract: $dl_file"
        fi
    fi

    echo -e "File extracted: $dl_file\\n"

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir"
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

download_patch()
{
    dl_path="$packages"
    dl_url="$2"
    dl_file="${2:-"${1##*/}"}"
    dl_patch="$3.patch"

    if [ -n "$dl_patch" ]; then
        dl_file="$packages/$dl_patch"
        dl_filename="${dl_file##*/}"
        output_dir="${dl_file%/*}"
        output_basefile="${dl_filename%.*}"
    fi

    target_file="$output_dir/$output_basefile/$dl_filename"
    target_dir="$output_dir/$output_basefile"

    if [ -f "$target_file" ]; then
        remove_file "$target_file"
    fi

    if [ -d "$target_dir" ]; then
        remove_dir "$target_dir"
    fi

    mkdir -p "$target_dir"

         echo "Downloading \"$dl_url\" and saving as \"$target_file\""
        if ! curl -Lso "$target_file" "$dl_url"; then
                        printf "\n%s\n\n%s\n\n" \
                "The script failed to download \"${target_file##*/}\" and will try again in 5 seconds." \
                'Sleeping for 5 seconds before trying again.'
            sleep 5
            if ! curl -Lso "$target_file" "$dl_url"; then
                fail_fn "The script failed to download \"${target_file##*/}\" twice and will now exit the build."
            fi
        fi
        echo 'Download Completed'

    echo -e "File extracted: $dl_file\\n"

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir"
}

# create txt files to check versions
ver_file_tmp="$workspace/latest-versions-tmp.txt"
ver_file="$workspace/latest-versions.txt"
sed -i -e '/null-/d' -e '/null /d' -e '/-null/d' -e '/-$/d' "$ver_file_tmp" "$ver_file"
if [ ! -f "$ver_file_tmp" ] || [ ! -f "$ver_file" ]; then
    touch "$ver_file_tmp" "$ver_file" 2>/dev/null
fi

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

git_2_fn()
{
    videolan_repo="$1"
    videolan_url="$2"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://code.videolan.org/api/v4/projects/$videolan_repo/repository/$videolan_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].commit.id')"
        g_sver="$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')"
        g_ver1="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver1="${g_ver1#v}"
    fi
}

git_3_fn()
{
    gitlab_repo="$1"
    gitlab_url="$2"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://gitlab.com/api/v4/projects/$gitlab_repo/repository/$gitlab_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#v}"

        g_ver1="$(echo "$curl_cmd" | jq -r '.[0].commit.id')"
        g_ver1="${g_ver1#v}"
        g_sver1="$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')"
    fi
}

git_4_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://gitlab.freedesktop.org/api/v4/projects/$gitlab_repo/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
    fi
}

git_5_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL 'https://bitbucket.org/!api/2.0/repositories/multicoreware/x265_git/effective-branching-model')"; then
        g_ver="$(echo "$curl_cmd" | jq '.development.branch.target' | grep -Eo '[0-9a-z][0-9a-z]+' | sort | head -n 1)"
        g_sver="${g_ver::7}"
    fi
}

git_6_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://gitlab.gnome.org/api/v4/projects/$gitlab_repo/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#v}"
    fi
}

git_7_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://git.archive.org/api/v4/projects/$gitlab_repo/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#v}"
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

    if [ "$v_flag" = 'B' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn' gv_url='branches'
    elif [ "$v_flag" = 'B' ] && [  "$v_tag" = '3' ]; then
        url_tag='git_3_fn' gv_url='branches'
    fi

    if [ "$v_flag" = 'X' ] && [  "$v_tag" = '5' ]; then
        url_tag='git_5_fn'
    fi

    if [ "$v_flag" = 'T' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn' gv_url='tags'
    elif [ "$v_flag" = 'T' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn' gv_url='tags'
    elif [ "$v_flag" = 'T' ] && [  "$v_tag" = '3' ]; then
        url_tag='git_3_fn' gv_url='tags'
    fi

    if [ "$v_flag" = 'R' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '3' ]; then
        url_tag='git_3_fn' gv_url='releases'
    fi

    if [ "$v_flag" = 'L' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases/latest'
    fi

    case "$v_tag" in
        2)          url_tag='git_2_fn';;
        3)          url_tag='git_3_fn';;
        4)          url_tag='git_4_fn';;
        5)          url_tag='git_5_fn';;
        6)          url_tag='git_6_fn';;
        7)          url_tag='git_7_fn';;
    esac

    "$url_tag" "$v_url" "$gv_url" 2>/dev/null
}

check_version()
{
    github_repo="$1"
    latest_txt_tmp="$ver_file_tmp"
    latest_txt="$ver_file"

    awk '!NF || !seen[$0]++' "$latest_txt_tmp" > "$latest_txt"
    check_ver="$(grep -Eo "${github_repo##*/}-[0-9\.]+" "$latest_txt" | sort | head -n1)"

        if [ -n "$check_ver" ]; then
            g_nocheck='0'
        else
            g_nocheck='1'
        fi
}

pre_check_ver()
{
    github_repo="$1"
    git_ver="$2"
    git_url_type="$3"

    check_version "$github_repo"
    if [ "$g_nocheck" -eq '1' ]; then
        git_ver_fn "$github_repo" "$git_ver" "$git_url_type"
        g_ver="${g_ver##*-}"
        g_ver3="${g_ver3##*-}"
    else
        g_ver="${check_ver##*-}"
    fi
}

execute()
{
    echo "$ $*"
# 2>&1
    if ! output=$("$@"); then
        fail_fn "Failed to Execute $*"
    fi
}

build()
{
    echo
    echo "building $1 - version $2"
    echo '===================================='

    if [ -f "$packages/$1.done" ]; then
    if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
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

build_done() { echo "$2" > "$packages/$1.done"; }

installed() { return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

cuda_fail_fn()
{
    echo '======================================================'
    echo '                    Script error:'
    echo '======================================================'
    echo
    echo 'Unable to locate the directory: cuda'
    echo
    read -p 'Press enter to exit.'
    clear
    fail_fn
}

gpu_arch_fn()
{
    is_wsl="$(uname -a | grep -Eo 'WSL2')"

    if [ -n "$is_wsl" ]; then
        sudo apt -y install nvidia-utils-525 &>/dev/null
    fi

    gpu_name="$(nvidia-smi --query-gpu=gpu_name --format=csv | sort -r | head -n 1)"

    if [ "$gpu_name" = 'name' ]; then
        gpu_name="$(nvidia-smi --query-gpu=gpu_name --format=csv | sort | head -n 1)"
    fi

    case "$gpu_name" in
        'NVIDIA GeForce GT 1010')         gpu_type='1';;
        'NVIDIA GeForce GTX 1030')        gpu_type='1';;
        'NVIDIA GeForce GTX 1050')        gpu_type='1';;
        'NVIDIA GeForce GTX 1060')        gpu_type='1';;
        'NVIDIA GeForce GTX 1070')        gpu_type='1';;
        'NVIDIA GeForce GTX 1080')        gpu_type='1';;
        'NVIDIA TITAN Xp')                gpu_type='1';;
        'NVIDIA Tesla P40')               gpu_type='1';;
        'NVIDIA Tesla P4')                gpu_type='1';;
        'NVIDIA GeForce GTX 1180')        gpu_type='2';;
        'NVIDIA GeForce GTX Titan V')     gpu_type='2';;
        'NVIDIA Quadro GV100')            gpu_type='2';;
        'NVIDIA Tesla V100')              gpu_type='2';;
        'NVIDIA GeForce GTX 1660 Ti')     gpu_type='3';;
        'NVIDIA GeForce RTX 2060')        gpu_type='3';;
        'NVIDIA GeForce RTX 2070')        gpu_type='3';;
        'NVIDIA GeForce RTX 2080')        gpu_type='3';;
        'NVIDIA Quadro RTX 4000')         gpu_type='3';;
        'NVIDIA Quadro RTX 5000')         gpu_type='3';;
        'NVIDIA Quadro RTX 6000')         gpu_type='3';;
        'NVIDIA Quadro RTX 8000')         gpu_type='3';;
        'NVIDIA T1000')                   gpu_type='3';;
        'NVIDIA T2000')                   gpu_type='3';;
        'NVIDIA Tesla T4')                gpu_type='3';;
        'NVIDIA GeForce RTX 3050')        gpu_type='4';;
        'NVIDIA GeForce RTX 3060')        gpu_type='4';;
        'NVIDIA GeForce RTX 3070')        gpu_type='4';;
        'NVIDIA GeForce RTX 3080')        gpu_type='4';;
        'NVIDIA GeForce RTX 3080 Ti')     gpu_type='4';;
        'NVIDIA GeForce RTX 3090')        gpu_type='4';;
        'NVIDIA RTX A2000')               gpu_type='4';;
        'NVIDIA RTX A3000')               gpu_type='4';;
        'NVIDIA RTX A4000')               gpu_type='4';;
        'NVIDIA RTX A5000')               gpu_type='4';;
        'NVIDIA RTX A6000')               gpu_type='4';;
        'NVIDIA GeForce RTX 4080')        gpu_type='5';;
        'NVIDIA GeForce RTX 4090')        gpu_type='5';;
        'NVIDIA H100')                    gpu_type='6';;
    esac

    if [ -n "$gpu_type" ]; then
        case "$gpu_type" in
            1)        gpu_arch='compute_61,code=sm_61';;
            2)        gpu_arch='compute_70,code=sm_70';;
            3)        gpu_arch='compute_75,code=sm_75';;
            4)        gpu_arch='compute_86,code=sm_86';;
            5)        gpu_arch='compute_89,code=sm_89';;
            6)        gpu_arch='compute_90,code=sm_90';;
        esac
    fi
}

# PRINT THE OPTIONS AVAILABLE WHEN MANUALLY RUNNING THE SCRIPT
usage()
{
    echo "Usage: $progname [OPTIONS]"
    echo
    echo 'Options:'
    echo '    -h, --help                                       Display usage information'
    echo '            --version                                Display version information'
    echo '    -b, --build                                      Starts the build process'
    echo '            --enable-gpl-and-non-free                Enable GPL and non-free codecs - https://ffmpeg.org/legal.html'
    echo '    -c, --cleanup                                    Remove all working dirs'
    echo '            --latest                                 Build latest version of dependencies if newer available'
    echo
}

echo "ffmpeg-build-script v$script_ver"
echo '======================================'
echo

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
            ffmpeg_libraries+=('--enable-nonfree')
            ffmpeg_libraries+=('--enable-gpl')
            nonfree_and_gpl='true'
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

echo "The script will utilize $cpu_threads CPU cores for parallel processing to accelerate the build speed."
echo

if "$nonfree_and_gpl"; then
    echo 'The script has been configured to run with GPL and non-free codecs enabled'
fi

if [ -n "$LDEXEFLAGS" ]; then
    echo 'The script has been configured to run in full static mode.'
fi

# set global variables
JAVA_HOME='/usr/lib/jvm/java-17-openjdk-amd64'
export JAVA_HOME

# libbluray requries that this variable be set
PATH="\
/usr/lib/ccache:\
$workspace/bin:\
$JAVA_HOME/bin:\
$PATH\
"
export PATH

# set the pkg-config path
PKG_CONFIG_PATH="\
$workspace/lib/pkgconfig:\
$workspace/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/open-coarrays/openmpi/pkgconfig:\
/usr/lib/x86_64-linux-gnu/openmpi/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/share/pkgconfig:\
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

if ! command_exists 'make'; then
    fail_pkg_fn 'make'
fi

if ! command_exists 'g++'; then
    fail_pkg_fn 'g++'
fi

if ! command_exists 'curl'; then
    fail_pkg_fn 'curl'
fi

if ! command_exists 'jq'; then
    fail_pkg_fn 'jq'
fi

if ! command_exists 'cargo'; then
    echo 'The '\''cargo'\'' command was not found.'
    echo
    echo 'The rav1e encoder will not be available.'
fi

if ! command_exists 'python3'; then
    echo 'The '\''python3'\'' command was not found.'
    echo
    echo 'The '\''Lv2'\'' filter and '\''dav1d'\'' decoder will not be available.'
fi

cuda_fn()
{
    clear

    local c_dist iscuda cuda_path

    printf "%s\n\n%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n" \
        'Pick your Linux distro from the list below:' \
        'Supported architecture: x86_64' \
        '[1] Debian 10' \
        '[2] Debian 11' \
        '[3] Ubuntu 18.04' \
        '[4] Ubuntu 20.04' \
        '[5] Ubuntu 22.04' \
        '[6] Ubuntu Windows (WSL)' \
        '[7] Skip this'

    read -p 'Your choices are (1 to 7): ' c_dist
    clear

    case "$c_dist" in
        1)
            wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.1/local_installers/cuda-repo-debian10-12-1-local_12.1.1-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-$cuda_ver.deb"
            sudo cp /var/cuda-repo-debian10-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            sudo add-apt-repository contrib
            ;;
        2)
            wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.1/local_installers/cuda-repo-debian11-12-1-local_12.1.1-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-$cuda_ver.deb"
            sudo cp /var/cuda-repo-debian11-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            sudo add-apt-repository contrib
            ;;
        3)
            wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-ubuntu1804.pin'
            sudo mv 'cuda-ubuntu1804.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.1/local_installers/cuda-repo-ubuntu1804-12-1-local_12.1.1-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-$cuda_ver.deb"
            sudo cp /var/cuda-repo-ubuntu1804-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        4)
            wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-ubuntu2004.pin'
            sudo mv 'cuda-ubuntu2004.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.1/local_installers/cuda-repo-ubuntu2004-12-1-local_12.1.1-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-$cuda_ver.deb"
            sudo cp /var/cuda-repo-ubuntu2004-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        5)
            wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin'
            sudo mv 'cuda-ubuntu2204.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.1/local_installers/cuda-repo-ubuntu2204-12-1-local_12.1.1-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-$cuda_ver.deb"
            sudo cp /var/cuda-repo-ubuntu2204-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        6)
            wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin'
            sudo mv 'cuda-wsl-ubuntu.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.1/local_installers/cuda-repo-wsl-ubuntu-12-1-local_12.1.1-1_amd64.deb'
            sudo dpkg -i "cuda-$cuda_ver.deb"
            sudo cp /var/cuda-repo-wsl-ubuntu-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        7)
            exit_fn
            ;;
        *)
            fail_fn 'Bad User Input. Run the script again.'
            ;;
    esac

    # UPDATE THE APT PACKAGES THEN INSTALL THE CUDA-SDK-TOOLKIT
    sudo apt update
    sudo apt -y install cuda

    # CHECK IF THE CUDA FOLDER EXISTS TO ENSURE IT WAS INSTALLED
    iscuda="$(sudo find /usr/local/ -type f -name nvcc)"
    cuda_path="$(sudo find /usr/local/ -type f -name nvcc | grep -Eo '^.*\/bi[n]?')"

    if [ -z "$cuda_path" ]; then
        cuda_fail_fn
    else
        export PATH="$cuda_path:$PATH"
    fi
}

##
## required build packages
##

build_pkgs_fn()
{
    echo
    echo 'Installing required development packages'
    echo '=========================================='

    pkgs=("$1" ant autogen binutils bison build-essential cabal-install ccache checkinstall curl flex freeglut3-dev \
          g++ gawk gcc git gnustep-gui-runtime gperf gtk-doc-tools help2man jq junit libavif-dev libbz2-dev libcairo2-dev \
          libcdio-paranoia-dev libcurl4-gnutls-dev libdmalloc-dev libglib2.0-dev libgvc6 libheif-dev libjemalloc-dev \
          liblz-dev liblzma-dev liblzo2-dev libmathic-dev libmimalloc-dev libmusicbrainz5-dev libncurses5-dev libnuma-dev \
          libopencv-dev libperl-dev libpstoedit-dev libraqm-dev libraw-dev librsvg2-dev librust-jemalloc-sys-dev librust-malloc-buf-dev \
          libssl-dev libtalloc-dev libtbbmalloc2 libyuv-dev libzstd-dev libzzip-dev lshw lvm2 lzma-dev make mercurial \
          meson ninja-build openjdk-17-jdk-headless pandoc python3 python3-pip ragel scons texi2html texinfo xmlto yasm libdevil-dev)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_vers+=" $pkg"
        fi
    done

    if [ -n "$missing_vers" ]; then
        for pkg in "$missing_vers"
        do
            if sudo apt install $pkg; then
                echo 'The required development packages were installed.'
            else
                echo 'The required development packages failed to install'
                echo
                exit 1
            fi
        done
    else
        echo 'The required development packages are already installed.'
    fi
}

##
## ADDITIONAL REQUIRED GEFORCE CUDA DEVELOPMENT PACKAGES
##

cuda_add_fn()
{
    echo
    echo 'Installing required cuda developement packages'
    echo '================================================'

    pkgs=(autoconf automake build-essential libc6 \
          libc6-dev libnuma1 libnuma-dev texinfo unzip wget)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_vers+=" $pkg"
        fi
    done

    if [ -n "$missing_vers" ]; then
        for pkg in "$missing_vers"
        do
            sudo apt -y install $pkg
        done
        echo 'The required cuda developement packages were installed'
    else
        echo 'The required cuda developement packages are already installed'
    fi
}

install_cuda_fn()
{
    local cuda_ans cuda_choice

    iscuda="$(sudo find /usr/local/ -type f -name nvcc)"
    cuda_path="$(sudo find /usr/local/ -type f -name nvcc | grep -Eo '^.*\/bi[n]?')"

    if [ -z "$iscuda" ]; then
        echo
        echo "The latest cuda-sdk-toolkit version is: v$cuda_ver"
        echo '====================================================='
        echo
        echo 'What do you want to do next?'
        echo
        echo '[1] Install the toolkit and add it to PATH'
        echo '[2] Only add it to PATH'
        echo '[3] Continue the build'
        echo
        read -p 'Your choices are (1 to 3): ' cuda_ans
        echo
        if [[ "$cuda_ans" -eq '1' ]]; then
            cuda_fn
            cuda_add_fn
        elif [[ "$cuda_ans" -eq '2' ]]; then
            if [ -d "$cuda_path" ]; then
                PATH="$PATH:$cuda_path"
                export PATH
            else
                echo 'The script was unable to add cuda to your PATH because the required folder was not found: /usr/local/cuda*/bin'
                echo
                read -p 'Press enter to exit'
                echo
                exit 1
            fi
        elif [[ "$cuda_ans" -eq '3' ]]; then
            echo
        else
            echo
            echo 'Error: Bad user input!'
            echo '======================='
            fail_fn
        fi
    else
        echo
        echo "The latest cuda-sdk-toolkit version is: v$cuda_ver"
        echo '====================================================='
        echo
        echo 'Do you want to update/reinstall it?'
        echo
        echo '[1] Yes'
        echo '[2] No'
        echo
        read -p 'Your choices are (1 or 2): ' cuda_choice
        echo
        if [[ "$cuda_choice" -eq '1' ]]; then
            cuda_fn
            cuda_add_fn
        elif [[ "$cuda_choice" -eq '2' ]]; then
            PATH="$PATH:$cuda_path"
            export PATH
            echo 'Continuing the build...'
        else
            echo
            echo 'Bad user input.'
            echo
            read -p 'Press enter to try again.'
            clear
            install_cuda_fn
        fi
    fi
}

ffmpeg_install_choice()
{
    printf "%s\n\n%s\n%s\n\n" \
        'Would you like to install the FFmpeg binaries system-wide? [/usr/bin]' \
        '[1] Yes ' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' install_choice

    case "$install_choice" in
            1)
                sudo cp -f "$workspace/bin/ffmpeg" "$install_dir/ffmpeg"
                sudo cp -f "$workspace/bin/ffprobe" "$install_dir/ffprobe"
                sudo cp -f "$workspace/bin/ffplay" "$install_dir/ffplay"
                ;;
            2)
                printf "\n%s\n\n%s\n" \
                    'The FFmpeg binaries are located:' \
                    "$workspace/bin"
                ;;
            *)
                echo 'Bad user input. Press enter to try again.'
                clear
                ffmpeg_install_choice
                ;;
    esac
}

ffmpeg_install_check()
{
    ff_binaries=(ffmpeg ffprobe ffplay)

    for i in ${ff_binaries[@]}
    do
        if [ ! -f "/usr/bin/$i" ]; then
            echo "Failed to copy: /usr/bin/$i"
        fi
    done
}

##
## install cuda
##

echo
install_cuda_fn

##
## build tools
##

# install required apt packages
build_pkgs_fn

##
## INSTALL DEBIAN PACKAGES
##

if ! which pandoc &>/dev/null; then
    pre_check_ver 'jgm/pandoc' '1' 'R'
    echo "\$ curl -Lso $packages/$g_deb_ver.deb $g_deb_url"
    curl -Lso "$packages/$g_deb_ver".deb "$g_deb_url" 2>&1
    echo "\$ sudo dpkg -i $packages/$g_deb_ver.deb"
    sudo dpkg -i "$packages/$g_deb_ver".deb 2>&1
fi

##
## BUILD FROM SOURCE CODE
##

export CXXFLAGS='-O3 -march=native -mtune=native'

if build 'giflib' '5.2.1'; then
    download 'https://cfhcable.dl.sourceforge.net/project/giflib/giflib-5.2.1.tar.gz' 'giflib-5.2.1.tar.gz'
    # PARELLEL BUILDING NOT AVAILABLE FOR THIS LIBRARY
    execute make
    execute make PREFIX="$workspace" install
    build_done 'giflib' '5.2.1'
fi

pre_check_ver 'pkgconf/pkgconf' '1' 'T'
if build 'pkg-config' "$g_ver"; then
    download "$g_url" "pkgconf-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --silent --prefix="$workspace" --with-pc-path="$workspace"/lib/pkgconfig --with-internal-glib --enable-static --disable-shared \
    	CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'pkg-config' "$g_ver"
fi

pre_check_ver 'yasm/yasm' '1' 'T'
if build 'yasm' "$g_ver"; then
    download "https://codeload.github.com/yasm/yasm/tar.gz/refs/tags/v$g_ver" "yasm-$g_ver.tar.gz"
    make_dir 'build'
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -G 'Ninja' -Wno-dev \
        CXXFLAGS='-O3 -march=native -mtune=native'
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'yasm' "$g_ver"
fi

if build 'nasm' '2.16.02rc1'; then
    download "https://www.nasm.us/pub/nasm/releasebuilds/2.16.02rc1/nasm-2.16.02rc1.tar.xz" "nasm-2.16.02rc1.tar.xz"
    execute ./configure --prefix="$workspace" --with-ccache CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'nasm' '2.16.02rc1'
fi

pre_check_ver 'madler/zlib' '1' 'T'
if build 'zlib' "$g_ver"; then
    download "https://github.com/madler/zlib/releases/download/v$g_ver/zlib-$g_ver.tar.gz" "zlib-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --static
    execute make "-j$cpu_threads"
    execute make install
    build_done 'zlib' "$g_ver"
fi

if build 'm4' '1.4.19'; then
    download 'https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz' 'm4-1.4.19.tar.xz'
    execute ./configure --prefix="$workspace" --enable-c++ --with-dmalloc CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'm4' '1.4.19'
fi

if build 'autoconf' 'git'; then
    download_git 'https://git.savannah.gnu.org/git/autoconf.git' 'autoconf-git'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'autoconf' 'git'
fi

if build 'automake' 'git'; then
    download_git 'https://git.savannah.gnu.org/git/automake.git' 'automake-git'
    execute ./bootstrap
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'automake' 'git'
fi

if build 'libtool' '2.4.7'; then
    download 'https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz' 'libtool-2.4.7.tar.xz'
    execute ./configure --prefix="$workspace" --enable-static --disable-shared CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libtool' '2.4.7'
fi

if $nonfree_and_gpl; then
    pre_check_ver 'openssl/openssl' '1' 'T'
    if build 'openssl' 'git'; then
        download_git 'https://github.com/openssl/openssl.git' 'openssl-git'
        execute ./config --prefix="$workspace" --openssldir="$workspace" --with-zlib-include="$workspace"/include/ --with-zlib-lib="$workspace"/lib no-shared zlib \
            CXXFLAGS='-O3 -march=native -mtune=native'
        execute make "-j$cpu_threads"
        execute make install_sw
        build_done 'openssl' 'git'
    fi
    ffmpeg_libraries+=('--enable-openssl')
else
    if build 'gmp' '6.2.1'; then
        download 'https://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make "-j$cpu_threads"
        execute make install
        build_done 'gmp' '6.2.1'
    fi

    if build 'nettle' '3.8.1'; then
        download 'https://ftp.gnu.org/gnu/nettle/nettle-3.8.1.tar.gz'
        execute ./configure --prefix="$workspace" --libdir="$workspace"/lib --disable-shared --enable-static \
        --disable-openssl --disable-documentation CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make "-j$cpu_threads"
        execute make install
        build_done 'nettle' '3.8.1'
    fi

    if build 'gnutls' '3.8.0'; then
        download 'https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.0.tar.xz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-doc --disable-tools \
            --disable-cxx --disable-tests --disable-gtk-doc-html --disable-libdane --disable-nls --enable-local-libopts \
            --disable-guile --with-included-libtasn1 --with-included-unistring --without-p11-kit CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make "-j$cpu_threads"
        execute make install
        build_done 'gnutls' '3.8.0'
    fi
    ffmpeg_libraries+=('--enable-gmp' '--enable-gnutls')
fi

pre_check_ver 'kitware/cmake' '1' 'T'
if build 'cmake' "$g_ver" "$packages/$1.done"; then
    download "$g_url" "cmake-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --parallel="$cpu_threads" --enable-ccache -- -DCMAKE_USE_OPENSSL='OFF'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'cmake' "$g_ver"
fi

##
## video libraries
##

if command_exists 'python3'; then
    # dav1d needs meson and ninja along with nasm to be built
    if command_exists 'pip3'; then
        # meson and ninja can be installed via pip3
        pip_tools_pkg="$(pip3 show setuptools)"
        if [ -z "$pip_tools_pkg" ]; then
            execute pip3 install pip setuptools --quiet --upgrade --no-cache-dir --disable-pip-version-check
        fi
    fi
    if command_exists 'meson'; then
        git_ver_fn '198' '2' 'T'
        if build 'dav1d' "$g_sver"; then
            download "https://code.videolan.org/videolan/dav1d/-/archive/$g_ver/$g_ver.tar.bz2" "dav1d-$g_sver.tar.bz2"
            make_dir 'build'
            execute meson setup 'build' --prefix="$workspace" --libdir="$workspace"/lib --pkg-config-path="$workspace"/lib/pkgconfig \
                --buildtype='release' --default-library='static' --strip
            execute ninja "-j$cpu_threads" -C 'build'
            execute ninja "-j$cpu_threads" -C 'build' install
            build_done 'dav1d' "$g_sver"
        fi
        ffmpeg_libraries+=('--enable-libdav1d')
    fi
fi

pre_check_ver 'google/googletest' '1' 'T'
if build 'googletest' "$g_ver"; then
    download "$g_url" "googletest-$g_ver.tar.gz"
    make_dir 'build'
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_GMOCK='OFF' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'googletest' "$g_ver"
fi

if build 'abseil' 'git'; then
    download_git 'https://github.com/abseil/abseil-cpp.git' 'abseil-git'
    make_dir 'build'
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_EXPORT_COMPILE_COMMANDS='ON' -DABSL_PROPAGATE_CXX_STD='ON' -G 'Ninja' -Wno-dev \
         CXXFLAGS='-O3 -march=native -mtune=native'
    execute cmake --build build --target all --parallel='32'
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'abseil' 'git'
fi

if build 'libgav1' 'git'; then
    # version 1.3.0, 1.2.4, and 1.2.3 fail to build successfully
    download_git 'https://chromium.googlesource.com/codecs/libgav1' 'libgav1-git'
    make_dir 'libgav1_build'
    execute git -C "$packages/libgav1-git" clone -b '20220623.0' --depth '1' 'https://github.com/abseil/abseil-cpp.git' 'third_party/abseil-cpp'
    execute cmake -B 'libgav1_build' -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_EXPORT_COMPILE_COMMANDS='ON' -DABSL_ENABLE_INSTALL='ON' \
        -DABSL_PROPAGATE_CXX_STD='ON' -DCMAKE_INSTALL_SBINDIR="sbin" -DBUILD_SHARED_LIBS='OFF' -G 'Ninja' -Wno-dev
    execute cmake -B 'third_party/abseil-cpp' -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_EXPORT_COMPILE_COMMANDS='ON' -DABSL_ENABLE_INSTALL='ON' \
        -DABSL_PROPAGATE_CXX_STD='ON' -DCMAKE_INSTALL_SBINDIR="sbin" -DBUILD_SHARED_LIBS='OFF' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'libgav1_build'
    execute ninja "-j$cpu_threads" -C 'third_party/abseil-cpp'
    execute ninja "-j$cpu_threads" -C 'libgav1_build' install
    execute ninja "-j$cpu_threads" -C 'third_party/abseil-cpp' install
    build_done 'libgav1' 'git'
fi

git_ver_fn '24327400' '3' 'T'
if build 'svtav1' "$g_ver"; then
    download "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$g_ver/SVT-AV1-v$g_ver.tar.bz2" "SVT-AV1-$g_sver.tar.bz2"
    execute cmake -S . -B 'Build/linux' -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -DCMAKE_BUILD_TYPE='Release' -G 'Ninja' \
        CXXFLAGS='-O3 -march=native -mtune=native'
    execute ninja -C 'Build/linux'
    execute ninja -C 'Build/linux' install
    execute cp 'Build/linux/SvtAv1Enc.pc' "$workspace"/lib/pkgconfig
    execute cp 'Build/linux/SvtAv1Dec.pc' "$workspace"/lib/pkgconfig
    build_done 'svtav1' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libsvtav1')

if command_exists 'cargo'; then
    pre_check_ver 'xiph/rav1e' '1' 'T'
    if build 'rav1e' "$g_ver"; then
        download "$g_url" "rav1e-$g_ver.tar.gz"
        exeucte RUSTFLAGS='-L $Workspace/lib -L /lib/x86_64-linux-gnu' cargo install --all-features --version '0.9.14+cargo-0.66' cargo-c
        execute cargo cinstall --prefix="$workspace" --library-type='staticlib' --crt-static --release
        build_done 'rav1e' "$g_ver"
    fi
    avif_tag='-DAVIF_CODEC_RAV1E=ON'
    ffmpeg_libraries+=('--enable-librav1e')
else
    avif_tag='-DAVIF_CODEC_RAV1E=OFF'
fi

if $nonfree_and_gpl; then
    git_ver_fn '536' '2' 'B'
    if build 'x264' "$g_sver"; then
        download "https://code.videolan.org/videolan/x264/-/archive/$g_ver/x264-$g_ver.tar.bz2" "x264-$g_sver.tar.bz2"
        execute ./configure --prefix="$workspace" --enable-static --enable-pic CXXFLAGS="$CXX_ZEN -fPIC"
        execute make "-j$cpu_threads"
        execute make install
        execute make install-lib-static
        build_done 'x264' "$g_sver"
    fi
    ffmpeg_libraries+=('--enable-libx264')
fi

if $nonfree_and_gpl; then
    git_ver_fn 'x265_git' '5' 'X'
    if build 'x265' "$g_sver"; then
        download_git 'https://bitbucket.org/multicoreware/x265_git.git' "x265-$g_sver"
        cd 'build/linux' || exit 1
        rm -fr {8,10,12}bit 2>/dev/null
        mkdir -p {8,10,12}bit
        cd 12bit || exit 1
        echo '$ making 12bit binaries'
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -DCMAKE_REQUIRED_LIBRARIES='numa' \
            -DHIGH_BIT_DEPTH='ON' -DENABLE_HDR10_PLUS='ON' -DEXPORT_C_API='OFF' -DENABLE_CLI='OFF' -DMAIN12='ON' -G 'Ninja' -Wno-dev
        execute ninja "-j$cpu_threads"
        echo '$ making 10bit binaries'
        cd ../10bit || exit 1
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -DCMAKE_REQUIRED_LIBRARIES='numa' \
            -DHIGH_BIT_DEPTH='ON' -DENABLE_HDR10_PLUS='ON' -DEXPORT_C_API='OFF' -DENABLE_CLI='OFF' -G 'Ninja' -Wno-dev
        execute ninja "-j$cpu_threads"
        echo '$ making 8bit binaries'
        cd ../8bit || exit 1
        ln -sf ../10bit/libx265.a libx265_main10.a
        ln -sf ../12bit/libx265.a libx265_main12.a
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -DCMAKE_REQUIRED_LIBRARIES='numa' \
            -DEXTRA_LIB='x265_main10.a;x265_main12.a;-ldl' -DEXTRA_LINK_FLAGS='-L.' -DLINKED_10BIT='ON' -DLINKED_12BIT='ON' -G 'Ninja' -Wno-dev
        execute ninja "-j$cpu_threads"
        mv libx265.a  libx265_main.a

        execute ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF

        execute ninja "-j$cpu_threads" install

        if [ -n "$LDEXEFLAGS" ]; then
            sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$workspace"/lib/pkgconfig/x265.pc
        fi

        build_done 'x265' "$g_sver"
    fi
    ffmpeg_libraries+=('--enable-libx265')
fi

pre_check_ver 'openvisualcloud/svt-hevc' '1' 'T'
if build 'SVT-HEVC' "$g_ver"; then
    download "$g_url" "SVT-HEVC-$g_ver.tar.gz"
    make_dir 'build'
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -DCMAKE_BUILD_TYPE='Release' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'SVT-HEVC' "$g_ver"
fi

pre_check_ver 'webmproject/libvpx' '1' 'T'
if build 'libvpx' "$g_ver"; then
    download "https://codeload.github.com/webmproject/libvpx/tar.gz/refs/tags/v$g_ver" "libvpx-$g_ver.tar.gz"
    execute sudo ./configure --prefix="$workspace" --target='x86_64-linux-gcc' --disable-unit-tests --enable-static --disable-shared --disable-examples \
        --target='x86_64-linux-gcc' --enable-ccache --enable-vp9-highbitdepth --enable-better-hw-compatibility \
        --enable-vp8 --enable-vp9 --enable-postproc --enable-vp9-postproc --enable-realtime-only --enable-onthefly-bitpacking \
        --enable-coefficient-range-checking --enable-runtime-cpu-detect --enable-small --enable-multi-res-encoding --enable-vp9-temporal-denoising \
        --enable-libyuv --extra-cxxflags='-g -O3 -march=native' --log='yes' --enable-pic --enable-install-srcs --as='yasm' \
        --enable-codec-srcs --disable-webm-io
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libvpx' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libvpx')

if $nonfree_and_gpl; then
    if build 'xvidcore' '1.3.7'; then
        download 'https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.bz2' 'xvidcore-1.3.7.tar.bz2'
        cd 'build/generic' || exit 1
        execute ./configure --prefix="$workspace" --disable-shared --enable-static CXXFLAGS='-O3 -march=native -mtune=native'
        execute make "-j$cpu_threads"
        execute make install

        if [ -f "$workspace"/lib/libxvidcore.4.dylib ]; then
            execute rm "$workspace"/lib/libxvidcore.4.dylib
        fi

        if [ -f "$workspace"/lib/libxvidcore.so ]; then
            execute rm "$workspace"/lib/libxvidcore.so*
        fi

        cd '=build' || exit 1
        execute ln -s 'libxvidcore.so.4.3' "$workspace"/lib/libxvidcore.so.4@
        execute ln -s 'libxvidcore.so.4@' "$workspace"/lib/libxvidcore.so

        build_done 'xvidcore' '1.3.7'
    fi
    ffmpeg_libraries+=('--enable-libxvid')
fi

if $nonfree_and_gpl; then
    pre_check_ver 'georgmartius/vid.stab' '1' 'T'
    if build 'vid_stab' "$g_ver"; then
        download "$g_url" "vid.stab-$g_ver.tar.gz"
        make_dir 'build'
        execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -DCMAKE_BUILD_TYPE='Release' \
             -DUSE_OMP='ON' -G 'Ninja' -Wno-dev
        execute ninja "-j$cpu_threads" -C 'build'
        execute ninja "-j$cpu_threads" -C 'build' install
        build_done 'vid_stab' "$g_ver"
    fi
    ffmpeg_libraries+=('--enable-libvidstab')
fi

if build 'av1' 'd192cdf'; then
    download 'https://aomedia.googlesource.com/aom/+archive/d192cdfc229d3d4edf6a0acd2e5b71fb4880d28e.tar.gz' 'av1-d192cdf.tar.gz' 'av1'
    make_dir "$packages"/aom_build
    cd "$packages"/aom_build || exit 1
    make_dir 'build'
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR="$workspace"/lib \
        -DCMAKE_BUILD_TYPE='Release' -DCONFIG_ACCOUNTING='0' -DCONFIG_ANALYZER='0' -DCONFIG_AV1_DECODER='1' \
        -DCONFIG_AV1_ENCODER='1' -DCONFIG_AV1_HIGHBITDEPTH='1' -DCONFIG_AV1_TEMPORAL_DENOISING='0' \
        -DCONFIG_BIG_ENDIAN='0' -DCONFIG_COLLECT_RD_STATS='0' -DCONFIG_DENOISE='1' -DCONFIG_DISABLE_FULL_PIXEL_SPLIT_8X8='1' \
        -DCONFIG_ENTROPY_STATS='0' -DBUILD_SHARED_LIBS='OFF' -DENABLE_CCACHE='1' -DENABLE_EXAMPLES='0' \
        -DENABLE_TESTS='0' "$packages"/av1 -G 'Ninja' "$packages"/av1
        execute ninja "-j$cpu_threads" -C 'build'
        execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'av1' 'd192cdf'
fi
ffmpeg_libraries+=('--enable-libaom')

pre_check_ver 'sekrit-twc/zimg' '1' 'T'
if build 'zimg' "$g_ver"; then
    download "$g_url" "zimg-$g_ver.tar.gz"
    execute "$workspace"/bin/libtoolize -fiq
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --enable-static --disable-shared CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'zimg' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libzimg')

if build "libpng" '1.6.39'; then
    download "https://github.com/glennrp/libpng/archive/refs/tags/v1.6.39.tar.gz" 'libpng-1.6.39.tar.gz'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared --enable-static --enable-unversioned-links \
        --enable-hardware-optimizations LDFLAGS="$LDFLAGS" CPPFLAGS="$CFLAGS" CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install-header-links
    execute make install-library-links
    execute make install
  build_done "libpng" '1.6.39'
fi

pre_check_ver 'AOMediaCodec/libavif' '1' 'T'
if build 'avif' "$g_ver"; then
    download "$g_url" "avif-$g_ver.tar.gz"
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -DAVIF_ENABLE_WERROR='OFF' -DAVIF_CODEC_DAV1D='ON' -DAVIF_CODEC_AOM='ON' \
        -DAVIF_BUILD_APPS='ON' "$avif_tag"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'avif' "$g_ver"
fi

pre_check_ver 'ultravideo/kvazaar' '1' 'T'
if build 'kvazaar' "$g_ver"; then
    download "$g_url" "kvazaar-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared --enable-fast-install='yes' CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'kvazaar' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libkvazaar')

##
## audio libraries
##

if command_exists 'python3'; then
    if command_exists 'meson'; then
        pre_check_ver 'lv2/lv2' '1' 'T'
        if build 'lv2' "$g_ver"; then
            download_git 'https://github.com/lv2/lv2.git' "lv2-$g_ver"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --libdir="$workspace"/lib  --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja "-j$cpu_threads" -C 'build'
            execute ninja "-j$cpu_threads" -C 'build' install
            build_done 'lv2' "$g_ver"
        fi

        git_ver_fn '7131569' '3' 'T'
        if build 'waflib' "$g_ver"; then
            download "https://gitlab.com/ita1024/waf/-/archive/$g_ver/waf-$g_ver.tar.bz2" "autowaf-$g_ver.tar.bz2"
            build_done 'waflib' "$g_ver"
        fi

        git_ver_fn '5048975' '3' 'T'
        if build 'serd' "$g_ver"; then
            download "https://gitlab.com/drobilla/serd/-/archive/v$g_ver/serd-v$g_ver.tar.bz2" "serd-$g_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --libdir="$workspace"/lib  --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja "-j$cpu_threads" -C 'build'
            execute ninja "-j$cpu_threads" -C 'build' install
            build_done 'serd' "$g_ver"
        fi

        pre_check_ver 'pcre2project/pcre2' '1' 'T'
        if build 'pcre2' "$g_ver"; then
            download "$g_url" "pcre2-$g_ver.tar.gz"
            execute ./autogen.sh
            execute ./configure --prefix="$workspace" --disable-shared --enable-static CXXFLAGS='-O3 -march=native -mtune=native'
            execute make "-j$cpu_threads"
            execute make install
            build_done 'pcre2' "$g_ver"
        fi

        git_ver_fn '14889806' '3' 'B'
        if build 'zix' "$g_sver1"; then
            download "https://gitlab.com/drobilla/zix/-/archive/$g_ver1/zix-$g_ver1.tar.bz2" "zix-$g_sver1.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --libdir="$workspace"/lib  --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja "-j$cpu_threads" -C 'build'
            execute ninja "-j$cpu_threads" -C 'build' install
            build_done 'zix' "$g_sver1"
        fi

          git_ver_fn '11853362' '3' 'B'
        if build 'sord' "$g_sver1"; then
            CFLAGS+="$CFLAGS -I$workspace/include/serd-0"
            download "https://gitlab.com/drobilla/sord/-/archive/$g_ver1/sord-$g_ver1.tar.bz2" "sord-$g_sver1.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --libdir="$workspace"/lib  --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja "-j$cpu_threads" -C 'build'
            execute ninja "-j$cpu_threads" -C 'build' install
            build_done 'sord' "$g_sver1"
        fi

        git_ver_fn '11853194' '3' 'T'
        if build 'sratom' "$g_ver"; then
            download "https://gitlab.com/lv2/sratom/-/archive/v$g_ver/sratom-v$g_ver.tar.bz2" "sratom-$g_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --libdir="$workspace"/lib  --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja "-j$cpu_threads" -C 'build'
            execute ninja "-j$cpu_threads" -C 'build' install
            build_done 'sratom' "$g_ver"
        fi

        git_ver_fn '11853176' '3' 'T'
        if build 'lilv' "$g_ver"; then
            download "https://gitlab.com/lv2/lilv/-/archive/v$g_ver/lilv-v$g_ver.tar.bz2" "lilv-$g_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --libdir="$workspace"/lib  --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja "-j$cpu_threads" -C 'build'
            execute ninja "-j$cpu_threads" -C 'build' install
            build_done 'lilv' "$g_ver"
        fi
        CFLAGS+=" -I$workspace/include/lilv-0"
        ffmpeg_libraries+=('--enable-lv2')
    fi
fi

if build 'opencore' '0.1.6'; then
    download 'https://master.dl.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.6.tar.gz?viasf=1' 'opencore-amr-0.1.6.tar.gz'
    execute ./configure --prefix="$workspace" --disable-shared --enable-static --enable-fast-install CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'opencore' '0.1.6'
fi
ffmpeg_libraries+=('--enable-libopencore_amrnb' '--enable-libopencore_amrwb')

if build 'lame' '3.100'; then
    download 'https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download?use_mirror=gigenet' 'lame-3.100.tar.gz'
    execute ./configure --prefix="$workspace" --disable-shared --enable-static CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'lame' '3.100'
fi
ffmpeg_libraries+=('--enable-libmp3lame')

pre_check_ver 'xiph/opus' '1' 'T'
if build 'opus' "$g_ver"; then
    download "$g_url" "opus-$g_ver.tar.gz"
    make_dir 'build'
    execute autoreconf -isf
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -DCMAKE_C_FLAGS_DEBUG='-g' \
        -DCPACK_SOURCE_ZIP='OFF' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'opus' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libopus')

pre_check_ver 'xiph/ogg' '1' 'T'
if build 'libogg' "$g_ver"; then
    download "$g_url" "libogg-$g_ver.tar.gz"
    execute mkdir -p 'm4' 'build'
    execute autoreconf -fi
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace"  -DCMAKE_BUILD_TYPE='Release' -DBUILD_SHARED_LIBS='ON' \
        -DCPACK_BINARY_DEB='OFF' -DBUILD_TESTING='OFF'-DCPACK_SOURCE_ZIP='OFF' -DBUILD_SHARED_LIBS='OFF' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'libogg' "$g_ver"
fi

pre_check_ver 'xiph/vorbis' '1' 'T'
if build 'libvorbis' "$g_ver"; then
    download "$g_url" "libvorbis-$g_ver.tar.gz"
    make_dir 'build'
    execute ./autogen.sh
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'libvorbis' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libvorbis')

pre_check_ver 'xiph/theora' '1' 'T'
if build 'libtheora' '1.0'; then
    download "$g_url" "libtheora-1.0.tar.gz"
    execute ./autogen.sh
    sed 's/-fforce-addr//g' 'configure' >'configure.patched'
    chmod +x 'configure.patched'
    execute mv 'configure.patched' 'configure'
    execute rm 'config.guess'
    execute curl -4Lso 'config.guess' 'https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess'
    chmod +x 'config.guess'
    execute ./configure --prefix="$workspace" --with-ogg-libraries="$workspace"/lib --with-ogg-includes="$workspace"/include \
        --with-vorbis-libraries="$workspace"/lib --with-vorbis-includes="$workspace"/include --enable-static --disable-shared \
        --disable-oggtest --disable-vorbistest --disable-examples --disable-asm --disable-spec CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libtheora' '1.0'
fi
ffmpeg_libraries+=('--enable-libtheora')

./bootstrap

if $nonfree_and_gpl; then
    pre_check_ver 'knik0/faac' '1' 'T'
    if build 'faac' "$g_ver"; then
    download "$g_url" "faac-$g_ver.tar.gz"
        execute ./bootstrap
        execute ./configure --prefix="$workspace" --disable-shared --enable-static CXXFLAGS='-O3 -march=native -mtune=native'
        execute make "-j$cpu_threads"
        execute make install
        build_done 'faac' "$g_ver"
    fi
    ffmpeg_libraries+=('--enable-libfdk-aac')
fi

if $nonfree_and_gpl; then
    pre_check_ver 'mstorsjo/fdk-aac' '1' 'T'
    if build 'fdk_aac' "$g_ver"; then
    download "$g_url" "fdk_aac-$g_ver.tar.gz"
        execute ./autogen.sh
        execute ./configure --prefix="$workspace" --bindir="$workspace"/bin --disable-shared --enable-static CXXFLAGS="$CXX_ZEN -fno-exceptions -fno-rtti"
        execute make "-j$cpu_threads"
        execute make install
        build_done 'fdk_aac' "$g_ver"
    fi
    ffmpeg_libraries+=('--enable-libfdk-aac')
fi

##
## image libraries
##

pre_check_ver 'uclouvain/openjpeg' '1' 'T'
if build 'openjpeg' "$g_ver"; then
    download "$g_url" "openjpeg-$g_ver.tar.gz"
    make_dir 'build'
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace"  -DCMAKE_BUILD_TYPE='Release' -DBUILD_TESTING='OFF' \
        -DCPACK_BINARY_FREEBSD='ON' -DBUILD_THIRDPARTY='ON' -DCPACK_SOURCE_RPM='ON' -DCPACK_SOURCE_ZIP='ON' \
        -DCPACK_BINARY_IFW='ON' -DBUILD_SHARED_LIBS='OFF' -DCPACK_BINARY_DEB='ON' -DCPACK_BINARY_TBZ2='ON' \
        -DCPACK_BINARY_NSIS='ON' -DCPACK_BINARY_RPM='ON' -DCPACK_BINARY_TXZ='ON' -DCMAKE_EXPORT_COMPILE_COMMANDS='ON' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'openjpeg' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libopenjpeg')

git_ver_fn '4720790' '3' 'T'
if build 'libtiff' "$g_ver"; then
    download "https://gitlab.com/libtiff/libtiff/-/archive/v$g_ver/libtiff-v$g_ver.tar.bz2" "libtiff-$g_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libtiff' "$g_ver"
fi

if build 'libwebp' 'git'; then
    download_git 'https://chromium.googlesource.com/webm/libwebp' 'libwebp-git'
    execute autoreconf -fi
    make_dir 'build'
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DBUILD_SHARED_LIBS='OFF' -DCMAKE_BUILD_TYPE='Release' \
        -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG" -DWEBP_BUILD_EXTRAS='OFF' -DWEBP_BUILD_LIBWEBPMUX='OFF' \
        -DCMAKE_INSTALL_INCLUDEDIR="include" -DWEBP_LINK_STATIC='OFF' -DWEBP_BUILD_GIF2WEBP='OFF' -DWEBP_BUILD_IMG2WEBP='OFF' \
        -DCMAKE_EXPORT_COMPILE_COMMANDS='OFF' -DWEBP_BUILD_DWEBP='ON' -DWEBP_BUILD_CWEBP='ON' -DWEBP_BUILD_ANIM_UTILS='OFF' \
        -DWEBP_BUILD_WEBPMUX='OFF' -DWEBP_ENABLE_SWAP_16BIT_CSP='OFF' -DWEBP_BUILD_WEBPINFO='OFF' -DZLIB_INCLUDE_DIR="/usr/include" \
        -DWEBP_BUILD_VWEBP='OFF' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build' all
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'libwebp' 'git'
fi
ffmpeg_libraries+=('--enable-libwebp')

##
## other libraries
##

git_ver_fn '1665' '6' 'T'
if build 'xml2' "$g_ver"; then
    download "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$g_ver/libxml2-v$g_ver.tar.bz2" "xml2-$g_ver.tar.bz2"
    make_dir 'build'
    execute cmake -B 'build' -DBUILD_SHARED_LIBS='OFF' -DCMAKE_EXPORT_COMPILE_COMMANDS='OFF' -DCMAKE_INSTALL_PREFIX="$workspace" \
        -DCMAKE_VERBOSE_MAKEFILE='OFF' -DCPACK_BINARY_DEB='ON' -DCPACK_BINARY_FREEBSD='ON' -DCPACK_BINARY_IFW='ON' -DCPACK_BINARY_NSIS='ON' \
        -DCPACK_BINARY_RPM='ON' -DCPACK_BINARY_TBZ2='ON' -DCPACK_BINARY_TXZ='ON' -DCPACK_SOURCE_RPM='ON' -DCPACK_SOURCE_ZIP='ON' -G 'Ninja' -Wno-dev 
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'xml2' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libxml2')

pre_check_ver 'mm2/Little-CMS' '1' 'T'
if build 'lcms' "$g_ver"; then
    download "$g_url" "lcms-$g_ver.tar.gz"
    make_dir 'build'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'lcms' "$g_ver"
fi
ffmpeg_libraries+=('--enable-lcms2')

pre_check_ver 'dyne/frei0r' '1' 'T'
if build 'frei0r' "$g_ver"; then
    download "$g_url" "frei0r-$g_ver.tar.gz"
    make_dir 'build'
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DWITHOUT_OPENCV='OFF' -DCMAKE_CXX_COMPILER_RANLIB="/usr/bin/gcc-ranlib-12" \
        -DCMAKE_CXX_FLAGS_DEBUG="-g" -DCMAKE_EXPORT_COMPILE_COMMANDS='ON' -DBUILD_SHARED_LIBS='OFF' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'frei0r' "$g_ver"
fi
ffmpeg_libraries+=('--enable-frei0r')

pre_check_ver 'avisynth/avisynthplus' '1' 'T'
if build 'avisynth' "$g_ver"; then
    download "$g_url" "avisynth-$g_ver.tar.gz"
    make_dir 'build'
    execute cmake -S . -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'avisynth' "$g_ver"
fi
ffmpeg_libraries+=('--enable-avisynth')

git_ver_fn '363' '2' 'T'
if build 'udfread' "$g_ver1"; then
    download "https://code.videolan.org/videolan/libudfread/-/archive/$g_ver1/libudfread-$g_ver1.tar.bz2" "udfread-$g_ver1.tar.bz2"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared --enable-static --with-pic --with-gnu-ld CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'udfread' "$g_ver1"
fi

git_ver_fn '206' '2' 'T'
if build 'libbluray' "$g_ver1"; then
    download "https://code.videolan.org/videolan/libbluray/-/archive/$g_ver1/$g_ver1.tar.gz" "libbluray-$g_ver1.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared --enable-static --without-libxml2 CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libbluray' "$g_ver1"
fi
unset JAVA_HOME
ffmpeg_libraries+=('--enable-libbluray')

pre_check_ver 'xiph/flac' '1' 'T'
if build 'flac' "$g_ver"; then
    download "$g_url" "flac-$g_ver.tar.gz"
    make_dir 'build'
    execute cmake -B 'build' -DWITH_STACK_PROTECTOR='ON' -DBUILD_TESTING='OFF' -DBUILD_CXXLIBS='ON' -DWITH_FORTIFY_SOURCE='ON' -DCMAKE_BUILD_TYPE='Release' \
        -DCMAKE_INSTALL_PREFIX="/home/jman/tmp/ffmpeg-build/workspace" -DINSTALL_MANPAGES='ON' -DWITH_ASM='ON' -DINSTALL_PKGCONFIG_MODULES='ON' \
        -DWITH_AVX='ON' -DINSTALL_CMAKE_CONFIG_MODULE='ON' -DWITH_OGG='OFF' -DBUILD_PROGRAMS='ON' -DBUILD_DOCS='OFF' -DENABLE_64_BIT_WORDS='ON' \
        -DBUILD_EXAMPLES='OFF' -G 'Ninja' -Wno-dev
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'flac' "$g_ver"
fi

pre_check_ver 'mediaarea/zenLib' '1' 'T'
if build 'zenLib' "$g_ver"; then
    download "https://codeload.github.com/MediaArea/ZenLib/tar.gz/refs/tags/v$g_ver" "zenLib-$g_ver.tar.gz"
    cd 'Project/GNU/Library' || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'zenLib' "$g_ver"
fi

pre_check_ver 'MediaArea/MediaInfoLib' '1' 'T'
if build 'MediaInfoLib' "$g_ver"; then
    download "https://codeload.github.com/MediaArea/MediaInfoLib/tar.gz/refs/tags/v$g_ver" "MediaInfoLib-$g_ver.tar.gz"
    cd 'Project/GNU/Library' || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'MediaInfoLib' "$g_ver"
fi

pre_check_ver 'MediaArea/MediaInfo' '1' 'T'
if build 'MediaInfoCLI' "$g_ver"; then
    download "https://codeload.github.com/MediaArea/MediaInfo/tar.gz/refs/tags/v$g_ver" "MediaInfoCLI-$g_ver.tar.gz"
    cd 'Project/GNU/CLI' || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-staticlibs CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'MediaInfoCLI' "$g_ver"
fi

if command_exists 'meson'; then
    pre_check_ver 'harfbuzz/harfbuzz' '1' 'T'
    if build 'harfbuzz' "$g_ver"; then
        download_git 'https://github.com/harfbuzz/harfbuzz.git' "harfbuzz-$g_ver"
        execute ./autogen.sh
        execute meson setup 'build' --prefix="$workspace" --libdir="$workspace"/lib --pkg-config-path="$workspace"/lib/pkgconfig \
                --buildtype='release' --default-library='static' --strip
        execute ninja "-j$cpu_threads" -C 'build'
        execute ninja "-j$cpu_threads" -C 'build' install
        build_done 'harfbuzz' "$g_ver"
    fi
fi

if build 'c2man' 'git'; then
    download_git 'https://github.com/fribidi/c2man.git' 'c2man-git'
    execute ./Configure -desO -D prefix="$workspace" -D bin="$workspace"/bin -D bash='/bin/bash' -D cc='/usr/bin/cc' \
        -D d_gnu='/usr/lib/x86_64-linux-gnu' -D find='/usr/bin/find' -D gcc='/usr/lib/ccache/gcc' -D gzip='/usr/bin/gzip' \
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

pre_check_ver 'fribidi/fribidi' '1' 'T'
if build 'fribidi' "$g_ver"; then
    if [ -f "fribidi-$g_ver.tar.gz" ]; then
        rm "fribidi-$g_ver.tar.gz"
    fi
    download "$g_url" "fribidi-$g_ver.tar.gz"
    execute meson setup 'build' --prefix="$workspace" --libdir="$workspace"/lib --pkg-config-path="$workspace"/lib/pkgconfig \
        --buildtype='release' --default-library='static' --strip
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'fribidi' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libfribidi')

pre_check_ver 'libass/libass' '1' 'T'
if build 'libass' "$g_ver"; then
    download "$g_url" "libass-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libass' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libass')

git_ver_fn '890' '4'
if build 'fontconfig' "$g_ver"; then
    download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$g_ver/fontconfig-$g_ver.tar.bz2" "fontconfig-$g_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --sysconfdir="$workspace"/etc --mandir="$workspace"/share/man CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'fontconfig' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libfontconfig')

git_ver_fn '7950' '4'
if build 'freetype' "$g_ver"; then
    extracommands=(-D{harfbuzz,png,bzip2,brotli,zlib,tests}'=disabled')
    download "https://codeload.github.com/freetype/freetype/tar.gz/refs/tags/$g_ver" "freetype-$g_ver.tar.gz"
    execute ./autogen.sh
    execute meson setup 'build' --prefix="$workspace" --buildtype='release' --default-library='static' \
        --includedir="$workspace"/include --libdir="$workspace"/lib  --pkg-config-path="$workspace"/lib/pkgconfig --strip
    execute ninja "-j$cpu_threads" -C 'build'
    execute ninja "-j$cpu_threads" -C 'build' install
    build_done 'freetype' "$g_ver"
fi
ffmpeg_libraries+=('--enable-libfreetype')

pre_check_ver 'libsdl-org/SDL' '1' 'T'
if build 'libsdl' "$g_ver"; then
    download "$g_url" "libsdl-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libsdl' "$g_ver"
fi

if $nonfree_and_gpl; then
    pre_check_ver 'Haivision/srt' '1' 'T'
    if build 'srt' '1.5.1'; then
        download 'https://github.com/Haivision/srt/archive/refs/tags/v1.5.1.tar.gz' 'srt-1.5.1.tar.gz'
        export OPENSSL_ROOT_DIR="$workspace"
        export OPENSSL_LIB_DIR="$workspace"/lib
        export OPENSSL_INCLUDE_DIR="$workspace"/include
        make_dir 'build'
        execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_APPS='OFF' -DENABLE_STATIC='ON' \
            -DPKG_CONFIG_EXECUTABLE='/usr/bin' -DENABLE_DEBUG='OFF' -G 'Ninja'
        execute ninja -C 'build' "-j$cpu_threads"
        execute ninja -C 'build' "-j$cpu_threads" install

        if [ -n "$LDEXEFLAGS" ]; then
            sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$workspace"/lib/pkgconfig/srt.pc
        fi

        build_done 'srt' '1.5.1'
    fi
        ffmpeg_libraries+=('--enable-libsrt')
fi

pre_check_ver 'gpac/gpac' '1' 'T'
if build 'gpac' "$g_ver"; then
    download "https://codeload.github.com/gpac/gpac/tar.gz/refs/tags/v$g_ver" "gpac-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --cc='gcc-12' --cxx='g++-12' --extra-cflags="$CFLAGS" \
        --extra-ldflags="-L$workspace/lib -L$workspace/src/lib -L$workspace/lib64" --extra-libs="$EXTRALIBS" \
        --cpu='x86_64' --static-build --static-bin --static-modules --enable-gprof CXXFLAGS='-O3 -march=native -mtune=native'


    execute make "-j$cpu_threads"
    execute make install
    build_done 'gpac' "$g_ver"
fi

#####################
## HWaccel library ##
#####################

pre_check_ver 'khronosgroup/opencl-headers' '1' 'T'
if build 'opencl' "$g_ver"; then
    CFLAGS+=" -DLIBXML_STATIC_FOR_DLL -DNOLIBTOOL"
    download "$g_url" "opencl-$g_ver.tar.gz"
    execute cmake -B 'build' -DCMAKE_INSTALL_PREFIX="$workspace"
    execute cmake --build build --target install
    build_done 'opencl' "$g_ver"
fi
ffmpeg_libraries+=('--enable-opencl')

# Vaapi doesn't work well with static links FFmpeg.
if [ -z "$LDEXEFLAGS" ]; then
    # If the libva development SDK is installed, enable vaapi.
    if library_exists 'libva'; then
        if build 'vaapi' '1'; then
            build_done 'vaapi' '1'
        fi
        ffmpeg_libraries+=('--enable-vaapi')
    fi
fi

pre_check_ver 'GPUOpen-LibrariesAndSDKs/AMF' '1' 'T'
if build 'amf' "$g_ver"; then
    download "$g_url" "AMF-$g_ver.tar.gz"
    execute rm -fr "$workspace"/include/AMF
    execute mkdir -p "$workspace"/include/AMF
    execute cp -fr "$packages"/AMF-"$g_ver"/amf/public/include/* "$workspace"/include/AMF/
    build_done 'amf' "$g_ver"
fi
ffmpeg_libraries+=('--enable-amf')


if [ -n "$iscuda" ]; then
    pre_check_ver 'FFmpeg/nv-codec-headers' '1' 'T'
    if build 'nv-codec' "$g_ver"; then
        download_git 'https://git.videolan.org/git/ffmpeg/nv-codec-headers.git' "nv-codec-$g_ver"
        execute make PREFIX="$workspace" "-j$cpu_threads"
        execute make install PREFIX="$workspace"
        build_done 'nv-codec' "$g_ver"
    fi

    export CFLAGS+=" -I/usr/local/cuda/targets/x86_64-linux/include -I/usr/local/cuda/include -I$workspace/usr/include -I$packages/nv-codec-$g_ver/include"
    export LDFLAGS+=' -L/usr/local/cuda/targets/x86_64-linux/lib -L/usr/local/cuda/lib64'
    export LDPATH+=' -lcudart'

    ffmpeg_libraries+=('--enable-cuda-nvcc' '--enable-cuvid' '--enable-cuda-llvm')

    if [ -z "$LDEXEFLAGS" ]; then
        ffmpeg_libraries+=('--enable-libnpp')
    fi

    gpu_arch_fn

    # https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards/
    ffmpeg_libraries+=("--nvccflags=-gencode arch=$gpu_arch")
fi

##
## BUILD FFMPEG
##

ff_ver='n6.0'
# CLONE FFMPEG FROM THE LATEST GIT RELEASE
if build 'FFmpeg' "$ff_ver"; then
    download "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/$ff_ver.tar.gz" "FFmpeg-$ff_ver.tar.gz"
    ./configure \
            "${ffmpeg_libraries[@]}" \
            --prefix="$workspace" \
            --cpu="$cpu_cores" \
            --disable-debug \
            --disable-doc \
            --disable-shared \
            --enable-pthreads \
            --enable-static \
            --enable-small \
            --enable-version3 \
            --enable-ffnvcodec \
            --extra-cflags="$CFLAGS" \
            --extra-ldexeflags="$LDEXEFLAGS" \
            --extra-ldflags="$LDFLAGS" \
            --extra-libs="$EXTRALIBS" \
            --pkg-config-flags='--static' \
            --extra-version="$EXTRA_VERSION" \
            CXXFLAGS='-O3 -march=native -mtune=native'
    execute make "-j$cpu_threads"
    execute make install
fi

sudo ldconfig

# PROMPT THE USER TO INSTALL THE FFMPEG BINARIES SYSTEM-WIDE
ffmpeg_install_choice

# CHECK THAT FILES WERE COPIED TO THE INSTALL DIRECTORY
ffmpeg_install_check

# DISPLAY FFMPEG'S VERSION
ff_ver_fn

# PROMPT THE USER TO CLEAN UP THE BUILD FILES
cleanup_fn

# DISPLAY A MESSAGE AT THE SCRIPT'S END
exit_fn
