#!/usr/bin/env bash

###################################
## FFPROBE LIST IMAGE DIMENSIONS ##
###################################

ffp() {
    find "$PWD" -type f -iname '*.jpg' -exec sh -c 'for image do identify -format "%wx%h" "$image"; printf " %s\n" "$image"; done' sh {} + > 00-pic-sizes.txt
}
