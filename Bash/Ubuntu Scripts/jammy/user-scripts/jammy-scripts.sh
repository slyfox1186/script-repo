#!/usr/bin/env bash

script_array=(".bashrc" ".bash_aliases" ".bash_functions")
tf=$(mktemp)
td=$(mktemp -d)

fail() {
    echo -e "\\n[ERROR] $1\\n"
    read -p "Press enter to exit."
    exit 1
}

if ! dpkg -l | grep -o wget &>/dev/null; then
    sudo apt-get -y install wget
    clear
fi

cd "$td" || exit 1

cat > "$tf" <<'EOF'
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc
EOF

wget -qN - -i "$tf"

find . ! \( -name ".*" -o -name "*.sh" \) -type f -delete 2>/dev/null

for script in "${script_array[@]}"; do
    cp -f "$script" "$HOME" || fail "Failed to move $script to $HOME. Line $LINENO"
    chown "$USER":"$USER" "$HOME/$script" || fail "Failed to update permissions for $script. Line $LINENO"
done

cd "$HOME" || exit 1
for script in "${script_array[@]}"; do
    command -v nano &>/dev/null || fail "The script failed to open the newly installed scripts using the EDITOR \"nano\"."
    nano "$script"
done

sudo rm -fr "$td"
