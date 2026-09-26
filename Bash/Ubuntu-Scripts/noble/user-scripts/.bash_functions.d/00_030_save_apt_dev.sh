#!/usr/bin/env bash

# Pipe all development packages names to file
save_apt_dev() {
    apt-cache search dev | grep '\-dev' | cut -d " " -f1 | sort > dev-packages.list
    gnome-text-editor dev-packages.list
}
