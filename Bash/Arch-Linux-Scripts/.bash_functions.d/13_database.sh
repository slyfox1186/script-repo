#!/usr/bin/env bash
# Database Related Functions

# POSTGRES DB
sql_mem() {
    local NUM
    if [[ -z "$1" ]]; then
        read -rp "How many memories do you want to list (default 5): " NUM
    else
        NUM="$1"
    fi
    NUM="${NUM:-5}"

    if [[ ! "$NUM" =~ ^[0-9]+$ ]]; then
        echo "Error: argument must be a positive integer (got: $NUM)" >&2
        return 1
    fi

    psql -U jman -d phi4nix -c "SELECT * FROM messages ORDER BY created_at DESC LIMIT $NUM;"
}
