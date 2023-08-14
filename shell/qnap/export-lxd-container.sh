#!/bin/bash

# This script will export an LXD Container

clear

# Set the output directory
FOLDER='<change this to the path where you want to save the output file>'

# Bold
Blue='\033[1;34m'         # Blue
Cyan='\033[1;36m'         # Cyan
Green='\033[1;32m'        # Green
Purple='\033[1;35m'       # Purple
Red='\033[1;31m'          # Red
White='\033[1;37m'        # White
Yellow='\033[1;33m'       # Yellow
Orange='\e[0;1;38;5;220m' # Other
EC='\e[0m'                # Line Clear

# Set the output directory
FOLDER='/share/Container'
# Create a time var
TIME="$(date "+%m.%d.%Y_%I.%M.%S.%p")"

clear

# Display THE AVAILABLE PACKAGES FOR EXPORT
echo -e "${Green}"
lxc list

# Display the current working directory
echo -e "\\n${Cyan}Current Working Directory:${EC} ${Red}$PWD${EC}\\n"

# prompt user for input
echo -e "${Orange}Enter the ${Blue}input ${Orange}container name:${EC} "
read cName
clear
echo -e "${Orange}Enter the ${Blue}output ${Orange}file name ${Red}(${Cyan}date ${Orange}and ${Cyan}extension ${Orange}will be ${Cyan}appended${Red})${EC}:"
read oName
clear

# Display the user's choices before executing
echo -e "${White}Input: ${Green}${cName}${EC}\\n"
echo -e "${White}Output: ${Green}${FOLDER}/${oName}-${TIME}.tar.gz${EC}\\n"

# Prompt user to continue
echo -e "${Red}Important ${Yellow}!${Red}: ${Red}You have 30 seconds to exit by pressing ${Yellow}^Z${EC}\\n"
read -t 30 -p 'Press Enter to continue...'
clear

# Display command line used
echo -e "${Cyan}Executing: ${Green}lxc export ${Purple}\"${cName}\" \"${FOLDER}/${oName}-${TIME}.tar.gz\" ${Orange}--optimized-storage -v\\n${EC}"

# Compressed mode
lxc export "${cName}" "${FOLDER}/${oName}-${TIME}.tar.gz" --optimized-storage -v
