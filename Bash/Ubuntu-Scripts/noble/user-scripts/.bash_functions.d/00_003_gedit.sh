#!/usr/bin/env bash

## WHEN LAUNCHING CERTAIN PROGRAMS FROM THE TERMINAL, SUPPRESS ANY WARNING MESSAGES ##
gedit() {
    command gedit "$@" &>/dev/null
}
