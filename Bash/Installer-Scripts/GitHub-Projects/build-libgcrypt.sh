#!/usr/bin/env bash
# shellcheck disable=sc2016,sc2034,sc2046,sc2066,sc2068,sc2086,SC2162,SC2317

##  Install libgcrypt LTS + libgcrypt-error
##  Updated: 07.03.23
##  Script version: 1.1

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables
script_ver="1.1"
version1=$(curl -fsS "https://gnupg.org/ftp/gcrypt/libgcrypt/" | grep -oP 'libgcrypt-\K\d+\.\d+\.\d+' | sort -ruV | head -n1)
version2=$(curl -fsS "https://gnupg.org/ftp/gcrypt/libgpg-error/" | grep -oP 'libgpg-error-\K\d+\.\d+' | sort -ruV | head -n1)
prog_name1="libgcrypt"
prog_name2="libgpg-error"
archive_name1="$prog_name1-$version1"
archive_name2="$prog_name2-$version2"
cwd="$PWD/gcrypt-build-script"
packages="$cwd/packages"
workspace="$cwd/workspace"
debug=OFF

# Create the output directories
mkdir -p "$packages" "$workspace"

# Get cpu core count for parallel processing
if [[ -f /proc/cpuinfo ]]; then
    cpu_threads="$(grep -c ^processor /proc/cpuinfo)"
else
    cpu_threads="$(nproc --all)"
fi

# Set the c + cpp compilers
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export CC CXX CFLAGS CXXFLAGS PATH PKG_CONFIG_PATH

# Print banner
    echo "libgcrypt build script - v$script_ver"
    echo "========================================="
    echo "This script will utilize ($cpu_threads) CPU threads for parallel processing to accelerate the build process."
    echo

# Define functions
fail_fn() {
    echo
    echo "$1"
    echo "You can enable the script's debugging feature by changing the variable 'debug' to 'ON'"
    echo "To report a bug visit: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

exit_function() {
    echo
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    echo
    exit 0
}

cleanup_fn() {
    local choice

    echo
    echo "Do you want to cleanup the build files?"
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choices are (1 or 2): " choice
    clear

    case "$choice" in
        1) sudo rm -fr "$cwd" ;;
        2) ;;
        *)
           unset choice
           echo
           cleanup_fn
           ;;
    esac
}

execute() {
    echo "$ $*"

    if [[ "${debug}" = "ON" ]]; then
        if ! output=$("$@"); then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail_fn "Failed to execute: $*"
        fi
    else
        if ! output=$("$@" 2>&1); then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail_fn "Failed to execute: $*"
        fi
    fi
}

download() {
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

    if [[ -f "$target_file" ]]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! wget -cqO "$target_file" "$dl_url"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! wget -cqO "$target_file" "$dl_url"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit. Line: ${LINENO}"
            fi
        fi
        echo "Download Completed"
    fi

    if [[ -d "$target_dir" ]]; then
        sudo rm -fr "$target_dir"
    fi
    mkdir -p "$target_dir"

    if [[ -n "$3" ]]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: ${LINENO}"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: ${LINENO}"
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: ${LINENO}"
}

build() {
    echo
    echo "building $1 - version $2"
    echo "===================================="

    if [[ -f "$packages/$1.done" ]]; then
        if grep -Fx "$2" "$packages/$1.done" > /dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        else
            echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $packages/$1.done lockfile."
            return 1
        fi
    fi

    return 0
}

build_done() {
    echo "$2" > "$packages/$1.done"
}

installed() {
    return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}')
}

# Install required apt packages
pkgs=(autoconf autoconf-archive autogen automake autotools-dev
      build-essential ccache curl gettext libtool libtool-bin
      m4 pkg-config
)

for pkg in ${pkgs[@]}
do
    if ! installed "${pkg}"; then
        missing_pkgs+=" ${pkg}"
    fi
done

echo "Installing required apt packages"
echo "================================================"

if [[ -n "$missing_pkgs" ]]; then
    sudo apt install $missing_pkgs
    echo "The required APT packages were installed."
else
    echo "The required APT packages are already installed."
fi

# Build libraries from source
if build "libgpg-error" "$version2"; then
    download "https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-$version2.tar.bz2" "libgpg-error-$version2.tar.bz2"
    execute ./autogen.sh
    mkdir build; cd build || exit 1
    execute ../configure --prefix="/usr/local/programs/$archive_name2" \
                         --disable-doc \
                         --disable-nls \
                         --disable-tests \
                         --disable-werror \
                         --enable-maintainer-mode \
                         --enable-static \
                         --enable-threads=posix \
                         --with-libiconv-prefix=/usr \
                         --with-libintl-prefix=/usr \
                         --with-pic
    execute make "-j$cpu_threads"
    execute sudo make install
    execute sudo cp -f "src/gpg-error-config" "$install_dir/bin"
    execute ln -sf "/usr/local/programs/$archive_name2/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    build_done "libgpg-error" "$version2"
fi

if build "libgcrypt" "$version1"; then
    download "https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-$version1.tar.bz2" "libgcrypt-$version1.tar.bz2"
    execute ./autogen.sh
    mkdir build; cd build || exit 1
    ../configure --prefix="/usr/local/programs/libgcrypt-1.11.0" \
                 --enable-static \
                 --with-libgpg-error-prefix="/usr/local/programs/$archive_name2" \
                 --with-pic \
                 CFLAGS="-I/usr/local/programs/$archive_name2/include" \
                 LDFLAGS="-L/usr/local/programs/$archive_name2/lib -lgpg-error"
    execute make "-j$cpu_threads"
    execute sudo make install
fi

# Ldconfig must be run next in order to update file changes or the version commands might not work
sudo ldconfig 2>/dev/null

# Cleanup leftover files
cleanup_fn

# Display exit message
exit_function
