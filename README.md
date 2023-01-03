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
curl -sSL https://ffn.optimizethis.net | sudo bash
```
**Without GPL and non-free: https://ffmpeg.org/legal.html**
```
curl -sSL https://ff.optimizethis.net | sudo bash
```
