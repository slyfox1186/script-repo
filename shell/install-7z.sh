#!/bin/bash

clear

# VERIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [[ "${EUID}" -gt '0' ]]; then
    echo 'You must run this script as root/sudo'
    echo
    exit 1
fi

# SET VARIABLES
VERSION='7z2201'
DOWNLOAD_FILE="${VERSION}.tar.xz"
DONWLOAD_DIR='7z'
OUTPUT_FILE='/usr/bin/7z'

# DOWNLOAD THE CUDA DEBIAN FILE IF NOT EXIST
if [ ! -f "${DOWNLOAD_FILE}" ]; then
    wget -cqO "${DOWNLOAD_FILE}" "https://www.7-zip.org/a/${VERSION}-linux-x64.tar.xz"
fi

# UPACKAGE THE CUDA DEBIAN FILE
if [ ! -f "${DOWNLOAD_FILE}" ]; then
    echo 'The script was unable to find the downloaded file.'
    echo
    exit 1
fi

# CREATE OUTPUT DIRECOTRY BEFORE UNCOMPRESSING WITH THE TAR COMMAND
if [ ! -d "${DONWLOAD_DIR}" ]; then
    mkdir -p "${DONWLOAD_DIR}"
fi

# EXTRACT FILES INTO DIRECTORY '7Z'
tar -xf "${DOWNLOAD_FILE}" -C "${DONWLOAD_DIR}"

# CD INTO DIRECOTRY
cd "${DONWLOAD_DIR}" || echo -e "\\nCan't cd into the 7z folder. Check your tar command.\\n"

# THROW AN ERROR IF THE COPY FILE FAILS
if ! cp -f '7zzs' "${OUTPUT_FILE}"; then
    echo "The script was unable to copy the file '7zzs' to '${OUTPUT_FILE}'"
    echo
    exit 1
fi

# COPY THE FILE TO ITS DESTINATION
cp -f '7zzs' "${OUTPUT_FILE}"
clear

cd ..

# RUN THE COMMAND '7Z' TO SHOW ITS OUTPUT AND CONFIRM THAT EVERYTHING WORKED AS EXPECTED
"${OUTPUT_FILE}" | head -n 2 | cut -d " " -f1,3 | awk 'NF' | xargs printf "%s: v%s\n" "${@}"
rm -rf "${DOWNLOAD_FILE}" "${DONWLOAD_DIR}"
