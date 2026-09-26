#!/usr/bin/env bash

geds() {
    sudo -H -u root -- gedit "$@" &>/dev/null
}
