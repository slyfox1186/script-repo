#!/bin/bash

clear

# REQUIRED PACKAGES
if ! which bc &> /dev/null; then
    sudo apt -y install bc
fi

# INSTALL FFPB IF NOT INSTALLED
get_pkg="$(pip list | grep -Eo '^ffpb')"
if [ -z "${get_pkg}" ]; then
    pip install ffpb
fi

# DELETE LEFTOVER FILES
del_this="$(du -ah | grep -Eo '\..*\(.*\)\.mp4')"

if [ -n "${del_this:2}" ]; then
    sudo rm "${del_this:2}"
fi

# CAPTURE THE VIDEO WITHOUT (X265).MP4 AS THE ENDING
video="$(find . -type f -name *.mp4 -exec echo '{}' +)"

for v in "${video:2}"
do
    # STORES THE CURRENT VIDEO WIDTH, ASPECT RATIO, PROFILE, BIT RATE, AND TOTAL DURATION IN VARIABLES FOR USE LATER IN THE FFMPEG COMMAND LINE
    ar="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 -pretty "${v}" 2>/dev/null)"
    ln="$(ffprobe -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${v}" 2>/dev/null)"
    mr="$(ffprobe -hide_banner -show_entries format=bit_rate -of default=nk=1:nw=1 -pretty "${v}" 2>/dev/null)"
    vh="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 -pretty "${v}" 2>/dev/null)"
    vw="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 -pretty "${v}" 2>/dev/null)"
done

# MODIFY VARS TO GET FILE INPUT AND OUTPUT NAMES
file="${v}"
file_out="${file%.*} (x265).mp4"

# TRIM THE STRINGS
trim_back="${mr::-11}"
trim_front="${trim_back:3}"

# GETS THE INPUT VIDEOS MAX DATARATE AND APPLIES LOGIC TO DETERMINE BITRATE, BUFSIZE, AND MAXRATE VARIABLES
trim_back="$(bc <<< "scale=2 ; ${trim_back} * 1000")"
br="$(bc <<< "scale=2 ; ${trim_back} / 2")"
bitrate="${br::-3}"
maxrate="$(( ${bitrate} * 2 ))"
bc_bf="$(bc <<< "scale=2 ; ${br} * 2")"
bufsize="${bc_bf::-3}"
length="$(( ${ln::-7} / 60 ))"
length+=" Minutes"

# ECHO THE STORED VARIABLES THAT CONTAIN THE VIDEOS STATS
echo ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
echo
echo "Input File:      ${file}"
echo
echo "Output File:     ${file_out}"
echo
echo "Dimensions:      ${vw}x${vh}"
echo "Aspect Ratio:    ${ar}"
echo
echo "Maxrate:         ${maxrate}"k
echo "Bufsize:         ${bufsize}"k
echo "Bitrate:         ${bitrate}"k
echo
echo "Length:          ${length}"
echo
echo ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
echo

# EXECUTE FFMPEG

echo ffpb \
    -y \
    -threads '0' \
    -hide_banner \
    -hwaccel_output_format 'cuda' \
    -i "${file}" \
    -pix_fmt 'p010le' \
    -movflags 'frag_keyframe+empty_moov' \
    -c:v 'hevc_nvenc' \
    -preset:v 'medium' \
    -profile:v 'main' \
    -rc:v 'vbr' \
    -b:v "${bitrate}"k \
    -bufsize:v "${bufsize}"k \
    -bf:v '3' \
    -b_ref_mode:v 'middle' \
    -qmin:v '0' \
    -qmax:v '99' \
    -temporal-aq:v '1' \
    -rc-lookahead:v '20' \
    -i_qfactor:v '0.75' \
    -b_qfactor:v '1.1' \
    -fps_mode vfr \
    -c:a copy \
    "${file_out}"

if [ "${?}" -lt '1' ]; then
    google_speech "Video conversion completed"
else
    google_speech "Video conversion failed"
fi
