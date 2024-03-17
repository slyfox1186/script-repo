#!/usr/bin/env bash


if [ "$EUID" -eq 0 ]; then
    printf "%s\n\n" 'You must run this script WITHOUT root/sudo.'
    exit 1
fi


script_ver=1.0
progname="$0"
cwd="$PWD"/nasm-build-script
install_prefix=/usr/local
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
web_repo=https://github.com/slyfox1186/script-repo


if [ -d "$cwd" ]; then
    sudo rm -fr "$cwd"
fi
mkdir -p "$cwd"


export CC=gcc CXX=g++


export {CFLAGS,CXXFLAGS}='-g -O3 -pipe -march=native'


if [ -f /proc/cpuinfo ]; then
    cpu_threads="$(grep --count ^processor /proc/cpuinfo)"
else
    cpu_threads="$(nproc --all)"
fi

PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin:\
/usr/local/games:\
/usr/games:\
/snap/bin\
"
export PATH

PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig:\
/lib64/pkgconfig:\
/lib/pkgconfig\
"
export PKG_CONFIG_PATH


exit_fn() {
    printf "\n%s\n\n%s\n%s\n\n"                                    \
        'The script has completed'                                \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n\n%s\n\n%s\n\n%s\n\n"      \
        "$1"                           \
        'To report a bug please visit: ' \
        "$web_repo/issues"
    exit 1
}

cleanup_fn() {
    local choice

    printf "%s\n\n%s\n%s\n\n"                    \
        'Do you want to remove the build files?' \
        '[1] Yes'                                \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice

    case "$choice" in
        1)      sudo rm -fr "$cwd";;
        2)      clear;;
        *)
                clear
                printf "%s\n\n" 'Error: bad user input. Reverting script...'
                sleep 3
                unset choice
                clear
                cleanup_fn
                ;;
    esac
}

execute() {
    echo "$ ${*}"

    if [ "$debug" = 'ON' ]; then
        if ! output="$("$@")"; then
            notify-send -t 5000 "Failed to execute: ${*}" 2>/dev/null
            fail_fn "Failed to execute: ${*}"
        fi
    else
        if ! output="$("$@" 2>&1)"; then
            notify-send -t 5000 "Failed to execute: ${*}" 2>/dev/null
            fail_fn "Failed to execute: ${*}"
        fi
    fi
}

build() {
    printf "\n%s\n%s\n" \
        "Building $1 - version $2" \
        '=========================================='

    if [ -f "$cwd/$1.done" ]; then
        if grep -Fx "$2" "$cwd/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $cwd/$1.done lockfile to rebuild it."
            return 1
        fi
    fi
    return 0
}

build_done() { echo "$2" > "$cwd/$1.done"; }

download() {
    dl_path="$cwd"
    dl_url="$1"

    if [[ "$dl_file" =~ tar. ]]; then
        output_dir="${dl_file%.*}"
        output_dir="${3:-"${output_dir%.*}"}"
    else
        output_dir="${3:-"${dl_file%.*}"}"
    fi

    target_file="$dl_path/$dl_file"
    target_dir="$dl_path/$output_dir"

    if [ -f "$target_file" ]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! wget --show-progress -t 2 -cqO "$target_file" "$dl_url"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! wget --show-progress -t 2 -cqO "$target_file" "$dl_url"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit. Line: $LINENO"
            fi
        fi
        printf "\n%s\n\n" 'Download completed'
    fi

    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    fi

    mkdir -p "$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: $LINENO"
}

git_1_fn() {
    local curl_cmd github_repo github_url

    github_repo="$1"
    github_url="$2"

    if curl_cmd="$(curl -m 10 -sSL "https://api.github.com/repos/$github_repo/$github_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[1].name' 2>/dev/null)"
        g_url="$(echo "$curl_cmd" | jq -r '.[1].tarball_url' 2>/dev/null)"
    fi
}

git_ver_fn() {
    local t_flag v_flag v_url

    v_url="$1"
    v_flag="$2"

    case "$v_flag" in
            R)      t_flag=releases;;
            T)      t_flag=tags;;
    esac

    git_1_fn "$v_url" "$t_flag" 2>/dev/null
}


pkgs=(autoconf autoconf-archive automake autopoint binutils binutils-dev bison
      build-essential ccache clang cmake curl jq libc6 libc6-dev libedit-dev
      libtool libtool-bin libxml2-dev m4 nasm ninja-build yasm zlib1g-dev)

for i in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "$i")"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+=" $i"
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
    clear
else
    printf "%s\n" 'The APT packages are already installed'
fi


box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner "Nasm Build Script - version $script_ver"

if build 'nasm' '2.16.01'; then
    download 'https://www.nasm.us/pub/nasm/stable/nasm-2.16.01.tar.xz'
    execute ./autogen.sh
    execute ./configure --prefix=/usr/local                \
                        --enable-ccache
    execute make "-j$cpu_threads"
    execute sudo make install
fi

cleanup_fn

exit_fn
