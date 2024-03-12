#!/usr/bin/env bash

# Define the input and output file names
input_video="path/to/your/input_video.mp4"
output_video="path/to/your/normalized_output_video.mp4"

# Use ffmpeg with the loudnorm filter to normalize the audio
ffmpeg -i "$input_video" -c:v copy -af "loudnorm=I=-23:LRA=7:TP=-2" "$output_video"

# Explanation of the loudnorm filter parameters:
# I=-23: Target integrated loudness in LUFS (Loudness Units relative to Full Scale). -23 LUFS is a common target for broadcast standards.
# LRA=7: Loudness Range Target in LU. This value helps in controlling the range between the loudest and quietest parts.
# TP=-2: True Peak Target in dBTP. It sets the maximum true peak level, preventing clipping.

# Note: -c:v copy tells ffmpeg to copy the video stream directly without re-encoding, so only the audio stream is processed.
