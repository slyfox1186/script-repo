#!/usr/bin/env bash


if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

keys=(112695A0E562B32A 54404762BBB6E853)

for key in ${keys[@]}; do
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv $key
done
