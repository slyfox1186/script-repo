#!/usr/bin/env bash

# Constants
MASTER_FOLDER="$HOME/python-venv"
VENV_NAME="myenv"
VENV_PATH="$MASTER_FOLDER/$VENV_NAME"
REQUIREMENTS_FILE="$VENV_PATH/requirements.txt"

# Set your default pip packages
pip_packages=(
    async-lru async-openai async-timeout attrs avro Babel backoff bcrypt beautifulsoup4
    colorama ffpb Flask fuzzywuzzy google-speech jsonschema nltk openai python-dateutil
    python-dotenv python-Levenshtein python-whois regex requests setuptools termcolor wheel
    whois
)

# Activate the virtual environment
activate_venv() {
    source "$VENV_PATH/bin/activate"
}

# Deactivate the virtual environment
deactivate_venv() {
    deactivate &>/dev/null
}

# Install or update packages from requirements.txt or default array
install_packages() {
    pip install --upgrade pip
    if [[ -f "$REQUIREMENTS_FILE" ]]; then
        pip install -r "$REQUIREMENTS_FILE"
    else
        printf "%s\n" "${pip_packages[@]}" | pip install -r /dev/stdin
    fi
}

# Handle specific packages (install, upgrade, remove)
handle_specific_packages() {
    local operation=$1; shift
    activate_venv
    for package in "$@"; do
        case "$operation" in
            install) pip install "$package" ;;
            upgrade) pip install --upgrade "$package" ;;
            remove) pip uninstall -y "$package" ;;
        esac
    done
    deactivate_venv
}

# Create the virtual environment and install default or specified packages
create_venv() {
    echo "Creating Python virtual environment at $VENV_PATH..."
    mkdir -p "$VENV_PATH" && python3 -m venv "$VENV_PATH"
    activate_venv
    install_packages
    echo "Installation completed."
    deactivate_venv
}

# Update the virtual environment with new or updated packages
update_venv() {
    [[ -d "$VENV_PATH" ]] || { echo "Virtual environment does not exist, creating..."; create_venv; return; }
    echo "Updating Python virtual environment at $VENV_PATH..."
    activate_venv
    install_packages
    echo "Update completed."
    deactivate_venv
}

# Delete the virtual environment
delete_venv() {
    echo "Deleting Python virtual environment at $VENV_PATH..."
    rm -rf "$VENV_PATH"
    echo "Deletion completed."
}

# List installed packages in the virtual environment
list_packages() {
    [[ -d "$VENV_PATH" ]] || { echo "Virtual environment does not exist."; return; }
    activate_venv
    pip list
    deactivate_venv
}

# Import packages from pip freeze
import_packages() {
    if [[ -d "$VENV_PATH" ]]; then
        echo "Importing packages from pip freeze into $REQUIREMENTS_FILE..."
        activate_venv
        pip freeze | awk -F'=' '{print $1}' > "$REQUIREMENTS_FILE"
        echo "Packages imported successfully and stored in $REQUIREMENTS_FILE."
        deactivate_venv
    else
        echo "Virtual environment does not exist. Create one using the -c or --create option."
    fi
}

# Add the virtual environment's bin folder to the user's PATH
add_to_path() {
    local bashrc_file="$HOME/.bashrc"
    local path_entry="export PATH=\"$VENV_PATH/bin:\$PATH\""

    if grep -q "$path_entry" "$bashrc_file"; then
        echo "Virtual environment's bin folder is already in PATH."
    else
        echo "Adding virtual environment's bin folder to PATH..."
        echo "$path_entry" >> "$bashrc_file"
        source "$bashrc_file"
        echo "Virtual environment's bin folder has been added to PATH."
    fi
}

# Display help
display_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help                 Display this help message.
  -l, --list                 List installed packages in the virtual environment.
  -i, --import               Import packages from pip freeze into the requirements.txt file.
  -c, --create               Create a new Python virtual environment.
  -u, --update               Update the existing Python virtual environment.
  -d, --delete               Delete the Python virtual environment.
  -a, --add PACKAGES         Install specific packages (space-separated) in the virtual environment.
  -U, --upgrade PACKAGES     Upgrade specific packages (space-separated) in the virtual environment.
  -r, --remove PACKAGES      Remove specific packages (space-separated) from the virtual environment.
  -p, --path                 Add the virtual environment's bin folder to the user's PATH.

Examples:
  $0 --help
  $0 --create
  $0 --path
EOF
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help) display_help; exit 0 ;;
        -c|--create) create_venv; exit 0 ;;
        -u|--update) update_venv; exit 0 ;;
        -d|--delete) delete_venv; exit 0 ;;
        -l|--list) list_packages; exit 0 ;;
        -i|--import) import_packages; exit 0 ;;
        -a|--add) shift; handle_specific_packages install "$@"; exit 0 ;;
        -U|--upgrade) shift; handle_specific_packages upgrade "$@"; exit 0 ;;
        -r|--remove) shift; handle_specific_packages remove "$@"; exit 0 ;;
        -p|--path) add_to_path; exit 0 ;;
        *) echo "Invalid option: $1" >&2; display_help; exit 1 ;;
    esac
    shift
done

# If no arguments provided, show help
display_help
