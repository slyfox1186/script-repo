#!/usr/bin/env bash

# User inputs
original_size_mb=500        # Original file size in MB
target_size_mb=700         # Desired target size in MB
audio_bitrate_kbps=128     # Audio bitrate in kbps
duration_seconds=7200      # Duration of the video in seconds

# Convert sizes to bits
original_size_bits=$((original_size_mb * 1024 * 1024 * 8))
target_size_bits=$((target_size_mb * 1024 * 1024 * 8))
audio_bitrate_bps=$((audio_bitrate_kbps * 1000))

# Calculate target video bitrate
target_video_bitrate_bps=$(( (target_size_bits - (audio_bitrate_bps * duration_seconds)) / duration_seconds ))

# Convert target video bitrate to kbps for FFmpeg
target_video_bitrate_kbps=$((target_video_bitrate_bps / 1000))

# Command to resize the movie
ffmpeg -i input_movie.mp4 -b:v ${target_video_bitrate_kbps}k -b:a ${audio_bitrate_kbps}k output_movie.mp4

echo "Target video bitrate: ${target_video_bitrate_kbps} kbps"
