#!/usr/bin/env bash

gteds() {
    sudo -H -u root -- gnome-text-editor "$@" &>/dev/null
}
