#!/bin/bash

clear

# SET PATH
export PATH="/usr/lib/ccache:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/cuda/bin:$PATH"

# DELETE ANY USELESS ZONE IDENFIER FILES THAT SPAWN FROM COPYING A FILE FROM WINDOWS NTFS INTO A WSL DIRECTORY
find . -type f -name "*:Zone.Identifier" -delete 2>/dev/null

# THE FILE EXTENSION TO SEARCH FOR (DO NOT INCLUDE A '.' WITH THE EXTENSION)
fext=jpg

# GET THE FILE COUNT TO USE IN THE FOR LOOP BELOW
cnt_queue=$(find . -maxdepth 2 -type f -iname *.jpg | wc -l)
cnt_total=$(find . -maxdepth 2 -type f -iname *.jpg | wc -l)

# GET THE UNMODIFIED PATH OF EACH MATCHING FILE
get_path="$(find . -type f -iname "*.${fext}" -exec sh -c 'i="${1}"; echo "${i%*.}"' shell {} \;)"

# FIND ALL JPG FILES AND CREATE TEMPORARY CACHE FILES FROM THEM
for i in ${get_path[@]}
do
    fname_in="${i:2}"
    fpath_full="${PWD}/$fname_in"
    fpath=${fpath_full%/*}
    fdir="${fpath%%.*}"
    # IF YOUR SUB-DIRECTORY IS NOT NAMED "Pics" THEN CHANGE THE BELOW COMMAND AS NEEDED
    cd "${fdir//\/Pics\/Pics/\/Pics}" || exit 1
done
unset i

for i in *.jpg
do
    cnt_queue=$(( cnt_queue-1 ))

cat <<EOF
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

File Path: ${fpath//\/Pics\/Pics/\/Pics}

Folder: $(basename ${PWD})

Total Files:    ${cnt_total}
Files in queue: ${cnt_queue}

Converting:  ${i}

             >> ${i%%.jpg}.mpc
            
                >> ${i%%.jpg}.cache
               
                   >> ${i%%.jpg}-IM.jpg

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF
    echo
    random_dir="$(mktemp -d)"
    dimensions="$(identify -format '%wx%h' "${i}")"
    convert "${i}" -monitor -filter Triangle -define filter:support=2 -thumbnail "${dimensions}" -strip \
        -unsharp '0.25x0.08+8.3+0.045' -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off \
        -auto-level -enhance -interlace none -colorspace sRGB "${random_dir}/${i%%.jpg}.mpc"

    for file in "${random_dir}"/*.mpc
    do
        if [ -f "${file}" ]; then
            if convert "${file}" -monitor "${file%%.mpc}.jpg"; then
                if [ -f "${file%%.mpc}.jpg" ]; then
                    cwd="$(echo "${file}" | sed 's:.*/::')"
                    mv "${file%%.mpc}.jpg" "${PWD}/${cwd%%.*}-IM.jpg"
                    rm -f "${PWD}/${cwd%%.*}.jpg"
                    for v in ${file}
                    do
                        v_noslash="${v%/}"
                        rm -fr "${v_noslash%/*}"
                    done
                fi
            else
                clear
                printf "%s\n\n" 'Error: Unable to find the optimized image.'
                read -p 'Press enter to exit.'
                return 1
            fi
        fi
    done
    clear
done

# The text-to-speech below requires the following packages:
# pip install google_speech; sudo apt -y install sox
if [ "${?}" -eq '0' ]; then
    google_speech 'Image conversion completed.' 2>/dev/null
    exit 0
else
    google_speech 'Image conversion failed.' 2>/dev/null
    exit 1
fi

unlink $TEMPFILE
