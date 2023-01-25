# The Big Script-Repository
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



## Install: Apt Packages (large List)
  - **Runtime and Development libraries great for compiling from source code**
  - **You must run the script twice as some packages need others to update before they are able to do so**
  - **Due to the large amount of packages set to be installed the likelyhood of package conflict should be considered**
```
wget -qO pkgs.sh https://pkgs.optimizethis.net; sudo bash pkgs.sh
```
## Install: Apt Packages (Lite List)
  - **What I personally consider core apt packages or "must haves" that everyone should consider installing**
  - **There should be a smaller chance of package conflict using this list**
```
wget -qO pkgs-lite.sh https://pkgs-lite.optimizethis.net; sudo bash pkgs-lite.sh
```

## Install: [7-Zip](www.7-zip.org/download.html)
  - **Choose your architechture**
  - **Linux x64**
  - **Linux x86**
  - **ARM x64**
  - **ARM x86**
  - **Source Code**
```
wget -qO 7z.sh https://7z.optimizethis.net; sudo bash 7z.sh
```

## Install: [ImageMagick 7](https://github.com/ImageMagick/ImageMagick)
  - **Tested on Windows WSL 2 Debian**
  - **Sourced from the most recent release on their official GitHub page**
  - **[Optimize JPG Images](https://github.com/slyfox1186/imagemagick-optimize-jpg)**
```
wget -qO imagick.sh https://imagick.optimizethis.net; sudo bash imagick.sh
```


## Install: [FFmpeg](https://ffmpeg.org/download.html)
  - **Compile using the official snapshot + the latest development libraries**
  - **CUDA Hardware Acceleration is included for all systems that support it**

**With GPL and non-free: https://ffmpeg.org/legal.html**
```
wget -qO ffn.sh https://ffn.optimizethis.net; bash ffn.sh
```
**Without GPL and non-free: https://ffmpeg.org/legal.html**
```
wget -qO ff.sh https://ff.optimizethis.net; bash ff.sh
```

## Create SSH key pairs and export the public key to a remote computer

 1. **Prompt user with instructions**
    - **Main Menu:**
      1. **Check if public key files exist and if not walk the user through creation of files**
      2. **Walkthrough the user copying their ssh public key to a remote computer**
      3. **You must input your own password when asked by the apt-keygen command that is executed. This is to keep your security strong!**
```
wget -qO ssh-keys.sh https://ssh-keys.optimizethis.net; bash ssh-keys.sh
```

## Add Copy as Path to Windows context menu
  - **Steps to install**
  1. **Run cmd.exe as administrator**
    - **To add to the context menu, paste the first command into cmd.exe and press enter to execute**
    - **To remove from the context menu, paste the second command into cmd.exe and press enter to execute**
```
curl.exe -Lso add-copy-as-path.reg https://copy-path.optimizethis.net && call add-copy-as-path.reg
```
```
curl.exe -Lso remove-copy-as-path.reg https://rm-copy-path.optimizethis.net && call remove-copy-as-path.reg
```

## Add Open WSL Here to Windows Context-Menu
  - **Steps to install**
  1. **Run cmd.exe as administrator**
    - **To add to the context menu, paste the first command into cmd.exe and press enter to execute**
    - **To remove from the context menu, paste the second command into cmd.exe and press enter to execute**
```
curl.exe -sSL https://wsl.optimizethis.net > open-wsl-here.bat && call open-wsl-here.bat
```
