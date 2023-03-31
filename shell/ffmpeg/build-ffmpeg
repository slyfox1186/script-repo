#!/bin/bash
# shellcheck disable=SC2016,SC2046,SC2066,SC2068,SC2086,SC2162,SC2317,SC2034,SC2093

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
##  Updated: 03.23.29
##
##  Version: 3.3
##
#################################################################################

##
## define variables
##

script_ver='3.2'
progname="${0:2}"
ffmpeg_ver='n5.1.3'
cuda_ver='12.1'
packages="$PWD"/packages
workspace="$PWD"/workspace
install_dir='/usr/bin'
CFLAGS="-I$workspace"/include
LDFLAGS="-L$workspace"/lib
LDEXEFLAGS=''
EXTRALIBS='-ldl -lpthread -lm -lz'
cnf_ops=()
nonfree='false'
latest='false'

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

    if [[ "$cleanup_ans" -eq '1' ]]; then
        remove_dir "$packages"
        remove_dir "$workspace"
        remove_file "$0"
        echo 'cleanup finished.'
        exit_fn
    elif [[ "$cleanup_ans" -eq '2' ]]; then
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
    echo '===================================='
    echo '       FFmpeg Build Complete        '
    echo '===================================='
    echo
    echo 'The binary files can be found in the following locations'
    echo
    echo "ffmpeg:  $install_dir/ffmpeg"
    echo "ffprobe: $install_dir/ffprobe"
    echo "ffplay:  $install_dir/ffplay"
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
    else
        echo
        echo "$dl_file is already downloaded"
    fi

    if [ -d "$dl_path/$target_dir" ]; then
        remove_dir "$dl_path/$target_dir"
    fi

    make_dir "$dl_path/$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" &>/dev/null; then
            echo "Failed to extract $dl_file"
            echo
            fail_fn
        fi
    else
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" --strip-components 1 &>/dev/null; then
            echo "Failed to extract $dl_file"
            echo
            fail_fn
        fi
    fi

    echo -e "File extracted: $dl_file\\n"

    cd "$dl_path/$target_dir" || (
        echo 'Script error!'
        echo
        echo "Unable to change the working directory to $target_dir"
        echo
        fail_fn
    )
}

download_git()
{
    dl_path="$packages"
    dl_url="$1"
    dl_file="$2"
    target_dir="$dl_path/$dl_file"

    # first download attempt
    if [ ! -d "$target_dir" ]; then
        echo "Downloading $dl_file"
        if ! git clone -q "$dl_url" "$target_dir"; then
            echo
            echo "The script failed to download \"$dl_file\" and will try again in 10 seconds"
            sleep 10
            echo
            if ! git clone -q "$dl_url" "$target_dir"; then
                echo
                echo "The script failed to download \"$dl_file\" two times and will exit the build"
                fail_fn
            fi
        fi
        echo 'Download Complete'
        echo
    else
        echo
        echo "$dl_file is already downloaded"
    fi

    cd "$target_dir" || (
        echo 'Script error!'
        echo
        echo "Unable to change the working directory to $target_dir"
        fail_fn
    )
}

# PULL THE LATEST VERSIONS OF EACH PACKAGE FROM THE WEBSITE API
net_timeout='10'

git_1_fn()
{
    # SCRAPE GITHUB WEBSITE FOR LATEST REPO VERSION
    github_repo="$1"
    github_url="$2"
    if curl_cmd=$(curl -m "$net_timeout" -sSL "https://api.github.com/repos/$github_repo/$github_url?per_page=1"); then
        g_ver=$(echo "$curl_cmd" | jq -r '.[0].name')
        g_ver=${g_ver#v}
        g_ver_ssl=$(echo "$curl_cmd" | jq -r '.[0].name')
        g_ver_ssl=${g_ver_ssl#OpenSSL }
        g_ver_pkg=$(echo "$curl_cmd" | jq -r '.[0].name')
        g_ver_pkg=${g_ver_pkg#pkg-config-}
        g_ver_zimg=$(echo "$curl_cmd" | jq -r '.[0].name')
        g_ver_zimg=${g_ver_zimg#release-}
        g_ver_libva=$(echo "$curl_cmd" | jq -r '.[0].name')
        g_ver_libva=${g_ver_libva#Libva }
        g_url=$(echo "$curl_cmd" | jq -r '.[0].tarball_url')
    fi
}

git_2_fn()
{
    videolan_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" -sSL "https://code.videolan.org/api/v4/projects/$videolan_repo/repository/branches?"); then
        videolan_ver=$(echo "$curl_cmd" | jq -r '.[0].commit.id')
        videolan_sver=$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')
    fi
}

git_3_fn()
{
    gitlab_repo="$1"
    
    if curl_cmd=$(curl -m "$net_timeout" -sSL "https://gitlab.com/api/v4/projects/$gitlab_repo/repository/branches?"); then
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
    if curl_cmd=$(curl -m "$net_timeout" -sSL "https://gitlab.com/api/v4/projects/$gitlab_repo/repository/tags"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name')
        gitlab_ver=${gitlab_ver#v}
        gitlab_sver=$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')
    fi
}

git_5_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" -sSL "https://gitlab.freedesktop.org/api/v4/projects/$gitlab_repo/repository/tags?"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name')
    fi
}

git_6_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$net_timeout" -sSL 'https://bitbucket.org/!api/2.0/repositories/multicoreware/x265_git/effective-branching-model')"; then
        gitlab_ver=$(echo "$curl_cmd" | jq '.development.branch.target' | grep -Eo '[0-9a-z][0-9a-z]+' | sort | head -n 1)
    fi
}

git_7_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" -sSL "https://gitlab.gnome.org/api/v4/projects/$gitlab_repo/repository/tags?"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name')
        gitlab_ver=${gitlab_ver#v}
    fi
}

git_8_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" -sSL "https://git.archive.org/api/v4/projects/$gitlab_repo/repository/tags?"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name')
        gitlab_ver=${gitlab_ver#v}
    fi
}

git_9_fn()
{
    # SCRAPE GITHUB WEBSITE FOR LATEST REPO VERSION
    github_repo="$1"
    github_url="$2"
        if curl_cmd=$(curl -m "$net_timeout" -sSL "https://api.github.com/repos/$github_repo/$github_url?per_page=1"); then
        g_ver=$(echo "$curl_cmd" | jq -r '.[0].name')
        g_url=$(echo "$curl_cmd" | jq -r '.[0].tarball_url')
    fi
}

git_10_fn()
{
    videolan_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" -sSL "https://code.videolan.org/api/v4/projects/$videolan_repo/repository/tags?"); then
        videolan_sver=$(echo "$curl_cmd" | jq -r '.[0].name')
        videolan_sver=${videolan_sver#v}
    fi
}

git_ver_fn()
{
    local v_flag v_tag

    v_url="$1"
    v_tag="$2"

    if [ -n "$3" ]; then
        v_flag="$3"
    fi

    if [ "$v_flag" = 'X' ]; then
        url_tag='git_6_fn'
        "$url_tag" 2>/dev/null

        return 0
    fi

    if [  "$v_flag" = 'T' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn' gv_url='tags'
    elif [ "$v_flag" = 'T' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn' gv_url='tags'
    elif [ "$v_flag" = 'T' ] && [  "$v_tag" = '9' ]; then
        url_tag='git_9_fn' gv_url='tags'
    fi

    if [  "$v_flag" = 'R' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '9' ]; then
        url_tag='git_9_fn' gv_url='releases'
    fi

    case "$v_tag" in
        2)          url_tag='git_2_fn';;
        3)          url_tag='git_3_fn';;
        4)          url_tag='git_4_fn';;
        5)          url_tag='git_5_fn';;
        6)          url_tag='git_6_fn';;
        7)          url_tag='git_7_fn';;
        8)          url_tag='git_8_fn';;
        9)          url_tag='git_9_fn';;
       10)          url_tag='git_10_fn';;
    esac

    "$url_tag" "$v_url" "$gv_url" 2>/dev/null
}

