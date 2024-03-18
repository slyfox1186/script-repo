# Slys Script Repository
## A mix of my favorite scripts for both Windows and Linux.

### Included languages
 -   [x] AutoHotkey
 -   [x] Batch
 -   [x] Powershell
 -   [x] Python 3
 -   [x] Shell / Bash
 -   [x] Visual Basic / VBS
 -   [x] Windows Registry
 -   [x] XML
------

## Updated 10.16.23
  - Added Arch Linux support to some of the build scripts. Additional scripts will be converted to add this support in the future
### OS Support
  - Arch Linux
  - Debian 11/12
  - Ubuntu (22/20/18).04

### Why this repository exists:
1. This repository was created as a way to share my custom scripts
2. Make the scripts publicly available with the hope that they are beneficial to others
3. Spark ideas for better and more efficient ways of coding that lead to an overall improvement in the efficiency and usefulness of each script
4. Have a centralized zone where users can access the scripts they need quickly and efficiently

## Build Menu
  - All of the below Linux installers are located in one menu.
```bash
bash <(curl -fsSL https://build-menu.optimizethis.net)
```
------

## Build All GNU Scripts
  - Master script to build all GNU scripts at once
```bash
bash <(curl -fsSL https://build-all-gnu.optimizethis.net)
```
------

## Build All GitHub Scripts
  - Master script to build all GitHub project scripts at once
```bash
bash <(curl -fsSL https://build-all-git.optimizethis.net)
```
------

## Install [GCC](https://github.com/gcc-mirror/gcc) versions latest
  - **Sourced from the official GitHub repository**
  - **For personal/testing use only**
  - **Check the top of the script for build [results](https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc)**
  - **Supported OS:**
    - Ubuntu - (20/22/23).04
    - Debian - 11/12
    - Other Debian-based distros may work as well

#### For native Linux systems (Windows WSL not working)
```bash
curl -fsSLo build-gcc.sh https://gcc.optimizethis.net
sudo bash build-gcc.sh
```
## Install [Clang-17](https://github.com/llvm/llvm-project)
  - **Automatically finds the latest release version and installs clang from source code.**
```bash
curl -fsSLo build-clang.sh https://clang.optimizethis.net
sudo bash build-clang.sh
```
------

## Install [7-Zip](www.7-zip.org/download.html)
  - **Installs the latest static version of 7-Zip based on your PC's processor and architecture**
    - **Arch**         - **i386** | **x86_x64**
    - **Processor**    - **Linux** | **ARM**
### v23.01 Release
```bash
curl -fsSLo install-7zip.sh https://7zip.optimizethis.net
sudo bash install-7zip.sh
```
------

## Install [ImageMagick 7](https://github.com/ImageMagick/ImageMagick)
  - **Sourced from the most recent release on the official Git**
  - **Tested on Windows WSL 2 Debian/Ubuntu**
  - **[Optimize JPG Images](https://github.com/slyfox1186/script-repo/tree/main/Bash/Installer%20Scripts/ImageMagick/scripts)**
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04
    - Other Debian-based distros may work as well
  
```bash
curl -fsSLo build-magick.sh https://imagick.optimizethis.net
sudo bash build-magick.sh
```
------

## Install [FFmpeg](https://ffmpeg.org/download.html)
  - **Compiles the latest updates from source code by issuing API calls to each repositories backend**
  - **The CUDA SDK Toolkit which unlocks Hardware Acceleration is available during the installation to make things as easy as possible**
  -  **See my dedicated FFmpeg build page for more info: [ffmpeg-build-script](https://github.com/slyfox1186/ffmpeg-build-script)**
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04 / 23.04
    - Other Debian-based distros may work as well

**With GPL and <ins>non-free</ins> libraries: https://ffmpeg.org/legal.html**
```bash
git clone https://github.com/slyfox1186/ffmpeg-build-script.git
cd ffmpeg-build-script || exit
sudo bash build-ffmpeg.sh --build --enable-gpl-and-non-free --latest
```
------

## Install [OpenSSL](https://www.openssl.org/source/)
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04
    - Other Debian-based distros may work as well
  - **Pass arguments to the script**
    - -h|--help) : Display the help menu
    - -6|--enable-ipv6) : Enables IPV6 (Default disabled)
    - -j|--jobs) : Sets the number of parallel jobs to use
    - -k|--keep-build) : Keep the build files after the script finishes
    - -p|--prefix) : Set the prefix location to install the OpenSSL
    - -v|--version) : Build other versions.
      - To build OpenSSL version 3.1.5 pass this to the script: **build-openssl.sh -v 3.1.5**

