#!/usr/bin/env bash

# Set the path for the virtual environment directory
venv_dir="$HOME/python-venv"

# Create the virtual environment directory if it doesn't exist
mkdir -p "$venv_dir"

# Function to create or activate a virtual environment for a package
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

# Function to deactivate the virtual environment
deactivate_venv() {
    echo "Deactivating virtual environment..."
    deactivate
}

# Get the list of installed packages
list_pkgs="$(pip list --format=columns | awk 'NR > 2 {print $1}')"

# Iterate over each package
for pkg in $list_pkgs; do
    if [ "$pkg" != "wxPython" ]; then
        activate_venv "$pkg"

        echo "Upgrading $pkg..."
        pip install --upgrade "$pkg"

        deactivate_venv
        echo
    fi
done

# Upgrade pip outside of any virtual environment
echo "Upgrading pip..."
pip install --user --upgrade pip
