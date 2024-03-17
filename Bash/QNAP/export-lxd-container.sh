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
printf "%s\n" "$green"
lxc list

# Display the current working directory
printf "\n%s\n" "$cyanCurrent Working Directory:$ec $red$PWD$ec"

# prompt user for input
read -p "$orangeEnter the $blueinput $orangecontainer name:$ec " cname
read -p "$orangeEnter the $blueoutput $orangefile name $red($cyandate $orangeand $cyanextension $orangewill be $cyanappended$red)$ec:" oname
clear

# Display the user's choices before executing
printf "%s\n" "$whiteInput: $green$cname$ec"
printf "%s\n" "$whiteOutput: $green$folder/$oname-$time.tar.gz$ec"

# Prompt user to continue
printf "%s\n" "$redImportant $yellow!$red: $redYou have 30 seconds to exit by pressing $yellow^Z$ec"
read -t 30 -p 'Press Enter to continue...'
clear

# Display command line used
printf "%s\n" "$cyanExecuting: $greenlxc export $purple\"$cname\" \"$folder/$oname-$time.tar.gz\" $orange--optimized-storage -v$ec"

# Compressed mode
lxc export "$cname" "$folder/$oname-$time.tar.gz" --optimized-storage -v
