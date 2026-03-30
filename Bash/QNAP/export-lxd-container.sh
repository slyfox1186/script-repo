#!/usr/bin/env bash

set -euo pipefail

# Terminal colors (empty string if not a terminal)
if [[ -t 1 ]]; then
    green=$'\033[0;32m'
    red=$'\033[0;31m'
    cyan=$'\033[0;36m'
    blue=$'\033[0;34m'
    orange=$'\033[0;33m'
    yellow=$'\033[1;33m'
    white=$'\033[1;37m'
    purple=$'\033[0;35m'
    ec=$'\033[0m'
else
    green="" red="" cyan="" blue="" orange="" yellow="" white="" purple="" ec=""
fi

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <output_directory>"
    echo "  The directory where the exported container archive will be saved."
    exit 1
fi

folder="$1"

if [[ ! -d "$folder" ]]; then
    echo "Error: Output directory does not exist: $folder"
    exit 1
fi

timestamp="$(date "+%m.%d.%Y_%I.%M.%S.%p")"

clear
echo "${green}"
lxc list
echo "${ec}"

printf "%s\n" "${cyan}Current Working Directory:${ec} ${red}${PWD}${ec}"

read -rp "${orange}Enter the ${blue}input ${orange}container name:${ec} " cname
read -rp "${orange}Enter the ${blue}output ${orange}file name ${red}(${cyan}date ${orange}and ${cyan}extension ${orange}will be ${cyan}appended${red})${ec}: " oname

if [[ -z "$cname" || -z "$oname" ]]; then
    echo "Error: Container name and output file name cannot be empty."
    exit 1
fi

output_path="$folder/$oname-$timestamp.tar.gz"

clear
printf "%s\n" "${white}Input:  ${green}${cname}${ec}"
printf "%s\n" "${white}Output: ${green}${output_path}${ec}"

printf "\n%s\n" "${red}You have 30 seconds to exit by pressing Ctrl+C${ec}"
read -rt 30 -p 'Press Enter to continue...' || true
clear

printf "%s\n" "${cyan}Executing: ${green}lxc export ${purple}\"${cname}\" \"${output_path}\" ${orange}--optimized-storage -v${ec}"

lxc export "$cname" "$output_path" --optimized-storage -v

echo "${green}Export complete: ${output_path}${ec}"
