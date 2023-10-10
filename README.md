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
 -   [x] Visual Basic / VBS
 -   [x] Windows Registry
 -   [x] XML
------

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

## Install [GCC](https://github.com/gcc-mirror/gcc) versions - 11.4.0 / 12.3.0 / 13.2.0

  - **Sourced from the official GitHub repository**
  - **For personal/testing use only**
  - **Check the top of the script for build [results](https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc)**
  - **Supported OS:**
    - Debian - 10 / 11 / 12
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other  - Debian-based distros may work as well

#### For native Linux systems (Windows WSL not working)
```bash
bash <(curl -fsSL https://gcc.optimizethis.net)
```

## Install [7-Zip](www.7-zip.org/download.html)
  - **Auto installs based on your os architecture. No user input is required.**
    - **Arch** - i386 + x86_x64
    - **Processor** - Linux + ARM
### v23.01 Release
```bash
bash <(curl -fsSL https://7z.optimizethis.net)
```
------

## Install [ImageMagick 7](https://github.com/ImageMagick/ImageMagick)
  - **Sourced from the most recent release on the official Git**
  - **Tested on Windows WSL 2 Debian/Ubuntu**
  - **[Optimize JPG Images](https://github.com/slyfox1186/script-repo/tree/main/Bash/Installer%20Scripts/ImageMagick/scripts)**
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other  - Debian-based distros may work as well
  
```bash
bash <(curl -fsSL https://magick.optimizethis.net)
```
------

## Install [FFmpeg](https://ffmpeg.org/download.html)
  - **Compiles the latest updates from source code by issuing API calls to each repositories backend**
  - **The CUDA SDK Toolkit which unlocks Hardware Acceleration is available during the installation to make things as easy as possible**
  -  **See the my dedicated ffmpeg build page for more info on supplying your own GitHub API tokens: [ffmpeg-build-script](https://github.com/slyfox1186/ffmpeg-build-script)**
  - **Supported OS:**
    - Debian - 10 / 11 / 12
    - Ubuntu - 18.04 / 20.04 / 22.04 / 23.04
    - Other  - Debian-based distros may work as well

**With GPL and <ins>non-free</ins> libraries: https://ffmpeg.org/legal.html**
```bash
bash <(curl -fsSL https://build-ffmpeg.optimizethis.net) --build --latest
```
## Fast Build FFmpeg (Much faster with additional libraries)
```bash
bash <(curl -fsSL https://fast-build-ffmpeg.optimizethis.net)
```
------

## Install [CMake](https://cmake.org/), [Ninja](https://github.com/ninja-build/ninja), [Meson](https://github.com/mesonbuild/meson) & [Golang](https://github.com/golang/go)
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other  - Debian-based distros may work as well

```bash
bash <(curl -fsSL https://build-tools.optimizethis.net)
````
------

## Install [ARIA2C](https://github.com/aria2/aria2)
  - Aria2 max connections increased from 16 to 64
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other  - Debian-based distros may work as well

```bash
bash <(curl -fsSL aria2.optimizethis.net)
````
------

## Install [cURL](https://github.com/curl/curl), [WGET](https://ftp.gnu.org/gnu/wget) & [ARIA2C](https://github.com/aria2/aria2)
  - Aria2 max connections increased from 16 to 64
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other  - Debian-based distros may work as well

#### List of Libraries activated during build: [Libs](https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/installers/GitHub%20Projects/Download%20Tools/build-dl-tools.txt)
```bash
bash <(curl -fsSL https://dl-tools.optimizethis.net)
````
------

## Add custom mirrors to: /etc/apt/sources.list
  - **Supported OS:**
    - Ubuntu - 18.04 / 20.04 / 22.04 / 23.04
    - Debian - 11 / 12

**Warning! This will overwrite your files!**
```bash
bash <(curl -fsSL https://mirrors-menu.optimizethis.net)
```
------

## Add custom user scripts to the user's home directory
  - **Files included**
```bash
    .bashrc
    .bash_aliases
    .bash_functions
```
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
bash -c "$(curl -fsL https://git.io/vokNn)"
```
------

## Install apt and ppa packages
  - **What I consider to be core apt packages or "must haves" that everyone should consider installing**

**Ubuntu 22.04**
```bash
bash <(curl -fsSL pkgs.sh https://jammy-pkgs.optimizethis.net)
```
**Ubuntu 20.04**
```bash
bash <(curl -fsSL pkgs.sh https://focal-pkgs.optimizethis.net)
```
**Debian 10 / 11 / 12**
```bash
bash <(curl -fsSL pkgs.sh https://debian-pkgs.optimizethis.net))
```
------

## Change your network settings to Static or DHCP with netplan.io
  - The user will be prompted to enter the network settings
```bash
bash <(curl -fsSL https://netplan.optimizethis.net)
```
------

## Debian Package Downloader
  - Download APT packages to your pc by entering a space-separated list of values.
  - Input a single entry or an entire list of APT packages and the script will download its respective .deb file to the current directory.
```bash
bash <(curl -fsSL https://download.optimizethis.net)
```

## Install [Tilix](https://github.com/gnunn1/tilix) Advanced Terminal with custom color themes
  - Dracula theme included + many others
  - **Supported OS:**
    - Debian - 10 / 11 / 12
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other  - Debian-based distros may work as well
  - To install with no other actions required execute the first command, otherwise, use the second command to
    only download the files without executing the scripts immediately.
     - Open the file `install-tilix` and read the instructions at the top of the script to easily customize the
       color themes further and then run `bash install-tilix`
```bash
bash <(curl -fsSL https://tilix.optimizethis.net)
````
```bash
curl -Lso build-tilix https://tilix.optimizethis.net
````
------

## Install [Python3](https://devguide.python.org/getting-started/setup-building/#get-the-source-code) v3.11.4
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other  - Debian-based distros may work as well

```bash
bash <(curl -fsSL https://python3.optimizethis.net)
````
------

## Install the [WSL2](https://github.com/microsoft/WSL2-Linux-Kernel) latest kernel release from [Linux](https://github.com/torvalds/linux)
  - **Supported OS:**
    - Debian - 10 / 11
    - Ubuntu - 18.04 / 20.04 / 22.04
    - Other  - Debian-based distros may work as well

```bash
bash <(curl -fsSL https://wsl2-kernel.optimizethis.net)
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
```
.NET Framework 3.5 (all options)
Windows Communication Foundation HTTP Activation
Windows Communication Foundation Non-HTTP Activation    
.NET Framework 4.8 Advanced Services
ASP .NET 4.8
WCF Services
  HTTP Activation
  Message Queuing Activation
  Named Pip Activation
  TCP Activation
  TCP Port Sharing
Active Directory Lightweight Directory Services
Device Lockdown
Custom Logon
Shell Launcher
Unbranded Boot
Internet Information Services
Microsoft Message Queue (MSMQ) Server
Microsoft Print to PDF
Print and Document Services
Remote Differential Compression API Support
Services for NFS
Simple TCPIP Services
SMB 1.0/CIFS File Sharing Suppor (All suboptions enabled)
SMB Direct
Telnet Client
TFTP Client
Windows Identity Foundation 3.5
Windows PowerShell 2.0
Windows Process Activation Service
Windows Subsystem for Linux (WSL)
Windows TIFF IFliter
Work Folders Client
```
   
2. **To add to the context menu, paste the below command into cmd.exe and press enter to execute**
```
curl.exe -Lso features.bat https://win-optional-features.optimizethis.net && CALL features.bat && DEL /Q features.bat
```
------

## Add Open WSL Here to Windows Context Menu
  1. **Run cmd.exe as administrator**
  2. **To add to the context menu, paste the below command into cmd.exe and press enter to execute**
```batch
curl.exe -fsSL https://open-wsl-here.optimizethis.net > open-wsl-here.bat && call open-wsl-here.bat
```
3. **To remove to the context menu, paste the below command into cmd.exe and press enter to execute**
```batch
curl.exe -fsSL https://open-wsl-here-rm.optimizethis.net > open-wsl-here-rm.bat && call open-wsl-here-rm.bat
```
