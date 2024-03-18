#!/Usr/bin/env bash


clear

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

script_ver=1.0
cwd="$PWD"/build-all-gnu-safer-arch-script
web_repo=https://github.com/slyfox1186/script-repo
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'

if [ -d "$cwd" ]; then
    sudo rm -fr "$cwd"
fi
mkdir -p "$cwd"/completed "$cwd"/failed

cd "$cwd" || exit 1


printf "%s\n%s\n\n"                                      \
    "Build All GNU Safer ArchLinux Script - version $script_ver" \
    '============================================================'
sleep 2

exit_fn() {
    printf "\n%s\n\n%s\n\n"                                       \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n%s\n\n%s\n\n" \
        "$1"              \
        "To report a bug create an issue at: $web_repo/issues"
    exit 1
}

pkgs=(asciidoc autogen autoconf autoconf-archive automake binutils bison base-devel bzip2
      ccache cmake curl glibc perl-libintl-perl libtool lzip m4 meson nasm ninja texinfo
      xmlto xz yasm zlib)

for i in ${pkgs[@]}
do
    missing_pkg="$(sudo pacman -Qi | grep -o "$i")"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+=" $i"
    fi
done

if [ -n "$missing_pkgs" ]; then
    for pkg in "${missing_pkgs[@]}"
    do
        sudo pacman -Sq --noconfirm $pkg
    done
    clear
fi

scripts=(pkg-config m4 autoconf autoconf-archive libtool bash make sed tar gawk grep nano wget)
cnt=0

for script in ${scripts[@]}
do
    let cnt=cnt+1
    wget -U "$user_agent" --show-progress -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-$script"
    mv "build-$script" "0$cnt-build-$script"'.sh' 2>/dev/null
done
unset cnt script scripts

scripts=(tar gawk grep nano wget)
cnt=9

for i in 1
do
    for script in ${scripts[@]}
    do
    done
done

clear

for file in $(ls -v)
do
    if echo '1' | bash "$file"; then
        mv "$file" 'completed'
    else
        mv "$file" 'failed'
    fi
done

sudo rm -fr "$cwd"

exit_fn