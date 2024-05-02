#!/usr/bin/env bash

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this without root or sudo."
    exit
fi

echo
read -p "To link static choose yes else choose no (y/n): " choice
case "$choice" in
    [yY]) yay -S rate-mirrors-bin ;;
    [nN]) yay -S rate-mirrors ;;
esac
