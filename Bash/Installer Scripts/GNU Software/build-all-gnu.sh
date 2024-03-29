#!/usr/bin/env bash

cwd="$PWD/build-all-gnu-master"
web_repo="https://github.com/slyfox1186/script-repo"

if [ ! -d "$cwd/completed" ]; then
    mkdir -p "$cwd/completed"
fi

exit_fn() {
    printf "\n%s\n\n%s\n\n" \
        "Make sure to star this repository to show your support!" \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug create an issue at: $web_repo/issues"
    exit 1
}

cleanup_fn() {
    local answer

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        "============================================" \
        "  Do you want to clean up the build files?  " \
        "============================================" \
        "[1] Yes" \
        "[2] No"
    read -p "Your choices are (1 or 2): " answer

    case "$answer" in
        1)  sudo rm -fr "$cwd" "${0}" ;;
        2)  echo ;;
        *)  printf "\n%s\n\n" "Bad user input. Re-asking question..."
            sleep 3
            clear
            cleanup_fn
            ;;
    esac
}

pkgs=(
    asciidoc autogen autoconf autoconf-archive automake binutils bison build-essential bzip2 ccache cmake
    curl libc6-dev libintl-perl libpth-dev libtool libtool-bin lzip lzma-dev m4 meson nasm ninja-build
    texinfo xmlto yasm zlib1g-dev
)

for i in "${pkgs[@]}"
do
    if ! dpkg -l | grep -q "$i"; then
        missing_pkgs+=("$i")
    fi
done

if [ "${#missing_pkgs[@]}" -ne 0 ]; then
    sudo apt install "${missing_pkgs[@]}"
    sudo apt -y autoremove
    clear
fi

install_scripts_fn() {
    local i
    clear

    for i in *.sh
    do
        if bash "$i"; then
            mv "$i" completed
            printf "\n%s\n\n" "Script finished: $i"
        else
            fail_fn "Failed to install: $i"
        fi
        sleep 2
    done
}

install_choice_fn() {
    local answer

    printf "\n%s\n\n%s\n\n%s\n%s\n\n" \
        "Do you want to install all of the scripts now?" \
        "You must manually remove any scripts you do not want to install before continuing." \
        "[1] Yes" \
        "[2] No"
    read -p "Your choices are (1 or 2): " answer

    case "$answer" in
        1)  install_scripts_fn ;;
        2)  exit_fn ;;
        *)  printf "%s\n\n" "Bad user input... Resetting script."
            sleep 3
            clear
            install_choice_fn
            ;;
    esac
}

cd "$cwd" || exit 1

scripts=(
    attr autoconf bash binutils coreutils dbus diffutils emacs eog gawk gcc gettext-libiconv gnutls grep gzip
    imath isl libtool m4 make nano ncurses nettle pkg-config readline sed systemd tar texinfo wget
)

for script in "${scripts[@]}"
do
    wget --show-progress -cq "https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-${script}"
    mv "build-${script}" "$(printf "%02d" "${#scripts[@]}")-build-${script}"
done

# ASK THE USER IF THEY WANT TO INSTALL ALL OF THE SCRIPTS
install_choice_fn

# CLEANUP THE FILES
cleanup_fn

# SHOW THE EXIT MESSAGE
exit_fn
