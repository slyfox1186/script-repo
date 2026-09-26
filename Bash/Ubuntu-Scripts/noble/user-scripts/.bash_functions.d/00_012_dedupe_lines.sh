#!/usr/bin/env bash

## AWK COMMANDS ##

# Remove duplicate lines: output to the terminal.
dedupe_lines() {
    awk '!seen[$0]++' "$1"
}
