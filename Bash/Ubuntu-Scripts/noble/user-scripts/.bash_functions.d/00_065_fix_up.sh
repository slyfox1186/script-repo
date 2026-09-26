#!/usr/bin/env bash

## FIX USER FOLDER PERMISSIONS up = user permissions
fix_up() {
    sudo find "$HOME/.gnupg" -type f -exec chmod 600 {} \;
    sudo find "$HOME/.gnupg" -type d -exec chmod 700 {} \;
    sudo find "$HOME/.ssh" -type d -exec chmod 700 {} \;
    sudo find "$HOME/.ssh/id_rsa.pub" -type f -exec chmod 644 {} \;
    sudo find "$HOME/.ssh/id_rsa" -type f -exec chmod 600 {} \;
}
