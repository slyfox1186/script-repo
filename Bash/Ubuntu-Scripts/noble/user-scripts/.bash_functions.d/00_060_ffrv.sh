#!/usr/bin/env bash

ffrv() {
    bash -v "$1" --build --enable-gpl-and-non-free --latest
}
