#!/usr/bin/env bash
# Shellcheck disable=sc2162,sc2317

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-python2
##  Purpose: Install Python2 - version 2.7.18
##  Updated: 10.26.23
##  Script version: 1.0

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the script variables
script_ver=1.0
py_ver=2.7.18
archive_dir="python2-${py_ver}"
archive_url="https://www.python.org/ftp/python/2.7.18/Python-${py_ver}.tar.xz"
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.${archive_ext}"
install_dir=/usr/local
working="$PWD/python2-build-script"

# Start the python2 build
echo "Python2 Build Script -- version ${script_ver}"
echo "==============================================="
echo

# Create the output directory
if [ -d "$working" ]; then
    sudo rm -fr "$working"
fi
mkdir -p "$working"

# Set the c & cpp compilers
export CC=gcc CXX=g++

# Set the compiler optimization flags

CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
CPPFLAGS="-I/usr/local/include -I/usr/include"
export CFLAGS CXXFLAGS CPPFLAGS

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PATH PKG_CONFIG_PATH

# Create functions
exit_function()
{
    printf "\n%s\n\n%s\n%s\n\n"                                   \
        'The script has completed!'                               \
        'Make sure to star this repository to show your support!' \
        "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail_fn()
{
    printf "\n\n%s\n\n%s\n\n%s\n\n"                              \
        "$1"                                                   \
        'Please create a support ticket so I can work on a fix.' \
        "https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

show_ver_fn()
{
    clear
    python_ver="$(python2 -c 'import sys; print(sys.version)' | grep -Eo '^[0-9\.]+')"
    printf "%s\n\n" "The installed python2 version is: ${python_ver}"
}

cleanup_fn()
{
    local answer

    printf "%s\n\n%s\n%s\n\n"                    \
        'Do you want to remove the build files?' \
        '[1] Yes'                                \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer

    case "${answer}" in
        1)      sudo rm -fr "$working";;
        2)      return 0;;
        *)
                clear
                unset answer
                cleanup_fn
                ;;
    esac
}

installed() { return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

pkgs_fn()
{
    clear

    pkgs=("$1" autoconf autoconf-archive autogen automake binutils build-essential ccache
          curl git itstool libb2-dev libexempi-dev libgnome-desktop-3-dev libhandy-1-dev
          libpeas-dev libpeasd-3-dev libtool libtool-bin m4 packaging-dev python3 valgrind
          yasm zlib1g-dev)

    for pkg in ${pkgs[@]}
    do
        if ! installed "${pkg}"; then
            missing_pkgs+=" ${pkg}"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        printf "%s\n%s\n\n"                   \
            'Installing missing APT packages' \
            '======================================'
        for i in "$missing_pkgs"
            do
                if ! sudo apt install ${i}; then
                    fail_fn "Failed to install the following APT packages: ${i}. Line: ${LINENO}"
                fi
            done
    else
        printf "%s\n\n" '$ The APT packages are already installed.'
    fi
}

# Install required apt packages

install_libportal_fn()
{
    if ! wget --show-progress -t 2 -cqO 'https://github.com/flatpak/libportal/releases/download/0.7.1/libportal-0.7.1.tar.xz'; then
        clear
        printf "%s\n\n" "Failed to download the libportal archive file. Line: ${LINENO}"
        exit 1
    fi
    mkdir libportal-0.7.1
    tar -xf libportal-0.7.1.tar.xz -C libportal-0.7.1 --strip-components 1
    cd libportal-0.7.1 || exit 1
    meson setup build --prefix=/usr/local      \
                      --buildtype=release      \
                      --default-library=static \
                      --strip                  \
                      -Dc_args="${CFLAGS}"     \
                      -Dcpp_args="${CXXFLAGS}"
    ninja "-j$(nproc --all)" -C build
    sudo ninja "-j$(nproc --all)" -C build install
}

debian_os_version()
{
    case "${VER}" in
        12|trixie)      pkgs_fn 'libgnome-desktop-4-dev libportal-dev libportal-gtk3-dev libportal-gtk4-dev';;
        10|11)
                        pkgs_fn 'libgnome-desktop-3-dev'
                        install_libportal_fn
                        ;;
        *)              fail_fn "Could not detect the Debian version. Line: ${LINENO}";;
    esac
}

# Test the os and its version

find_lsb_release="$(sudo find /usr -type f -name 'lsb_release')"

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

if [ -z "${VER}" ]; then
    VER="${CODENAME}"
fi

case "${OS}" in
    'Debian'|'n/a')     debian_os_version;;
    'Ubuntu')           pkgs_fn;;
    *)                  fail_fn "Could not detect the OS architecture. Line: ${LINENO}";
esac

# Download the archive file

if [ ! -f "$working/${archive_name}" ]; then
    curl -A "$user_agent" -Lso "$working/${archive_name}" "${archive_url}"
fi

# Create the output directory

if [ -d "$working/$archive_dir" ]; then
    sudo rm -fr "$working/$archive_dir"
fi
mkdir -p "$working/$archive_dir/build"

# Extract the archive files

if ! tar -xf "$working/${archive_name}" -C "$working/$archive_dir" --strip-components 1; then
    fail_fn "Failed to extract: $working/${archive_name}. Line: ${LINENO}"
    exit 1
fi

# Store file paths in variables for use with the configure script

libm_lib="$(sudo find /usr/lib/ -type f -name libm.so | head -n1)"
libc_lib="$(sudo find /usr/lib/ -type f -name libc.so | head -n1)"

# Build the program from source code

cd "$working/$archive_dir/build" || exit 1
../configure --prefix="$install_dir"          \
             --{build,host,target}="${pc_type}" \
             --disable-ipv6                     \
             --disable-profiling                \
             --enable-optimizations             \
             --with-ensurepip=install           \
             --with-libc="${libc_lib}"          \
             --with-libm="${libm_lib}"          \
             --with-lto                         \
             --with-pth                         \
             --with-pymalloc                    \
             --with-valgrind                    \
             CFLAGS="${CFLAGS}"                 \
             CXXFLAGS="${CXXFLAGS}"             \
             CPPFLAGS="${CPPFLAGS}"             \
             LDFLAGS="${LDFLAGS}"

no_optimize_fn()
{
    if ! make "-j$(nproc --all)" build_all; then
        printf "\n%s\n\n" "Failed to execute: make -j$(nproc --all) build_all. Line: ${LINENO}"
        exit 1
    fi
    if ! sudo make "-j$(nproc --all)" install; then
        printf "\n%s\n\n" "Failed to execute: make -j$(nproc --all) install. Line: ${LINENO}"
        exit 1
    fi
}

optimize_fn()
{
    if ! make "-j$(nproc --all)"; then
        printf "\n%s\n\n" "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
        exit 1
    fi
    if ! sudo make "-j$(nproc --all)" install; then
        printf "\n%s\n\n" "Failed to execute: make -j$(nproc --all) install. Line: ${LINENO}"
        exit 1
    fi
}

optimize_prompt_fn()
{
    local choice
    clear

    printf "%s\n%s\n\n"                                                   \
        'Do you want to optimize the code by running the compiler tests?' \
        'Doing so will increase the overall compile time.'
    read -p '[Y]es or [N]o: ' choice
    clear

    case "${choice}" in
        Y|y)     optimize_fn;;
        N|n)     no_optimize_fn;;
        *)
                unset choice
                optimize_prompt_fn
                ;;
    esac
}
optimize_prompt_fn

# Show the new version
show_ver_fn

# Prompt the user to clean up the build files
cleanup_fn

# Show the exit message
exit_function
