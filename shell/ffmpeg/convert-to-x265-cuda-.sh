#!/bin/bash

clear

# REQUIRED PACKAGES
if ! which bc &> /dev/null; then
    sudo apt -y install bc
fi

# DELETE LEFTOVER FILES
DEL_THIS="$(du -ah | grep -Eo '\..*\(.*\)\.mp4')"

if [ -n "${DEL_THIS:2}" ]; then
    clear
    echo "Do you want to delete this?: ${DEL_THIS}"
    echo
    echo '[1] Yes'
    echo '[2] No'
    echo '[3] Exit'
    echo
    read -p 'Your choices are (1 to 3): ' DEL_ANSWER
    if [[ "${DEL_ANSWER}" -eq '1' ]]; then
        echo ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
        echo
        sudo rm "${DEL_THIS:2}"
        echo "Removed File: ${DEL_THIS:2}"
        echo
    elif [[ "${DEL_ANSWER}" -eq '2' ]]; then
        clear
    elif [[ "${DEL_ANSWER}" -eq '3' ]]; then
        echo
        exit 0
    else
        echo 'Bad user input: Start over'
        echo
        exit 1
    fi
fi

# CAPTURE THE VIDEO WITHOUT (X265).MP4 AS THE ENDING
video="$(find . -type f -name *.mp4 -exec echo '{}' +)"

for v in "${video:2}"
do
    # STORES THE CURRENT VIDEO WIDTH, ASPECT RATIO, PROFILE, BIT RATE, AND TOTAL DURATION IN VARIABLES FOR USE LATER IN THE FFMPEG COMMAND LINE
    AR="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 -pretty "${v}" 2>/dev/null)"
    LN="$(ffprobe -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${v}" 2>/dev/null)"
    MR="$(ffprobe -hide_banner -show_entries format=bit_rate -of default=nk=1:nw=1 -pretty "${v}" 2>/dev/null)"
    VH="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 -pretty "${v}" 2>/dev/null)"
    VW="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 -pretty "${v}" 2>/dev/null)"
done

# MODIFY VARS TO GET FILE INPUT AND OUTPUT NAMES
file="${v}"
file_out="${file%.*} (x265).mp4"

# TRIM THE STRINGS
trim_back="${MR::-11}"
trim_front="${trim_back:3}"

# GETS THE INPUT VIDEOS MAX DATARATE AND APPLIES LOGIC TO DETERMINE BITRATE, BUFSIZE, AND MAXRATE VARIABLES
trim_back="$(bc <<< "scale=2 ; ${trim_back} * 1000")"
br="$(bc <<< "scale=2 ; ${trim_back} / 2")"
bitrate="${br::-3}"
bc_bf="$(bc <<< "scale=2 ; ${br} * 2")"
bufsize="${bc_bf::-3}"
length="$(( ${LN::-7} / 60 ))"
length+=" Minutes"

# GETS THE INPUT VIDEOS MAX DATARATE AND APPLIES LOGIC TO DETERMINE BITRATE, BUFSIZE, AND MAXRATE VARIABLES
# TEST IF THE DECIMAL IS 0.51 OR HIGHER THEN ADD NUMBERS TO THE VARAIABLE MAXRATE BASED ON LOGIC.
# IF THE MAXRATE DECIMAL PLACE IS 0.51 OR HIGHER ADD 3 TO MAXRATE ELSE ADD 2.

if [[ "${trim_front}" -ge '50' ]]; then
    maxrate="$(( ${bitrate} * 2 ))"
else
    maxrate="$(( ${bitrate} * 1 ))"
fi

# ECHO THE STORED VARIABLES THAT CONTAIN THE VIDEOS STATS
echo ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
echo
echo "INPUT FILE:      ${file}"
echo
echo "OUTPUT FILE:     ${file_out}"
echo
echo "DIMENSIONS:      ${VW}x${VH}"
echo "ASPECT RATIO:    ${AR}"
echo
echo "MAXRATE:         ${maxrate}"k
echo "BUFSIZE:         ${bufsize}"k
echo "BITRATE:         ${bitrate}"k
echo
echo "LENGTH:          ${length}"
echo
echo ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
echo

# EXECUTE FFMPEG

ffmpeg \
    -y \
    -threads '0' \
    -hide_banner \
    -hwaccel_output_format 'cuda' \
    -i "${file}" \
    -pix_fmt 'p010le' \
    -movflags 'frag_keyframe+empty_moov' \
    -c:v 'hevc_nvenc' \
    -preset:v 'fast' \
    -profile:v 'main' \
    -rc:v 'vbr' \
    -b:v "${bitrate}"k \
    -bufsize:v "${bufsize}"k \
    -maxrate:v "${maxrate}"k \
    -bf:v '3' \
    -b_ref_mode:v 'middle' \
    -qmin:v '0' \
    -qmax:v '99' \
    -temporal-aq:v '1' \
    -rc-lookahead:v '20' \
    -i_qfactor:v '0.75' \
    -b_qfactor:v '1.1' \
    -c:a copy \
    "${file_out}"

exit 0
