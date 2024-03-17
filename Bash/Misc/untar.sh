#!/usr/bin/env bash


untar() {
    clear
    local archive ext gflag jflag xflag

    for archive in *.*
    do

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
