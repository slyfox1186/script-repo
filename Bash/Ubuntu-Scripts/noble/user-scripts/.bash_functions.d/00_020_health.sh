#!/usr/bin/env bash

# Post-upgrade sanity check. Safe to run on its own at any time. Catches:
#   - new kernels that get installed but never actually booted
#   - an NVIDIA userspace upgrade that leaves no matching kernel module behind,
#     which kills the GPU at the next boot without apt reporting anything
health() {
    local running newest rc=0
    local -a kernels
    running=$(uname -r)

    # Glob instead of `ls`: the interactive `ls` alias carries -F, which appends
    # a trailing slash to the directory name so it never matches `uname -r`.
    # `command` for the same reason - aliases expand inside function bodies.
    kernels=(/lib/modules/*/)
    kernels=("${kernels[@]%/}")
    kernels=("${kernels[@]##*/}")
    if [[ ${kernels[0]} == "*" ]]; then
        newest=$running
    else
        newest=$(printf '%s\n' "${kernels[@]}" | sort -V | tail -n1)
    fi

    if ! command dpkg -s linux-generic &>/dev/null; then
        echo -e "${RED}Kernel: linux-generic is not installed - no new kernels will arrive.${NC}"
        echo "  Fix: sudo apt -y install linux-generic"
        rc=1
    elif [[ $running != "$newest" ]]; then
        echo -e "${YELLOW}Kernel: running $running but $newest is installed. Reboot to use it.${NC}"
        rc=1
    fi

    if command grep -qs 0x10de /sys/bus/pci/devices/*/vendor; then
        if ! compgen -G "/lib/modules/$newest/updates/dkms/nvidia.ko*" > /dev/null; then
            echo -e "${RED}GPU: no NVIDIA kernel module built for $newest.${NC}"
            echo "  Fix: sudo apt -y install nvidia-open && sudo reboot"
            rc=1
        elif ! nvidia-smi &> /dev/null; then
            echo -e "${YELLOW}GPU: NVIDIA module built but not loaded. Reboot to activate it.${NC}"
            rc=1
        fi
    fi

    ((rc)) || echo -e "${GREEN}OK: running newest kernel ($running); nothing needs attention.${NC}"
    return $rc
}
