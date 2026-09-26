#!/usr/bin/env bash

# Update OS, then confirm the upgrade did not leave the box in a state that only
# breaks at the next boot. apt exits 0 for both failures that `health` guards.
update() {
    if ! sudo apt update; then
        echo
        echo -e "${YELLOW}Note: 'apt update' reported an error above (usually one unreachable repo).${NC}"
        echo -e "${YELLOW}Package lists may be stale, so a new version could be missed.${NC}"
        echo -e "${YELLOW}Upgrading anyway from the lists already on disk.${NC}"
        echo
    fi
    sudo apt -y full-upgrade
    echo
    health
}