```bash
curl -fsSLo build-openssl.sh https://ossl.optimizethis.net
sudo bash build-openssl.sh
````
------

## Install [Rust](https://github.com/rust-lang/rust)
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04
    - Other Debian-based distros may work as well

```bash
bash <(curl -fsSL https://rust.optimizethis.net)
````
------

## Install [CMake](https://cmake.org/), [Ninja](https://github.com/ninja-build/ninja), [Meson](https://github.com/mesonbuild/meson) & [Golang](https://github.com/golang/go)
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04
    - Other Debian-based distros may work as well

```bash
bash <(curl -fsSL https://build-tools.optimizethis.net)
````
------

## Install [Aria2](https://github.com/aria2/aria2)
  - Updated to version 1.37.0
  - Aria2 max connections increased from 16 to 64
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04
    - Other Debian-based distros may work as well

```bash
sudo curl -fsSLo /tmp/aria2 https://aria2.optimizethis.net
sudo bash /tmp/aria2
````
------

## Add custom mirrors to: /etc/apt/sources.list
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04 / 23.04

**Warning! This will overwrite your files!**
```bash
bash <(curl -fsSL https://mirrors.optimizethis.net)
```
------

## Add custom user scripts to the user's home directory
  - **Files included**
  - .bashrc
  - .bash_aliases
  - .bash_functions

**Warning! This will overwrite your files!**
```bash
bash <(curl -fsSL https://user-scripts.optimizethis.net)
```
------

## Install Adobe Fonts system-wide
  - **Sourced from the official GitHub [repository](https://github.com/adobe-fonts/)**
```bash
bash <(curl -fsSL https://adobe-fonts.optimizethis.net)
```
------

## Quick Install **apt-fast**
```bash
bash -c "$(curl -fsSL https://git.io/vokNn)"
```
------

## Change your network settings to Static or DHCP with netplan.io
  - The user will be prompted to enter the network settings
```bash
bash <(curl -fsSL https://static-ip.optimizethis.net)
```
------

## Debian Package Downloader
  - Download APT packages to your PC by entering a space-separated list of values.
  - Input a single entry or an entire list of APT packages and the script will download its respective .deb file to the current directory.
```bash
bash <(curl -fsSL https://download.optimizethis.net)
```

## Install [Tilix](https://github.com/gnunn1/tilix) Advanced Terminal with custom color themes
  - Dracula theme included + many others
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04
    - Other Debian-based distros may work as well
```bash
bash <(curl -fsSL https://tilix.optimizethis.net)
````
------

## Install [Python3](https://devguide.python.org/getting-started/setup-building/#get-the-source-code) v3.12.0
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04
    - Other Debian-based distros may work as well

```bash
bash <(curl -fsSL https://python3.optimizethis.net)
````
------

## Install the [WSL2](https://github.com/microsoft/WSL2-Linux-Kernel) latest kernel release from [Linux](https://github.com/torvalds/linux)
  - **Supported OS:**
    - Debian - 11/12
    - Ubuntu - (20/22/23).04
    - Other Debian-based distros may work as well

```bash
bash <(curl -fsSL https://wsl2-kernel.optimizethis.net)
````
------

## Install [Squid Proxy Server](http://www.squid-cache.org/) for home use
```bash
curl -fsSLo squid.sh https://squid-proxy.optimizethis.net; sudo bash squid.sh
```
------

## Install Media Players
  - Prompt user with options to download
    - VLC
    - Kodi
    - SMPlayer
    - GNOME Videos (Totem)
    - Bomi
```bash
bash <(curl -fsSL https://players.optimizethis.net)
```
------

## Install: GParted's extra functionality packages
  - Unlock the following options in GParted
    - exFAT
    - btrfs
    - f2fs
    - jfs
    - udf
    - lvm2 pv
    - hfs/hfs 2
    - Reiser 4/reiserfs
```bash
bash <(curl -fsSL https://gparted.optimizethis.net)
```
------

## Create SSH key pairs and export the public key to a remote computer
 1. **Prompt user with instructions**
    - **Main Menu:**
      1. **Check if public key files exist and if not walk the user through the creation of files**
      2. **Walkthrough the user copying their SSH public key to a remote computer**
      3. **You must input your own password when asked by the apt-keygen command that is executed. This is to keep your security strong!**
```bash
curl -fsSLo ssh-keys.sh https://ssh-keys.optimizethis.net; sudo bash ssh-keys.sh
```
