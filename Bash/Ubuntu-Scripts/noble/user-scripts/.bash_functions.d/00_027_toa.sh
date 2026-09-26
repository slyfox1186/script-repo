#!/usr/bin/env bash

# TAKE OWNERSHIP COMMANDS

toa() {
    sudo chown -R "$USER":"$USER" "$PWD"
    sudo chmod -R 744 "$PWD"
    clear; ls -1AvhF --color --group-directories-first
}
