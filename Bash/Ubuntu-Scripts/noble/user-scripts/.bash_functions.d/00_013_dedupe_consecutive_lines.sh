#!/usr/bin/env bash

# Remove consecutive duplicate lines: output to the terminal.
dedupe_consecutive_lines() {
    awk 'f!=$0{print;f=$0}' "$1"
}
