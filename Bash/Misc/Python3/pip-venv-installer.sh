
#!/usr/bin/env bash

# Constants
MASTER_FOLDER="$HOME/python-venv"
VENV_NAME="myenv"
VENV_PATH="$MASTER_FOLDER/$VENV_NAME"
REQUIREMENTS_FILE="$VENV_PATH/requirements.txt"

# Set your default pip packages
pip_packages=(
    argparse async async-lru async-openai async-timeout attr attrs bcrypt
    beautifulsoup4 brotli bs4 colorama contrib cryptography Cython eval
    executing fabric ffmpeg-python ffpb "Flask>=3.0.0" fuzzywuzzy google-speech
    Levenshtein modules nltk openai pandas psutil pydantic pygments PyOpenGL pyparsing
    pyppeteer pyproj pyproject pyproject_hooks pyqt5 pyquery PyTest python-dotenv
    PyTest "pymediainfo==4.0" python-Levenshtein python-whois redis regex requests
    requests-html scrapy "selenium>=4.18.0" service setuptools soupsieve sqlparse
    termcolor tk toml urllib3 venv_dependencies virtualenv wheel whois
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
    pip "$operation" "$@"
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

    grep -q "$path_entry" "$bashrc_file" || {
        echo "Adding virtual environment's bin folder to PATH..."
        echo "$path_entry" >> "$bashrc_file"
        source "$bashrc_file"
        echo "Virtual environment's bin folder has been added to PATH."
    }
}

# Display help
display_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help                 Display this help message.

  -i, --import               Import packages from pip freeze into the requirements.txt file.
  -l, --list                 List installed packages in the virtual environment.
  -p, --path                 Add the virtual environment's bin folder to the user's PATH.

  -c, --create               Create a new Python virtual environment.
  -d, --delete               Delete the Python virtual environment.
  -u, --update               Update the existing Python virtual environment.

  -a, --add PACKAGES         Install specific packages (space-separated) in the virtual environment.
  -r, --remove PACKAGES      Remove specific packages (space-separated) from the virtual environment.
  -U, --upgrade PACKAGES     Upgrade specific packages (space-separated) in the virtual environment.

Examples:
  $0 -h
  $0 -c
  $0 -p
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
        -U|--upgrade) shift; handle_specific_packages install --upgrade "$@"; exit 0 ;;
        -r|--remove) shift; handle_specific_packages uninstall -y "$@"; exit 0 ;;
        -p|--path) add_to_path; exit 0 ;;
        *) echo "Invalid option: $1" >&2; display_help; exit 1 ;;
    esac
    shift
done

# If no arguments provided, show help
display_help
