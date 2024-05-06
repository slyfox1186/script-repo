#!/usr/bin/env python3

import os
import sys
import subprocess
import requests
import glob
from urllib.parse import urlparse
from colorama import init, Fore, Style
from simple_term_menu import TerminalMenu

init()  # Initialize colorama for color support

# Function to display colorized messages
def colorecho(color, message):
    color_code = getattr(Fore, color.upper(), Fore.WHITE)
    print(color_code + message + Style.RESET_ALL)

# Function to check and install wget if not available
def check_wget():
    try:
        subprocess.run(["wget", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        colorecho("yellow", "wget not found. Installing...")
        if sys.platform == "win32":
            colorecho("red", "Please install wget manually on Windows.")
            sys.exit(1)
        else:
            try:
                subprocess.run(["apt-get", "update"], check=True)
                subprocess.run(["apt-get", "install", "-y", "wget"], check=True)
            except subprocess.CalledProcessError:
                colorecho("red", "Failed to install wget. Please install it manually.")
                sys.exit(1)

# Function to download scripts
def download_scripts(output_dir):
    colorecho("cyan", f"Downloading scripts to {output_dir} ...")
    os.makedirs(output_dir, exist_ok=True)
    for url in selected_scripts:
        script_name = os.path.basename(url)
        if url in ffmpeg_scripts:
            repo_name = os.path.basename(os.path.dirname(urlparse(url).path))
            script_name_with_repo = f"{os.path.splitext(script_name)[0]}_{repo_name}{os.path.splitext(script_name)[1]}"
        else:
            script_name_with_repo = script_name
        colorecho("blue", f"Downloading {script_name} ...")
        response = requests.get(url)
        if response.status_code == 200:
            script_path = os.path.join(output_dir, script_name_with_repo)
            os.makedirs(os.path.dirname(script_path), exist_ok=True)
            with open(script_path, "wb") as file:
                file.write(response.content)
            colorecho("green", f"{script_name_with_repo} downloaded successfully.")
        else:
            colorecho("red", f"Failed to download {script_name}.")
    colorecho("cyan", "Setting ownership and permissions for downloaded scripts...")
    script_files = glob.glob(os.path.join(output_dir, "**", "*.sh"), recursive=True)
    subprocess.run(["chown", f"{os.getuid()}:{os.getgid()}"] + script_files, check=True)
    subprocess.run(["chmod", "644"] + script_files, check=True)

# Parse command-line arguments
output_dir = os.getcwd()  # Default output directory is the current directory
if "-o" in sys.argv or "--output" in sys.argv:
    try:
        output_dir = sys.argv[sys.argv.index("-o" if "-o" in sys.argv else "--output") + 1]
    except IndexError:
        colorecho("red", "Output directory not specified.")
        sys.exit(1)

# Check and install wget if not available
check_wget()

# Define base URLs for each category
ff_url = "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/"
git_url = "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/"
gnu_url = "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/"
magick_url = "https://raw.githubusercontent.com/slyfox1186/imagemagick-build-script/main/"
sly_url = "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/"
wsl_url = "https://raw.githubusercontent.com/slyfox1186/wsl2-kernel-build-script/main/"

# Define script URLs using base URLs and script names
slyfox1186_scripts = [
    f"{sly_url}7zip-installer.sh",
    f"{sly_url}build-dmd.sh",
    f"{sly_url}build-gparted.sh",
    f"{sly_url}build-grub-customizer.sh",
    f"{sly_url}build-menu.sh",
    f"{sly_url}build-players.sh",
    f"{sly_url}create-and-copy-ssh-key-pairs-to-remote-host.sh",
    f"{sly_url}create-desktop-file.sh",
    f"{sly_url}debian-package-downloader.sh",
    f"{sly_url}download-your-github-repos.sh",
    f"{sly_url}enable-headless-mode.sh",
    f"{sly_url}fix-dbus.sh",
    f"{sly_url}mirrors-menu.sh",
    f"{sly_url}squid-proxy.sh",
    f"{sly_url}user-scripts-menu.sh"
]

gnu_software_scripts = [
    f"{gnu_url}build-all-gnu-safer-archlinux.sh",
    f"{gnu_url}build-all-gnu-safer.sh",
    f"{gnu_url}build-all-gnu.sh",
    f"{gnu_url}build-attr.sh",
    f"{gnu_url}build-autoconf-archive.sh",
    f"{gnu_url}build-autoconf.sh",
    f"{gnu_url}build-automake.sh",
    f"{gnu_url}build-bash.sh",
    f"{gnu_url}build-binutils.sh",
    f"{gnu_url}build-coreutils.sh",
    f"{gnu_url}build-dbus.sh",
    f"{gnu_url}build-diffutils.sh",
    f"{gnu_url}build-emacs.sh",
    f"{gnu_url}build-eog.sh",
    f"{gnu_url}build-gawk.sh",
    f"{gnu_url}build-gcc.sh",
    f"{gnu_url}build-gettext-libiconv.sh",
    f"{gnu_url}build-glibc.sh",
    f"{gnu_url}build-gnutls.sh",
    f"{gnu_url}build-grep.sh",
    f"{gnu_url}build-gzip.sh",
    f"{gnu_url}build-imath.sh",
    f"{gnu_url}build-isl.sh",
    f"{gnu_url}build-libtool.sh",
    f"{gnu_url}build-m4.sh",
    f"{gnu_url}build-make.sh",
    f"{gnu_url}build-nano.sh",
    f"{gnu_url}build-ncurses.sh",
    f"{gnu_url}build-nettle.sh",
    f"{gnu_url}build-parallel.sh",
    f"{gnu_url}build-pkg-config-arm.sh",
    f"{gnu_url}build-pkg-config.sh",
    f"{gnu_url}build-readline.sh",
    f"{gnu_url}build-sed.sh",
    f"{gnu_url}build-systemd.sh",
    f"{gnu_url}build-tar.sh",
    f"{gnu_url}build-texinfo.sh",
    f"{gnu_url}build-wget.sh",
    f"{gnu_url}build-which.sh"
]

github_projects_scripts = [
    f"{git_url}build-adobe-fonts.sh",
    f"{git_url}build-alive-progress.sh",
    f"{git_url}build-all-git-safer.sh",
    f"{git_url}build-all-git.sh",
    f"{git_url}build-aria2-git.sh",
    f"{git_url}build-aria2.sh",
    f"{git_url}build-brotli.sh",
    f"{git_url}build-clang.sh",
    f"{git_url}build-curl-git.sh",
    f"{git_url}build-curl-with-openssl-quic.sh",
    f"{git_url}build-curl.sh",
    f"{git_url}build-garbage-collector.sh",
    f"{git_url}build-git.sh",
    f"{git_url}build-gperftools.sh",
    f"{git_url}build-jemalloc.sh",
    f"{git_url}build-jq.sh",
    f"{git_url}build-libboost.sh",
    f"{git_url}build-libgcrypt.sh",
    f"{git_url}build-libhwy.sh",
    f"{git_url}build-libpng.sh",
    f"{git_url}build-libxml2.sh",
    f"{git_url}build-linux-kernel.sh",
    f"{git_url}build-mainline.sh",
    f"{git_url}build-nasm.sh",
    f"{git_url}build-opencl-sdk.sh",
    f"{git_url}build-openssl.sh",
    f"{git_url}build-python2.sh",
    f"{git_url}build-python3.sh",
    f"{git_url}build-rust.sh",
    f"{git_url}build-terminator-terminal.sh",
    f"{git_url}build-tilix.sh",
    f"{git_url}build-tools.sh",
    f"{git_url}build-wsl2-kernel.sh",
    f"{git_url}build-yasm.sh",
    f"{git_url}build-zlib.sh",
    f"{git_url}build-zstd.sh"
]

ffmpeg_scripts = [
    f"{ff_url}build-ffmpeg.sh",
    "https://raw.githubusercontent.com/slyfox1186/ffmpeg-build-script/main/build-ffmpeg.sh"
]

imagemagick_scripts = [
    f"{magick_url}build-magick.sh"
]

wsl2_kernel_scripts = [
    f"{wsl_url}build-kernel.sh"
]

# Create menu items for each category
menu_items = [
    {"name": "SlyFox1186 Scripts", "scripts": slyfox1186_scripts},
    {"name": "GNU Software Scripts", "scripts": gnu_software_scripts},
    {"name": "GitHub Projects Scripts", "scripts": github_projects_scripts},
    {"name": "FFmpeg Scripts", "scripts": ffmpeg_scripts},
    {"name": "ImageMagick Scripts", "scripts": imagemagick_scripts},
    {"name": "WSL2 Kernel Scripts", "scripts": wsl2_kernel_scripts},
]

# Display interactive menu
selected_scripts = []
submenu_cursor_indexes = [0] * len(menu_items)
main_menu_cursor_index = 0
while True:
    os.system("cls" if sys.platform == "win32" else "clear")
    colorecho("cyan", "Select scripts to download (press Enter to finish):")
    menu_entries = []
    for item in menu_items:
        submenu_entries = []
        for script in item["scripts"]:
            script_name = os.path.basename(script)
            checked = " [✓]" if script in selected_scripts else ""
            submenu_entries.append(f"{script_name}{checked}")
        menu_entries.append((item["name"], submenu_entries))
    menu_entries.append(("[Done]", "done"))
    menu_entries.append(("[Exit]", "exit"))
    main_menu = TerminalMenu([entry[0] for entry in menu_entries], title="Script Categories", show_search_hint=True, cursor_index=main_menu_cursor_index)
    menu_index = main_menu.show()
    main_menu_cursor_index = menu_index if menu_index is not None else main_menu_cursor_index
    if menu_index == len(menu_entries) - 1:
        colorecho("red", "Exiting the script.")
        sys.exit(0)
    elif menu_index == len(menu_entries) - 2:
        break
    elif menu_index is not None:
        submenu = None
        submenu_cursor_index = submenu_cursor_indexes[menu_index]
        while True:
            submenu_entries = []
            for script in menu_items[menu_index]["scripts"]:
                script_name = os.path.basename(script)
                checked = " [✓]" if script in selected_scripts else ""
                submenu_entries.append(f"{script_name}{checked}")
            submenu = TerminalMenu(
                submenu_entries,
                title=menu_entries[menu_index][0],
                show_search_hint=True,
                cursor_index=submenu_cursor_index
            )
            script_index = submenu.show()
            if script_index is None:
                submenu_cursor_indexes[menu_index] = submenu_cursor_index
                break
            script = menu_items[menu_index]["scripts"][script_index]
            if script in selected_scripts:
                selected_scripts.remove(script)
            else:
                selected_scripts.append(script)
            submenu_cursor_index = script_index

if not selected_scripts:
    colorecho("red", "No scripts selected. Exiting.")
    sys.exit(0)

# Download selected scripts
download_scripts(output_dir)

colorecho("green", "Script execution completed.")

if not selected_scripts:
    colorecho("red", "No scripts selected. Exiting.")
    sys.exit(0)

# Download selected scripts
download_scripts(output_dir)

colorecho("green", "Script execution completed.")
