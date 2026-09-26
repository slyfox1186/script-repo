#!/usr/bin/env bash

# Stop aria2 daemon
aria2_off() {
    clear
    killall aria2c
}
