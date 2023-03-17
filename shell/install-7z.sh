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

# Verify the script has root access before continuing
if [ "${EUID}" -ne '0' ]; then
    echo 'You must run this script as root/sudo'
    echo
    exec sudo bash "${0}" "${@}"
fi

##
## Set variables
##

version='7z2201'
tar_file="${version}.tar.xz"
target_dir='7z-build'
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

version_fn()
{
    show_ver="$("${output_file}" | head -n 2 | cut -d " " -f3 | awk 'NF' | xargs printf "v%s\n" "${@}")"
    echo -e "\\n7-zip has been updated to:" "${show_ver}"
}

cleanup_fn()
{
    echo -e "\\nDo you want to cleanup the download files before exiting?\\n"
    echo '[1] Yes'
    echo -e "[2] No\\n"
    read -p 'Your choices are (1 or 2): ' choice
    clear

    if [ "${choice}" = '1' ]; then
        cd ../ || exit 1
        rm -r "${target_dir}" "${tar_file}" "${0}"
    fi

    return 0
}

# Detect arcitecture
case "$(uname -m)" in 
      x86_64)          url='linux-x64.tar.xz';;
      i386|i686)       url='linux-x86.tar.xz';;
      aarch64*|armv8*) url='linux-arm64.tar.xz';;
      arm|armv7*)      url='linux-arm.tar.xz';;
      *) fail_fn "Unrecognized architecture '$(uname -m)'";;
esac

# Download the tar file if missing
if [ ! -f "${tar_file}" ]; then
   wget --show-progress -cqO "${tar_file}" "https://www.7-zip.org/a/${version}-${url}"
fi

# Create an output folder for the tar command
mkdir -p "${target_dir}"

# Extract files into directory '7z'
if ! tar -xf "${tar_file}" -C "${target_dir}"; then
    fail_fn 'The script was unable to find the download file.'
fi

# cd into directory
if ! cd "${target_dir}"; then
    fail_fn "The script was unable to cd into '${target_dir}'."
fi

# Copy the file to its destination or throw an error if the copying of the file fails
if ! cp -f '7zzs' "${output_file}"; then
    fail_fn "The script was unable to copy the static file '7zzs' to '${output_file}'"
fi

# Run the command '7z' to show its output and confirm that everthing works as expected
version_fn

# Prompt the user to cleanup files
cleanup_fn
