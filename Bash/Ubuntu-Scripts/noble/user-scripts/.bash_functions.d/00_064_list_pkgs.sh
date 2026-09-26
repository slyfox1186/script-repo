#!/usr/bin/env bash

## LIST INSTALLED PACKAGES BY ORDER OF IMPORTANCE
list_pkgs() {
    dpkg-query -Wf '${Package;-40}${Priority}\n' | sort -b -k2,2 -k1,1
}
