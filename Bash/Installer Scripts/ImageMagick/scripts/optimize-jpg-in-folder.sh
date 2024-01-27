#!/usr/bin/env bash

# https://github.com/slyfox1186/script-repo/new/main/Bash/Installer%20Scripts/ImageMagick/scripts
# Optimzes all jpg files in the script's folder
# Updated: 01.27.24

# Create the output directory
[ ! -d "output" ] && mkdir "output"

# FIND ALL JPG FILES AND OPTIMIZE THEM
for f in *.jpg
do
    dimensions=$(identify +ping -format "%wx%h" "$f")
    printf "\n%s\n" "Optimizing JPG: $f"
    mogrify -path output/ -monitor -filter Triangle -define filter:support=2 -thumbnail "$dimensions" \
            -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 90% -define jpeg:fancy-upsampling=off \
            -define jpeg:optimize-coding=true -define jpeg:colorspace=RGB -define jpeg:sampling-factor=2x2,1x1,1x1 \
            -define png:compression-filter=5 -define png:compression-level=9 -define png:compression-strategy=1 \
            -define png:exclude-chunk=all -interlace Plane -colorspace sRGB -format jpg "$f"
done
