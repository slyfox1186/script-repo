#!/usr/bin/env bash

# Function to check if a specific architecture is supported
check_arch_support() {
    local arch="$1"
    if gcc -Q --help=target | grep -Eo "\s$arch" | grep -q "$arch"; then
        march="$arch"
        return 0
    else
        return 1
    fi
}

# List of architectures to check
archs=(
    # Test AMD architectures
    "znver4"
    "znver3"
    "znver2"
    "znver1"
    # Test Intel architectures
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

# Determine the appropriate -march value
march="native"  # Default value

# Check for AMD and Intel architectures
for arch in "${archs[@]}"; do
    if check_arch_support "$arch"; then
        break
    fi
done

if [ "$march" = "native" ]; then
    echo "No specific architecture matched. Using native."
fi

# You can now call this script and retrieve the $march variable
echo "$march"
