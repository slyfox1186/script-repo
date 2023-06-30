# Slys Script Repository
## A mix of my favorite scripts for both Windows and Linux.

### Why this repository exists:
1. This repository was created as a way to share my custom scripts
2. Make the scripts publicly available with the hope that they are beneficial to others
3. Spark ideas for better and more efficient ways of coding that leads to an overall improvement in the efficiency and usefulness of each script
4. Have a centralized zone where users can access the scripts they need quickly and efficiently

### Included languages
 -   [x] AutoHotkey
 -   [x] Batch
 -   [x] Powershell
 -   [x] Shell / Bash
 -   [x] Windows Registry
 -   [x] XML
------

## Build Menu
  - All of the below Linux installers are located in one menu.
```bash
bash <(curl -sSL https://build-menu.optimizethis.net)
```
------

## Debian Package Downloader
  - Download APT packages to your pc by entering a space-separated list of values.
  - Input a single entry or an entire list of APT packages and the script will download its respective .deb file to the current directory.
```bash
bash <(curl -sSL https://download.optimizethis.net)
```

## Install [GCC](https://github.com/gcc-mirror/gcc) 11.4.0, 12.3.0, & 13.1.0

  - **Sourced from the official GitHub repository**
  - **Compiled on Ubuntu Jammy 22.04.02**
  - **For personal/testing use only**
  - **Check the top of the script for build [results](https://github.com/slyfox1186/script-repo/blob/main/shell/installers/build-gcc)**
  - **Supported OS:**
    - Debian - 11 / 12
    - Ubuntu - 22.04
    - Other Debian-style distros may work as well

#### For native Linux systems (Windows WSL not working)
```bash
bash <(curl -sSL https://gcc.optimizethis.net)
```

## Install [7-Zip](www.7-zip.org/download.html)
  - **Auto installs based on your os architecture. No user input is required.**
    - Linux x86/x64
    - ARM i386/x64
### v23.01 Release
```bash
bash <(curl -sSL https://7z.optimizethis.net)
```
------

## Install [ImageMagick 7](https://github.com/ImageMagick/ImageMagick)
  - **Sourced from the most recent release on their official Git**
  - **Tested on Windows WSL 2 Debian/Ubuntu**
  - **[Optimize JPG Images](https://github.com/slyfox1186/imagemagick-optimize-jpg)**
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other Debian-style distros may work as well

```bash
bash <(curl -sSL https://magick.optimizethis.net) --build --latest
```
------

## Install [FFmpeg](https://ffmpeg.org/download.html)
  - **Compiles the latest updates from source code by issuing API calls to each repositories backend**
  - **The CUDA SDK Toolkit which unlocks Hardware Acceleration is available during the installation to make things as easy as possible**
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other Debian-style distros may work as well

**With GPL and <ins>non-free</ins> libraries: https://ffmpeg.org/legal.html**
```bash
bash <(curl -sSL https://build-ffmpeg.optimizethis.net) --build --latest
```
------

## Install [CMake](https://cmake.org/), [Ninja](https://github.com/ninja-build/ninja), [Meson](https://github.com/mesonbuild/meson) & [Golang](https://github.com/golang/go)
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other Debian-style distros may work as well

```bash
bash <(curl -sSL https://build-tools.optimizethis.net)
````
------

## Install [cURL](https://github.com/curl/curl), [WGET](https://ftp.gnu.org/gnu/wget) & [ARIA2C](https://github.com/aria2/aria2)
#### Aria2 max connections increased from 16 to 64
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other Debian-style distros may work as well

#### List of Libraries activated during build: [Libs](https://github.com/slyfox1186/script-repo/blob/main/shell/installers/dl-tools/dl-tools-libs-list.txt)

```bash
bash <(curl -sSL https://dl-tools.optimizethis.net)
````
------

## Add custom user scripts to the user's home directory
  - **Warning! This will overwrite your files!**
  - **Files Included**
    - `.bashrc`
    - `.bash_aliases`
    - `.bash_functions`
#### Ubuntu 23.04 (Lunar)
```bash
bash <(curl -sSL https://lunar-scripts.optimizethis.net)
```
#### Ubuntu 22.04 (Jammy), 20.04 (Focal), 18.04 (Bionic)
```bash
bash <(curl -sSL https://jammy-scripts.optimizethis.net)
```
#### Debian 10 (Buster) / 11 (Bullseye) / 12 (Bookworm)
```bash
bash <(curl -sSL https://bookworm-scripts.optimizethis.net)
```
------

## Optimize the APT package manager by installing extra mirrors
  - Ubuntu - Lunar 23.04, Jammy 22.04, Focal 20.04, Bionic 18.04
  - Debian - Bullseye 11, Bookworm 12

**Warning! This will overwrite your files!**
```bash
bash <(curl -sSL https://mirrors-menu.optimizethis.net)
```
------

## Install apt and ppa packages
  - **What I consider to be core apt packages or "must haves" that everyone should consider installing**

**Ubuntu Jammy 22.04.02**
```bash
bash <(curl -sSL pkgs.sh https://jammy-pkgs.optimizethis.net)
```
**Ubuntu Focal 20.04.05**
```bash
bash <(curl -sSL pkgs.sh https://focal-pkgs.optimizethis.net)
```
**Debian 10 / 11**
```bash
bash <(curl -sSL pkgs.sh https://debian-pkgs.optimizethis.net))
```
------

## Install [Tilix](https://github.com/gnunn1/tilix) Advanced Terminal with custom color themes
  - Dracula theme included + many others
  - Supported OS
    - Ubuntu 22.04
    - Other Debian-style distros may work as well
  - To install with no other actions required execute the first command, otherwise use the second command to
    only download the files without executing the scripts immediately.
     - Open the file `install-tilix` and read the instructions at the top of the script to easily customize the
       color themes further and then run `bash install-tilix`
```bash
wget -qN - -i https://build-tilix.optimizethis.net/; bash run-tilix
````
```bash
wget -qN - -i https://build-tilix.optimizethis.net/
````
------

## Install [Python3](https://devguide.python.org/getting-started/setup-building/#get-the-source-code) v3.11.4
  - Supported OS
    - Debian 10 / 11
    - Ubuntu 18.04 / 20.04 / 22.04
    - Other Debian-style distros may work as well

```bash
bash <(curl -sSL https://python3.optimizethis.net)
````
------

## Install the [WSL2](https://github.com/microsoft/WSL2-Linux-Kernel) latest kernel release from [Linux](https://github.com/torvalds/linux)
  - Supported OS
    - Debian 10 / 11
    - Ubuntu 18.04 / 20.04 / 22.04
    - Other Debian-style distros may work as well

```bash
bash <(curl -sSL https://wsl2.optimizethis.net)
````
------

## Install [Squid Proxy Server](http://www.squid-cache.org/) for home use
```bash
curl -Lso squid.sh https://squid-proxy.optimizethis.net; sudo bash squid.sh
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
bash <(curl -sSL https://players.optimizethis.net)
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
bash <(curl -sSL https://gparted.optimizethis.net)
```
------

## Create SSH key pairs and export the public key to a remote computer
 1. **Prompt user with instructions**
    - **Main Menu:**
      1. **Check if public key files exist and if not walk the user through the creation of files**
      2. **Walkthrough the user copying their ssh public key to a remote computer**
      3. **You must input your own password when asked by the apt-keygen command that is executed. This is to keep your security strong!**
```bash
curl -Lso ssh-keys.sh https://ssh-keys.optimizethis.net; sudo bash ssh-keys.sh
```
------

# Windows Section
## Add Copy as Path to Windows Context Menu
  1. Run cmd.exe as administrator
  2. To add to the context menu, paste the below command into cmd.exe and press enter to execute
```
curl.exe -Lso add-copy-as-path.reg https://copy-path.optimizethis.net && call add-copy-as-path.reg
```
  - **To remove from the context menu, paste the next command into cmd.exe and press enter to execute**
```
curl.exe -Lso remove-copy-as-path.reg https://rm-copy-path.optimizethis.net && call remove-copy-as-path.reg
```
------

## Enable Windows Optional Features
#### Enables the following Features
  - .NET Framework 3.5 (all options)
    - Windows Communication Foundation HTTP Activation
    - Windows Communication Foundation Non-HTTP Activation    
  - .NET Framework 4.8 Advanced Services
    - ASP .NET 4.8
    - WCF Services
      - HTTP Activation
      - Message Queuing Activation
      - Named Pip Activation
      - TCP Activation
      - TCP Port Sharing
  - Active Directory Lightweight Directory Services
  - Device Lockdown
    - Custom Logon
    - Shell Launcher
    - Unbranded Boot
  - Internet Information Services
  - Microsoft Message Queue (MSMQ) Server
  - Microsoft Print to PDF
  - Print and Document Services
  - Remote Differential Compression API Support
  - Services for NFS
  - Simple TCPIP Services
  - SMB 1.0/CIFS File Sharing Suppor (All suboptions enabled)
  - SMB Direct
  - Telnet Client
  - TFTP Client
  - Windows Identity Foundation 3.5
  - Windows PowerShell 2.0
  - Windows Process Activation Service
  - Windows Subsystem for Linux (WSL)
  - Windows TIFF IFliter
  - Work Folders Client
  
   
2. **To add to the context menu, paste the below command into cmd.exe and press enter to execute**
```
curl.exe -Lso features.bat https://win-features.optimizethis.net && call features.bat && DEL /Q features.bat
```
------

## Add Open WSL Here to Windows Context Menu
  1. **Run cmd.exe as administrator**
  2. **To add to the context menu, paste the below command into cmd.exe and press enter to execute**
```
curl.exe -sSL https://wsl.optimizethis.net > open-wsl-here.bat && call open-wsl-here.bat
```
