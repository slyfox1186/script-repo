#!/usr/bin/env bash

# Define the input and output file names
input_video="path/to/your/input_video.mp4"
output_video="path/to/your/normalized_output_video.mp4"

# Use ffmpeg with the loudnorm filter to normalize the audio
ffmpeg -i "$input_video" -c:v copy -af "loudnorm=I=-23:LRA=7:TP=-2" "$output_video"

# Explanation of the loudnorm filter parameters:
# I=-23: target integrated loudness in lufs (loudness units relative to full scale). -23 lufs is a common target for broadcast standards.
# Lra=7: loudness range target in lu. this value helps in controlling the range between the loudest and quietest parts.
# Tp=-2: true peak target in dbtp. it sets the maximum true peak level, preventing clipping.

# Note: -c:v copy tells ffmpeg to copy the video stream directly without re-encoding, so only the audio stream is processed.