execute()
{
    echo "$ $*"

    if ! output=$("$@" &>/dev/null); then
        echo "$output"
        echo
        echo "Failed to Execute $*" >&2
        echo
        fail_fn
    fi
}

build()
{
    echo
    echo "building $1 - version $2"
    echo '======================================'

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
    echo "Unable to locate directory: /usr/local/cuda-$cuda_ver/bin/"
    echo
    read -p 'Press enter to exit.'
    clear
    fail_fn
}

gpu_arch_fn()
{
    local gpu_name gpu_type

    is_wsl="$(echo $(uname -a) | grep -Eo 'WSL2')"
    
    if [ -n "$is_wsl" ]; then
        sudo apt -q -y install nvidia-utils-525
    fi
    
    gpu_name="$(nvidia-smi --query-gpu=gpu_name --format=csv | sort | head -n 1)"

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

echo "The script will utilize $cpu_threads CPU cores for parallel processing to accelerate the build speed."
echo

if "$nonfree"; then
    echo 'The script has been configured to run with GPL and non-free codecs enabled'
    echo
fi

if [ -n "$LDEXEFLAGS" ]; then
    echo 'The script has been configured to run in full static mode.'
    echo
fi

# create the output directories
mkdir -p "$packages"
mkdir -p "$workspace"

# set global variables
JAVA_HOME='/usr/lib/jvm/java-17-openjdk-amd64'
export JAVA_HOME

# libbluray requries that this variable be set
PATH="\
$workspace/bin:\
$JAVA_HOME/bin:\
$PATH\
"
export PATH

# set the pkg-config path
PKG_CONFIG_PATH="\
$packages/pkg-config-0.29.2:\
$workspace/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/gcc:\
/usr/share/gcc\
"
export PKG_CONFIG_PATH

LD_LIBRARY_PATH="\
$packages/pkg-config-0.29.2\
$workspace/lib/pkgconfig:\
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
    echo
    echo 'Pick your Linux distro from the list below:'
    echo
    echo 'Supported architecture: x86_x64'
    echo
    echo '[1] Debian 10'
    echo '[2] Debian 11'
    echo '[3] Ubuntu 18.04'
    echo '[4] Ubuntu 20.04'
    echo '[5] Ubuntu 22.04'
    echo '[6] Ubuntu Windows (WSL)'
    echo '[7] Skip this'
    echo
    read -p 'Your choices are (1 to 7): ' cuda_dist
    clear
    if [[ "$cuda_dist" -eq '1' ]]; then
        wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-debian10-12-1-local_12.1.0-530.30.02-1_amd64.deb'
        sudo dpkg -i "cuda-$cuda_ver.deb"
        sudo cp /var/cuda-repo-debian10-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
        sudo add-apt-repository contrib
       elif [[ "$cuda_dist" -eq '2' ]]; then
        wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-debian11-12-1-local_12.1.0-530.30.02-1_amd64.deb'
        sudo dpkg -i "cuda-$cuda_ver.deb"
        sudo sudo cp /var/cuda-repo-debian11-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
        sudo add-apt-repository contrib
    elif [[ "$cuda_dist" -eq '3' ]]; then
        wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-ubuntu1804.pin'
        sudo mv 'cuda-ubuntu1804.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
        wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-ubuntu1804-12-1-local_12.1.0-530.30.02-1_amd64.deb'
        sudo dpkg -i "cuda-$cuda_ver.deb"
        sudo cp /var/cuda-repo-ubuntu1804-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
    elif [[ "$cuda_dist" -eq '4' ]]; then
        wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-ubuntu2004.pin'
        sudo mv 'cuda-ubuntu2004.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
        wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-ubuntu2004-12-1-local_12.1.0-530.30.02-1_amd64.deb'
        sudo dpkg -i "cuda-$cuda_ver.deb"
        sudo cp /var/cuda-repo-ubuntu2004-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
    elif [[ "$cuda_dist" -eq '5' ]]; then
        wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin'
        sudo mv 'cuda-ubuntu2204.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
        wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-ubuntu2204-12-1-local_12.1.0-530.30.02-1_amd64.deb'
        sudo dpkg -i "cuda-$cuda_ver.deb"
        sudo cp /var/cuda-repo-ubuntu2204-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
    elif [[ "$cuda_dist" -eq '6' ]]; then
        wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin'
        sudo mv 'cuda-wsl-ubuntu.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
        wget --show progress -cqO "cuda-$cuda_ver.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-wsl-ubuntu-12-1-local_12.1.0-1_amd64.deb'
        sudo dpkg -i "cuda-$cuda_ver.deb"
        sudo cp /var/cuda-repo-wsl-ubuntu-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
    elif [[ "$cuda_dist" -eq '7' ]]; then
        return 0
    fi

    # UPDATE THE APT PACKAGES THEN INSTALL THE CUDA-SDK-TOOLKIT
    sudo apt update
    sudo apt -y install cuda

    # CHECK IF THE CUDA FOLDER EXISTS TO ENSURE IT WAS INSTALLED
    iscuda="$(find /usr/local/ -type f -name 'nvcc')"
    cudaPATH="$(find /usr/local/ -type f -name 'nvcc' | grep -Eo '^.*\/bi[n]?')"

    if [ -z "$cudaPATH" ]; then
        cuda_fail_fn
    else
        PATH="$PATH:$cudaPATH"
        export PATH
    fi
}

