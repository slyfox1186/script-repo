#!/bin/bash

clear

# REQUIRED APT PACKAGES
apt_pkgs=(bc ffmpegthumbnailer ffmpegthumbs libffmpegthumbnailer4v5 sox)
for i in ${apt_pkgs[@]}
do
    if ! dpkg -l | grep $i &>/dev/null; then
        sudo apt -y install $i
    fi
done
unset i

# INSTALL PYTHON3'S GOOGLE SPEECH TO ANNOUNCE WHEN THE CONVERSION HAS BEEN COMPLETED
pip_pkgs=(ffpb google_speech)
for i in ${pip_pkgs[@]}
do
    if ! pip show $i &>/dev/null; then
        pip install $i
    fi
done

# DELETE FILES PROM PRIOR RUNS
del_this="$(du -ah --max-depth=1 | grep -Eo '[\/].*\(x265\)\.(mp4|mkv)$' | grep -Eo '[A-Za-z0-9].*\(x265\)\.(mp4|mkv)$')"

clear
if [ -n "$del_this" ]; then
    printf "%s\n\n%s\n%s\n%s\n\n" \
        "Do you want to delete this video before continuing?: $del_this" \
        '[1] Yes' \
        '[2] No' \
        '[3] Exit'
    read -p 'Your choices are (1 to 3): ' choice

    case "$choice" in
        1)      rm "$del_this"; clear;;
        2)      clear;;
        3)      exit 0;;
        *)
                clear
                printf "%s\n\n" 'Bad user input.'
                exit 1
                ;;
    esac
fi

# CAPTURE THE VIDEO WITHOUT (X265).MP4 AS THE ENDING
video="$(find . -maxdepth 1 -type f \( -iname \*.mp4 -o -iname \*.mkv \) -exec echo '{}' +)"

for i in "${video:2}"
do
    # STORES THE CURRENT VIDEO WIDTH, ASPECT RATIO, PROFILE, BIT RATE, AND TOTAL DURATION IN VARIABLES FOR USE LATER IN THE FFMPEG COMMAND LINE
    aspect_ratio="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 -pretty "$i" 2>/dev/null)"
    file_length="$(ffprobe -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$i" 2>/dev/null)"
    max_rate="$(ffprobe -hide_banner -show_entries format=bit_rate -of default=nk=1:nw=1 -pretty "$i" 2>/dev/null)"
    file_height="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 -pretty "$i" 2>/dev/null)"
    file_width="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 -pretty "$i" 2>/dev/null)"
done

# MODIFY VARS TO GET FILE INPUT AND OUTPUT NAMES
file_in="$i"
file_ext="${file_in#*.}"
file_out="${file_in%.*} (x265).$file_ext"

# TRIM THE STRINGS
trim="${max_rate::-11}"

# GETS THE INPUT VIDEOS MAX DATARATE AND APPLIES LOGIC TO DETERMINE bitrate, bufsize, AND MAXRATE VARIABLES
trim="$(bc <<< "scale=2 ; $trim * 1000")"
_bitrate="$(bc <<< "scale=2 ; $trim / 2")"
bitrate="${_bitrate::-3}"
maxrate="$(( bitrate * 2 ))"
_bufsize="$(bc <<< "scale=2 ; $_bitrate * 2")"
bufsize="${_bufsize::-3}"
length="$(( ${file_length::-7} / 60 ))"
length+=' Minutes'

cat <<EOF
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

Input File:      $file_in

Output File:     $file_out

Dimensions:      $file_width'x'$file_height
Aspect Ratio:    $aspect_ratio

Maxrate:         ${maxrate}k
Bufsize:         ${bufsize}k
Bitrate:         ${bitrate}k

Length:          $length

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF

# EXECUTE FFPB (FFMPEG)
if ffpb \
        -y \
        -threads 0 \
        -hide_banner \
        -hwaccel_output_format cuda \
        -i "$file_in" \
        -pix_fmt p010le \
        -movflags frag_keyframe+empty_moov \
        -c:v hevc_nvenc \
        -preset:v medium \
        -profile:v main \
        -rc:v vbr \
        -b:v ${bitrate}k \
        -bufsize:v ${bufsize}k \
        -bf:v 4 \
        -b_ref_mode:v middle \
        -qmin:v 0 \
        -qmax:v 99 \
        -temporal-aq:v 1 \
        -rc-lookahead:v 20 \
        -i_qfactor:v 0.75 \
        -b_qfactor:v 1.1 \
        -c:a libfdk_aac \
        -qmin:a 1 \
        -qmax:a 4 \
        "$file_out"; then
    google_speech 'Video conversion completed' 2>/dev/null
else
    google_speech 'Video conversion failed' 2>/dev/null
fi
