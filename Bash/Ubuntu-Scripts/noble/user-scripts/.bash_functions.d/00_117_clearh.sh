#!/usr/bin/env bash

# Clear Bash History
clearh() {
    history -c
    clear; ls -1AhFv
    echo -e "\n${GREEN}Bash History Cleared${NC}"
}
