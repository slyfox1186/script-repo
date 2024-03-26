# Sly's Script Repository

Welcome to Sly's Script Repository! This collection is dedicated to sharing my favorite scripts for both Windows and Linux platforms. It includes a wide range of tools and utilities designed to enhance productivity and automate routine tasks.

## Included Languages and Technologies
- AutoHotkey
- Batch
- PowerShell
- Python 3
- Shell / Bash
- Visual Basic / VBS
- Windows Registry
- XML

_Last Updated: October 16, 2023_

### Supported Operating Systems
The scripts have been tested and confirmed to work on the following operating systems:
- Arch Linux
- Debian 11/12
- Ubuntu 18.04, 20.04, 22.04

### Purpose of This Repository
The goals behind creating and maintaining this repository are:
1. To share my collection of custom scripts with the wider community.
2. To provide a publicly available resource that others might find helpful.
3. To inspire improvements and new ways of thinking about coding tasks, enhancing the efficiency and functionality of the scripts.
4. To offer a centralized location for users to quickly find and utilize the scripts they need.

## Featured Scripts and Installations

### Linux Build Menu
Access a comprehensive menu of Linux installers with a single command:
```bash
bash <(curl -fsSL https://build-menu.optimizethis.net)
```

### Build All GNU Scripts
Compile all GNU scripts simultaneously with this master script:
```bash
bash <(curl -fsSL https://build-all-gnu.optimizethis.net)
```

### Build All GitHub Scripts
Automatically build all GitHub project scripts in one go:
```bash
bash <(curl -fsSL https://build-all-git.optimizethis.net)
```

### Install [GCC](https://ftp.gnu.org/gnu/gcc/?C=M;O=D) Latest Version
Directly source and install the latest GCC versions from the official GitHub repository. Note: Intended for personal/testing use only. Check the top of the script for build results.
- **Supported OS:** Ubuntu (20.04/22.04/23.04), Debian 11/12, and possibly other Debian-based distros.
```bash
curl -LSso build-gcc.sh https://gcc.optimizethis.net
sudo bash build-gcc.sh
```

### Install Latest [Clang-17](https://github.com/llvm/llvm-project) Release
Automatically finds and installs the latest Clang release from source.
```bash
curl -LSso build-clang-17.sh https://clang.optimizethis.net
sudo bash build-clang-17.sh
```

### Install Latest [Clang-18](https://github.com/llvm/llvm-project) Release
Automatically finds and installs the latest Clang release from source.
```bash
curl -LSso build-clang-18.sh https://clang.optimizethis.net
sudo bash build-clang-18.sh
```

### Install Latest 7-Zip Version
Installs the most recent static version of 7-Zip suitable for your system's architecture.
- **v23.01 Release**
```bash
curl -LSso install-7zip.sh https://7zip.optimizethis.net
sudo bash install-7zip.sh
```

### Install ImageMagick 7
Source the latest ImageMagick release directly from the official repository. Includes scripts for optimizing JPG images.
- **Supported OS:** Debian 11/12, Ubuntu 20.04/22.04/23.04, and possibly other Debian-based distros.
```bash
curl -LSso build-magick.sh https://imagick.optimizethis.net
sudo bash build-magick.sh
```

### Compile FFmpeg from Source
Compile the latest FFmpeg updates and optionally include the CUDA SDK Toolkit for hardware acceleration.
- **With GPL and non-free libraries.**
- **Supported OS:** Debian 11/12, Ubuntu (20.04/22.04/23.04), and possibly other Debian-based distros.
```bash
git clone https://github.com/slyfox1186/ffmpeg-build-script.git
cd ffmpeg-build-script || exit
sudo bash build-ffmpeg.sh --build --enable-gpl-and-non-free --latest
```

### Install OpenSSL Latest Version
Supports building different OpenSSL versions with various configuration options.
- **Supported OS:** Debian 11/12, Ubuntu 20.04/22.04/23.04, and possibly other Debian-based distros.
```bash
curl -LSso build-openssl.sh https://ossl.optimizethis.net
sudo bash build-openssl.sh
```

### Install Rust Programming Language
```bash
bash <(curl -fsSL https://rust.optimizethis.net)
```

### Install Essential Build Tools: CMake, Ninja, Meson, and Golang
```bash
curl -LSso build-tools.sh https://build-tools.optimizethis.net
sudo bash build-tools.sh
```

### Install Aria2 with Enhanced Configurations
Updated to Aria2 version 1.37.0 with increased max connections for improved download speeds.
```bash
sudo curl -LSso build-aria2.sh https://aria2.optimizethis.net
sudo bash build-aria2.sh
```

### Add Custom Mirrors to `/etc/apt/sources.list`
Enhance your package manager's efficiency by adding faster, more reliable mirrors.
- **Warning:** This action will overwrite your existing `sources.list` file.
```bash
bash <(curl -fsSL https://mirrors.optimizethis.net)
```

### Customize Your Shell Environment
Automatically add custom scripts to enhance your shell's functionality. This includes:
- `.bashrc`
- `.bash_aliases`
- `.bash_functions`

**Warning:** This will replace your existing files with the new versions.
```bash
bash <(curl -fsSL https://user-scripts.optimizethis.net)
```

### Install Adobe Fonts System-Wide
Get the latest Adobe Fonts installed on your system for a better visual experience.
```bash
bash <(curl -fsSL https://adobe-fonts.optimizethis.net)
```

### Debian Package Downloader
Easily download `.deb` files for offline installation or backup. Just provide a list of package names, and the script will handle the rest.
```bash
bash <(curl -fsSL https://download.optimizethis.net)
```

### Install Tilix: Advanced Terminal Emulator with Custom Themes
Tilix offers advanced features and customizable themes to enhance your terminal experience.
```bash
curl -LSso build-tilix.sh https://tilix.optimizethis.net
sudo bash build-tilix.sh
```

### Install Python 3.12.0
Ensure you have the latest version of Python 3 installed on your system for all your development needs.
```bash
curl -LSso build-python3.sh https://python3.optimizethis.net
sudo bash build-python3.sh

```

### Update WSL2 with the Latest Linux Kernel
Keep your Windows Subsystem for Linux (WSL2) updated with the latest kernel enhancements.
```bash
curl -LSso build-wsl2-kernel.sh https://wsl.optimizethis.net
sudo bash build-wsl2-kernel.sh
```

### Install Squid Proxy Server for Home Use
Set up a Squid Proxy Server on your home network for caching, filtering, and enhanced privacy.
```bash
curl -LSso build-squid.sh https://squid-proxy.optimizethis.net
sudo bash build-squid.sh
```

### Media Player Installations
Choose from a selection of popular media players and install them with ease.
```bash
bash <(curl -fsSL https://players.optimizethis.net)
```

### Enhance GParted with Extra Functionality
Unlock additional filesystem support in GParted, including support for exFAT, btrfs, and more.
```bash
bash <(curl -fsSL https://gparted.optimizethis.net)
```

## Contributing
Contributions are always welcome! Whether it's adding new scripts, improving existing ones, or reporting issues, your feedback helps make this repository more valuable for everyone.

Thank you for exploring Sly's Script Repository. Happy scripting!

---

For more information and updates, follow me on [GitHub](https://github.com/slyfox1186).
