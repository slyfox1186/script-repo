#!/usr/bin/env bash
# Database Related Functions

# POSTGRES DB
sql_mem() {
    if [[ -z "$1" ]]; then
        read -p "How many memories do you want to list (default 5): " NUM
    else
        NUM="$1"
    fi

    psql -U jman -d phi4nix -c "SELECT * FROM messages ORDER BY created_at DESC LIMIT $NUM;"
}