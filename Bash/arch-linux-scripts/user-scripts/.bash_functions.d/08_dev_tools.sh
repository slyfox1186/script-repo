#!/usr/bin/env bash
# Development Tools Functions

## TEST GCC & CLANG ##
test_gcc() {
    local choice random_dir

    # CREATE A TEMPORARY C FILE TO RUN OUR TESTS AGAINST
    random_dir=$(mktemp -d)
    cat > "$random_dir/hello.c" <<'EOF'
#include <stdio.h>
int main(void)
{
   printf("Hello World!\n");
   return 0;
}
EOF

    if [[ -n "$1" ]]; then
        "$1" -Q -v "$random_dir/hello.c"
    else
        read -r -p "Enter the GCC binary you wish to test (example: gcc-11): " choice
        echo
        "$choice" -Q -v "$random_dir/hello.c"
    fi
    sudo rm -fr "$random_dir"
}

test_clang() {
    local choice random_dir

    # CREATE A TEMPORARY C FILE TO RUN OUR TESTS AGAINST
    random_dir=$(mktemp -d)
    cat > "$random_dir/hello.c" <<'EOF'
#include <stdio.h>
int main(void)
{
   printf("Hello World!\n");
   return 0;
}
EOF

    if [[ -n "$1" ]]; then
        "$1" -v "$random_dir/hello.c" -o "$random_dir/hello" && "$random_dir/hello"
    else
        read -r -p "Enter the Clang binary you wish to test (example: clang-11): " choice
        echo
        "$choice" -v "$random_dir/hello.c" -o "$random_dir/hello" && "$random_dir/hello"
    fi
    sudo rm -fr "$random_dir"
}

gcc_native() {
    echo "Checking GCC default target..."
    gcc -dumpmachine

    echo "Checking GCC version..."
    gcc --version

    echo "Inspecting GCC verbose output for -march=native..."
    # Create a temporary empty file
    local temp_source
    temp_source=$(mktemp /tmp/dummy_source.XXXXXX.c)
    trap 'rm -f "$temp_source"' EXIT

    # Using echo to create an empty file
    echo "" > "$temp_source"

    # Using GCC with -v to get verbose information, including the default march
    gcc -march=native -v -E "$temp_source" 2>&1 | grep -- '-march='
}

## CMAKE commands
c_cmake() {
    local dir
    if ! sudo dpkg -l | grep -q cmake-curses-gui; then
        sudo apt -y install cmake-curses-gui
    fi
    echo

    if [[ -z "$1" ]]; then
        read -r -p "Enter the relative source directory: " dir
    else
        dir=$1
    fi

    cmake "$dir" -B build -G Ninja -Wno-dev
    ccmake "$dir"
}

########################
## PKG-CONFIG COMMAND ##
########################

# SHOW THE PATHS PKG-CONFIG COMMAND SEARCHES BY DEFAULT
pkg-config-path() {
    clear
    pkg-config --variable pc_path pkg-config | tr ":" "\n"
}

######################################
## SHOW BINARY RUNPATH IF IT EXISTS ##
######################################

show_rpath() {
    local binary find_rpath
    clear

    if [[ -z "$1" ]]; then
        read -r -p "Enter the full path to the binary/program: " find_rpath
    else
        find_rpath="$1"
    fi

    clear
    if ! binary=$(command -v -- "$find_rpath"); then
        printf 'Command not found: %s\n' "$find_rpath" >&2
        return 1
    fi
    sudo chrpath -l "$binary"
}

## SHELLCHECK ##
sc() {
    local file
    local -a files

    if (($# == 0)); then
        read -r -a files -p "Input the file path(s) to check: "
        echo
    else
        files=("$@")
    fi

    for file in "${files[@]}"; do
        box_out_banner "Parsing: $file"
        echo
        shellcheck --color=always -x --severity=warning --source-path="$PATH:$HOME/tmp:/etc:/usr/local/lib64:/usr/local/lib:/usr/local64:/usr/lib:/lib64:/lib:/lib32" "$file"
        echo
    done
}

# Python Virtual Environment
venv() {
    local choice random_dir
    local -a package_names venv_args
    random_dir=$(mktemp -d)
    if ! wget -cqO "$random_dir/pip-venv-installer.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/Python3/pip-venv-installer.sh"; then
        rm -rf -- "$random_dir"
        return 1
    fi

    case "$#" in
        0)
            printf "\n%s\%s\%s\%s\%s\%s\%s\%s\%s\%s\n\n" \
                "[h]elp" \
                "[l]ist" \
                "[i]mport" \
                "[c]reate" \
                "[u]pdate" \
                "[d]elete" \
                "[a]dd" \
                "[U]pgrade" \
                "[r]emove" \
                "[p]ath"
            read -r -p "Choose a letter: " choice
            case "$choice" in
                h) venv_args=(-h) ;;
                l) venv_args=(-l) ;;
                i) venv_args=(-i) ;;
                c) venv_args=(-c) ;;
                u) venv_args=(-u) ;;
                d) venv_args=(-d) ;;
                a|U|r)
                    read -r -a package_names -p "Enter package names (space-separated): "
                    venv_args=("-$choice" "${package_names[@]}")
                    ;;
                p) venv_args=(-p) ;;
                *)
                    clear
                    rm -rf -- "$random_dir"
                    return 1
                    ;;
            esac
            ;;
        *)
            venv_args=("$@")
            ;;
    esac

    bash "$random_dir/pip-venv-installer.sh" "${venv_args[@]}"
    local status
    status=$?
    rm -rf -- "$random_dir"
    return "$status"
}

