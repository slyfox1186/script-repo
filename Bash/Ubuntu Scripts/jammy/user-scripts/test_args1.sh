#!/usr/bin/env bash

clear

if [ -n "${1}" ]; then
    echo "${1}"
else
    echo 'No args were passed.'
fi
