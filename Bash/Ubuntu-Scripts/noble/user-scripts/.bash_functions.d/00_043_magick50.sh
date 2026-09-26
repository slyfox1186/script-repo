#!/usr/bin/env bash

# Downsample image to 50% of the original dimensions using sharper settings
magick50() {
    local pic

    for pic in *.jpg; do
        convert "$pic" -colorspace sRGB -filter LanczosRadius -distort Resize 50% -colorspace sRGB "${pic%.jpg}-50.jpg"
    done
}
