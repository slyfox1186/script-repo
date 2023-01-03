# Script-Repository
## A mix of my favorite scripts for both Windows and Linux.

### Purpose
#### This repository was created as a way to share my custom scripts

#### Goal
  - Make them available to the general public with the hope that they are beneficial to others
  - To spark ideas for better and more efficient ways of doing things that leads to improvements in the overall efficiency and usefulness of the scripts.
  
### Current script languages that are included
  - AutoHotkey
  - Batch
  - Powershell
  - Shell / Bash
  - Windows Registry.
  - XML

### Install: Runtime and Development libraries
  - **Good for compiling binaries from source code**
  - **You must run the script twice to install all packages available**
```
wget -qO pkgs.sh https://pkgs.optimizethis.net; sudo bash pkgs.sh
```

### Install: [7-Zip](www.7-zip.org/download.html)
  - **Official 64-bit Linux x86-64 tar.gz file**
```
wget -qO 7z.sh https://7z.optimizethis.net; sudo bash 7z.sh
```

### Install: [FFmpeg](https://ffmpeg.org/download.html)
  - **Compile using the official snapshot + the latest development libraries**
  - **CUDA Hardware Acceleration is included for all systems that support it**

**With GPL and non-free: https://ffmpeg.org/legal.html**

```
wget -qO ffn.sh https://ffn.optimizethis.net; sudo bash ffn.sh
```
**Without GPL and non-free: https://ffmpeg.org/legal.html**
```
wget -qO ff.sh https://ff.optimizethis.net; sudo bash ff.sh
```

### Create ssh key pair and export to remote computer
 1. **Prompt user with instructions**
    - **Main Menu:**
      1. **Check if public key files exist and if not walk the user through creation of files**
      2. **Walkthrough the user copying their ssh public key to a remote computer**
```
wget -qO ssh-keys.sh https://ssh-keys.optimizethis.net; bash ssh-keys.sh
```
