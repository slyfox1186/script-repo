#!/usr/bin/env bash
# shellcheck disable=sc2016,sc2034,sc2046,sc2066,sc2068,sc2086,SC2162,SC2317

##  Install libgcrypt LTS + libgcrypt-error
##  Updated: 10.14.23
##  Script version: 1.0

if [ "$EUID" -eq 0 ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables
script_ver=1.0
install_prefix=/usr/local
cwd="$PWD"/gcrypt-build-script
packages="$cwd"/packages
workspace="$cwd"/workspace
pc_type=$(gcc -dumpmachine)
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
web_repo=https://github.com/slyfox1186/script-repo
debug=OFF

# Create output directories

mkdir -p "$packages" "$workspace"

# Get cpu core count for parallel processing

if [ -f /proc/cpuinfo ]; then
    cpu_threads="$(grep --count ^processor /proc/cpuinfo)"
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
printf "%s\n%s\n%s\n" \
    "libgcrypt build script - v${script_ver}" \
    '=========================================' \
    "This script will utilize (${cpu_threads}) CPU threads for parallel processing to accelerate the build process."


# Define functions

fail_fn() {
    printf "\n%s\n%s\n%s\n\n" \
        "$1" \
        'You can enable the script'\''s debugging feature by changing the variable "debug" to "ON"' \
        "To report a bug visit: $web_repo/issues"
    exit 1
}

exit_function() {
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

cleanup_fn() {
    local choice
 
    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to cleanup the build files?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice
    clear

    case "${choice}" in
        1)      sudo rm -fr "$cwd";;
        2)      clear;;
        *)
                unset choice
                cleanup_fn
                ;;
    esac
}

# Scrape github website for the latest repo version

git_1_fn() {
    local curl_cmd github_repo github_url

    github_repo="$1"
    github_url="$2"

    if curl_cmd="$(curl -A "$user_agent" -m 10 -sSL "https://api.github.com/repos/${github_repo}/${github_url}")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_url="$(echo "$curl_cmd" | jq -r '.[0].tarball_url' 2>/dev/null)"
        g_ver="${g_ver#Cares-}"
        g_ver="${g_ver#Aria2 }"
        g_ver="${g_ver#Nghttp2 v}"
        g_ver="${g_ver#Nghttp3 v}"
        g_ver="${g_ver#OpenSSL }"
        g_ver="${g_ver#Release-}"
        g_ver="${g_ver#V}"
    fi

}

git_ver_fn() {
    local v_flag v_url v_tag url_tag t_url

    v_url="$1"
    v_tag="$2"

    if [ -n "$3" ]; then
        v_flag="$3"
        case "${v_flag}" in
            T)      t_url=tags;;
            R)      t_url=releases;;
            *)      fail_fn 'Failed to pass "tags" and "releases" to the command: curl_cmd.';;
        esac
    fi

    git_1_fn "${v_url}" "${t_url}" 2>/dev/null
}

execute() {
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

build() {
    printf "\n%s\n%s\n" \
        "building $1 - version $2" \
        '===================================='

    if [ -f "$packages/$1.done" ]; then
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
      build-essential ccache curl libtool libtool-bin m4 pkg-config)

for pkg in ${pkgs[@]}
do
    if ! installed "${pkg}"; then
        missing_pkgs+=" ${pkg}"
    fi
done

printf "\n%s\n%s\n" \
    'Installing required apt packages' \
    '================================================'

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
    sudo apt -y autoremove
    printf "%s\n" 'The required APT packages were installed.'
else
    printf "%s\n" 'The required APT packages are already installed.'
fi

# Build libraries from source

if build 'libgpg-error' '1.47'; then
    download 'https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.47.tar.bz2' 'libgpg-error-1.47.tar.bz2'
    execute ./autogen.sh
    execute ./configure --prefix="$install_prefix" \
                        --{build,host}="${pc_type}"  \
                        --disable-doc                \
                        --disable-nls                \
                        --disable-tests              \
                        --disable-werror             \
                        --enable-maintainer-mode     \
                        --enable-static              \
                        --enable-threads=posix       \
                        --with-libiconv-prefix=/usr  \
                        --with-libintl-prefix=/usr   \
                        --with-pic
    execute make "-j${cpu_threads}"
    execute sudo make install
    execute sudo cp -f 'src/gpg-error-config' "$install_prefix"/bin
    build_done 'libgpg-error' '1.47'
fi

if build 'libgcrypt' '1.8.10-LTS'; then
    download 'https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.8.10.tar.bz2' 'libgcrypt-1.8.10-LTS.tar.bz2'
    execute ./autogen.sh
    ./configure --prefix="$install_prefix"                   \
                --{build,host}="${pc_type}"                    \
                --enable-static                                \
                --with-libgpg-error-prefix="$install_prefix" \
                --with-pic
    execute make "-j${cpu_threads}"
    execute sudo make install
    build_done 'libgcrypt' '1.8.10-LTS'
fi

# Ldconfig must be run next in order to update file changes or the version commands might not work
sudo ldconfig 2>/dev/null

# Cleanup leftover files
cleanup_fn

# Display exit message
exit_function
