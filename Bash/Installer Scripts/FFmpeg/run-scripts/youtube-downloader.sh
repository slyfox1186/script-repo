#!/usr/bin/env bash

clear

ouput_dir='/path/to/Youtube-Download'
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
ff="$(type -P ffmpeg)"
regex='\.txt$'

# Check if the first argument being passed ends in '.txt'
if [[ $1 =~ $regex ]]; then
    yt-dlp --ffmpeg-location "$ff" --audio-quality 0 -f "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4] / bv*+ba/b" --windows-filenames --user-agent "$user_agent" --progress --paths "all:$ouput_dir" --batch-file "$1"
else
    yt-dlp --ffmpeg-location "$ff" --audio-quality 0 -f "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4] / bv*+ba/b" --windows-filenames --user-agent "$user_agent" --progress -o "$ouput_dir/%(title)s.%(ext)s" "$@"
fi
