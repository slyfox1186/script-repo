#!/bin/bash

clear

fext=bat,sh
prefix='./'

outfile="$(find . -type f -iname "*.$fext" -exec bash -c "echo {} | sed -E 's/.*\s(.*)/\1/'" \;)"

for i in ${outfile[@]}
do
    fpath="${i:2}"
    echo "$PWD/$fpath"
done