#################
## PYTHON3 PIP ##
#################

pipu() {
    pipua "$@"
}

pipua() {
    local outdated_json package_names
    local -a packages

    if ! outdated_json=$(pip list --outdated --exclude-editable --format=json); then
        return 1
    fi

    if ! package_names=$(/home/jman/miniconda3/bin/python -c '
import json
import sys

for package in json.load(sys.stdin):
    print(package["name"])
' <<< "$outdated_json"); then
        printf '%s\n' 'pipua: failed to parse the list of outdated packages' >&2
        return 1
    fi

    if [[ -z "$package_names" ]]; then
        printf '%s\n' 'All non-editable packages are up to date.'
        return 0
    fi

    # Resolve all upgrades together, then verify the installed dependency set.
    mapfile -t packages <<< "$package_names"
    pip install --upgrade -- "${packages[@]}" || return
    pip check
}

######################################
## DOWNLOAD CLANG INSTALLER SCRIPTS ##
######################################

dl_clang() {
    clear
    if [[ ! -d "$HOME/tmp" ]]; then
        mkdir -p "$HOME/tmp"
    fi
    wget --show-progress -cqO "$HOME/tmp/build-clang-16" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-16"
    wget --show-progress -cqO "$HOME/tmp/build-clang-17" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-17"
    sudo chmod rwx "$HOME/tmp/build-clang-16" "$HOME/tmp/build-clang-17"
    sudo chown "$USER":"$USER" "$HOME/tmp/build-clang-16" "$HOME/tmp/build-clang-17"
    clear
    ls -1AvhF--color --group-directories-first
}

######################################
## DOWNLOAD IMPORTANT BUILD SCRIPTS ##
######################################

gitdl() {
    clear
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/build-ffmpeg"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/build-magick"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/repo.sh"
    sudo chmod -R build-gcc build-magick build-ffmpeg repo.sh -- *
    sudo chown -R "$USER:$USER" build-gcc build-magick build-ffmpeg repo.sh
    clear
    ls -1AvhF --color --group-directories-first
}

dlfs() {
    local file
    local -a scripts
    clear

    wget --show-progress -qN - -i "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/favorite-installer-scripts.txt"

    scripts=(build-ffmpeg build-all-git-safer build-all-gnu-safer build-magick)

    for file in "${scripts[@]}"; do
        chown -R "$USER:$USER" "$file"
        chmod -R 744 "$PWD" "$file"
        if [[ $file == "build-all-git-safer" || $file == "build-all-gnu-safer" ]]; then
            mv "$file" "${file%-safer}"
        fi
    done
    rm -f -- "favorite-installer-scripts.txt"

    clear
    ls -1AhFv --color --group-directories-first
}

# GitHub Script-Repo Script Menu
script_repo() {
  local opt
  local -a command_args options

  echo "Select a script to install:"
  options=(
    [1]="Linux Build Menu"
    [2]="Build All GNU Scripts"
    [3]="Build All GitHub Scripts"
    [4]="Install GCC Latest Version"
    [5]="Install Clang"
    [6]="Install Latest 7-Zip Version"
    [7]="Install ImageMagick 7"
    [8]="Compile FFmpeg from Source"
    [9]="Install OpenSSL Latest Version"
    [10]="Install Rust Programming Language"
    [11]="Install Essential Build Tools"
    [12]="Install Aria2 with Enhanced Configurations"
    [13]="Add Custom Mirrors for /etc/apt/sources.list"
    [14]="Customize Your Shell Environment"
    [15]="Install Adobe Fonts System-Wide"
    [16]="Debian Package Downloader"
    [17]="Install Tilix"
    [18]="Install Python 3.12.0"
    [19]="Update WSL2 with the Latest Linux Kernel"
    [20]="Enhance GParted with Extra Functionality"
    [21]="Quit"
  )

  select opt in "${options[@]}"; do
    case "$opt" in
      "Linux Build Menu")
        bash <(curl -fsSL "https://build-menu.optimizethis.net")
        break
        ;;
      "Build All GNU Scripts")
        bash <(curl -fsSL "https://build-all-gnu.optimizethis.net")
        break
        ;;
      "Build All GitHub Scripts")
        bash <(curl -fsSL "https://build-all-git.optimizethis.net")
        break
        ;;
      "Install GCC Latest Version")
        wget --show-progress -cqO build-gcc.sh "https://gcc.optimizethis.net"
        sudo bash build-gcc.sh
        break
        ;;
      "Install Clang")
        wget --show-progress -cqO build-clang.sh "https://build-clang.optimizethis.net"
        sudo bash build-clang.sh --help
        echo
        read -r -a command_args -p "Enter your chosen arguments: (e.g. -c -v 17.0.6): "
        sudo bash build-clang.sh "${command_args[@]}"
        break
        ;;
      "Install Latest 7-Zip Version")
        bash <(curl -fsSL "https://7z.optimizethis.net")
        break
        ;;
      "Install ImageMagick 7")
        wget --show-progress -cqO build-magick.sh "https://imagick.optimizethis.net"
        sudo bash build-magick.sh
        break
        ;;
      "Compile FFmpeg from Source")
        ffs --help || return
        read -r -a command_args -p "Builder arguments (e.g. --build --enable-gpl-and-non-free --latest): " || return 1
        ffs "${command_args[@]}" || return
        break
        ;;
      "Install OpenSSL Latest Version")
        wget --show-progress -cqO build-openssl.sh "https://ossl.optimizethis.net"
        echo
        read -r -a command_args -p "Enter arguments for OpenSSL (e.g., '-v 3.1.5'): "
        sudo bash build-openssl.sh "${command_args[@]}"
        break
        ;;
      "Install Rust Programming Language")
        bash <(curl -fsSL "https://rust.optimizethis.net")
        break
        ;;
      "Install Essential Build Tools")
        wget --show-progress -cqO build-tools.sh "https://build-tools.optimizethis.net"
        sudo bash build-tools.sh
        break
        ;;
      "Install Aria2 with Enhanced Configurations")
        sudo wget --show-progress -cqO build-aria2.sh "https://aria2.optimizethis.net"
        sudo bash build-aria2.sh
        break
        ;;
      "Add Custom Mirrors for /etc/apt/sources.list")
        bash <(curl -fsSL "https://mirrors.optimizethis.net")
        break
        ;;
      "Customize Your Shell Environment")
        bash <(curl -fsSL "https://user-scripts.optimizethis.net")
        break
        ;;
      "Install Adobe Fonts System-Wide")
        bash <(curl -fsSL "https://adobe-fonts.optimizethis.net")
        break
        ;;
      "Debian Package Downloader")
        wget --show-progress -cqO debian-package-downloader.sh "https://download.optimizethis.net"
        echo
        read -r -a command_args -p "Enter apt package name(s) (e.g., clang-15): "
        sudo bash debian-package-downloader.sh "${command_args[@]}"
        break
        ;;
      "Install Tilix")
        wget --show-progress -cqO build-tilix.sh "https://tilix.optimizethis.net"
        sudo bash build-tilix.sh
        break
        ;;
      "Install Python 3.12.0")
        wget --show-progress -cqO build-python3.sh "https://python3.optimizethis.net"
        sudo bash build-python3.sh
        break
        ;;
      "Update WSL2 with the Latest Linux Kernel")
        wget --show-progress -cqO build-wsl2-kernel.sh "https://wsl.optimizethis.net"
        sudo bash build-wsl2-kernel.sh
        break
        ;;
      "Enhance GParted with Extra Functionality")
        bash <(curl -fsSL "https://gparted.optimizethis.net")
        break
        ;;
      "Quit")
        break
        ;;
      *) echo "Invalid option $REPLY";;
    esac
  done
}

# The master script download menu for github repository script-repo
dlmaster() {
    local script_path="/usr/local/bin/download-master.py"
    local script_url="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/download-master.py"

    # Check if the script exists
    if [[ ! -f "$script_path" ]]; then
        echo "The required script does not exist. Downloading now."
        # Download the script
        sudo wget --show-progress -cqO "$script_path" "$script_url"
        # Set the owner to root and permissions to 755
        sudo chown root:root "$script_path"
        sudo chmod 755 "$script_path"
        echo "The required script was successfully installed."
        sleep 3
        clear
    fi

    # Run the script
    python3 "$script_path"
}
