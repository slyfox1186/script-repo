#!/usr/bin/env bash


    case "$1" in
        ([!$excluded_chars]*[!$excluded_chars]) USER="$1"
                                                echo $USER
                                                exit 0
                                                ;;
    esac
done
