#!/bin/bash

##############################################################################
##
## GitHub: https://github.com/slyfox1186/script-repo
##
## Purpose: Install the latest 7-zip package across multiple OS types.
##          The user will be prompted to select their OS architecture before
##          installing.
##
## Updated: 01.30.23
##
#########################################################

clear

# VERIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [ "${EUID}" -gt '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exit 1
fi

# SET VARIABLES
VERSION='7z2201'
TAR_FILE="${VERSION}.tar.xz"
DIR='7z'
OUTPUT_FILE='/usr/bin/7z'

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

# DOWNLOAD THE TAR FILE IF MISSING
if [ ! -f "${TAR_FILE}" ]; then
    wget --show-progress -cqO "${TAR_FILE}" "https://www.7-zip.org/a/${VERSION}-${URL}"
fi

# DELETE ANY FILES LEFTOVER FROM PRIOR RUNS
if [ -d "${DIR}" ]; then rm -fr "${DIR}"; fi

# CREATE AN OUTPUT FOLDER FOR THE TAR COMMAND
mkdir -p "${DIR}"

# EXTRACT FILES INTO DIRECTORY '7Z'
if ! tar -xf "${TAR_FILE}" -C "${DIR}"; then
    fail_fn 'The script was unable to find the download file.'
fi

# CD INTO DIRECTORY
if ! cd "${DIR}"; then
    fail_fn "The script was unable to cd into '${DIR}'."
fi

# COPY THE FILE TO ITS DESTINATION OR THROW AN ERROR IF THE COPYING OF THE FILE FAILS
if ! cp -f '7zzs' "${OUTPUT_FILE}"; then
    fail_fn "The script was unable to copy the static file '7zzs' to '${OUTPUT_FILE}'"
fi

# RUN THE COMMAND '7Z' TO SHOW ITS OUTPUT AND CONFIRM THAT EVERTHING WORKS AS EXPECTED
clear
echo '7-zip has been updated to:'
"${OUTPUT_FILE}" | head -n 2 | cut -d " " -f3 | awk 'NF' | xargs printf "v%s\n" "${@}"
echo

# REMOVE LEFTOVER FILES
cd ../ || exit 1
rm -fr "${TAR_FILE}" "${DIR}" "${0}"
