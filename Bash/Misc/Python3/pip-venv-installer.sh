#!/usr/bin/env bash

# Help Menu: ./pip-virtual-installer.sh -h

# Define the master folder path
MASTER_FOLDER="$HOME/python-venv"
VENV_NAME="myenv"
REQUIREMENTS_FILE="$MASTER_FOLDER/requirements.txt"

# Define an array of pip package names
pip_packages=(
    "async-lru" "async-openai" "async-timeout" "attrs" "avro" "Babel" "backoff" "bcrypt" "beautifulsoup4"
    "colorama" "ffpb" "Flask" "fuzzywuzzy" "google-speech" "jsonschema" "nltk" "openai" "python-dateutil"
    "python-dotenv" "python-Levenshtein" "python-whois" "regex" "requests" "setuptools" "termcolor" "wheel"
    "whois"
)

# Function to install specific packages
install_specific_packages() {
    activate_venv
    for package in "${@}"; do
        pip install "$package"
    done
    deactivate_venv
}

# Function to upgrade specific packages
upgrade_specific_packages() {
    activate_venv
    for package in "${@}"; do
        pip install --upgrade "$package"
    done
    deactivate_venv
}

# Function to remove specific packages
remove_specific_packages() {
    activate_venv
    for package in "${@}"; do
        pip uninstall -y "$package"
    done
    deactivate_venv
}

# Function to activate the virtual environment
activate_venv() {
    source "$MASTER_FOLDER/$VENV_NAME/bin/activate"
}

# Function to deactivate the virtual environment
deactivate_venv() {
    deactivate
}

# Function to install packages from requirements.txt or default pip_packages array
install_packages() {
    pip install --upgrade pip

    if [[ -f "$REQUIREMENTS_FILE" ]]; then
        pip install -r "$REQUIREMENTS_FILE"
    else
        printf "%s\n" "${pip_packages[@]}" > "$REQUIREMENTS_FILE"
        pip install -r "$REQUIREMENTS_FILE"
    fi
}

# Function to import packages from pip freeze
import_packages() {
    if [[ -d "$MASTER_FOLDER/$VENV_NAME" ]]; then
        printf "\n%s\n\n" "Importing packages from pip freeze..."
        activate_venv
        pip freeze | awk -F'=' '{print $1}' > "$REQUIREMENTS_FILE"
        printf "\n%s\n\n" "Packages imported successfully and stored in $REQUIREMENTS_FILE."
        deactivate_venv
    else
        printf "\n%s\n\n" "Virtual environment does not exist. Create one using the -c or --create option."
    fi
}

# Function to create a virtual environment and install packages
create_venv() {
    echo "Creating Python virtual environment..."
    mkdir -p "$MASTER_FOLDER"
    python3 -m venv "$MASTER_FOLDER/$VENV_NAME"

    echo "Activating virtual environment..."
    activate_venv

    echo "Installing pip packages..."
    install_packages

    echo "Installation completed."
    deactivate_venv
}

# Function to update virtual environment
update_venv() {
    if [[ -d "$MASTER_FOLDER/$VENV_NAME" ]]; then
        printf "\n%s\n\n" "Updating Python virtual environment..."
        activate_venv
        install_packages
        printf "\n%s\n\n" "Update completed."
        deactivate_venv
    else
        printf "\n%s\n\n" "Virtual environment does not exist. Creating one now..."
        create_venv
    fi
}

# Function to delete virtual environment
delete_venv() {
    printf "\n%s\n\n" "Deleting Python virtual environment..."
    rm -rf "$MASTER_FOLDER/$VENV_NAME"
    printf "\n%s\n\n" "Deletion completed."
    [[ -f "$REQUIREMENTS_FILE" ]] && rm -f "$REQUIREMENTS_FILE"
}

# Function to list installed packages
list_packages() {
    if [[ -d "$MASTER_FOLDER/$VENV_NAME" ]]; then
        printf "\n%s\n\n" "Listing installed packages in the virtual environment..."
        activate_venv
        pip list
        deactivate_venv
    else
        printf "\n%s\n\n" "Virtual environment does not exist. Create one using the -c or --create option."
    fi
}

# Function to display help
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo
    echo "  -h, --help                 Display this help message."
    echo "  -l, --list                 List the installed packages in the virtual environment."
    echo "  -i, --import               Import packages from pip freeze into the requirements.txt file."
    echo "  -c, --create               Create a new Python virtual environment."
    echo "  -u, --update               Update the existing Python virtual environment."
    echo "  -d, --delete               Delete the Python virtual environment."
    echo "  -a, --add PACKAGES         Install specific packages (comma-separated) in the virtual environment."
    echo "  -U, --upgrade PACKAGES     Upgrade specific packages (comma-separated) in the virtual environment."
    echo "  -r, --remove PACKAGES      Remove specific packages (comma-separated) from the virtual environment."
    echo
    echo "Examples: ./$0 --help"
    echo "Examples: ./$0 --create"
    echo "Examples: ./$0 -i && ./$0 -U setuptools,wheel"
}

# Handling arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            display_help
            exit 0
            ;;
        -c|--create)
            create_venv
            ;;
        -u|--update)
            update_venv
            ;;
        -d|--delete)
            delete_venv
            ;;
        -l|--list)
            list_packages
            ;;
        -i|--import)
            import_packages
            ;;
        -a|--add)
            IFS=',' read -ra PACKAGES <<< "$2"
            install_specific_packages "${PACKAGES[@]}"
            shift
            ;;
        -U|--upgrade)
            IFS=',' read -ra PACKAGES <<< "$2"
            upgrade_specific_packages "${PACKAGES[@]}"
            shift
            ;;
        -r|--remove)
            IFS=',' read -ra PACKAGES <<< "$2"
            remove_specific_packages "${PACKAGES[@]}"
            shift
            ;;
        *)
            echo "Invalid option: $1. Use -h for help."
            exit 1
            ;;
    esac
    shift
done
