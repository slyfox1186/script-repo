#!/usr/bin/env bash

ffs() {
    wget --show-progress -cqO "https://raw.githubusercontent.com/slyfox1186/ffmpeg-build-script/main/build-ffmpeg.sh"
    clear
    ffr build-ffmpeg.sh
}
