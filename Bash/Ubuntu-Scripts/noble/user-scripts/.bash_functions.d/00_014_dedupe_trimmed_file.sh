#!/usr/bin/env bash

# Remove trailing spaces and duplicate lines in place.
dedupe_trimmed_file() {
    perl -i -lne "s/\s*$//; print if ! \$x{\$_}++" "$1"
    gnome-text-editor "$1"
}
