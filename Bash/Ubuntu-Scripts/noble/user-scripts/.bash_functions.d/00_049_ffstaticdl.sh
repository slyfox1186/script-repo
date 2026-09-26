#!/usr/bin/env bash

ffstaticdl() {
    if wget --connect-timeout=2 --tries=2 --show-progress -cqO ffmpeg-n7.0.tar.xz https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n7.0-latest-linux64-lgpl-7.0.tar.xz; then
        mkdir ffmpeg-n7.0
        tar -Jxf ffmpeg-n7.0.tar.xz -C ffmpeg-n7.0 --strip-components 1
        cd ffmpeg-n7.0/bin || exit 1
        sudo cp -f ffmpeg ffplay ffprobe /usr/local/bin/
        clear
        ffmpeg -version
    else
        echo "Downloading the static FFmpeg binaries failed!"
        return 1
    fi
}
