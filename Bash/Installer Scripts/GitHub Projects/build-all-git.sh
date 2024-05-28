#!/usr/bin/env bash

cwd="$PWD/build-all-git-master"

if [ ! -d "$cwd"/completed ]; then
    mkdir -p "$cwd"/completed
fi

exit_function() {
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail() {
    echo
    echo "[ERROR] $1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    echo
    exit 1
}

cleanup() {
    local choice

    echo
    echo "============================================"
    echo "  Do you want to clean up the build files?  "
    echo "============================================"
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p 'Your choices are (1 or 2): ' choice
    echo

    case "${choice}" in
        1) sudo rm -fr "$cwd" "$0" ;;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

pkgs=(asciidoc autogen autoconf autoconf-archive automake binutils bison
      build-essential bzip2 ccache cmake curl libc6-dev libintl-perl
      libpth-dev libtool libtool-bin lzip lzma-dev m4 meson nasm ninja-build
      texinfo xmlto yasm zlib1g-dev)

for pkg in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+="$pkg "
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt-get update
    sudo apt-get install $missing_pkgs
    echo
fi

install_scripts() {
    local script scripts

    scripts="$(sudo find ./ -maxdepth 1 -type f | sort -V)"

    for script in ${scripts[@]}; do
        if bash "$script"; then
            sudo find ./ -maxdepth 1 -type f -name "$script" -exec mv {} completed \;
            echo
            echo "Successfully completed $script"
            echo
        else
            fail "Failed to install $script"
        fi
        sleep 2
    done
}

install_choice() {
    echo
    echo "Do you want to install all of the scripts now?"
    echo "You MUST manually remove any scripts you do not want to install before continuing."
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p 'Your choices are (1 or 2): ' choice
    echo

    case "$choice" in
        1) install_scripts ;;
        2) ;;
        *) unset choice
           install_choice
           ;;
    esac
}

# Download all of the git-project scripts and number them ascending starting with one
cd "$cwd" || exit 1

scripts=(aria2 brotli clang-16 garbage-collector git libpng
         libxml2 nasm openssl python3 wsl2-kernel yasm zlib
         zstd)
count=0

for script in ${scripts[@]}; do
    ((count++))
    wget --show-progress -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-${script}.sh"
    mv "build-${script}" "0$count-build-${script}"
done

# Rename all scripts that start with the number 10 and higher so they execute in the intended order
files=(openssl python3 terminator-terminal tools wsl2-kernel yasm zlib zstd)
count=9

for i in 1; do
    for file in ${files[@]}; do
        ((count++)) # << start counting here
        mv "0$count-build-${file}" "$count-build-${file}" # << move the files, thus renaming them
    done
done

# Ask the user if they want to install all of the scripts
install_choice

# Cleanup the files
cleanup

# Show the exit message
exit_function
