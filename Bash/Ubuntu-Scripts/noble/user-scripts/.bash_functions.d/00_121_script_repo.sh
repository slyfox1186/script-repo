#!/usr/bin/env bash

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
        git clone "https://github.com/slyfox1186/ffmpeg-build-script.git"
        cd ffmpeg-build-script || return 1
        clear
        sudo ./build-ffmpeg.sh -h
        read -r -a command_args -p "Enter your chosen arguments: (e.g. --build --gpl-and-nonfree --latest): "
        sudo ./build-ffmpeg.sh "${command_args[@]}"
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
