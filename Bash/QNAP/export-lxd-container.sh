#!/usr/bin/env bash

# This script will export an LXD Container

clear

# Set the output directory
folder='<change this to the full PATH of where you want to save the output file to>'

# Bold
blue='\033[1;34m'         # blue
cyan='\033[1;36m'         # cyan
green='\033[1;32m'        # green
purple='\033[1;35m'       # purple
red='\033[1;31m'          # red
white='\033[1;37m'        # white
yellow='\033[1;33m'       # yellow
orange='\e[0;1;38;5;220m' # Other
ec='\e[0m'                # Line Clear

# Create a time var
time="$(date "+%m.%d.%Y_%I.%M.%S.%p")"

clear

# Display THE AVAILABLE PACKAGES FOR EXPORT
printf "%s\n" "${green}"
lxc list

# Display the current working directory
printf "\n%s\n" "${cyan}Current Working Directory:${ec} ${red}$PWD${ec}"

# prompt user for input
read -p "${orange}Enter the ${blue}input ${orange}container name:${ec} " cname
read -p "${orange}Enter the ${blue}output ${orange}file name ${red}(${cyan}date ${orange}and ${cyan}extension ${orange}will be ${cyan}appended${red})${ec}:" oname
clear

# Display the user's choices before executing
printf "%s\n" "${white}Input: ${green}${cname}${ec}"
printf "%s\n" "${white}Output: ${green}${folder}/${oname}-${time}.tar.gz${ec}"

# Prompt user to continue
printf "%s\n" "${red}Important ${yellow}!${red}: ${red}You have 30 seconds to exit by pressing ${yellow}^Z${ec}"
read -t 30 -p 'Press Enter to continue...'
clear

# Display command line used
printf "%s\n" "${cyan}Executing: ${green}lxc export ${purple}\"${cname}\" \"${folder}/${oname}-${time}.tar.gz\" ${orange}--optimized-storage -v${ec}"

# Compressed mode
lxc export "${cname}" "${folder}/${oname}-${time}.tar.gz" --optimized-storage -v
