#!/usr/bin/env bash

clear

# Define apt package names
packages=
    (
    aria2 bc bison build-essential cmake curl debootstrap dwarves flex g++
    g++-s390x-linux-gnu gcc gcc-s390x-linux-gnu gdb-multiarch git libcap-dev
    libelf-dev libelf-dev libncurses-dev libncurses5 libncursesw5 libncursesw5-dev
    libssl-dev make pkg-config python3 qemu-system-misc qemu-utils rsync wget
)

# Define URL file names
urls=
    (
    'urls/ubuntu-focal.txt'
    'urls/ubuntu-focal-updates.txt'
    'urls/ubuntu-focal-backports.txt'
)

# Convert packages array to a single string
package_list="$(IFS=,; echo "${packages[*]}")"

# Delete old output files
rm -f 'exact-matches.txt' 'close-matches.txt' 'non-matches.txt'

# Pass the URL input text files and package list to the Python script
for url in "${urls[@]}"
do
    python3 scrape1.py "$url" "$package_list"
done
