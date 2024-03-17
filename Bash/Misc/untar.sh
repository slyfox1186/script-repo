#!/usr/bin/env bash

###############################################################################################################################
##
##  How to demonstrate:
##
##  1) Add all of the following types of archives to an empty directory
##      - name.tar.gz
##      - name.tgz
##      - name.tar.xz
##      - name.tar.bz2
##      - name.tar.lz
##      - name.zip
##      - name.7z
##
##  2) Add the untar function to your .bash_functions or .bashrc file and source it or restart your terminal
##
##  3) Simply type "untar" in the same directory as the above archive files
##     - The second method is to run this script in the same directory with the archive files using the command "bash untar.sh"
##
##  Result: All archives will be extracted and ready to use
##
###############################################################################################################################

untar() {
    clear
    local archive ext gflag jflag xflag

    for archive in *.*
    do
        ext="$archive##*."

        [[ ! -d "$PWD"/"$archive%%.*" ]] && mkdir -p "$PWD"/"$archive%%.*"

        unset flag
        case "$ext" in
            7z|zip) 7z x -o./"$archive%%.*" ./"$archive";;
            bz2)    flag='jxf';;
            gz|tgz) flag='zxf';;
            xz|lz)  flag='xf';;
        esac

        [ -n "$flag" ] && tar $flag ./"$archive" -C ./"$archive%%.*" --strip-components 1
    done
}
untar
