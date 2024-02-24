#!/usr/bin/env bash
# shellcheck disable=SC2066,SC2068,SC2086,SC2162

clear

#
# MODIFY THE PATH VARIABLE IF THE DIRECTORY EXISTS
#

if [ -d "${HOME}/.local/bin" ]; then
    PATH="${PATH}:${HOME}/.local/bin"
    export PATH
fi

#
# REQUIRED APT PACKAGES
#

apt_pkgs=(bc ffmpegthumbnailer ffmpegthumbs libffmpegthumbnailer4v5 sox libsox-dev trash-cli)

for i in ${apt_pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "${i}")"
    if [ -z "${missing_pkg}" ]; then
        missing_pkgs+=" ${i}"
    fi
done

if [ -n "${missing_pkgs}" ]; then
    sudo apt -y install ${missing_pkgs}
    sudo apt -y autoremove
    clear
fi
unset apt_pkgs i missing_pkg missing_pkgs

#
# REQUIRED PIP PACKAGES
#

pip_lock="$(sudo find /usr/lib/python3* -name 'EXTERNALLY-MANAGED')"
if [ -n "${pip_lock}" ]; then
    sudo rm "${pip_lock}"
fi

pip_pkgs=(ffpb google_speech)
for py in ${pip_pkgs[@]}
do
    missing_pkg="$(pip show "${py}" 2>/dev/null)"
    if [ -z "${missing_pkg}" ]; then
        missing_pkgs+=" ${py}"
    fi
done

if [ -n "${missing_pkgs}" ]; then
    pip install ${missing_pkgs}
    clear
fi
unset py pip_lock pip_pkgs missing_pkg missing_pkgs

# DELETE FILES PROM PRIOR RUNS
del_this="$(du -ah --max-depth=1 | grep -Eo '[\/].*\(x265\)\.m(p4|kv)$' | grep -Eo '[A-Za-z0-9].*\(x265\)\.m(p4|kv)$')"
clear

del_prompt()
{
    clear
    if [ -n "${del_this}" ]; then
        printf "%s\n\n%s\n%s\n%s\n\n" \
            "Do you want to delete this video before continuing?: ${del_this}" \
            '[1] Yes (Recommended)' \
            '[2] No' \
            '[3] Exit'
        read -p 'Your choices are (1 to 3): ' del_choice
    
        case "${del_choice}" in
            1)      rm "${del_this}";;
            2)      clear;;
            3)      exit 0;;
            *)
                    clear
                    printf "%s\n\n" 'Bad user input. Reverting script...'
                    sleep 3
                    unset del_choice
                    del_prompt
                    ;;
        esac
    fi
}
del_prompt
clear

# MAKE SURE THERE ARE ACTUAL VIDEOS IN THE FOLDER WITH THIS SCRIPT BEFORE CONTINUING
for vid in "${PWD}"/*.{mp4,mkv}
do
    vid_exist="$(echo ${vid})"
    if [ -n "${vid_exist}" ]; then
        vid_list=" ${vid}"
    fi
    if [ -n "${vid_list}" ]; then
        clear
    else
        printf "%s\n\n%s\n" \
            'You dummy, there are no video files in this folder... what is this script supposed to do without those?!' \
            'Fix this problem to continue.'
        exit 1
    fi
done
unset vid vid_exist vid_list

# CAPTURE THE VIDEO WITHOUT (X265).MP4 AS THE ENDING
video="$(sudo find . -maxdepth 1 -type f \( -iname \*.mp4 -o -iname \*.mkv \) -exec echo '{}' +)"

for v in "${video:2}"
do
    # STORES THE CURRENT VIDEO WIDTH, ASPECT RATIO, PROFILE, BIT RATE, AND TOTAL DURATION IN VARIABLES FOR USE LATER IN THE FFMPEG COMMAND LINE
    aspect_ratio="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 -pretty "${v}" 2>/dev/null)"
    file_length="$(ffprobe -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${v}" 2>/dev/null)"
    max_rate="$(ffprobe -hide_banner -show_entries format=bit_rate -of default=nk=1:nw=1 -pretty "${v}" 2>/dev/null)"
    file_height="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 -pretty "${v}" 2>/dev/null)"
    file_width="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 -pretty "${v}" 2>/dev/null)"
done

# MODIFY VARS TO GET FILE INPUT AND OUTPUT NAMES
file_in="${v}"
fext="${file_in#*.}"
file_out="${file_in%.*} (x265).${fext}"

# TRIM THE STRINGS
trim="${max_rate::-11}"

# GETS THE INPUT VIDEOS MAX DATARATE AND APPLIES LOGIC TO DETERMINE bitrate, bufsize, AND MAXRATE VARIABLES
trim="$(bc <<< "scale=2 ; ${trim} * 1000")"
br="$(bc <<< "scale=2 ; ${trim} / 2")"
bitrate="${br::-3}"
maxrate="$(( bitrate * 2 ))"
bs="$(bc <<< "scale=2 ; ${br} * 2")"
bufsize="${bs::-3}"
length="$(( ${file_length::-7} / 60 ))"
length+=' Minutes'

cat <<EOF
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

Input File:      ${file_in}
Output File:     ${file_out}

Dimensions:      ${file_width}x${file_height}
Aspect Ratio:    ${aspect_ratio}

Maxrate:         ${maxrate}k
Bufsize:         ${bufsize}k
Bitrate:         ${bitrate}k

Length:          ${length}

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF

# EXECUTE FFMPEG THROUGH FFPB
if ffmpeg \
        -y \
        -threads 0 \
        -hide_banner \
        -hwaccel cuda \
        -hwaccel_output_format cuda \
        -i "${file_in}" \
        -pix_fmt p010le \
        -movflags 'frag_keyframe+empty_moov' \
        -c:v hevc_nvenc \
        -preset:v medium \
        -profile:v main \
        -rc:v vbr \
        -b:v "${bitrate}"k \
        -bufsize:v "${bufsize}"k \
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
        "${file_out}"; then
    google_speech 'Video conversion completed.' 2>/dev/null
    # MOVE INPUT FILE TO TRASH
    trash -f "${file_in}"
    exit 0
else
    google_speech 'Video conversion failed.' 2>/dev/null
    echo
    read -p 'Press enter to exit.'
    exit 1
fi
