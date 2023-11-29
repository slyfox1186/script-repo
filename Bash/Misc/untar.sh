#!/usr/bin/env bash

clear

####################################################################################
##
##  How to demonstrate:
##
##  1) Add all of the following types of archives to an empty directory
##      - name.tar.gz
##      - name.tar.tgz
##      - name.tar.xz
##      - name.tar.bz2
##      - name.tar.lz
##      - name.zip
##      - name.7z
##
##  2) Add the untar function to your .bash_functions or .bashrc file and source it or restart your terminal
##
##  3) Simply type "untar" in the same directory as the above archive files
##     - Second method is to run this script in the same direcotry with the archive files using the command "bash untar.sh"
##
##  Result: All archives will be extracted and ready to use
##
####################################################################################

untar()
{
    clear
    local ext gflag jflag xflag

    for archive in *.*
    do
        ext="${archive##*.}"

        [[ ! -d "${PWD}"/"${archive%%.*}" ]] && mkdir -p "${PWD}"/"${archive%%.*}"

        case "${ext}" in
            7z|zip)             7z x -o"${PWD}"/"${archive%%.*}" "${PWD}"/"${archive}";;
            bz2|gz|lz|tgz|xz)
                                unset gflag jflag xflag
                                [[ "${ext}" = 'bz2' && "${ext}" != 'gz' && "${ext}" != 'tgz' && "${ext}" != 'lz' ]] && jflag='jxf'
                                [[ "${ext}" != 'lz' && "${ext}" != 'xz' && "${ext}" != 'bz2' && "${ext}" = 'gz' || "${ext}" = 'tgz' ]] && gflag='zxf'
                                [[ "${ext}" = 'lz' || "${ext}" = 'xz' && "${ext}" != 'bz2' && "${ext}" != 'gz' && "${ext}" != 'tgz' ]] && xflag='xf'
                                tar -${xflag}${gflag}${jflag} "${PWD}"/"${archive}" -C "${PWD}"/"${archive%%.*}" --strip-components 1
                                ;;
        esac
    done
}
untar
