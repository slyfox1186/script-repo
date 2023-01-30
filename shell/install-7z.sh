#!/bin/bash

##############################################################################
##
## GitHub: https://github.com/slyfox1186/script-repo
##
## Purpose: Install the latest 7-zip package across multiple OS types.
##          The user will be prompted to choose the OS type before installing.
##
#########################################################

clear

# VERSIONIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [ "${EUID}" -gt '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exit 1
fi

##
## Create Functions
##

fail_fn()
{
    clear
    echo "${1}"
    echo
    echo 'Please create a support ticket: https://github.com/slyfox1186/script-repo/issues'
    echo
    exit 1
}

# SET VARIABLES
VERSION='7z2201'
FILE="${VERSION}.tar.xz"
DIR='7z'
OUTPUT_FILE='/usr/bin/7z'

echo '[i] Choose your os architechture'
echo
echo '[1] Linux x64'
echo '[2] Linux x86'
echo '[3] ARM x64'
echo '[4] ARM x86'
echo '[5] Source Code'
echo '[6] Exit'
echo
read -p 'Your choices are (1 to 6): ' OS_TYPE
clear

# Parse user input
if [ "${OS_TYPE}" -eq '1' ]; then URL='linux-x64.tar.xz'
elif [ "${OS_TYPE}" -eq '2' ]; then URL='linux-x86.tar.xz'
elif [ "${OS_TYPE}" -eq '3' ]; then URL='linux-arm64.tar.xz'
elif [ "${OS_TYPE}" -eq '4' ]; then URL='linux-arm.tar.xz'
elif [ "${OS_TYPE}" -eq '5' ]; then URL='src.tar.xz'
elif [ "${OS_TYPE}" -eq '6' ]; then exit
fi

# DOWNLOAD THE CUDA DEBIAN FILE IF NOT EXIST
if [ ! -f "${FILE}" ]; then
    wget --show-progress -cqO "${FILE}" "https://www.7-zip.org/a/${VERSION}-${URL}"
fi

# DELETE ANY FILES LEFTOVERSION FROM PRIOR RUNS
if [ -d "${DIR}" ]; then rm -fr "${DIR}"; fi

# CREATE AN OUTPUT FOLDER FOR THE TAR COMMAND
mkdir -p "${DIR}"

# EXTRACT FILES INTO DIRECTORY '7Z'
if ! tar -xf "${FILE}" -C "${DIR}"; then
    fail_fn 'The script was unable to find the downloaded file.'
fi

# CD INTO DIRECTORY
if ! cd "${DIR}"; then
    fail_fn "The script was unable to cd into the '${DIR}' folder."
fi

# COPY THE FILE TO ITS DESTINATION OR THROW AN ERROR IF THE COPYING OF THE FILE FAILS
if ! cp -f '7zzs' "${OUTPUT_FILE}"; then
    fail_fn "The script was unable to copy the file '7zzs' to '${OUTPUT_FILE}'"
fi

# RUN THE COMMAND '7Z' TO SHOW ITS OUTPUT AND CONFIRM THAT EVERSIONYTHING WORKED AS EXPECTED
clear
echo '7-zip has been updated to:'
"${OUTPUT_FILE}" | head -n 2 | cut -d " " -f3 | awk 'NF' | xargs printf "v%s\n" "${@}"
echo

# REMOVE LEFTOVER DIRECTORY
cd ../ || exit 1
rm -fr "${FILE}" "${DIR}" "${0}"