## Get the CPU thread count for use in parallel processing
if [ -f '/proc/cpuinfo' ]; then
    cpu_threads="$(grep -c ^processor '/proc/cpuinfo')"
else
    cpu_threads="$(nproc --all)"
fi

## Get the CPU core count for use in parallel processing
cpu_cores="$(grep ^cpu\\scores '/proc/cpuinfo' | uniq | awk '{print $4}')"

##
## required build packages
##

build_pkgs_fn()
{
    echo
    echo 'Installing required development packages'
    echo '=========================================='

    pkgs=(ant automake cmake g++ gcc git gtk-doc-tools help2man javacc \
          jq junit libcairo2-dev libcdio-paranoia-dev libcurl4-gnutls-dev \
          libdrm-dev libglib2.0-dev libmusicbrainz5-dev libopus-dev \
          libtinyxml2-dev libtool meson openjdk-17-jdk pkg-config ragel)

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
                echo 'The required development packages were installed.'
            else
                echo 'The required development packages failed to install'
                echo
                exit 1
            fi
        done
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
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        for pkg in "$missing_pkgs"
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

    iscuda="$(find /usr/local/ -type f -name 'nvcc')"
    cudaPATH="$(find /usr/local/ -type f -name 'nvcc' | grep -Eo '^.*\/bi[n]?')"

    if [ -z "$iscuda" ]; then
        echo
        echo 'The cuda-sdk-toolkit isn'\''t installed or it is not in $PATH'
        echo '==============================================================='
        echo
        echo 'What do you want to do next?'
        echo
        echo '[1] Install the toolkit and add it to $PATH'
        echo '[2] Only add it to $PATH'
        echo '[3] Continue the build'
        echo
        read -p 'Your choices are (1 to 3): ' cuda_ans
        clear
        if [[ "$cuda_ans" -eq '1' ]]; then
            cuda_fn
            cuda_add_fn
        elif [[ "$cuda_ans" -eq '2' ]]; then
            if [ -d "$cudaPATH" ]; then
                PATH="$PATH:$cudaPATH"
                export PATH
            else
                echo 'The script was unable to add cuda to your $PATH because the required folder was not found: /usr/local/cuda-12.1/bin'
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
        echo "The cuda-sdk-toolkit v$cuda_ver is already installed."
        echo '================================================='
        echo
        echo 'Do you want to update/reinstall it?'
        echo
        echo '[1] Yes'
        echo '[2] No'
        echo
        read -p 'Your choices are (1 or 2): ' cuda_choice
        clear
        if [[ "$cuda_choice" -eq '1' ]]; then
            cuda_fn
            cuda_add_fn
        elif [[ "$cuda_choice" -eq '2' ]]; then
            PATH="$PATH:$cudaPATH"
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

##
## install cuda
##

install_cuda_fn

##
## build tools
##

# install required apt packages
build_pkgs_fn

# begin source code building
if build 'giflib' 'git'; then
    download_git 'https://github.com/mirrorer/giflib.git' 'giflib-git'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make
    execute make install
    build_done 'giflib' 'git'
fi

git_ver_fn 'freedesktop/pkg-config' '1' 'T'
if build 'pkg-config' "$g_ver_pkg"; then
    download "https://pkgconfig.freedesktop.org/releases/$g_ver.tar.gz"
    execute ./configure --silent --prefix="$workspace" --with-pc-path="$workspace"/lib/pkgconfig/ --with-internal-glib
    execute make -j "$cpu_threads"
    execute make install
    build_done 'pkg-config' "$g_ver_pkg"
fi

git_ver_fn 'yasm/yasm' '1' 'T'
if build 'yasm' "$g_ver"; then
    download "https://github.com/yasm/yasm/releases/download/v$g_ver/yasm-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'yasm' "$g_ver"
fi

if build 'nasm' '2.16.01'; then
    download 'https://www.nasm.us/pub/nasm/releasebuilds/2.16.01/nasm-2.16.01.tar.xz'
    execute sh ./autogen.sh
    execute sh ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'nasm' '2.16.01'
fi

git_ver_fn 'madler/zlib' '1' 'T'
if build 'zlib' "$g_ver"; then
    download "$g_url" "zlib-$g_ver.tar.gz"
    execute ./configure --static --prefix="$workspace"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'zlib' "$g_ver"
fi

if build 'm4' '1.4.19'; then
    download 'https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz'
    execute ./configure --prefix="$workspace"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'm4' '1.4.19'
fi

if build 'autoconf' '2.71'; then
    download 'https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.xz'
    execute ./configure --prefix="$workspace"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'autoconf' '2.71'
fi

if build 'automake' '1.16.5'; then
    download 'https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.xz'
    execute ./configure --prefix="$workspace"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'automake' '1.16.5'
fi

if build 'libtool' '2.4.7'; then
    download 'https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz'
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libtool' '2.4.7'
fi

if $nonfree; then
    git_ver_fn 'openssl/openssl' '1' 'R'
    if build 'openssl' "$g_ver_ssl"; then
        download "$g_url" "openssl-$g_ver_ssl.tar.gz"
        execute ./config --prefix="$workspace" --openssldir="$workspace" \
            --with-zlib-include="$workspace"/include/ --with-zlib-lib="$workspace"/lib no-shared zlib
        execute make -j "$cpu_threads"
        execute make install_sw
        build_done 'openssl' "$g_ver_ssl"
    fi
    cnf_ops+=('--enable-openssl')
else
    if build 'gmp' '6.2.1'; then
        download 'https://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz' 'gmp-6.2.1.tar.xz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make -j "$cpu_threads"
        execute make install
        build_done 'gmp' '6.2.1'
    fi
    cnf_ops+=('--enable-gmp')

    if build 'nettle' '3.8.1'; then
        download 'https://ftp.gnu.org/gnu/nettle/nettle-3.8.1.tar.gz' 'nettle-3.8.1.tar.gz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-openssl \
            --disable-documentation --libdir="$workspace"/lib CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make -j "$cpu_threads"
        execute make install
        build_done 'nettle' '3.8.1'
    fi

    if build 'gnutls' '3.8.0'; then
        download 'https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.0.tar.xz' 'gnutls-3.8.0.tar.xz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-doc --disable-tools \
            --disable-cxx --disable-tests --disable-gtk-doc-html --disable-libdane --disable-nls --enable-local-libopts \
            --disable-guile --with-included-libtasn1 --with-included-unistring --without-p11-kit CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make -j "$cpu_threads"
        execute make install
        build_done 'gnutls' '3.8.0'
    fi
    cnf_ops+=('--enable-gnutls')
fi

git_ver_fn 'Kitware/CMake' '1' 'T'
if build 'cmake' "$g_ver"; then
    download "$g_url" "cmake-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --parallel="$cpu_threads" -- -DCMAKE_USE_OPENSSL='OFF'
    execute make -j "$cpu_threads"
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
        execute pip3 install pip setuptools --quiet --upgrade --no-cache-dir --disable-pip-version-check
        for r in meson ninja
        do
            if ! command_exists $r; then
                execute pip3 install $r --quiet --upgrade --no-cache-dir --disable-pip-version-check
            fi
            export PATH="$PATH:$HOME/Library/Python/3.9/bin"
        done
    fi
    if command_exists 'meson'; then
        git_ver_fn '198' '2'
        if build 'dav1d' "$videolan_sver"; then
            download "https://code.videolan.org/videolan/dav1d/-/archive/$videolan_ver/$videolan_ver.tar.bz2" "dav1d-$videolan_sver.tar.bz2"
            make_dir build
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'dav1d' "$videolan_sver"
        fi
        cnf_ops+=('--enable-libdav1d')
    fi
fi

git_ver_fn '24327400' '4'
if build 'svtav1' "$gitlab_ver"; then
    download "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$gitlab_ver/SVT-AV1-v$gitlab_ver.tar.bz2" "SVT-AV1-$gitlab_ver.tar.bz2"
    cd 'Build/linux' || exit 1
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
        ../.. -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE='Release' -DENABLE_EXAMPLES='OFF'
    execute make -j "$cpu_threads"
    execute make install
    execute cp 'SvtAv1Enc.pc' "$workspace"/lib/pkgconfig/
    execute cp 'SvtAv1Dec.pc' "$workspace"/lib/pkgconfig/
    build_done 'svtav1' "$gitlab_ver"
fi
cnf_ops+=('--enable-libsvtav1')

if command_exists 'cargo'; then
    git_ver_fn 'xiph/rav1e' '1' 'T'
    if build 'rav1e' "$g_ver"; then
        execute cargo install --version '0.9.14+cargo-0.66' cargo-c
        download "$g_url" "rav1e-$g_ver.tar.gz"
        execute cargo cinstall --prefix="$workspace" --library-type='staticlib' --crt-static --release
        build_done 'rav1e' "$g_ver"
    fi
    avif_tag='-DAVIF_CODEC_RAV1E=ON'
    cnf_ops+=('--enable-librav1e')
else
    avif_tag='-DAVIF_CODEC_RAV1E=OFF'
fi

if $nonfree; then
    git_ver_fn '536' '2'
    if build 'x264' "$videolan_sver"; then
        download "https://code.videolan.org/videolan/x264/-/archive/$videolan_ver/x264-$videolan_ver.tar.bz2" "x264-$videolan_sver.tar.bz2"
        cd "$packages/x264-$videolan_sver" || exit 1
        execute ./configure --prefix="$workspace" --enable-static --enable-pic CXXFLAGS="-fPIC $CXXFLAGS"
        execute make -j "$cpu_threads"
        execute make install
        execute make install-lib-static
        build_done 'x264' "$videolan_sver"
    fi
    cnf_ops+=('--enable-libx264')
fi

if $nonfree; then
    git_ver_fn 'x265_git' '6' 'X'
    if build 'x265' "${gitlab_ver:0:7}"; then
        download "https://bitbucket.org/multicoreware/x265_git/get/$gitlab_ver.tar.bz2" "x265-${gitlab_ver:0:7}.tar.bz2"
        cd "$PWD/build/linux" || exit 1
        rm -fr {8,10,12}bit 2>/dev/null
        mkdir -p {8,10,12}bit
        cd '12bit' || exit 1
        echo -e "\\n\$ making 12bit binaries"
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
            -DHIGH_BIT_DEPTH='ON' -DENABLE_HDR10_PLUS='ON' -DEXPORT_C_API='OFF' -DENABLE_CLI='OFF' -DMAIN12='ON'
        execute make -j "$cpu_threads"
        echo -e "\\n\$ making 10bit binaries"
        cd ../'10bit' || exit 1
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' \
            -DBUILD_SHARED_LIBS='OFF' -DHIGH_BIT_DEPTH='ON' -DENABLE_HDR10_PLUS='ON' -DEXPORT_C_API='OFF' -DENABLE_CLI='OFF'
        execute make -j "$cpu_threads"
        echo -e "\\n\$ making 8bit binaries"
        cd ../'8bit' || exit 1
        ln -sf ../'10bit/libx265.a' 'libx265_main10.a'
        ln -sf ../'12bit/libx265.a' 'libx265_main12.a'
        execute cmake ../../../'source' -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
            -DEXTRA_LIB='x265_main10.a;x265_main12.a;-ldl' -DEXTRA_LINK_FLAGS='-L.' -DLINKED_10BIT='ON' -DLINKED_12BIT='ON'
        execute make -j "$cpu_threads"
        # must rename this file
        mv 'libx265.a' 'libx265_main.a'

        execute ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF

        execute make install

        if [ -n "$LDEXEFLAGS" ]; then
            sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$workspace"/lib/pkgconfig/x265.pc
        fi

        build_done 'x265' "${gitlab_ver:0:7}"
    fi
    cnf_ops+=('--enable-libx265')
fi

git_ver_fn 'OpenVisualCloud/SVT-HEVC' '1' 'R'
if build 'SVT-HEVC' "$g_ver"; then
    download "$g_url" "SVT-HEVC-$g_ver.tar.gz"
    make_dir Build
    cd "$PWD"/Build || exit 1
    execute cmake .. -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' -DCMAKE_BUILD_TYPE='Release'
    execute make -j "$cpu_threads"
    execute make install
    build_done 'SVT-HEVC' "$g_ver"
fi

git_ver_fn 'OpenVisualCloud/SVT-VP9' '1' 'T'
if build 'SVT-VP9' "$g_ver"; then
    download "https://github.com/OpenVisualCloud/SVT-VP9/archive/refs/tags/v$g_ver.tar.gz" "SVT-VP9-$g_ver.tar.gz"
    cd 'Build/linux' || exit 1
    execute ./build.sh -xi static
    cd '../..' || exit 1
    execute cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' -DCMAKE_BUILD_TYPE='Release'
    execute cmake --build build --target install
    execute chmod +x "$workspace"/bin/SvtVp9EncApp
    build_done 'SVT-VP9' "$g_ver"
fi

git_ver_fn 'webmproject/libvpx' '1' 'T'
if build 'libvpx' "$g_ver"; then
    download "$g_url" "libvpx-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --disable-unit-tests --disable-shared --disable-examples --as='yasm'
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libvpx' "$g_ver"
fi
cnf_ops+=('--enable-libvpx')

if $nonfree; then
    if build 'xvidcore' '1.3.7'; then
        download 'https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.bz2' 'xvidcore-1.3.7.tar.bz2'
        cd 'build/generic' || exit 1
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make -j "$cpu_threads"
        execute make install

        if [[ -f "$workspace"/lib/libxvidcore.4.dylib ]]; then
            execute rm "$workspace"/lib/libxvidcore.4.dylib
        fi

        if [[ -f "$workspace"/lib/libxvidcore.so ]]; then
            execute rm "$workspace"/lib/libxvidcore.so*
        fi

        build_done 'xvidcore' '1.3.7'
    fi
    cnf_ops+=('--enable-libxvid')
fi

if $nonfree; then
    git_ver_fn 'georgmartius/vid.stab' '1' 'T'
    if build 'vid_stab' "$g_ver"; then
        download "$g_url" "vid.stab-$g_ver.tar.gz"
        execute cmake -DBUILD_SHARED_LIBS='OFF' -DCMAKE_INSTALL_PREFIX="$workspace" -DUSE_OMP='OFF' -DENABLE_SHARED='OFF' .
        execute make -j "$cpu_threads"
        execute make install
        build_done 'vid_stab' "$g_ver"
    fi
    cnf_ops+=('--enable-libvidstab')
fi

if build 'av1' '39f5013'; then
    download 'https://aomedia.googlesource.com/aom/+archive/39f50137f189ef57f4c58778f1b11d6806e58fdf.tar.gz' 'av1-39f5013.tar.gz' 'av1'
    make_dir "$packages"/aom_build
    cd "$packages"/aom_build || exit 1
    execute cmake -DENABLE_TESTS='0' -DENABLE_EXAMPLES='0' -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' "$packages"/av1
    execute make -j "$cpu_threads"
    execute make install
    build_done 'av1' '39f5013'
fi
cnf_ops+=('--enable-libaom')

git_ver_fn 'sekrit-twc/zimg' '1' 'T'
if build 'zimg' "$g_ver_zimg"; then
    download "$g_url" "zimg-$g_ver_zimg.tar.gz"
    execute "$workspace"/bin/libtoolize -i -f -q
    execute ./autogen.sh --prefix="$workspace"
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'zimg' "$g_ver_zimg"
fi
cnf_ops+=('--enable-libzimg')

git_ver_fn 'AOMediaCodec/libavif' '1' 'R'
if build 'avif' "$g_ver"; then
    download "$g_url" "avif-$g_ver.tar.gz"
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
        -DENABLE_STATIC='ON' -DAVIF_ENABLE_WERROR='OFF' -DAVIF_CODEC_DAV1D='ON' -DAVIF_CODEC_AOM='ON' \
        -DAVIF_BUILD_APPS='ON' "$avif_tag"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'avif' "$g_ver"
fi

git_ver_fn 'ultravideo/kvazaar' '1' 'T'
if build 'kvazaar' "$g_ver"; then
    download "$g_url" "kvazaar-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'kvazaar' "$g_ver"
fi
cnf_ops+=('--enable-libkvazaar')

##
## audio libraries
##

if command_exists 'python3'; then
    if command_exists 'meson'; then

        git_ver_fn 'lv2/lv2' '1' 'T'
        if build 'lv2' "$g_ver"; then
            download "$g_url" "lv2-$g_ver.tar.gz"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'lv2' "$g_ver"
        fi

        git_ver_fn '7131569' '4'
        if build 'waflib' "$gitlab_sver"; then
            download "https://gitlab.com/ita1024/waf/-/archive/$gitlab_ver/waf-$gitlab_ver.tar.bz2" "autowaf-$gitlab_sver.tar.bz2"
            build_done 'waflib' "$gitlab_sver"
        fi

        git_ver_fn '5048975' '4'
        if build 'serd' "$gitlab_ver"; then
            download "https://gitlab.com/drobilla/serd/-/archive/v$gitlab_ver/serd-v$gitlab_ver.tar.bz2" "serd-$gitlab_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'serd' "$gitlab_ver"
        fi

        git_ver_fn 'PCRE2Project/pcre2' '9' 'R'
        case_lower="$(echo "$g_ver" | tr "[:upper:]" "[:lower:]")"
        if build 'pcre2' "$case_lower"; then
            download "$g_url" "pcre-$case_lower.tar.bz2"
            execute ./autogen.sh
            execute ./configure --prefix="$workspace" --disable-shared --enable-static
            execute make -j "$cpu_threads"
            execute make install
            build_done 'pcre2' "$case_lower"
        fi

        git_ver_fn '14889806' '3'
        if build 'zix' "$gitlab_sver0"; then
            download "https://gitlab.com/drobilla/zix/-/archive/$gitlab_ver0/zix-$gitlab_ver0.tar.bz2" "zix-$gitlab_sver0.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'zix' "$gitlab_sver0"
        fi

        git_ver_fn '11853362' '4'
        if build 'sord' "$gitlab_ver"; then
            download "https://gitlab.com/drobilla/sord/-/archive/v$gitlab_ver/sord-v$gitlab_ver.tar.bz2" "sord-$gitlab_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'sord' "$gitlab_ver"
        fi

        git_ver_fn '11853194' '4'
        if build 'sratom' "$gitlab_ver"; then
            download "https://gitlab.com/lv2/sratom/-/archive/v$gitlab_ver/sratom-v$gitlab_ver.tar.bz2" "sratom-$gitlab_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'sratom' "$gitlab_ver"
        fi

        git_ver_fn '11853176' '4'
        if build 'lilv' "$gitlab_ver"; then
            download "https://gitlab.com/lv2/lilv/-/archive/v$gitlab_ver/lilv-v$gitlab_ver.tar.bz2" "lilv-$gitlab_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'lilv' "$gitlab_ver"
        fi
        CFLAGS+=" -I$workspace/include/lilv-0"
        cnf_ops+=('--enable-lv2')
    fi
fi

git_ver_fn 'acidanthera/OpenCorePkg' '9' 'R'
if build 'opencore' 'git'; then
    download_git 'git://git.code.sf.net/p/opencore-amr/code' 'opencore-amr-git'
    execute autoreconf -fiv
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'opencore' 'git'
fi
cnf_ops+=('--enable-libopencore_amrnb' '--enable-libopencore_amrwb')

if build 'lame' '3.100'; then
    download 'https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download?use_mirror=gigenet' 'lame-3.100.tar.gz'
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'lame' '3.100'
fi
cnf_ops+=('--enable-libmp3lame')

git_ver_fn 'xiph/opus' '1' 'T'
if build 'opus' "$g_ver"; then
    download "$g_url" "opus-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'opus' "$g_ver"
fi
cnf_ops+=('--enable-libopus')

git_ver_fn 'xiph/ogg' '1' 'T'
if build 'libogg' "$g_ver"; then
    download "$g_url" "libogg-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libogg' "$g_ver"
fi

git_ver_fn 'xiph/vorbis' '1' 'T'
if build 'libvorbis' "$g_ver"; then
    download "$g_url" "libvorbis-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --with-ogg-libraries="$workspace"/lib \
        --with-ogg-includes="$workspace"/include/ --enable-static --disable-shared --disable-oggtest
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libvorbis' "$g_ver"
fi
cnf_ops+=('--enable-libvorbis')

git_ver_fn 'xiph/theora' '1' 'T'
if build 'libtheora' "$g_ver"; then
    download "$g_url" "libtheora-$g_ver.tar.gz"
    execute ./autogen.sh
    sed 's/-fforce-addr//g' 'configure' >'configure.patched'
    chmod +x 'configure.patched'
    mv 'configure.patched' 'configure'
    rm 'config.guess'
    curl -Lso 'config.guess' 'https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess'
    chmod +x 'config.guess'
    execute ./configure --prefix="$workspace" --with-ogg-libraries="$workspace"/lib --with-ogg-includes="$workspace"/include/ \
        --with-vorbis-libraries="$workspace"/lib --with-vorbis-includes="$workspace"/include/ --enable-static --disable-shared \
        --disable-oggtest --disable-vorbistest --disable-examples --disable-asm --disable-spec
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libtheora' "$g_ver"
fi
cnf_ops+=('--enable-libtheora')

if $nonfree; then
    git_ver_fn 'mstorsjo/fdk-aac' '1' 'T'
    if build 'fdk_aac' "$g_ver"; then
        download "https://github.com/mstorsjo/fdk-aac/archive/refs/tags/v$g_ver.tar.gz" "fdk_aac-$g_ver.tar.gz"
        execute ./autogen.sh
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --enable-pic --bindir="$workspace"/bin CXXFLAGS=' -fno-exceptions -fno-rtti'
        execute make -j "$cpu_threads"
        execute make install
        build_done 'fdk_aac' "$g_ver"
    fi
    cnf_ops+=('--enable-libfdk-aac')
fi

##
## image libraries
##

git_ver_fn '4720790' '4'
if build 'libtiff' "$gitlab_ver"; then
    download "https://gitlab.com/libtiff/libtiff/-/archive/v$gitlab_ver/libtiff-v$gitlab_ver.tar.bz2" "libtiff-$gitlab_ver.tar.bz2"
    execute ./autogen.sh
    execute cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$workspace" -D{webp,jbig,UNIX,lerc}=OFF
    execute cmake --build build --target install
    build_done 'libtiff' "$gitlab_ver"
fi

git_ver_fn 'glennrp/libpng' '1' 'T'
if build 'libpng' "$g_ver"; then
    download "$g_url" "libpng-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libpng' "$g_ver"
fi

if build 'libwebp' '1.2.2'; then
    # libwebp can fail to compile on ubuntu if cflags are set
    # version 1.3.0, 1.2.4, and 1.2.3 fail to build successfully
    CPPFLAGS=
    download 'https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.2.2.tar.gz' 'libwebp-1.2.2.tar.gz'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-dependency-tracking \
        --disable-gl --with-zlib-include="$workspace"/include/ --with-zlib-lib="$workspace"/lib
    make_dir build
    cd 'build'|| exit 1
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
        -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON' -DWEBP_BUILD_CWEBP=ON -DWEBP_BUILD_DWEBP=ON ../
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libwebp' '1.2.2'
fi
cnf_ops+=('--enable-libwebp')

##
## other libraries
##

git_ver_fn '363' '2'
if build 'udfread' "$videolan_sver"; then
    download "https://code.videolan.org/videolan/libudfread/-/archive/$videolan_ver/libudfread-$videolan_ver.tar.bz2" "udfread-$videolan_sver.tar.bz2"
    execute autoreconf -fiv
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'udfread' "$videolan_sver"
fi

git_ver_fn '206' '2'
if build 'libbluray' "$videolan_sver"; then
    download "https://code.videolan.org/videolan/libbluray/-/archive/$videolan_ver/$videolan_ver.tar.gz" "libbluray-$videolan_sver.tar.gz"
    execute autoreconf -fiv
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libbluray' "$videolan_sver"
fi
unset JAVA_HOME
cnf_ops+=('--enable-libbluray')

git_ver_fn 'mediaarea/zenLib' '1' 'R'
if build 'zenLib' "$g_ver"; then
    download "$g_url" "zenLib-$g_ver.tar.gz"
    cd 'Project/CMake' || exit 1
    execute cmake . -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
        -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON' -DENABLE_APPS='OFF' \
        -DUSE_STATIC_LIBSTDCXX='ON' -DBUILD_ZLIB='ON'
    execute make -j "$cpu_threads"
    execute make install
    build_done 'zenLib' "$g_ver"
fi

git_ver_fn 'MediaArea/MediaInfoLib' '1' 'R'
if build 'MediaInfoLib' "$g_ver"; then
    download "$g_url" "MediaInfoLib-$g_ver.tar.gz"
    cd 'Project/CMake' || exit 1
    execute cmake . -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
        -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON' -DENABLE_APPS='OFF' \
        -DUSE_STATIC_LIBSTDCXX='ON' -DBUILD_ZLIB='OFF' -DBUILD_ZENLIB='OFF'
    execute make install
    build_done 'MediaInfoLib' "$g_ver"
fi

git_ver_fn 'MediaArea/MediaInfo' '1' 'T'
if build 'MediaInfoCLI' "$g_ver"; then
    download "$g_url" "MediaInfoCLI-$g_ver.tar.gz"
    cd 'Project/GNU/CLI' || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-staticlibs
    build_done 'MediaInfoCLI' "$g_ver"
fi

if command_exists 'meson'; then
    git_ver_fn 'harfbuzz/harfbuzz' '1' 'R'
    if build 'harfbuzz' "$g_ver"; then
        download "$g_url" "harfbuzz-$g_ver.tar.gz"
        execute ./autogen.sh
        execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute ninja -C build
        execute ninja -C build install
        build_done 'harfbuzz' "$g_ver"
    fi
fi

if build 'c2man' '2.0'; then
    download_git 'https://github.com/fribidi/c2man.git' 'c2man'
    execute ./Configure -des
    execute make depend
    execute make -j "$cpu_threads"
    execute sudo make install
    build_done 'c2man' '2.0'
fi

git_ver_fn 'fribidi/fribidi' '1' 'R'
if build 'fribidi' "$g_ver"; then
    download "$g_url" "fribidi-$g_ver.tar.gz"
    execute ./autogen.sh
    make_dir build
    execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
    execute ninja -C build
    execute ninja -C build install
    build_done 'fribidi' "$g_ver"
fi
cnf_ops+=('--enable-libfribidi')

git_ver_fn 'libass/libass' '1' 'T'
if build 'libass' "$g_ver"; then
    download "$g_url" "libass-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libass' "$g_ver"
fi
cnf_ops+=('--enable-libass')

git_ver_fn '890' '5'
if build 'fontconfig' "$gitlab_ver"; then
    download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$gitlab_ver/fontconfig-$gitlab_ver.tar.bz2" "fontconfig-$gitlab_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --sysconfdir="$workspace"/etc/ --mandir="$workspace"/share/man/
    execute make -j "$cpu_threads"
    execute make install
    build_done 'fontconfig' "$gitlab_ver"
fi
cnf_ops+=('--enable-libfontconfig')

git_ver_fn '7950' '5'
if build 'freetype' "$gitlab_ver"; then
    extracommands=(-D{harfbuzz,png,bzip2,brotli,zlib,tests}"=disabled")
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/$gitlab_ver/freetype-$gitlab_ver.tar.bz2" "freetype-$gitlab_ver.tar.bz2"
    execute ./autogen.sh
    execute cmake -S . -B build/release-static -DCMAKE_INSTALL_PREFIX="$workspace" \
        -DVVDEC_ENABLE_LINK_TIME_OPT='OFF' -DCMAKE_VERBOSE_MAKEFILE='OFF' -DCMAKE_BUILD_TYPE='Release' "${extracommands[@]}"
    execute cmake --build build/release-static -j
    build_done 'freetype' "$gitlab_ver"
fi
cnf_ops+=('--enable-libfreetype')

git_ver_fn 'libsdl-org/SDL' '1' 'R'
if build 'libsdl' "$g_ver"; then
    download "$g_url" "libsdl-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libsdl' "$g_ver"
fi

if $nonfree; then
    git_ver_fn 'Haivision/srt' '1' 'T'
    if build 'srt' "$g_ver"; then
        download "$g_url" "srt-$g_ver.tar.gz"
        export OPENSSL_ROOT_DIR="$workspace"
        export OPENSSL_LIB_DIR="$workspace"/lib
        export OPENSSL_INCLUDE_DIR="$workspace"/include/
        execute cmake . -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
            -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON' -DENABLE_APPS='OFF' -DUSE_STATIC_LIBSTDCXX='ON'
        execute make install

        if [ -n "$LDEXEFLAGS" ]; then
            sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$workspace"/lib/pkgconfig/srt.pc
        fi

        build_done 'srt' "$g_ver"
    fi
        cnf_ops+=('--enable-libsrt')
fi

git_ver_fn '1665' '7'
if build 'libxml2' "$gitlab_ver"; then
    download "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$gitlab_ver/libxml2-v$gitlab_ver.tar.bz2" "libxml2-$gitlab_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libxml2' "$gitlab_ver"
fi
cnf_ops+=('--enable-libxml2')

#####################
## HWaccel library ##
#####################

git_ver_fn 'khronosgroup/opencl-headers' '1' 'R'
if build 'opencl' "$g_ver"; then
    download "$g_url" "opencl-$g_ver.tar.gz"
    execute cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$workspace"
    execute cmake --build build --target install
    build_done 'opencl' "$g_ver"
fi
cnf_ops+=('--enable-opencl')

# Vaapi doesn't work well with static links FFmpeg.
if [ -z "$LDEXEFLAGS" ]; then
    # If the libva development SDK is installed, enable vaapi.
    git_ver_fn 'intel/libva' '1' 'R' 
    if build 'libva' "$g_ver_libva"; then
        download "$g_url" "libva-$g_ver_libva.tar.gz"
        execute ./autogen.sh --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu
        execute make -j "$cpu_threads"
        execute sudo make install
        build_done 'libva' "$g_ver_libva"
    fi

    if build 'vaapi' '1'; then
        build_done 'vaapi' '1'
    fi
    cnf_ops+=('--enable-vaapi')
fi

git_ver_fn 'GPUOpen-LibrariesAndSDKs/AMF' '1' 'T'
if build 'amf' "$g_ver"; then
    download "$g_url" "AMF-$g_ver.tar.gz"
    execute rm -rf "$workspace"/include/AMF
    make_dir "$workspace"/include/AMF
    execute cp -fr "$packages"/AMF-"$g_ver"/amf/public/include/* "$workspace"/include/AMF/
    build_done 'amf' "$g_ver"
fi
cnf_ops+=('--enable-amf')

git_ver_fn 'fraunhoferhhi/vvenc' '1' 'T'
if build 'vvenc' "$g_ver"; then
    download "$g_url" "vvenc-$g_ver.tar.gz"
    execute cmake -S . -B build/release-static -DCMAKE_INSTALL_PREFIX="$workspace" \
        -DVVDEC_ENABLE_LINK_TIME_OPT='OFF' -DCMAKE_VERBOSE_MAKEFILE='OFF' -DCMAKE_BUILD_TYPE='Release'
    execute cmake --build build/release-static -j
    build_done 'vvenc' "$g_ver"
fi
cnf_ops+=('--enable-nvenc')

git_ver_fn 'fraunhoferhhi/vvdec' '1' 'T'
if build 'vvdec' "$g_ver"; then
    download "$g_url" "vvdec-$g_ver.tar.gz"
    execute cmake -S . -B build/release-static -DCMAKE_INSTALL_PREFIX="$workspace" \
        -DVVDEC_ENABLE_LINK_TIME_OPT='OFF' -DCMAKE_VERBOSE_MAKEFILE='OFF' -DCMAKE_BUILD_TYPE='Release'
    execute cmake --build build/release-static -j
    build_done 'vvdec' "$g_ver"
fi
cnf_ops+=('--enable-nvdec')

if which 'nvcc' &>/dev/null ; then
    git_ver_fn 'FFmpeg/nv-codec-headers' '1' 'T'
    if build 'nv-codec' "$g_ver"; then
        download "$g_url" "nv-codec-$g_ver.tar.gz"
        execute make PREFIX="$workspace"
        execute make install PREFIX="$workspace"
        build_done 'nv-codec' "$g_ver"
    fi
    CFLAGS+=' -I/usr/local/cuda-12.1/include'
    LDFLAGS+=' -L/usr/local/cuda-12.1/lib64'
    cnf_ops+=('--enable-cuda-nvcc' '--enable-cuvid' '--enable-cuda-llvm')

    if [ -z "$LDEXEFLAGS" ]; then
        cnf_ops+=('--enable-libnpp')
    fi

    # customize ffmpeg's nvcodec flags to target the exact type of GPU that is being used.
    # this will optimize ffmpeg's code and increase it's overall speed
    gpu_arch_fn

    ##
    ## https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards/
    ##
    cnf_ops+=("--nvccflags=-gencode arch=$gpu_arch")
fi

##
## BUILD FFMPEG
##

# REMOVE ANY FILES FROM PRIOR RUNS
if [ -d "$packages/FFmpeg-$ffmpeg_ver" ]; then
    rm -fr "$packages/FFmpeg-$ffmpeg_ver"
fi

# CLONE FFMPEG FROM THE LATEST GIT RELEASE
build 'ffmpeg' "$ffmpeg_ver"
download "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/$ffmpeg_ver.tar.gz" "FFmpeg-$ffmpeg_ver.tar.gz"
./configure \
    "${cnf_ops[@]}" \
    --disable-debug \
    --disable-doc \
    --disable-shared \
    --enable-pthreads \
    --enable-static \
    --enable-small \
    --enable-version3 \
    --enable-linux-perf \
    --cpu="$cpu_cores" \
    --extra-cflags="$CFLAGS" \
    --extra-ldexeflags="$LDEXEFLAGS" \
    --extra-ldflags="$LDFLAGS" \
    --extra-libs="$EXTRALIBS" \
    --pkgconfigdir="$workspace"/lib/pkgconfig \
    --pkg-config-flags='--static' \
    --prefix="$workspace" \
    --extra-version="$EXTRA_VERSION"

# EXECUTE MAKE WITH PARALLEL PROCESSING
execute make -j "$cpu_threads"
# EXECUTE MAKE INSTALL
execute make install

# MOVE BINARIES TO '/usr/bin'
if ! cp -f "$workspace/bin/ffmpeg" "$install_dir/ffmpeg"; then
    echo "ffmpeg failed to copy to: $install_dir/ffmpeg"
fi
if ! cp -f "$workspace/bin/ffprobe" "$install_dir/ffprobe"; then
    echo "ffprobe failed to copy to: $install_dir/ffprobe"
fi
if ! cp -f "$workspace/bin/ffplay" "$install_dir/ffplay"; then
    echo "ffplay failed to copy to: $install_dir/ffplay"
fi

# DISPLAY FFMPEG'S VERSION
ff_ver_fn
# PROMPT THE USER TO CLEAN UP THE BUILD FILES
cleanup_fn
# DISPLAY A MESSAGE AT THE SCRIPT'S END
exit_fn
