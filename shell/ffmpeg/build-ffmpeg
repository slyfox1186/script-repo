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

# verify the script does not have root access before continuing
if [ "${EUID}" -eq '0' ]; then
    echo 'You must run this script without root/sudo'
    echo
    exec bash "$0" "$@"
fi

##
## define variables
##

script_ver='3.2'
progname="${0:2}"
ffmpeg_ver='6.0'
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
## set the available cpu count for parallel processing (speeds up the build process)
##

if [ -f '/proc/cpuinfo' ]; then
    cpus="$(grep -c processor '/proc/cpuinfo')"
else
    cpus="$(nproc --all)"
fi

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
        remove_dir "$packages"
        remove_dir "$workspace"
        remove_file "$0"
        echo 'cleanup finished.'
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
                echo 'Please create a support ticket'
                echo
                echo 'https://github.com/slyfox1186/script-repo/issues'
                echo
                exit 1
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
            echo "Failed to extract $dl_file"
            echo
            exit 1
        fi
    else
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" --strip-components 1 &>/dev/null; then
            echo "Failed to extract $dl_file"
            echo
            exit 1
        fi
    fi

    echo "File extracted: $dl_file"

    cd "$dl_path/$target_dir" || (
        echo 'Script error!'
        echo
        echo "Unable to change the working directory to $target_dir"
        echo
        exit 1
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
    curl_cmd=$(curl -m "$net_timeout" -sSL "https://api.github.com/repos/$github_repo/$github_url?per_page=1")
    if [ "$?" -eq '0' ]; then
        g_ver=$(echo "$curl_cmd" | jq -r '.[0].name')
        g_ver=${g_ver#v}
        g_ver_ssl=$(echo "$curl_cmd" | jq -r '.[0].name')
        g_ver_ssl=${g_ver_ssl#OpenSSL }
        g_ver_pkg=$(echo "$curl_cmd" | jq -r '.[0].name')
        g_ver_pkg=${g_ver_pkg#pkg-config-}
        g_url=$(echo "$curl_cmd" | jq -r '.[0].tarball_url')
    fi
}

git_2_fn()
{
    videolan_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" \
        -sSL "https://code.videolan.org/api/v4/projects/$videolan_repo/repository/branches?"); then
        videolan_ver=$(echo "$curl_cmd" | jq -r '.[0].commit.id')
        videolan_sver=$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')
    fi
}

git_3_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" \
        -sSL "https://gitlab.com/api/v4/projects/$gitlab_repo/repository/branches?"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[3].commit.id')
        gitlab_ver=${gitlab_ver#v}
        gitlab_sver=$(echo "$curl_cmd" | jq -r '.[3].commit.short_id')
    fi
}

git_4_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" \
        -sSL "https://gitlab.com/api/v4/projects/$gitlab_repo/repository/tags"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name'  )
        gitlab_ver=${gitlab_ver#v}
        gitlab_sver=$(echo "$curl_cmd" | jq -r '.[3].commit.short_id')
    fi
}

git_5_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" \
        -sSL "https://gitlab.freedesktop.org/api/v4/projects/$gitlab_repo/repository/tags?"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name')
    fi
}

git_6_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$net_timeout" \
        -sSL 'https://bitbucket.org/!api/2.0/repositories/multicoreware/x265_git/effective-branching-model')"; then
        gitlab_ver=$(echo "$curl_cmd" | jq '.development.branch.target' | grep -Eo '[0-9a-z][0-9a-z]+' | sort | head -n 1)
    fi
}

git_7_fn()
{
    gitlab_repo="$1"
    if curl_cmd=$(curl -m "$net_timeout" \
        -sSL "https://gitlab.gnome.org/api/v4/projects/$gitlab_repo/repository/tags?"); then
        gitlab_ver=$(echo "$curl_cmd" | jq -r '.[0].name')
        gitlab_ver=${gitlab_ver#v}
    fi
}

git_ver_fn()
{
    local v_tag v_url

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
    fi

    if [  "$v_flag" = 'R' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn'; gv_url='releases'
    fi

    case "$v_flag" in
        2)          url_tag='git_2_fn';;
        3)          url_tag='git_3_fn';;
        4)          url_tag='git_4_fn';;
        5)          url_tag='git_5_fn';;
        6)          url_tag='git_6_fn';;
        7)          url_tag='git_7_fn';;
    esac

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

