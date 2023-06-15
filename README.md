# Slys Script Repository
## A mix of my favorite scripts for both Windows and Linux.

### Why this repository exists:
1. This repository was created as a way to share my custom scripts
2. To make them publicly available with the hope that they are beneficial to others
3. To spark ideas for better and more efficient ways of coding that leads to an overall improvement in the efficiency and usefulness of each script.
4. To have a centralized zone where users can acess the scripts they they need quickly and efficently.

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
  - Download APT packages to your pc by enter a space separated list of values.
  - Easy to use, just enter a list of APT package names and their debian file equivalent will download to the current folder.
```bash
bash <(curl -sSL https://download.optimizethis.net)
```

## Install [GCC](https://github.com/gcc-mirror/gcc) 11.4 & 13.1 on Ubuntu Jammy
  - **Sourced from the most recent releases on the official Git repository**
  - **Tested on Ubuntu Jammy 22.04**
  - **Strictly for personal, non-commercial use**
```bash
bash <(curl -sSL https://gcc.optimizethis.net)
```

## Install [7-Zip](www.7-zip.org/download.html)
  - **Auto installs based on your os architecture. No user input required.**
    - Linux x86/x64
    - ARM i386/x64
### v21.00 Release
```bash
bash <(curl -sSL https://7z.optimizethis.net)
```
### v23.00 Beta
```bash
bash <(curl -sSL https://7z-beta.optimizethis.net)
```
------

## Install [ImageMagick 7](https://github.com/ImageMagick/ImageMagick)
  - **Sourced from the most recent release on their official Git**
  - **Tested on Windows WSL 2 Debian/Ubuntu**
  - **[Optimize JPG Images](https://github.com/slyfox1186/imagemagick-optimize-jpg)**
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other debian style distros may work as well

```bash
bash <(curl -sSL https://magick.optimizethis.net) --build --latest
```
------

## Install [FFmpeg](https://ffmpeg.org/download.html)
  - **Compiles the latest updates from souce code by issuing API calls to each repositories backend**
  - **The CUDA SDK Toolkit which unlocks Hardware Acceleration is available during the install to make things as easy as possible**
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other debian style distros may work as well

**With GPL and <ins>non-free</ins> libraries: https://ffmpeg.org/legal.html**
```bash
bash <(curl -sSL https://build-ffmpeg.optimizethis.net) --build --latest
```
------

## Install [CMake](https://cmake.org/), [Ninja](https://github.com/ninja-build/ninja), [Meson](https://github.com/mesonbuild/meson) & [Golang](https://github.com/golang/go)
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other debian style distros may work as well

```bash
bash <(curl -sSL https://build-tools.optimizethis.net)
````
------

## Install [cURL](https://github.com/curl/curl) & [WGET](https://ftp.gnu.org/gnu/wget)
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other debian style distros may work as well

#### List of Libraries activated during build: [Libs](https://github.com/slyfox1186/script-repo/blob/main/shell/installers/dl-tools/dl-tools-libs-list.txt)

```bash
bash <(curl -sSL https://dl-tools.optimizethis.net)
````
------

## Add custom user scripts the the user's home directory
  - **Warning! This will overwrite your files!**
  - **Files Included**
    - `.bashrc`
    - `.bash_aliases`
    - `.bash_functions`
### Ubuntu 23.04 (Lunar)
```bash
bash <(curl -sSL https://lunar-scripts.optimizethis.net)
```
### Ubuntu 22.04 (Jammy), 20.04 (Focal), 18.04 (Bionic)
```bash
bash <(curl -sSL https://jammy-scripts.optimizethis.net)
```
------

## Install extra download mirrors
  - **Warning! This will overwrite your files!**
#### Ubuntu Lunar
```bash
curl -Lso mirrors https://lunar-mirrors.optimizethis.net; sudo bash mirrors
```
#### Ubuntu Jammy
```bash
curl -Lso mirrors https://jammy-mirrors.optimizethis.net; sudo bash mirrors
```
#### Ubuntu Focal
```bash
curl -Lso mirrors https://focal-mirrors.optimizethis.net; sudo bash mirrors
```
#### Ubuntu Bionic
```bash
curl -Lso mirrors https://bionic-mirrors.optimizethis.net; sudo bash mirrors
```
#### Debian Bullseye
```bash
curl -Lso mirrors https://debian-mirrors.optimizethis.net; sudo bash mirrors
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
    - Other debian style distros may work as well
  - To install with no other actions required execute the first command, otherwise use the second command to
    only download the files without executing the scripts immediatley.
     - Open the file `install-tilix` and read the instructions at the top of the script to easily customize the
       color themes further and then run `bash install-tilix`
```bash
wget -qN - -i https://build-tilix.optimizethis.net/; bash run-tilix
````
```bash
wget -qN - -i https://build-tilix.optimizethis.net/
````
------

## Install [Python3](https://devguide.python.org/getting-started/setup-building/#get-the-source-code) v3.11.3
  - Supported OS
    - Debian 10 / 11
    - Ubuntu 18.04 / 20.04 / 22.04
    - Other debian style distros may work as well

```bash
bash <(curl -sSL https://python3.optimizethis.net)
````
------

## Install the [WSL2](https://github.com/microsoft/WSL2-Linux-Kernel) latest kernel release from [Linux](https://github.com/torvalds/linux)
  - Supported OS
    - Debian 10 / 11
    - Ubuntu 18.04 / 20.04 / 22.04
    - Other debian style distros may work as well

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
    - exfat
    - btrfs
    - f2fs
    - jfs
    - udf
    - lvm2 pv
    - hfs/hfs 2
    - reiser 4/reiserfs
```bash
bash <(curl -sSL https://gparted.optimizethis.net)
```
------

## Create SSH key pairs and export the public key to a remote computer
 1. **Prompt user with instructions**
    - **Main Menu:**
      1. **Check if public key files exist and if not walk the user through creation of files**
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
