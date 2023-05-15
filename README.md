# The Big Script Repository
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

## Install apt and ppa packages
  - **What I consider to be core apt packages or "must haves" that everyone should consider installing**

**Ubuntu Jammy 22.04.02**
```bash
curl -Lso pkgs.sh https://jammy-pkgs.optimizethis.net; sudo bash pkgs.sh
```
**Ubuntu Focal 20.04.05**
```bash
curl -Lso pkgs.sh https://focal-pkgs.optimizethis.net; sudo bash pkgs.sh
```
**Debian 10 / 11**
```bash
curl -Lso pkgs.sh https://debian-pkgs.optimizethis.net; sudo bash pkgs.sh
```
------

## Add custom user scripts the the user's home directory
  - **Warning! This will overwrite your files!**
  - **Files Included**
    - .bashrc
    - .bash_aliases
    - .bash_functions
```bash
curl -Lso scripts.sh https://scripts.optimizethis.net; bash scripts.sh
```
------

## Install download mirrors to sources.list
  - **Warning! This will overwrite your files!**

#### Ubuntu Jammy
```bash
curl -Lso mirrors.sh https://jammy-mirrors.optimizethis.net; sudo bash mirrors.sh
```
#### Ubuntu Focal
```bash
curl -Lso mirrors.sh https://focal-mirrors.optimizethis.net; sudo bash mirrors.sh
```
#### Ubuntu Bionic
```bash
curl -Lso mirrors.sh https://bionic-mirrors.optimizethis.net; sudo bash mirrors.sh
```
#### Debian Bullseye
```bash
curl -sSL https://debian-mirrors.optimizethis.net | sudo bash
```
------

## Install [7-Zip](www.7-zip.org/download.html)
  - **Auto installs based on your os architecture. No user input required.**
    - **Linux x64**
    - **Linux x86**
    - **ARM x64**
    - **ARM x86**
```bash
curl -Lso 7z.sh https://7z.optimizethis.net; sudo bash 7z.sh
```
------

## Install [ImageMagick 7](https://github.com/ImageMagick/ImageMagick)
  - **Sourced from the most recent release on their official Git**
  - **Tested on Windows WSL 2 Debian/Ubuntu**
  - **[Optimize JPG Images](https://github.com/slyfox1186/imagemagick-optimize-jpg)**

#### Ubuntu 22.04.02 / 20.04.05 / 18.04.05
```bash
curl -Lso build-magick https://magick.optimizethis.net; sudo bash build-magick
```
#### Debian 10 / 11
```bash
curl -Lso build-magick https://debian.magick.optimizethis.net; sudo bash build-magick
```
------

## Install [FFmpeg](https://ffmpeg.org/download.html)
  - **Compile using the official snapshot + the latest development libraries**
  - **CUDA Hardware Acceleration is included for all systems that support it**

**With GPL and non-free: https://ffmpeg.org/legal.html**
```bash
bash <(curl -sSL https://ffn.optimizethis.net)
```
------

## Install [CMake](https://cmake.org/) v3.26.3
  - Supported OS
    - Debian 10 / 11
    - Ubuntu 18.04 / 20.04 / 22.04
    - Other debian style distros may work as well

```bash
curl -Lso build-cmake https://cmake.optimizethis.net; bash build-cmake
````
------

## Install [Curl](https://github.com/curl/curl) latest version (git clone)
  - Supported OS
    - Ubuntu 22.04
    - Other debian style distros may work as well

```bash
curl -Lso build-curl https://curl.optimizethis.net; bash build-curl
````
------

## Install [Tilix Advanced Terminal](https://github.com/gnunn1/tilix) with custom color themes (Dracula included)
  - Supported OS
    - Ubuntu 22.04
    - Other debian style distros may work as well
  - To install with no other actions required execute the first command, otherwise use the second command to
    git clone the repo and change what custom color themes you want to add or remove.
     - Navigate to the 'install-tilix' script to make your changes and the run `bash install-tilix`
```bash
wget -qN - -i https://build-tilix.optimizethis.net/; bash run-tilix
````
```bash
curl -Lso tilix-helper https://tilix-helper.optimizethis.net; bash tilix-helper
````
------

## Install [Python3](https://devguide.python.org/getting-started/setup-building/#get-the-source-code) v3.11.3
  - Supported OS
    - Debian 10 / 11
    - Ubuntu 18.04 / 20.04 / 22.04
    - Other debian style distros may work as well

```bash
curl -Lso py.sh https://python3.optimizethis.net; bash py.sh
````
------

## Install the [WSL2](https://devguide.python.org/getting-started/setup-building/#get-the-source-code) latest kernel release from [Linux Torvalds](https://github.com/torvalds/linux)
  - Supported OS
    - Debian 10 / 11
    - Ubuntu 18.04 / 20.04 / 22.04
    - Other debian style distros may work as well

```bash
curl -Lso build-kernel https://wsl2-kernel.optimizethis.net; sudo bash build-kernel
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
curl -Lso players.sh https://media-players.optimizethis.net; sudo bash players.sh
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
curl -Lso gparted.sh https://gparted.optimizethis.net; sudo bash gparted.sh
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
  1. **Run cmd.exe as administrator**
  2. **To add to the context menu, paste the below command into cmd.exe and press enter to execute**
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