execute()
{
    echo "$ $*"

    if ! output=$("$@" 2>&1); then
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
    echo "Unable to locate directory: /usr/local/cuda-$cuda_ver/bin/"
    echo
    read -p 'Press enter to exit.'
    clear
    fail_fn
}

gpu_arch_fn()
{
    local gpu_ans

    echo
    echo ' Tune the build to match your specific Nvidia GPU which will maximize the performance output'
    echo '============================================================================================='
    echo
    echo 'Please select your GPU'\''s architecture.'
    echo
    echo '[1] Pascal   | Geforce GTX [1030, 1050, 1060, 1070, 1080] GT [1010, Titan Xp, Tesla P40, Tesla P4, Discrete GPU on the NVIDIA Drive PX2]'
    echo '[2] Volta    | Geforce GTX [1180, Titan V] Quadro [GV100] Tesla [V100]'
    echo '[3] Turing   | Geforce GTX [1660 Ti] Geforce RTX [2060, 2070, 2080, Titan] Quadro RTX [4000, 5000, 6000, 8000, T1000/T2000, Tesla T4]'
    echo '[4] Ampere   | Geforce RTX [3050, 3060, 3070, 3080, 3090, A2000, A3000, A4000, A5000, A6000]'
    echo '[5] Lovelace | Geforce RTX [4080, 4090, 6000]'
    echo '[6] Hopper   | GH100'
    echo

    read -p 'Your choices are (1 to 6): ' gpu_ans

    if [[ "$gpu_ans" -eq '1' ]]; then
        gpu_arch='compute_61,code=sm_61'
    elif [[ "$gpu_ans" -eq '2' ]]; then
        gpu_arch='compute_70,code=sm_70'
    elif [[ "$gpu_ans" -eq '3' ]]; then
        gpu_arch='compute_75,code=sm_75'
    elif [[ "$gpu_ans" -eq '4' ]]; then
        gpu_arch='compute_86,code=sm_86'
    elif [[ "$gpu_ans" -eq '5' ]]; then
        gpu_arch='compute_89,code=sm_89'
    elif [[ "$gpu_ans" -eq '6' ]]; then
        gpu_arch='compute_90,code=sm_90'
    else
        echo
        echo 'Error: Bad user input.'
        echo
        echo 'Press enter to start over.'
        clear
        gpu_arch_fn
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
        exit 1
        ;;
    esac
done

if [ -z "$bflag" ]; then
    if [ -z "$cflag" ]; then
        usage
        echo
        exit 1
    fi
    exit 0
fi

echo "The script will utilize $cpus CPU cores for parallel processing to accelerate the build speed."
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
JAVA_HOME='/usr/lib/jvm/java-19-openjdk-amd64/bin'
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
$workspace/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig:\
/usr/lib64/pkgconfig\
"
export PKG_CONFIG_PATH

LD_LIBRARY_PATH="$workspace\lib\pkgconfig"
export LD_LIBRARY_PATH

if ! command_exists 'make'; then
    echo 'The '\''make'\'' package is not installed. It is required for this script to run.'
    echo
    exit 1
fi

if ! command_exists 'g++'; then
    echo 'The '\''g++'\'' package is not installed. It is required for this script to run.'
    echo
    exit 1
fi

if ! command_exists 'curl'; then
    echo 'The '\''curl'\'' package is not installed. It is required for this script to run.'
    echo
    exit 1
fi

if ! command_exists 'jq'; then
    echo 'The '\''jq'\'' package is not installed. It is required for this script to run.'
    echo
    exit 1
fi

if ! command_exists 'cargo'; then
    echo 'The '\''cargo'\'' command was not found. rav1e encoder will not be available.'
fi

if ! command_exists 'python3'; then
    echo 'The '\''python3'\'' command was not found. The '\''Lv2'\'' filter and '\''dav1d'\'' decoder will not be available.'
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
        sudo cp /var/cuda-repo-debian11-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
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
    if [ ! -d "/usr/local/cuda-$cuda_ver/bin" ]; then
        cuda_fail_fn
    else
        PATH="$PATH:/usr/local/cuda-$cuda_ver/bin"
        export PATH
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

    pkgs=(ant g++ gcc gtk-doc-tools help2man javacc jq junit \
          libcairo2-dev libcdio-paranoia-dev libcurl4-gnutls-dev \
          libglib2.0-dev libmusicbrainz5-dev libtinyxml2-dev \
          libudfread-dev openjdk-19-jdk pkg-config ragel)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        for pkg in "$missing_pkgs"
        do
            sudo apt install $pkg
        done
        echo 'The required development packages were installed.'
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

    if ! which 'nvcc' &>/dev/null ; then
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
            if [ -d '/usr/local/cuda-12.1/bin' ]; then
                PATH="$PATH:/usr/local/cuda-12.1/bin"
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
if build 'giflib' '5.2.1'; then
    download 'https://netcologne.dl.sourceforge.net/project/giflib/giflib-5.2.1.tar.gz'
    cd "$packages"/giflib-5.2.1 || exit 1
    # PARELLEL BUILDING NOT AVAILABLE FOR THIS LIBRARY
    execute make
    execute make PREFIX="$workspace" install
    build_done 'giflib' '5.2.1'
fi

git_ver_fn 'freedesktop/pkg-config' '1' 'T'
if build 'pkg-config' "${g_ver_pkg}"; then
    download "https://pkgconfig.freedesktop.org/releases/$g_ver.tar.gz" "$g_ver.tar.gz"
    execute ./configure --silent --prefix="$workspace" --with-pc-path="$workspace"/lib/pkgconfig/ --with-internal-glib
    execute make "-j$cpus"
    execute make install
    build_done 'pkg-config' "${g_ver_pkg}"
fi

git_ver_fn 'yasm/yasm' '1' 'T'
if build 'yasm' "$g_ver"; then
    download "https://github.com/yasm/yasm/releases/download/v$g_ver/yasm-$g_ver.tar.gz" "yasm-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace"
    execute make "-j$cpus"
    execute make install
    build_done 'yasm' "$g_ver"
fi

if build 'nasm' '2.16.02rc1'; then
    https://github.com/netwide-assembler/nasm/archive/refs/tags/nasm-2.16.02rc1.tar.gz
    download "https://www.nasm.us/pub/nasm/releasebuilds/2.16.02rc1/nasm-2.16.02rc1.tar.xz" "nasm-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
    execute make install
    build_done 'nasm' '2.16.02rc1'
fi

git_ver_fn 'madler/zlib' '1' 'T'
if build 'zlib' "$g_ver"; then
    download "$g_url" "zlib-$g_ver"
    execute ./configure --static --prefix="$workspace"
    execute make "-j$cpus"
    execute make install
    build_done 'zlib' "$g_ver"
fi

if build 'm4' '1.4.19'; then
    download 'https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz'
    execute ./configure --prefix="$workspace"
    execute make "-j$cpus"
    execute make install
    build_done 'm4' '1.4.19'
fi

if build 'autoconf' '2.71'; then
    download 'https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.xz'
    execute ./configure --prefix="$workspace"
    execute make "-j$cpus"
    execute make install
    build_done 'autoconf' '2.71'
fi

if build 'automake' '1.16.5'; then
    download 'https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.xz'
    execute ./configure --prefix="$workspace"
    execute make "-j$cpus"
    execute make install
    build_done 'automake' '1.16.5'
fi

if build 'libtool' '2.4.7'; then
    download 'https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz'
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make "-j$cpus"
    execute make install
    build_done 'libtool' '2.4.7'
fi

if $nonfree; then
    git_ver_fn 'openssl/openssl' '1' 'R'
    if build 'openssl' "$g_ver_ssl"; then
        download "$g_url" "openssl-$g_ver_ssl.tar.gz"
        execute ./config --prefix="$workspace" --openssldir="$workspace" \
            --with-zlib-include="$workspace"/include/ --with-zlib-lib="$workspace"/lib no-shared zlib
        execute make "-j$cpus"
        execute make install_sw
        build_done 'openssl' "$g_ver_ssl"
    fi
    cnf_ops+=('--enable-openssl')
else
    if build 'gmp' '6.2.1'; then
        download 'https://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make "-j$cpus"
        execute make install
        build_done 'gmp' '6.2.1'
    fi

    if build 'nettle' '3.8.1'; then
        download 'https://ftp.gnu.org/gnu/nettle/nettle-3.8.1.tar.gz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-openssl \
            --disable-documentation --libdir="$workspace"/lib CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make "-j$cpus"
        execute make install
        build_done 'nettle' '3.8.1'
    fi

    if build 'gnutls' '3.8.0'; then
        download 'https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.0.tar.xz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-doc --disable-tools \
            --disable-cxx --disable-tests --disable-gtk-doc-html --disable-libdane --disable-nls --enable-local-libopts \
            --disable-guile --with-included-libtasn1 --with-included-unistring --without-p11-kit CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make "-j$cpus"
        execute make install
        build_done 'gnutls' '3.8.0'
    fi
    cnf_ops+=('--enable-gmp' '--enable-gnutls')
fi

git_ver_fn 'Kitware/CMake' '1' 'T'
if build 'cmake' "$g_ver"; then
    download "$g_url" "cmake-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --parallel="$cpus" -- -DCMAKE_USE_OPENSSL='OFF'
    execute make "-j$cpus"
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
            if ! command_exists ${r}; then
                execute pip3 install ${r} --quiet --upgrade --no-cache-dir --disable-pip-version-check
            fi
            export PATH="$PATH:${HOME}/Library/Python/3.9/bin"
        done
    fi
    if command_exists 'meson'; then
        git_ver_fn '198' '2'
        if build 'dav1d' "$videolan_sver"; then
            download "https://code.videolan.org/videolan/dav1d/-/archive/$videolan_ver/$videolan_ver.tar.gz" "dav1d-$videolan_sver.tar.gz"
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
    cd "$PWD/Build/linux" || exit 1
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' ../.. -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE='Release' -DENABLE_EXAMPLES='OFF'
    execute make "-j$cpus"
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
        execute ./configure --prefix="$workspace" --enable-static --enable-pic CXXFLAGS="-fPIC ${CXXFLAGS}"
        execute make "-j$cpus"
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
        echo '$ making 12bit binaries'
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
            -DHIGH_BIT_DEPTH='ON' -DENABLE_HDR10_PLUS='ON' -DEXPORT_C_API='OFF' -DENABLE_CLI='OFF' -DMAIN12='ON'
        execute make "-j$cpus"
        echo '$ making 10bit binaries'
        cd ../'10bit' || exit 1
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' \
            -DBUILD_SHARED_LIBS='OFF' -DHIGH_BIT_DEPTH='ON' -DENABLE_HDR10_PLUS='ON' -DEXPORT_C_API='OFF' -DENABLE_CLI='OFF'
        execute make "-j$cpus"
        echo '$ making 8bit binaries'
        cd ../'8bit' || exit 1
        ln -sf ../'10bit/libx265.a' 'libx265_main10.a'
        ln -sf ../'12bit/libx265.a' 'libx265_main12.a'
        execute cmake ../../../'source' -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
            -DEXTRA_LIB='x265_main10.a;x265_main12.a;-ldl' -DEXTRA_LINK_FLAGS='-L.' -DLINKED_10BIT='ON' -DLINKED_12BIT='ON'
        execute make "-j$cpus"
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

        if [ -n "$LDEXEFLAGS" ]; then sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$workspace"/lib/pkgconfig/x265.pc; fi

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
    execute make "-j$cpus"
    execute make install    
    build_done 'SVT-HEVC' "$g_ver"
fi

git_ver_fn 'webmproject/libvpx' '1' 'T'
if build 'libvpx' "$g_ver"; then
    download "$g_url" "libvpx-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --disable-unit-tests --disable-shared --disable-examples --as='yasm'
    execute make "-j$cpus"
    execute make install
    build_done 'libvpx' "$g_ver"
fi
cnf_ops+=('--enable-libvpx')

if $nonfree; then
    if build 'xvidcore' '1.3.7'; then
        download 'https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.bz2'
        cd 'build/generic' || exit 1
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make "-j$cpus"
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
        download "https://github.com/georgmartius/vid.stab/archive/refs/tags/v$g_ver.tar.gz" "vid.stab-$g_ver.tar.gz"
        execute cmake -DBUILD_SHARED_LIBS='OFF' -DCMAKE_INSTALL_PREFIX="$workspace" -DUSE_OMP='OFF' -DENABLE_SHARED='OFF' .
        execute make "-j$cpus"
        execute make install
        build_done 'vid_stab' "$g_ver"
    fi
    cnf_ops+=('--enable-libvidstab')
fi

if build 'av1' '3.6.0'; then
    download 'https://aomedia.googlesource.com/aom/+archive/3c65175b1972da4a1992c1dae2365b48d13f9a8d.tar.gz' 'av1-3.6.0.tar.gz' 'av1'
    make_dir "$packages"/aom_build
    cd "$packages"/aom_build || exit 1
    execute cmake -DENABLE_TESTS='0' -DENABLE_EXAMPLES='0' -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' "$packages"/av1
    execute make "-j$cpus"
    execute make install
    build_done 'av1' '3.6.0'
fi
cnf_ops+=('--enable-libaom')

git_ver_fn 'sekrit-twc/zimg' '1' 'T'
if build 'zimg' "$g_ver"; then
    download "$g_url" "zimg-$g_ver.tar.gz"
    execute "$workspace"/bin/libtoolize -i -f -q
    execute ./autogen.sh --prefix="$workspace"
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make "-j$cpus"
    execute make install
    build_done 'zimg' "$g_ver"
fi
cnf_ops+=('--enable-libzimg')

git_ver_fn 'AOMediaCodec/libavif' '1' 'R'
if build 'avif' "$g_ver"; then
    download "$g_url" "avif-$g_ver.tar.gz"
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
        -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' -DENABLE_STATIC='ON' -DAVIF_ENABLE_WERROR='OFF' \
        -DAVIF_CODEC_DAV1D='ON' "$avif_tag" -DAVIF_CODEC_AOM='ON' -DAVIF_BUILD_APPS='ON'
    execute make "-j$cpus"
    execute make install
    build_done 'avif' "$g_ver"
fi

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
        if build 'waflib' 'aeef9f5f'; then
            download 'https://gitlab.com/drobilla/autowaf/-/archive/aeef9f5fdf416d9b68c61c75de7dae409f1ac6a4/autowaf-aeef9f5fdf416d9b68c61c75de7dae409f1ac6a4.tar.bz2' 'autowaf-aeef9f5f.tar.bz2'
            build_done 'waflib' 'aeef9f5f'
        fi
        if build 'serd' '61d53637'; then
            download 'https://gitlab.com/drobilla/serd/-/archive/61d53637dc62d15f9b3d1fa9e69891313c465c35/serd-61d53637dc62d15f9b3d1fa9e69891313c465c35.tar.bz2' 'serd-61d53637.tar.bz2'
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'serd' '61d53637'
        fi
        if build 'pcre' '8.45'; then
            download 'https://cfhcable.dl.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.bz2' 'pcre-8.45.tar.bz2'
            execute ./configure --prefix="$workspace" --disable-shared --enable-static
            execute make "-j$cpus"
            execute make install
            build_done 'pcre' '8.45'
        fi
        if build 'zix' '262d4a15'; then
            download 'https://gitlab.com/drobilla/zix/-/archive/262d4a1522c38be0588746e874159da5c7bb457d/zix-262d4a1522c38be0588746e874159da5c7bb457d.tar.bz2' 'zix-262d4a15.tar.gz'
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'zix' '262d4a15'
        fi
        if build 'sord' '0.16.14'; then
            download 'http://download.drobilla.net/sord-0.16.14.tar.xz' 'sord-0.16.14.tar.gz'
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'sord' '0.16.14'
        fi
        if build 'sratom' 'b1643412'; then
            download 'https://gitlab.com/lv2/sratom/-/archive/b1643412ef03f41fc174f076daff39ade0999bf2/sratom-b1643412ef03f41fc174f076daff39ade0999bf2.tar.bz2'  'sratom-b1643412.tar.bz2'
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'sratom' 'b1643412'
        fi
        git_ver_fn '11853176' '4'
        if build 'lilv' "$gitlab_ver"; then
            download "https://gitlab.com/lv2/lilv/-/archive/v0.24.20/lilv-v0.24.20.tar.gz" "lilv-0.24.20.tar.gz"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'lilv' "$gitlab_ver"
        fi
        CFLAGS+=" -I$workspace/include/lilv-0"
        cnf_ops+=('--enable-lv2')
    fi
fi

if build 'opencore' '0.1.6'; then
    download 'https://netactuate.dl.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.6.tar.gz' 'opencore-amr-0.1.6.tar.gz'
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
    execute make install
    build_done 'opencore' '0.1.6'
fi
cnf_ops+=('--enable-libopencore_amrnb' '--enable-libopencore_amrwb')

if build 'lame' '3.100'; then
    download 'https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download?use_mirror=gigenet' 'lame-3.100.tar.gz'
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
    execute make install
    build_done 'lame' '3.100'
fi
cnf_ops+=('--enable-libmp3lame')

git_ver_fn 'xiph/opus' '1' 'T'
if build 'opus' "$g_ver"; then
    download "$g_url" "opus-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
    execute make install
    build_done 'opus' "$g_ver"
fi
cnf_ops+=('--enable-libopus')

git_ver_fn 'xiph/ogg' '1' 'T'
if build 'libogg' "$g_ver"; then
    download "$g_url" "libogg-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
    execute make install
    build_done 'libogg' "$g_ver"
fi

git_ver_fn 'xiph/vorbis' '1' 'T'
if build 'libvorbis' "$g_ver"; then
    download "$g_url" "libvorbis-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --with-ogg-libraries="$workspace"/lib \
        --with-ogg-includes="$workspace"/include/ --enable-static --disable-shared --disable-oggtest
    execute make "-j$cpus"
    execute make install
    build_done 'libvorbis' "$g_ver"
fi
cnf_ops+=('--enable-libvorbis')

if build 'libtheora' '1.1.1'; then
    download 'https://github.com/xiph/theora/archive/refs/tags/v1.1.1.tar.gz' 'libtheora-1.1.1.tar.gz'
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
    execute make "-j$cpus"
    execute make install
    build_done 'libtheora' '1.1.1'
fi
cnf_ops+=('--enable-libtheora')

if $nonfree; then
    git_ver_fn 'mstorsjo/fdk-aac' '1' 'T'
    if build 'fdk_aac' "$g_ver"; then
        download "https://github.com/mstorsjo/fdk-aac/archive/refs/tags/v$g_ver.tar.gz" "fdk_aac-$g_ver.tar.gz"
        execute ./autogen.sh
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --enable-pic --bindir="$workspace"/bin CXXFLAGS=' -fno-exceptions -fno-rtti'
        execute make "-j$cpus"
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
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
    execute make install
    build_done 'libtiff' "$gitlab_ver"
fi

git_ver_fn '7950' '5'
if build 'freetype' "$gitlab_ver"; then
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/$gitlab_ver/freetype-$gitlab_ver.tar.bz2" "freetype-$gitlab_ver.tar.bz2"
    execute ./autogen.sh
    make_dir build
    execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
    execute ninja -C build
    execute ninja -C build install
    build_done 'freetype' "$gitlab_ver"
fi

if build 'libpng' "$g_ver"; then
    download "$g_url" "libpng-$g_ver.tar.gz"
    export LDFLAGS="$LDFLAGS"
    export CPPFLAGS="$CFLAGS"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
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
    execute make "-j$cpus"
    execute make install
    build_done 'libwebp' '1.2.2'
fi
cnf_ops+=('--enable-libwebp')

##
## other libraries
##

git_ver_fn '206' '2'
if build 'libbluray' "$videolan_sver"; then
    download "https://code.videolan.org/videolan/libbluray/-/archive/$videolan_ver/$videolan_ver.tar.gz" "libbluray-$videolan_sver.tar.gz"
    execute autoreconf -fiv
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
    execute make install
    build_done 'libbluray' "$videolan_sver"
fi
unset JAVA_HOME
cnf_ops+=('--enable-libbluray')

git_ver_fn 'mediaarea/zenLib' '1' 'R'
if build 'zenLib' "$g_ver"; then
    download "$g_url" "zenLib-$g_ver.tar.gz"
    cd "$PWD"/Project/CMake || exit 1
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
        -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON'
    execute make "-j$cpus"
    execute make install
    build_done 'zenLib' "$g_ver"
fi

git_ver_fn 'MediaArea/MediaInfoLib' '1' 'R'
if build 'MediaInfoLib' "$g_ver"; then
    download "$g_url" "MediaInfoLib-$g_ver.tar.gz"
    cd "$PWD"/Project/CMake || exit 1
    execute cmake . -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
        -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON' -DENABLE_APPS='OFF' \
        -DUSE_STATIC_LIBSTDCXX='ON' -DBUILD_ZLIB='OFF' -DBUILD_ZENLIB='OFF'
    execute make install
    build_done 'MediaInfoLib' "$g_ver"
fi

git_ver_fn 'MediaArea/MediaInfo' '1' 'T'
if build 'MediaInfoCLI' "$g_ver"; then
    download "$g_url" "MediaInfoCLI-$g_ver.tar.gz"
    cd "$PWD"/Project/GNU/CLI || exit 1
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

if build 'c2man' 'current'; then
    download_git 'https://github.com/fribidi/c2man.git' 'c2man'
    execute ./Configure -des
    execute make depend
    execute make "-j$cpus"
    execute sudo make install
    build_done 'c2man' 'current'
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

git_ver_fn 'libass/libass' '1' 'T'
if build 'libass' "$g_ver"; then
    download "$g_url" "libass-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
    execute make install
    build_done 'libass' "$g_ver"
fi
cnf_ops+=('--enable-libass')

git_ver_fn '7950' '5'
if build 'freetype' "$gitlab_ver"; then
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/$gitlab_ver/freetype-$gitlab_ver.tar.bz2" "freetype-$gitlab_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
    execute make install
    build_done 'freetype' "$gitlab_ver"
fi

git_ver_fn 'libsdl-org/SDL' '1' 'R'
if build 'libsdl' "$g_ver"; then
    download "$g_url" "libsdl-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make "-j$cpus"
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

#####################
## HWaccel library ##
#####################

git_ver_fn 'khronosgroup/opencl-headers' '1' 'R'
if build 'opencl' "$g_ver"; then
    CFLAGS+=" -DLIBXML_STATIC_FOR_DLL -DNOLIBTOOL"
    download "$g_url" "opencl-$g_ver.tar.gz"
    execute cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$workspace"
    execute cmake --build build --target install
    build_done 'opencl' "$g_ver"
fi
cnf_ops+=('--enable-opencl')

# Vaapi doesn't work well with static links FFmpeg.
if [ -z "$LDEXEFLAGS" ]; then
    # If the libva development SDK is installed, enable vaapi.
    if library_exists 'libva'; then
        if build 'vaapi' '1'; then
            build_done 'vaapi' '1'
        fi
        cnf_ops+=('--enable-vaapi')
    fi
fi

git_ver_fn 'GPUOpen-LibrariesAndSDKs/AMF' '1' 'T'
if build 'amf' "$g_ver"; then
    download "$g_url" "AMF-$g_ver.tar.gz"
    execute rm -rf "$workspace"/include/AMF
    execute mkdir -p "$workspace"/include/AMF
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

    gpu_arch_fn

    # https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards/
    cnf_ops+=("--nvccflags=-gencode arch=$gpu_arch")
fi

##
## BUILD FFMPEG
##

# REMOVE ANY FILES FROM PRIOR RUNS
if [ -d "$packages/ffmpeg-$ffmpeg_ver" ]; then
    rm -fr "$packages/ffmpeg-$ffmpeg_ver"
fi

# CLONE FFMPEG FROM THE LATEST GIT RELEASE
build 'ffmpeg' "$ffmpeg_ver"
download "https://github.com/FFmpeg/FFmpeg/archive/refs/heads/release/$ffmpeg_ver.tar.gz" "FFmpeg-release-$ffmpeg_ver.tar.gz"
./configure \
    "${cnf_ops[@]}" \
    --disable-debug \
    --disable-doc \
    --disable-shared \
    --enable-pthreads \
    --enable-static \
    --enable-small \
    --enable-version3 \
    --cpu="$cpus" \
    --extra-cflags="$CFLAGS" \
    --extra-ldexeflags="$LDEXEFLAGS" \
    --extra-ldflags="$LDFLAGS" \
    --extra-libs="$EXTRALIBS" \
    --pkgconfigdir="$workspace"/lib/pkgconfig \
    --pkg-config-flags='--static' \
    --prefix="$workspace" \
    --extra-version="$EXTRA_VERSION"

# EXECUTE MAKE WITH PARALLEL PROCESSING
execute make "-j$cpus"
# EXECUTE MAKE INSTALL
execute make install

# MOVE BINARIES TO '/usr/bin'
if which 'sudo' &>/dev/null; then
    sudo cp -f "$workspace/bin/ffmpeg" "$install_dir/ffmpeg"
    sudo cp -f "$workspace/bin/ffprobe" "$install_dir/ffprobe"
    sudo cp -f "$workspace/bin/ffplay" "$install_dir/ffplay"
else
    cp -f "$workspace/bin/ffmpeg" "$install_dir/ffmpeg"
    cp -f "$workspace/bin/ffprobe" "$install_dir/ffprobe"
    cp -f "$workspace/bin/ffplay" "$install_dir/ffplay"
fi

# CHECK THAT FILES WERE COPIED TO THE INSTALL DIRECTORY
if [ ! -f "$install_dir/ffmpeg" ]; then
    echo "Failed to copy: ffmpeg to $install_dir/"
fi
if [ ! -f "$install_dir/ffprobe" ]; then
    echo "Failed to copy: ffprobe to $install_dir/"
fi
if [ ! -f "$install_dir/ffplay" ]; then
    echo "Failed to copy: ffplay to $install_dir/"
fi

# DISPLAY FFMPEG'S VERSION
ff_ver_fn
# PROMPT THE USER TO CLEAN UP THE BUILD FILES
cleanup_fn
# DISPLAY A MESSAGE AT THE SCRIPT'S END
exit_fn
