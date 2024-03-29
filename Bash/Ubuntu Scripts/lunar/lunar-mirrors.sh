
#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

fname="/etc/apt/sources.list"

if [[ ! -f "$fname.bak" ]]; then
    cp -f "$fname" "$fname.bak"
fi

cat > "$fname" <<EOF
deb https://atl.mirrors.clouvider.net/ubuntu/ lunar main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ lunar-updates main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ lunar-backports main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ lunar-security main restricted universe multiverse
EOF

if command -v nano &>/dev/null; then
    nano "$fname"
else
    echo -e "\\nThe script failed to locate nano to open the file...\\n"
fi

script_path=$(readlink -f "${BASH_SOURCE[0]}")
script_name=$(basename "$script_path")

[[ -f "$script_name" ]] && rm "$script_name"
