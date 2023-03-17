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
version='7z2201'
tar_file="${version}.tar.xz"
target_dir='7z'
output_file='/usr/bin/7z'

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

echo '[i] Choose the OS architecture'
echo
echo '[1] Linux x64'
echo '[2] Linux x86'
echo '[3] ARM x64'
echo '[4] ARM x86'
echo '[5] Exit'
echo
read -p 'Your choices are (1 to 5): ' os_type
clear

# Parse user input
if [ "${os_type}" -eq '1' ]; then url='linux-x64.tar.xz'
elif [ "${os_type}" -eq '2' ]; then url='linux-x86.tar.xz'
elif [ "${os_type}" -eq '3' ]; then url='linux-arm64.tar.xz'
elif [ "${os_type}" -eq '4' ]; then url='linux-arm.tar.xz'
elif [ "${os_type}" -eq '5' ]; then exit
fi

# DOWNLOAD THE TAR FILE IF MISSING
if [ ! -f "${tar_file}" ]; then
    wget --show-progress -cqO "${tar_file}" "https://www.7-zip.org/a/${version}-${url}"
fi

# DELETE ANY FILES LEFTOVER FROM PRIOR RUNS
if [ -d "${target_dir}" ]; then rm -fr "${target_dir}"; fi

# CREATE AN OUTPUT FOLDER FOR THE TAR COMMAND
mkdir -p "${target_dir}"

# EXTRACT FILES INTO DIRECTORY '7Z'
if ! tar -xf "${tar_file}" -C "${target_dir}"; then
    fail_fn 'The script was unable to find the download file.'
fi

# CD INTO DIRECTORY
if ! cd "${target_dir}"; then
    fail_fn "The script was unable to cd into '${target_dir}'."
fi

# COPY THE FILE TO ITS DESTINATION OR THROW AN ERROR IF THE COPYING OF THE FILE FAILS
if ! cp -f '7zzs' "${output_file}"; then
    fail_fn "The script was unable to copy the static file '7zzs' to '${output_file}'"
fi

# RUN THE COMMAND '7Z' TO SHOW ITS OUTPUT AND CONFIRM THAT EVERTHING WORKS AS EXPECTED
clear
echo '7-zip has been updated to:'
"${output_file}" | head -n 2 | cut -d " " -f3 | awk 'NF' | xargs printf "v%s\n" "${@}"
echo

# REMOVE LEFTOVER FILES
cd ../ || exit 1
rm -fr "${tar_file}" "${target_dir}" "${0}"
