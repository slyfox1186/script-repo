#!/bin/bash

clear

# VERIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [ "${EUID}" -gt '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exit 1
fi

# SET VARIABLES
VER='7z2201'
FILE="${VER}.tar.xz"
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
    wget -4cqO "${FILE}" "https://www.7-zip.org/a/${VER}-${URL}"
fi

# UNCOMPRESS THE XZ FILE
if [ ! -f "${FILE}" ]; then
    echo 'The script was unable to find the downloaded file.'
    echo
    exit 1
fi

# DELETE ANY FILES LEFTOVER FROM PRIOR RUNS
if [ -d "${DIR}" ]; then
    rm -fr "${DIR}"
fi

# CREATE AN OUTPUT DIRECTORY BEFORE UNCOMPRESSING WITH THE TAR COMMAND
mkdir -p "${DIR}"

# EXTRACT FILES INTO DIRECTORY '7Z'
tar -xf "${FILE}" -C "${DIR}"

# CD INTO DIRECTORY
if ! cd "${DIR}"; then
    echo
    echo -e "Can't cd into the 7z folder. Check your tar command."
    echo
    exit 1
fi

# COPY THE FILE TO ITS DESTINATION OR THROW AN ERROR IF THE COPYING OF THE FILE FAILS
if ! cp -f '7zzs' "${OUTPUT_FILE}"; then
    echo "The script was unable to copy the file '7zzs' to '${OUTPUT_FILE}'"
    echo
    exit 1
fi

# RUN THE COMMAND '7Z' TO SHOW ITS OUTPUT AND CONFIRM THAT EVERYTHING WORKED AS EXPECTED
"${OUTPUT_FILE}" | head -n 2 | cut -d " " -f1,3 | awk 'NF' | xargs printf "%s: v%s\n" "${@}"

# REMOVE LEFTOVER DIRECTORY
rm -fr "${FILE}" "${DIR}"
