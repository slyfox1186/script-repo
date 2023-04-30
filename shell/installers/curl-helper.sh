#!/bin/bash

clear

git clone -n --depth=1 --filter=tree:0 \
  https://github.com/slyfox1186/script-repo
cd script-repo || exit 1
git sparse-checkout set --no-cone shell/installers/build-curl
git checkout
cd shell/installers || exit 1
sudo bash build-curl
