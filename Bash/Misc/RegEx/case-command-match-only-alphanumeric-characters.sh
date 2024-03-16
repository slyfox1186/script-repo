#!/usr/bin/env bash

excluded_chars='*&^%$#@!\\_/?\]\[\(\)<>;:=+|{}'

while (($# > 0)); do
    case "$1" in
        ([!$excluded_chars]*[!$excluded_chars]) USER="$1"
                                                echo $USER
                                                exit 0
                                                ;;
    esac
done
