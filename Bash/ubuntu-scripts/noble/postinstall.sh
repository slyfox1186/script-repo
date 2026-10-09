#!/bin/sh

# Install language packs for English
apt -y install $(check-language-support -l en)
