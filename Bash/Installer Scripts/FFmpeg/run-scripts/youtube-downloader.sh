#!/usr/bin/env bash

clear

ouput_dir='/path/to/directory'
filename="$ouput_dir/%(title)s.%(ext)s"
regex='\.txt$'
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
ff="$(type -P ffmpeg)"
format='bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4] / bv*+ba/b'

# Check if the first argument passed ends in ".txt"
if [[ $1 =~ $regex ]]; then
    yt-dlp --ffmpeg-location $ff    \
           --audio-quality 3        \
           -f $format               \
           --embed-thumbnail        \
           --windows-filenames      \
           --user-agent $user_agent \
           --progress               \
           --paths "$ouput_dir"     \
           --batch-file             \
           "$1"
else
    yt-dlp --ffmpeg-location $ff    \
           --audio-quality 3        \
           -f $format               \
           --embed-thumbnail        \
           --windows-filenames      \
           --user-agent $user_agent \
           --progress               \
           -o "$filename"           \
           "$@"
fi
