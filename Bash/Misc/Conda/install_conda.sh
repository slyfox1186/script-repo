#!/usr/bin/env bash

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Display messages in different colors
echo_success() {
    echo -e "\n\e[32m$1\e[0m"
}

echo_warning() {
    echo -e "\n\e[33m$1\e[0m"
}

echo_error() {
    echo -e "\n\e[31m$1\e[0m"
    exit 1
}

# Check if Conda is installed
check_conda_installed() {
    # Source Conda environment
    CONDA_PATH=$(find $HOME -type f -path "$HOME/miniconda*/*/conda.sh" 2>/dev/null | sort -uV | head -n1)

    if [[ -n "$CONDA_PATH" ]]; then
        source "$CONDA_PATH"
        echo_success "Sourced Conda successfully."
        echo
    else
        echo_error "Failed to source Conda. Please check your Conda installation."
        exit 1
    fi
}

set_output_folder() {
    read -p "Enter the name of the output folder to create: " PARENT_FOLDER

    if [[ -z "$PARENT_FOLDER" ]]; then
        set_output_folder
    fi
      echo "$PARENT_FOLDER"
}

# Find the latest Python 3 version
find_latest_python_version() {
    conda search "python=3" | grep -oP '^python\s+\K([0-9]+\.[0-9]+\.[0-9]+)(?!.*rc)' | sort -uV
    echo
    read -p "Enter the python version you want to use: " LATEST_PYTHON
    if [[ -z "$LATEST_PYTHON" ]]; then
        find_latest_python_version
    fi
}

# Create the parent folder structure
create_parent_folder() {
    echo_warning "Creating parent folder: $PARENT_FOLDER..."
    if mkdir -p "$PARENT_FOLDER"; then
        echo_success "Folder created succesfully!"
    else
        echo_error "Failed to create folder!"
    fi
    if cd "$PARENT_FOLDER"; then
        echo_success "Created and moved into parent folder: $PARENT_FOLDER"
    else
        echo_error "Failed to change to parent directory."
    fi
}

prompt_conda_env_name() {
    read -p "Enter the name for the new Conda environment: " ENV_NAME
    if [[ -z "$ENV_NAME" ]]; then
        prompt_conda_env_name
    fi
    echo "$ENV_NAME"
}

# Check if the environment already exists
check_env_exists() {
    if conda env list | grep -q "^$ENV_NAME\s"; then
        echo_warning "Conda environment \"$ENV_NAME\" already exists!"
        read -p "Do you want to overwrite the environment? (y/n): " choice
        case "$choice" in
            [yY]*) 
                echo_warning "Removing the existing environment \"$ENV_NAME\"..."
                if conda remove -n "$ENV_NAME" --all -y; then
                    echo_success "Environment \"$ENV_NAME\" removed!"
                else
                    echo_error "Failed to remove the Conda environment \"$ENV_NAME\"!"
                fi
                ;;
            [nN]*)
                echo_warning "Keeping the existing environment \"$ENV_NAME\". Exiting!"
                exit 0
                ;;
            *)
                echo_error "Invalid option. Exiting!"
                ;;
        esac
    fi
}

# Create a new Conda environment
create_conda_env() {
    echo_success "Creating a new Conda environment \"$ENV_NAME\" with Python $PYTHON_VERSION..."
    echo
    if conda create -n "$ENV_NAME" python="$PYTHON_VERSION" -y; then
        echo_success "Conda environment \"$ENV_NAME\" created successfully!"
    else
        echo_error "Failed to create the Conda environment \"$ENV_NAME\"!"
    fi
}

# Activate the new Conda environment
activate_conda_env() {
    echo_warning "Activating the \"$ENV_NAME\" environment..."
    if source "$(conda info --base)/etc/profile.d/conda.sh"; then
        echo_success "Activation successful!"
    else
        echo_error "Activation failed!"
    fi
    if conda activate "$ENV_NAME"; then
        echo_success "Activated Conda environment: $ENV_NAME"
    else
        echo_error "Failed to activate the new Conda environment: $ENV_NAME"
    fi
}

