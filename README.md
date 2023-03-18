# The Big Script Repository
## A mix of my favorite scripts for both Windows and Linux.

### Why this repository exists:
1. This repository was created as a way to share my custom scripts
2. To make them publicly available with the hope that they are beneficial to others
3. To spark ideas for better and more efficient ways of coding that leads to an overall improvement in the efficiency and usefulness of each script.
4. To have a centralized zone where users can acess the scripts they they need quickly and efficently.

### Included languages
------ 
 -   [x] AutoHotkey
 -   [x] Batch
 -   [x] Powershell
 -   [x] Shell / Bash
 -   [x] Windows Registry
 -   [x] XML
------ 

## Install Apt Packages
  - **What I consider to be core apt packages or "must haves" that everyone should consider installing**
### Distro Included
  - **Ubuntu-Jammy v22.04.02**
```
curl -sSL https://jammy-pkgs.optimizethis.net | sudo bash
```
  - **Ubuntu-Focal v22.04.05**
```
curl -sSL https://focal-pkgs.optimizethis.net | sudo bash
```

## Install [7-Zip](www.7-zip.org/download.html)
  - **Choose your architechture**
    - **Linux x64**
    - **Linux x86**
    - **ARM x64**
    - **ARM x86**
```
curl -sSL https://jammy-pkgs.optimizethis.net | sudo bash
```

## Install [ImageMagick 7](https://github.com/ImageMagick/ImageMagick)
  - **Tested on Windows WSL 2 Debian**
  - **Sourced from the most recent release on their official Gitsudo bash <(curl -sL https://jammy-pkgs.optimizethis.net)Hub page**
  - **[Optimize JPG Images](https://github.com/slyfox1186/imagemagick-optimize-jpg)**
```
wget -qO imagick.sh https://imagick.optimizethis.net; sudo bash imagick.sh
```

## Install [FFmpeg](https://ffmpeg.org/download.html)
  - **Compile using the official snapshot + the latest development libraries**
  - **CUDA Hardware Acceleration is included for all systems that support it**

**With GPL and non-free: https://ffmpeg.org/legal.html**
```
wget -qO ffn.sh https://ffn.optimizethis.net; bash ffn.sh
```
**Without GPL and non-free: https://ffmpeg.org/legal.html**
```ubuntu
wget -qO ff.sh https://ff.optimizethis.net; bash ff.sh
```

## Install Media Players
  - Prompt user with options to download
    - VLC
    - Kodi
    - SMPlayer
    - GNOME Videos (Totem)
    - Bomi
```
wget -qO media-players.sh https://media-players.optimizethis.net; bash media-players.sh
```

## Create SSH key pairs and export the public key to a remote computer
 1. **Prompt user with instructions**
    - **Main Menu:**
      1. **Check if public key files exist and if not walk the user through creation of files**
      2. **Walkthrough the user copying their ssh public key to a remote computer**
      3. **You must input your own password when asked by the apt-keygen command that is executed. This is to keep your security strong!**
```
curl -sSL https://ssh-keys.optimizethis.net | sudo bash
```
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
```
curl -sSL https://gparted.optimizethis.net | sudo bash
```

## Add .bashrc, .bash_aliases, and .bash_functions to the USER's directory
  - **Warning! This will overwrite your files!**
```
curl -sSL https://user-scripts.optimizethis.net | sudo bash
```

## Install extra download mirros for apt package manager
  - **Warning! This will overwrite your files!**
```
curl -sSL https://jammy-mirrors.optimizethis.net | sudo bash
```

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

## Add Open WSL Here to Windows Context Menu
  1. **Run cmd.exe as administrator**
  2. **To add to the context menu, paste the below command into cmd.exe and press enter to execute**
```
curl.exe -sSL https://wsl.optimizethis.net > open-wsl-here.bat && call open-wsl-here.bat
```
