#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-all-gnu-safer-arch-script
##  Purpose: Loops multiple build scripts to optimize efficiency. This is the safer of the two scripts.
##  Updated: 11.06.23
##  Script version: 1.0

if [[ "$EUID" -eq 0 ]]; then
    printf "%s\n\n" 'You must run this script WITHOUT root/sudo.'
    exit 1
fi

script_ver=1.0
cwd="$PWD/build-all-gnu-safer-arch-script"

[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd/completed" "$cwd/failed"
cd "$cwd" || exit 1

# Print the script banner
echo "Build All GNU Safer ArchLinux Script - version $script_ver"
echo "============================================================"
echo
sleep 2

exit_fn() {
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail_fn() {
    echo
    echo "$1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

pkgs=(
    asciidoc autogen autoconf autoconf-archive automake binutils bison base-devel bzip2
    ccache cmake curl glibc perl-libintl-perl libtool lzip m4 meson nasm ninja texinfo
    xmlto xz yasm zlib
)

for pkg in ${pkgs[@]}; do
    missing_pkg="$(sudo pacman -Qi | grep -o "$pkg")"

    if [[ -z "$missing_pkg" ]]; then
        missing_pkgs+=" $pkg"
    fi
done

if [[ -n "$missing_pkgs" ]]; then
    sudo pacman -Sq --needed --noconfirm $missing_pkgs
fi

scripts=(
    pkg-config m4 autoconf autoconf-archive
    libtool bash make sed tar gawk grep nano
    wget
)
cnt=0

for script in ${scripts[@]}; do
    ((cnt++))
    wget -U "$user_agent" --show-progress -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-${script}"
    mv "build-$script" "0$cnt-build-${script}.sh" 2>/dev/null
done

# Rename files with numbers 10 and higher so they execute in the intended order
scripts=(tar gawk grep nano wget)
cnt=9

for i in 1; do
    for script in ${scripts[@]}; do
        ((cnt++)) # << start counting here
        mv "0$cnt-build-$script" "$cnt-build-$script" 2>/dev/null # << move the files, thus renaming them
    done
done

clear

for file in $(ls -v); do
    if echo "1" | bash "$file"; then
        mv "$file" "completed"
    else
        mv "$file" "failed"
    fi
done

# Cleanup leftover files
sudo rm -fr "$cwd"

# Display exit message
exit_fn
