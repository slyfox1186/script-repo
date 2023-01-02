#!/bin/bash

clear

# VERIFY THAT THE SCRIPT IS RUNNING WITH ROOT ACCESS
if [[ "${EUID}" -gt '0' ]]; then
    echo 'You must run this script as root/sudo'
    exit 1
fi

# SET VARIABLES
VERSION='7z2201'
TAR_FILE="${PWD}/${VERSION}.tar.xz"
OUPUT_DIR="${PWD}/${VERSION}"
OUTPUT_FILE='/usr/bin/7z'

echo "Installing 7zip v${VERSION:2}"

if [ ! -f "${TAR_FILE}" ]; then
    wget -cO "${TAR_FILE}" "https://www.7-zip.org/a/${VERSION}-linux-x64.tar.xz"
fi

# CHECK IF OUTPUT FOLDER EXISTS
if [ ! -d "${OUPUT_DIR}" ]; then
    mkdir -p "${OUPUT_DIR}"
fi

tar -xf "${TAR_FILE}" -C "${OUPUT_DIR}"

if tar -xf "${TAR_FILE}" -C "${OUPUT_DIR}"; then
    # CD INTO OUTPUT DIRECTORY
    cd '7z2201' || exit 1

    # COPY STATIC FILE TO /usr/bin/7z
    sudo cp '7zzs' "${OUTPUT_FILE}"

    # VERIFY THAT THE COPY COMMAND WAS SUCCESFULL
    if ! sudo cp '7zzs' "${OUTPUT_FILE}"; then
        echo "Failed to copy 7zzs file to ${OUTPUT_FILE}."
        echo
        exit 1
    fi
fi

TEST_VERSION="$('/usr/bin/7z' | grep --color -Ewo '[0-9]+\.[0-9]+')"
clear

# PRINT THE NEW 7Z VERSION AND STATS
if [ -z "${TEST_VERSION}" ]; then
    # THE INSTALLATION HAS FAILED. PLEASE CREATE A SUPPORT TICKET TO ALERT THE REPO OWNER https://github.com/slyfox1186/script-repo/issues
    echo 'Failed to install 7zip.'
    echo
    echo 'Please create a support ticket to alert the repo owner: https://github.com/slyfox1186/script-repo/issues'

    exit 1
fi

# ALERT THE USER OF A SUCCESSFUL INSTALLATION
echo "7-zip v${TEST_VERSION} was succesfully installed."
echo
echo 'The static file is located at /usr/bin/7z and requires no other files to execute.'
echo
echo 'Enter '\''7z'\'' to print the help menu.'
echo

exit