# Install Conda and Pip packages
install_packages() {
    conda_packages=(
        flask
        markupsafe
        nltk
        bleach
        werkzeug
        python-dotenv
        beautifulsoup4
        requests
        python-magic
        pillow
        pypdf2
        python-docx
        openpyxl
        sympy
    )

    pip_packages=(
        aiofiles
        aiohttp
        aiosignal
        alembic
        async-timeout
        beautifulsoup4
        bleach
        bs4
        cachetools
        cffi
        chardet
        cryptography
        Flask
        Flask-Cors
        Flask-SocketIO
        Flask-SQLAlchemy
        gensim
        h5py
        httpcore
        httpx
        huggingface-hub
        Hypercorn
        hyperframe
        Jinja2
        keras
        lxml
        Markdown
        MarkupSafe
        nltk
        numpy
        openai
        openpyxl
        optuna
        packaging
        pandas
        pillow
        pydantic
        pydantic_core
        pyOpenSSL
        PyPDF2
        python-dateutil
        python-docx
        python-dotenv
        python-engineio
        python-magic
        python-socketio
        PyYAML
        quart
        quart-cors
        quart-depends
        regex
        requests
        safetensors
        scikit-learn
        scimpy
        scipy
        sentence-transformers
        simple-websocket
        six
        soupsieve
        spacy
        SQLAlchemy
        sympy
        tensorflow
        termcolor
        tf-keras
        tiktoken
        torch
        torchaudio
        torchvision
        tqdm
        transformers
        typing_extensions
    )

    echo_warning "Installing conda packages from conda-forge..."
    echo
    if conda install -c conda-forge "${conda_packages[@]}" -y; then
        echo_success "Conda packages installed successfully!"
    else
        echo_error "Conda packages failed to install!"
    fi

    echo_warning "Installing pip packages..."
    echo
    if pip install "${pip_packages[@]}"; then
        echo_success "Pip packages installed successfully!"
    else
        echo_error "Pip failed to install!"
    fi
}

# Download NLTK datasets
download_nltk_data() {
    echo_warning "Downloading NLTK datasets..."
    echo
    if python -m nltk.downloader all; then
        echo_success "NLTK datasets downloaded successfully!"
    else
        echo_warning "NLTK datasets failed to download!"
    fi
}

# Download and install pywebcopy from source
install_pywebcopy_from_source() {
    local url="https://github.com/rajatomar788/pywebcopy/archive/refs/tags/v7.0.1.tar.gz"
    local archive_name="pywebcopy-v7.0.1.tar.gz"
    local folder_name="pywebcopy-7.0.1"

    echo "Downloading pywebcopy from $url..."
    wget --show-progress -cqO "$archive_name" "$url"
    echo_success "Downloaded pywebcopy successfully."

    echo_warning "Extracting the tar file..."
    if tar -zxf "$archive_name"; then
        echo_success "Extracted the pywebcopy archive!"
    else
        echo_error "Failed to extracted the pywebcopy archive!"
    fi

    if cd "$folder_name"; then
        if [[ -f "setup.py" ]]; then
            echo "Running 'python3 setup.py install' in the pywebcopy directory..."
            if python3 setup.py install; then
                echo_success "pywebcopy installed successfully."

                # Clean up after successful installation
                cd ../  # Move out of the pywebcopy directory before cleanup
                rm -fr "$archive_name" "$folder_name"
                echo_success "Cleaned up pywebcopy files."
            else
                echo_error "pywebcopy installation failed."
            fi
        else
            echo_error "'setup.py' not found in the extracted pywebcopy directory."
        fi
    else
        echo_error "Failed to change directory to $folder_name."
    fi
}

# Main script
main() {
    check_conda_installed
    PARENT_FOLDER=$(set_output_folder)
    echo_warning "Finding the latest Python 3 versions..."
    find_latest_python_version
    create_parent_folder
    echo
    ENV_NAME=$(prompt_conda_env_name)
    PYTHON_VERSION="${PYTHON_VERSION:-$LATEST_PYTHON}"
    check_env_exists
    create_conda_env
    activate_conda_env
    install_packages
    download_nltk_data
    install_pywebcopy_from_source
}

# Execute the main function
main "$@"
