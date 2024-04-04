#!/usr/bin/env bash
set -x

##  Github: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-tilix.sh
##  Purpose: Compile the advanced Linux Terminal, Tilix, using source code from its official GitHub repository
##  Updated: 04.04.24
##  Version: 1.5

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without using root or sudo."
    exit 1
fi

script_ver="1.4"
cwd="$PWD/tilix-build-script"
program_name="tilix"

# Create the output folder and change into the build folder
mkdir -p "$cwd" "$HOME/.config/tilix/schemes"
cd "$cwd" || exit 1

# Print script banner
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner "Tilix Build Script - v$script_ver"

exit_fn() {
    printf "\n%s\n%s\n\n" \
        "Make sure to star this repository to show your support!" \
        "https://github.com/slyfox1186/script-repo"
    exit 0
}

# Function to get the latest version of tilix from github releases
get_latest_release_version() {
    curl -fsS "https://github.com/gnunn1/tilix/releases" | grep -oP '/gnunn1/tilix/releases/tag/\K[^"]+' | head -n1
}

# Install apt packages
packages=(autoconf autoconf-archive autogen automake build-essential ccache
          curl gettext git gtk-doc-tools libgtk-3-dev libgtk-4-dev libgtkd-3-dev
          libhwy-dev libtool libtool-bin m4 ninja-build pkg-config python3-nautilus)

# Array to hold packages that need to be installed
to_install=()

# Function to check if a package is installed
is_installed() {
    dpkg -l "$1" &>/dev/null
    return $?
}

# Check each package and add to the install list if not installed
for pkg in ${packages[@]}; do
    if ! is_installed "$pkg"; then
        to_install+=("$pkg")
    fi
done

# Install the packages if there are any to install
if [[ "${#to_install[@]}" -ne 0 ]]; then
    echo "Installing packages: ${to_install[*]}"
    sudo apt-get update
    sudo apt-get install "${to_install[@]}"
else
    printf "\n%s\n\n" "All packages are already installed."
fi
    
# Get the latest release version of tilix
version=$(get_latest_release_version)

# Define the download url and tar file name for tilix
download_url="https://github.com/gnunn1/tilix/archive/$version.tar.gz"
tar_file="$program_name-$version.tar.gz"

# Download the source code files if they are not already downloaded
if [[ ! -f "$tar_file" ]]; then
    printf "%s\n\n" "Downloading Tilix version $version..."
    curl -LSso "$tar_file" "$download_url"
else
   echo "Tilix version $version already downloaded."
fi

# Delete the output archive if it already exists
if [[ -d "$program_name-$version" ]]; then
    echo "Removing existing directory ${program_name}-${version}..."
    sudo rm -fr "$program_name-$version"
fi

# Extract the files
printf "%s\n\n" "Extracting $tar_file..."
if [[ -d "$program_name-$version" ]]; then
    sudo rm -fr "$program_name-$version"
fi
mkdir "$program_name-$version"
tar -zxf "$tar_file" -C "$program_name-$version" --strip-components 1

# Install the latest DMD compiler
echo "Installing the latest DMD Compiler..."
curl -fsS "https://dlang.org/install.sh" | bash -s dmd

# Activate the DMD environment
dmd_path=$(find "$HOME/dlang" -maxdepth 1 -type d -name 'dmd-*' | sort -Vr | head -n1)
if [[ -n "$dmd_path" && -f "$dmd_path/activate" ]]; then
    source "$dmd_path/activate"
else
    echo "Failed to find the DMD activation script."
    exit 1
fi

# Change to the tilix directory
cd "$program_name-$version"

# Build the tilix executable
echo "Building Tilix executable..."
echo
dub build --build=release

# Install tilix
printf "\n%s\n\n" "Installing Tilix..."
if sudo sh install.sh; then
    printf "\n%s\n\n" "Tilix was successfully installed."
else
    echo "Tilix failed to install."
    exit 1
fi

git clone -q "https://github.com/storm119/Tilix-Themes.git" "tilix-themes"

cd "tilix-themes/Themes" || exit 1
cp -f "argonaut.json" "dracula.json" "$HOME/.config/tilix/schemes"

cd "../Themes-2" || exit 1
cp -f "neopolitan.json" "vibrant-ink.json" "$HOME/.config/tilix/schemes"

# Make tilix the default terminal
sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/tilix 50

# REMOVE OPEN WITH GNOME-TERMINAL CONTEXT MENU ENTRY
if ! sudo killall -9 nautilus; then
    echo "Failed to execute the command \"sudo killall -9 nautilus\""
    echo
    read -p "Press enter to continue."
else
    sudo apt -y remove --purge nautilus-extension-gnome-terminal
    sudo apt -y autoremove
fi

# Re-open nautilus to the parent script directory
nautilus -w "$cwd"

# CLEANUP FILES
sudo rm -fr "$cwd"

# SHOW EXIT MESSAGE
exit_fn
