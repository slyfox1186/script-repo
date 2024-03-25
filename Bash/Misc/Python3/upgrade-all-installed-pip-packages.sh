#!/usr/bin/env bash

venv_dir="$HOME/python-venv"

mkdir -p "$venv_dir"

activate_venv() {
    local pkg="$1"
    local venv_path="$venv_dir/$pkg"

    if [ ! -d "$venv_path" ]; then
        echo "Creating virtual environment for $pkg..."
        python3 -m venv "$venv_path"
    fi

    echo "Activating virtual environment for $pkg..."
    source "$venv_path/bin/activate"
}

deactivate_venv() {
    echo "Deactivating virtual environment..."
    deactivate
}

list_pkgs="$(pip list --format=columns | awk 'NR > 2 {print $1}')"

for pkg in $list_pkgs; do
    if [ "$pkg" != "wxPython" ]; then
        activate_venv "$pkg"

        echo "Upgrading $pkg..."
        pip install --upgrade "$pkg"

        deactivate_venv
        echo
    fi
done

echo "Upgrading pip..."
pip install --user --upgrade pip
