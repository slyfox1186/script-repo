#!/Usr/bin/env bash

input_video="path/to/your/input_video.mp4"
output_video="path/to/your/normalized_output_video.mp4"

ffmpeg -i "$input_video" -c:v copy -af "loudnorm=I=-23:LRA=7:TP=-2" "$output_video"


