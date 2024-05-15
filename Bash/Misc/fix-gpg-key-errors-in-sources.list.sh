#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

keys=(0E98404D386FA1D9 54404762BBB6E853)

for key in ${keys[@]}; do
    apt-key adv --keyserver "hkp://keyserver.ubuntu.com:80" --recv "$key"
done
