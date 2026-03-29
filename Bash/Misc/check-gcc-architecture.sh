#!/usr/bin/env bash

check_arch_support() {
    local arch="$1"
    if gcc -Q --help=target | grep -Eo "\s$arch" | grep -q "$arch"; then
        march="$arch"
        return 0
    else
        return 1
    fi
}

archs=(
    "znver4"
    "znver3"
    "znver2"
    "znver1"
    "alderlake"
    "tigerlake"
    "cooperlake"
    "icelake-server"
    "icelake-client"
    "cascadelake"
    "cannonlake"
    "skylake-avx512"
    "skylake"
    "haswell"
    "ivybridge"
    "sandybridge"
)


for arch in "${archs[@]}"; do
    if check_arch_support "$arch"; then
        break
    fi
done

if [ "$march" = "native" ]; then
    echo "No specific architecture matched. Using native."
fi

echo "$march"
