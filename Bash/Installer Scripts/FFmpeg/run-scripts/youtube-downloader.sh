#!/usr/bin/env bash

clear

ouput_dir='/path/to/directory'
filename="$ouput_dir/%(title)s.%(ext)s"
ext='mp4'
regex='\.txt$'
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
#user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/120.0.2210.91'
ff='/usr/local/bin/ffmpeg'
format='bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4] / bv*+ba/b'
logfile='yt-dlp.log'

# Check if aria2c is installed
if ! command -v aria2c &> /dev/null; then
    printf "%s\n\n" "aria2c could not be found, please install it first."
    exit 1
fi

# Delete leftover log files if they exist
if [ -f 'yt-dlp.log' ]; then
    rm 'yt-dlp.log'
fi

# Check if the first argument passed ends in ".txt"
if [[ $1 =~ $regex ]]; then
    yt-dlp --ffmpeg-location $ff           \
           --audio-quality 3               \
           -f $format                      \
           --embed-thumbnail               \
           --windows-filenames             \
           --user-agent $user_agent        \
           --progress                      \
           --paths $ouput_dir              \
           --print-traffic                 \
           --abort-on-error                \
           --force-ipv4                    \
           --no-cookies-from-browser       \
           --no-write-comments             \
           --continue                      \
           --retry-sleep fragment:exp=1:20 \
           --downloader aria2c             \
           --batch-file                    \
           "$1" >> $logfile
else
    yt-dlp --ffmpeg-location $ff           \
           --audio-quality 3               \
           -f $format                      \
           --embed-thumbnail               \
           --windows-filenames             \
           --user-agent $user_agent        \
           --progress                      \
           --verbose                       \
           --print-traffic                 \
           --abort-on-error                \
           --force-ipv4                    \
           --no-cookies-from-browser       \
           --no-write-comments             \
           --continue                      \
           --retry-sleep fragment:exp=1:20 \
           --downloader aria2c             \
           -o "$filename"                  \
           "$@" >> $logfile
fi
