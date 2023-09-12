#!/usr/bin/env bash

####################################################################################################################################################
##
##  GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/install-adobe-sans+pro-fonts.sh
##
##  Purpose: install adobe sans+pro fonts
##
##  Created: 09.12.23
##
##  Script version: 1.0
##
####################################################################################################################################################

clear

if [ "${EUID}" -eq '0' ]; then
    printf "%s\n\n" 'You must run this script WITHOUT root/sudo.'
    exit 1
fi

#
# SET THE VARIABLES
#

script_name="${0:2}"
script_ver=2.5
pro_url=https://github.com/adobe-fonts/source-code-pro/archive/refs/tags/2.042R-u/1.062R-i/1.026R-vf.tar.gz
sans_url=https://github.com/adobe-fonts/source-sans/archive/refs/tags/3.052R.tar.gz
cwd="${PWD}"/adobe-fonts-installer
pro_dir="${cwd}"/pro-source
sans_dir="${cwd}"/sans-source
install_dir_pro=/usr/local/share/fonts/adobe-pro
install_dir_sans=/usr/local/share/fonts/adobe-sans
user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36'
web_repo=https://github.com/slyfox1186/script-repo

#
# PRINT SCRIPT BANNER
#

box_out_banner1()
{
    input_char=$(echo "${@}" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)${line}"
    space=${line//-/ }
    echo " ${line}"
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "${@}"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "${space}" ; printf "%s\n" '|';
    echo " ${line}"
    tput sgr 0
}
box_out_banner1 "FFmpeg Build Script - v${script_ver}"
printf "\n%s\n\n" "The script will utilize ${cpu_threads} CPU cores for parallel processing to accelerate the build speed."

#
# CREATE OR DELETE OLD OUTPUT DIRECTORIES FROM PREVIOUS RUNS
#

if [ -d "${pro_dir}" ] || [ -d "${sans_dir}" ]; then
    sudo rm -fr "${pro_dir}" "${sans_dir}"
fi
mkdir -p "${pro_dir}" "${sans_dir}"

if [ ! -d "${install_dir_pro}" ] ||  [ ! -d "${install_dir_sans}" ]; then
    sudo mkdir -p "${install_dir_pro}" "${install_dir_sans}" 2>/dev/null
fi

#
# CREATE FUNCTIONS
#

exit_fn()
{
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "${web_repo}"
    exit 0
}

fail_fn()
{
    printf "\n%s\n\n%s\n\n" \
        "${1}" \
        "To report a bug create an issue at: ${web_repo}/issues"
    exit 1
}

cleanup_fn()
{
    local answer

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        '============================================' \
        '  Do you want to clean up the build files?  ' \
        '============================================' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer

    case "${answer}" in
        1)      sudo rm -fr "${cwd}";;
        2)      echo;;
        *)
                clear
                printf "%s\n\n" 'Bad user input.'
                sleep 3
                unset answer
                clear
                cleanup_fn
                ;;
    esac
}

#
# DOWNLOAD THE ARCHIVE FILES
#

if ! wget --timeout=5 -t 1 --show-progress -U "${user_agent}" -cqO "${pro_dir}".tar.gz "${pro_url}"; then
    fail_fn "Failed to download the archive file \"${pro_dir}.tar.gz\":Line ${LINENO}"
fi
if ! wget --timeout=5 -t 1 --show-progress -U "${user_agent}" -cqO "${sans_dir}".tar.gz "${sans_url}"; then
    fail_fn "Failed to download the archive file \"${sans_dir}.tar.gz\":Line ${LINENO}"
fi

#
# EXTRACT THE ARCHIVE FILES
#

if ! tar -zxf "${pro_dir}".tar.gz -C "${pro_dir}" --strip-components 1; then
    fail_fn "Failed to extract the archive \"${pro_dir}.tar.gz\":Line ${LINENO}"
fi
if ! tar -zxf "${sans_dir}".tar.gz -C "${sans_dir}" --strip-components 1; then
    fail_fn "Failed to extract the archive \"${sans_dir}.tar.gz\":Line ${LINENO}"
fi

#
# FIND AND MOVE THE FONT FILES TO THE OUTPUT FOLDER
#

cd "${pro_dir}" || exit 1
sudo find . -maxdepth 4 -type f -iname '*.ttf' -exec bash -c "sudo mv -f \"{}\" \"${install_dir_pro}\"" \;
sudo find . -maxdepth 4 -type f -iname '*.otf' -exec bash -c "sudo mv -f \"{}\" \"${install_dir_pro}\"" \;
sudo find . -maxdepth 4 -type f -iname '*.woff' -exec bash -c "sudo mv -f \"{}\" \"${install_dir_pro}\"" \;
cd "${sans_dir}" || exit 1
sudo find . -maxdepth 4 -type f -iname '*.ttf' -exec bash -c "sudo mv -f \"{}\" \"${install_dir_sans}\"" \;
sudo find . -maxdepth 4 -type f -iname '*.otf' -exec bash -c "sudo mv -f \"{}\" \"${install_dir_sans}\"" \;
sudo find . -maxdepth 4 -type f -iname '*.woff' -exec bash -c "sudo mv -f \"{}\" \"${install_dir_sans}\"" \;

#
# MAKE SURE THERE ARE 64 FONT FILES IN THE OUTPUT FOLDER
#

if [ "$(sudo find "${install_dir_pro}" -type f -iname '*.*' | wc -l)" -ne '64' ]; then
    fail_fn "\n%s\n\n" "The script failed to extract 64 total fonts to the adobe-pro directory:Line ${LINENO}"
elif [ "$(sudo find "${install_dir_sans}" -type f -iname '*.*' | wc -l)" -ne '64' ]; then
    fail_fn "The script failed to extract 64 total fonts to the adobe-pro directory:Line ${LINENO}"
else
    sudo fc-cache -fv
fi

# PROMPT THE USER TO CLEAN UP THE LEFTOVER BUILD FILES
cleanup_fn

# SHOW THE EXIT MESSAGE
exit_fn

