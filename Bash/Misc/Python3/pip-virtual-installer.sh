#!/usr/bin/env bash

# Define the master folder path
MASTER_FOLDER="$HOME/python-venv"
VENV_NAME="myenv"
REQUIREMENTS_FILE="$MASTER_FOLDER/requirements.txt"

# Define an array of pip package names
pip_packages=(
    "adal" "aiohttp" "aiohttpx" "aiosignal" "annotated-types" "anyio" "appdirs" "asgiref" "async-generator"
    "async-lru" "async-openai" "async-timeout" "attrs" "avro" "Babel" "backoff" "bcrypt" "beautifulsoup4" "beniget"
    "blinker" "boto3" "botocore" "cachetools" "certifi" "cffi" "chardet" "charset-normalizer" "click" "cmarkgfm"
    "colorama" "colorlog" "commonmark" "cryptography" "dbus-python" "decorator" "Deprecated" "distro" "Django"
    "exceptiongroup" "ffpb" "fixedint" "Flask" "frozendict" "frozenlist" "future" "fuzzywuzzy" "gast" "gcovr"
    "gensim" "google-api-core" "google-auth" "google-speech" "googleapis-common-protos" "h11" "html5lib" "httpcore"
    "httpx" "idna" "importlib-metadata" "iniconfig" "invoke" "isodate" "itsdangerous" "Jinja2" "jmespath" "joblib"
    "jsonpointer" "jsonschema" "jsonschema-specifications" "lazyops" "Levenshtein" "loguru" "lxml" "Mako" "Markdown"
    "MarkupSafe" "marshmallow" "meson" "more-itertools" "msal" "msal-extensions" "msrest" "msrestazure" "multidict"
    "nltk" "npx" "numpy" "oauthlib" "olefile" "openai" "opencensus" "opencensus-context" "opencensus-ext-azure"
    "opencensus-ext-logging" "opentelemetry-api" "opentelemetry-sdk" "opentelemetry-semantic-conventions" "outcome"
    "packaging" "paramiko" "pillow" "pluggy" "ply" "portalocker" "proto-plus" "protobuf" "psutil" "py" "pyasn1"
    "pyasn1-modules" "pycairo" "pycparser" "pycups" "pydantic" "pydantic-settings" "pydantic_core" "pydash" "Pygments"
    "PyGObject" "pyinotify" "PyJWT" "PyNaCl" "pyOpenSSL" "pyparsing" "pyrsistent" "pysmbc" "PySocks" "pytest"
    "python-dateutil" "python-dotenv" "python-Levenshtein" "python-whois" "pythran" "pytz" "PyYAML" "rapidfuzz"
    "referencing" "regex" "requests" "requests-oauthlib" "rfc3987" "robot-detection" "rpds-py" "rsa" "ruamel.yaml"
    "ruamel.yaml.clib" "s3transfer" "scipy" "SCons" "selenium" "selenium-stealth" "simplejson" "six" "smart-open"
    "sniffio" "sortedcontainers" "soupsieve" "sqlparse" "strictyaml" "termcolor" "tiktoken" "tqdm" "trash-cli" "trio"
    "trio-websocket" "typing_extensions" "uamqp" "uritemplate" "urllib3" "web-cache" "webcolors" "webencodings" "Werkzeug"
    "whois" "wrapt" "wsproto" "yarl" "zipp"
)

# Function to import packages from pip freeze
import_packages() {
    if [[ -d "$MASTER_FOLDER/$VENV_NAME" ]]; then
        printf "\n%s\n\n" "Importing packages from pip freeze..."
        source "$MASTER_FOLDER/$VENV_NAME/bin/activate"
        pip freeze | awk -F'=' '{print $1}' > "$REQUIREMENTS_FILE"
        printf "\n%s\n\n" "Packages imported successfully and stored in $REQUIREMENTS_FILE."
        deactivate
    else
        printf "\n%s\n\n" "Virtual environment does not exist. Create one using the -c or --create option."
    fi
}

# Function to create virtual environment and install packages
create_venv() {
    echo "Creating Python virtual environment..."
    mkdir -p "$MASTER_FOLDER"
    python3 -m venv "$MASTER_FOLDER/$VENV_NAME"

    echo "Activating virtual environment..."
    source "$MASTER_FOLDER/$VENV_NAME/bin/activate"

    echo "Installing pip packages..."
    pip install --upgrade pip

    # Install packages from requirements.txt if it exists, otherwise use the default pip_packages array
    if [[ -f "$REQUIREMENTS_FILE" ]]; then
        pip install -r "$REQUIREMENTS_FILE"
    else
        # Output array content into the requirements.txt file
        printf "%s\n" "${pip_packages[@]}" > "$REQUIREMENTS_FILE"
        pip install -r "$REQUIREMENTS_FILE"
    fi

    echo "Installation completed."
    deactivate

    # Delete leftover files
    [[ -f "$REQUIREMENTS_FILE" ]] && rm -f "$REQUIREMENTS_FILE"
}

# Function to update virtual environment
update_venv() {
    if [[ -d "$MASTER_FOLDER/$VENV_NAME" ]]; then
        printf "\n%s\n\n" "Updating Python virtual environment..."
        source "$MASTER_FOLDER/$VENV_NAME/bin/activate"
        pip install --upgrade pip
        pip install -r "$REQUIREMENTS_FILE"
        printf "\n%s\n\n" "Update completed."
        deactivate
    else
        printf "\n%s\n\n" "Virtual environment does not exist. Creating one now..."
        create_venv
    fi
    # Delete leftover files
    [[ -f "$REQUIREMENTS_FILE" ]] && rm -f "$REQUIREMENTS_FILE"
}

# Function to delete virtual environment
delete_venv() {
    printf "\n%s\n\n" "Deleting Python virtual environment..."
    rm -rf "$MASTER_FOLDER/$VENV_NAME"
    printf "\n%s\n\n" "Deletion completed."

    # Delete leftover files
    [[ -f "$REQUIREMENTS_FILE" ]] && rm -f "$REQUIREMENTS_FILE"
}

# Function to list installed packages
list_packages() {
    if [[ -d "$MASTER_FOLDER/$VENV_NAME" ]]; then
        printf "\n%s\n\n" "Listing installed packages in the virtual environment..."
        source "$MASTER_FOLDER/$VENV_NAME/bin/activate"
        pip list
        deactivate
    else
        printf "\n%s\n\n" "Virtual environment does not exist. Create one using the -c or --create option."
    fi
}

# Function to display help
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help       Display this help message."
    echo "  -c, --create     Create a new Python virtual environment."
    echo "  -u, --update     Update the existing Python virtual environment."
    echo "  -d, --delete     Delete the Python virtual environment."
    echo "  -l, --list       List the installed packages in the virtual environment."
    echo "  -i, --import     Import packages from pip freeze into the requirements.txt file."
}

# Handling arguments
case "$1" in
    -h|--help)
        display_help
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
    *)
        echo "Invalid option. Use -h for help."
        exit 1
        ;;
esac
