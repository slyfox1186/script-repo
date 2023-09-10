#!/usr/bin/env bash

clear

export TSAN_OPTIONS='ignore_noninstrumented_modules=1'

# THE FILE EXTENSION TO SEARCH FOR (DO NOT INCLUDE A '.' WITH THE EXTENSION)
fext=jpg

#
# REQUIRED APT PACKAGES
#

sudo apt -y install sox libsox-dev
sudo apt -y autoremove
clear

#
# REQUIRED PIP PACKAGES
#

pip_lock="$(find /usr/lib/python3* -name EXTERNALLY-MANAGED)"
if [ -n "${pip_lock}" ]; then
    sudo rm "${pip_lock}"
fi

test_pip="$(pip show google_speech)"
if [ -z "$test_pip" ]; then
    pip install google_speech
fi
unset p pip_lock pip_pkgs missing_pkg missing_pkgs

# DELETE ANY USELESS ZONE IDENFIER FILES THAT SPAWN FROM COPYING A FILE FROM WINDOWS NTFS INTO A WSL DIRECTORY
find . -type f -iname "*:Zone.Identifier" -delete 2>/dev/null

# GET THE FILE COUNT INSIDE THE DIRECTORY
cnt_queue=$(find . -maxdepth 2 -type f -iname "*.jpg" | wc -l)
cnt_total=$(find . -maxdepth 2 -type f -iname "*.jpg" | wc -l)
# GET THE UNMODIFIED PATH OF EACH MATCHING FILE

if [ -d Pics ]; then
    cd Pics || exit 1
fi

for i in *.${fext}
do
    cnt_queue=$(( cnt_queue-1 ))
    cat <<EOF
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

File Path: ${PWD}

Folder: $(basename "${PWD}")

Total Files:    ${cnt_total}
Files in queue: ${cnt_queue}

Converting: ${i}
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
        convert "${file}" -monitor "${file%%.mpc}.jpg"
        tmp_file="$(echo "${file}" | sed 's:.*/::')"
        mv "${file%%.mpc}.jpg" "${PWD}/${tmp_file%%.*}-IM.jpg"
        rm -f "${PWD}/${tmp_file%%.*}.jpg"
        for v in ${file}
        do
            v_noslash="${v%/}"
            rm -fr "${v_noslash%/*}"
        done
    done
clear
done

if [ "${?}" -eq '0' ]; then
    google_speech 'Image conversion completed.' 2>/dev/null
    exit 0
else
    echo
    google_speech 'Image conversion failed.' 2>/dev/null
    echo
    read -p 'Press enter to exit.'
    exit 1
fi

unset TSAN_OPTIONS
