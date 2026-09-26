#!/usr/bin/env bash

big_img() {
    clear
    sudo find . -size +10M -type f -name "*.jpg" 2>/dev/null
}
