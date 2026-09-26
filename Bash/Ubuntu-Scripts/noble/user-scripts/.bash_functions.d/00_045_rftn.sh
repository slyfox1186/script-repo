#!/usr/bin/env bash

## Refresh thumbnail cache
rftn() {
    sudo rm -fr "$HOME/.cache/thumbnails"*
    sudo file "$HOME/.cache/thumbnails"
}
