#!/usr/bin/env bash


clear

folder='<change this to the full PATH of where you want to save the output file to>'


time="$(date "+%m.%d.%Y_%I.%M.%S.%p")"

clear

printf "%s\n" "$green"
lxc list

printf "\n%s\n" "$cyanCurrent Working Directory:$ec $red$PWD$ec"

read -p "$orangeEnter the $blueinput $orangecontainer name:$ec " cname
read -p "$orangeEnter the $blueoutput $orangefile name $red($cyandate $orangeand $cyanextension $orangewill be $cyanappended$red)$ec:" oname
clear

printf "%s\n" "$whiteInput: $green$cname$ec"
printf "%s\n" "$whiteOutput: $green$folder/$oname-$time.tar.gz$ec"

printf "%s\n" "$redImportant $yellow!$red: $redYou have 30 seconds to exit by pressing $yellow^Z$ec"
read -t 30 -p 'Press Enter to continue...'
clear

printf "%s\n" "$cyanExecuting: $greenlxc export $purple\"$cname\" \"$folder/$oname-$time.tar.gz\" $orange--optimized-storage -v$ec"

lxc export "$cname" "$folder/$oname-$time.tar.gz" --optimized-storage -v
