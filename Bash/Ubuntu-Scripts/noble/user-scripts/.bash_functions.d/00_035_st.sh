#!/usr/bin/env bash

# Get current time
st() {
    date +%r | cut -d " " -f1-2 | grep -E "^.*$"
}
