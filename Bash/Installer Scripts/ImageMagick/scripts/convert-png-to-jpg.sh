#!/Usr/bin/env bash


mkdir "output"

for f in *.png
do
    fsize=$(identify -ping -format "%wx%h" "$f")
    mogrify -monitor -path output/ -filter Triangle -define filter:support=2 -thumbnail "$fsize" \
            -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 90 -define jpeg:fancy-upsampling=off \
            -define png:compression-filter=5 -define png:compression-level=9 -define png:compression-strategy=1 \
            -define png:exclude-chunk=all -interlace none -colorspace sRGB -format jpg "$f"
done
