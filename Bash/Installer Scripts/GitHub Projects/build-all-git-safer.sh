#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-all-git-safer.sh
##  Purpose: Loops multiple build scripts and installs them.
##  Disclaimer: This is the safer of the two scripts offered in the "GitHub Projects" folder. This is because this script is less likely
##              To experience unexpected bugs of various types of severity. When the code gets updated, eventually unintentional bugs will
##              Happen, and you will unfortunately one day be there to experience it.... guaranteed.
##  Updated: 03.19.24
##  Script version: 1.2

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables
script_ver=1.2
cwd="$PWD/build-all-git-safer-script"

printf "%s\n%s\n\n"                                      \
    "Build All Git Safer Script version $script_ver" \
    '===================================================='
sleep 2

# Create the output directories
[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd/completed"

# Set the functions
exit_function() {
    echo
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    exit 0
}

log() {
    echo "[INFO] $1"
}

warn() {
    echo "[WARNING] $1"
}

fail() {
    echo
    echo "[ERROR] $1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Install required apt packages
pkgs=(asciidoc autoconf autoconf-archive autogen automake
      binutils bison build-essential bzip2 ccache cmake
      curl libtool libtool-bin lzip m4 meson nasm ninja-build
      yasm wget zlib1g-dev)

for pkg in ${pkgs[@]}; do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"

    if [[ -z "$missing_pkg" ]]; then
        missing_pkgs+=" $pkg"
    fi
done

if [[ -n "$missing_pkgs" ]]; then
    sudo apt update
    sudo apt install $missing_pkgs
    echo
fi

# Add additional search paths to the ld library linker
wget --show-progress -cqO /tmp/ld-script.sh "https://ld.optimizethis.net"
sudo bash /tmp/ld-script.sh || fail "Failed to execute /tmp/ld-script.sh"
sudo rm -f /tmp/ld-script.sh

# Change into the working directory
cd "$cwd" || exit 1

# Download scripts
scripts=(
         tools aria2 curl zlib zstd
         git jq libxml2 nasm yasm
     )

count=0
for script in ${scripts[@]}; do
    ((count++))
    wget --show-progress -t 2 -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-$script.sh"
    mv "build-$script.sh" "$count-build-$script.sh" || fail "Failed to move the file build-$script.sh"
done

# Loop and execute the scripts in numerical order
for file in $(find ./ -maxdepth 1 -type f | sort -V); do
    if echo "1" | bash "$file"; then
        mv "$file" "$cwd/completed"
    else
        [[ ! -d "$cwd/failed" ]] && mkdir -p "$cwd/failed"
        mv "$file" "$cwd/failed"
    fi
done

# If a script failed during the loop, alert the user and do not delte the file so the user can tell which one it was
if [[ -d "$cwd/failed" ]]; then
    echo
    warn "One of the scripts failed to build successfully."
    log "You can find the failed script at: $cwd/failed"
    echo
    exit_function
fi

# Cleanup leftover files
sudo rm -fr "$cwd"

# Display exit message
exit_function
