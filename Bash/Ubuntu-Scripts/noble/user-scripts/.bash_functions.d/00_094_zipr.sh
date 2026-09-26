#!/usr/bin/env bash

## RECURSIVELY UNZIP ZIP FILES AND NAME THE OUTPUT FOLDER THE SAME NAME AS THE ZIP FILE
zipr() {
    clear
    find . -type f -iname '*.zip' -exec sh -c 'for archive do unzip -o -d "${archive%.*}" "$archive" && trash-put "$archive"; done' sh {} +
}
