#!/usr/bin/env bash

# GitHub repository URL for Docker Compose releases.
readonly REPO_URL=https://github.com/docker/compose/releases
readonly INSTALL_DIR="${DOCKER_COMPOSE_INSTALL_DIR:-/usr/local/bin}"
readonly INSTALL_PATH="$INSTALL_DIR/docker-compose"

log() {
    printf '[LOG] %s\n' "$1"
}

error() {
    printf '[ERROR] %s\n' "$1" >&2
}

usage() {
    printf 'Usage: %s [-f|--force]\n' "${0##*/}"
}

# Bound every GitHub request so a dead connection cannot stall installation
# indefinitely. Curl retries operation timeouts, including low-speed timeouts.
curl_with_network_limits() {
    curl \
        --connect-timeout 5 \
        --max-time 300 \
        --retry 2 \
        --retry-delay 2 \
        --retry-max-time 600 \
        "$@"
}

get_compose_filename() {
    local arch_type os_type

    os_type="$(uname -s | tr '[:upper:]' '[:lower:]')" || return 1
    arch_type="$(uname -m | tr -d '\n\r')" || return 1

    case $os_type in
        linux)
            case $arch_type in
                x86_64) arch_type=x86_64 ;;
                armv6l|armv6) arch_type=armv6 ;;
                armv7l|armv7) arch_type=armv7 ;;
                aarch64) arch_type=aarch64 ;;
                *)
                   error "Unsupported Linux architecture: $arch_type"
                   return 1
                   ;;
            esac
            ;;
        darwin)
            case $arch_type in
                x86_64) arch_type=x86_64 ;;
                arm64) arch_type=aarch64 ;;
                *)
                   error "Unsupported Darwin architecture: $arch_type"
                   return 1
                   ;;
            esac
            ;;
        *)
           error "Unsupported operating system: $os_type"
           return 1
           ;;
    esac

    printf 'docker-compose-%s-%s\n' "$os_type" "$arch_type"
}

calculate_sha256() {
    local checksum_output file_path
    file_path="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        if ! checksum_output="$(sha256sum "$file_path")"; then
            error "sha256sum failed while verifying the download."
            return 1
        fi
    elif command -v shasum >/dev/null 2>&1; then
        if ! checksum_output="$(shasum -a 256 "$file_path")"; then
            error "shasum failed while verifying the download."
            return 1
        fi
    else
        error "Neither sha256sum nor shasum is available to verify the download."
        return 1
    fi

    printf '%s\n' "${checksum_output%%[[:space:]]*}"
}

normalize_compose_version() {
    local version
    version="$1"

    # Docker Compose reports a bare version while GitHub release tags are
    # prefixed with "v". Trim both forms to the same value for comparison.
    version="${version#"${version%%[![:space:]]*}"}"
    version="${version%"${version##*[![:space:]]}"}"
    version="${version#[vV]}"

    printf '%s\n' "$version"
}

get_installed_compose_path() {
    local compose_path

    # Prefer the binary managed by this script, even if another installation
    # appears earlier on PATH.
    if [[ -x "$INSTALL_PATH" && ! -d "$INSTALL_PATH" ]]; then
        printf '%s\n' "$INSTALL_PATH"
        return 0
    fi

    if compose_path="$(type -P docker-compose)" && [[ -n "$compose_path" ]]; then
        printf '%s\n' "$compose_path"
        return 0
    fi

    return 1
}

# Run the installation in a subshell so its temporary-file cleanup trap cannot
# affect a shell that sources this script for testing or reuse.
fetch_and_install_docker_compose() (
    local actual_checksum checksum_link checksum_response download_link expected_checksum
    local file_name force installed_path installed_version latest_release_url
    local normalized_installed_version normalized_release_tag release_tag temp_file version_output

    force="${1:-false}"
    temp_file=""

    trap '[[ -n "$temp_file" ]] && rm -f -- "$temp_file"' EXIT HUP INT TERM

    log "Fetching the latest release information from $REPO_URL..."

    if ! file_name="$(get_compose_filename)"; then
        return 1
    fi

    if ! latest_release_url=$(curl_with_network_limits \
        --fail --silent --show-error --location \
        --output /dev/null --write-out '%{url_effective}' "$REPO_URL/latest"); then
        error "Failed to identify the latest Docker Compose release."
        return 1
    fi

    case "$latest_release_url" in
        "$REPO_URL/tag/"*) release_tag=${latest_release_url#"$REPO_URL/tag/"} ;;
        *)
           error "GitHub returned an unexpected latest-release URL: $latest_release_url"
           return 1
           ;;
    esac

    if [[ -z "$release_tag" || "$release_tag" == */* ]]; then
        error "GitHub returned an invalid Docker Compose release tag."
        return 1
    fi

    if [[ "$force" != true ]] && installed_path="$(get_installed_compose_path)"; then
        if installed_version=$("$installed_path" version --short 2>/dev/null); then
            normalized_installed_version="$(normalize_compose_version "$installed_version")"
            normalized_release_tag="$(normalize_compose_version "$release_tag")"

            if [[ -n "$normalized_installed_version" &&
                  "$normalized_installed_version" == "$normalized_release_tag" ]]; then
                echo
                log "Docker Compose $installed_version is already installed at $installed_path."
                log "It matches the latest release ($release_tag); there is no need to download or install it again."
                log "Use --force or -f to reinstall it anyway."
                return 0
            fi
        fi
    elif [[ "$force" == true ]]; then
        log "Force option enabled; Docker Compose will be downloaded and installed again."
    fi

    download_link="$REPO_URL/download/$release_tag/$file_name"
    checksum_link="$download_link.sha256"

    echo
    log "Successfully identified the latest release"
    log "Release: $release_tag"
    log "File name: $file_name"
    log "Download link: $download_link"
    echo
    log "Downloading Docker Compose..."

    if [[ "${INSTALL_DIR}" != /* ]]; then
        error "The installation directory must be an absolute path: $INSTALL_DIR"
        return 1
    fi

    if ! mkdir -p -- "$INSTALL_DIR"; then
        error "Failed to create the installation directory: $INSTALL_DIR"
        return 1
    fi

    if [[ -d "$INSTALL_PATH" ]]; then
        error "The installation path is a directory: $INSTALL_PATH"
        return 1
    fi

    if ! temp_file=$(mktemp "${INSTALL_DIR}/.docker-compose.XXXXXX"); then
        error "Failed to create a temporary file in: $INSTALL_DIR"
        return 1
    fi

    if ! curl_with_network_limits --fail --show-error --location --progress-bar \
        --output "$temp_file" "$download_link"; then
        error "Failed to download Docker Compose."
        return 1
    fi

    if [[ ! -s "$temp_file" ]]; then
        error "The downloaded Docker Compose binary is empty."
        return 1
    fi

    if ! checksum_response=$(curl_with_network_limits \
        --fail --silent --show-error --location "$checksum_link"); then
        error "Failed to download the Docker Compose checksum."
        return 1
    fi
    read -r expected_checksum _ <<< "$checksum_response"

    local regex_match
    regex_match='^[[:xdigit:]]{64}$'

    if [[ ! "$expected_checksum" =~ $regex_match ]]; then
        error "GitHub returned an invalid Docker Compose checksum."
        return 1
    fi

    if ! actual_checksum="$(calculate_sha256 "$temp_file")"; then
        return 1
    fi

    actual_checksum=$(printf '%s' "$actual_checksum" | tr '[:upper:]' '[:lower:]')
    expected_checksum=$(printf '%s' "$expected_checksum" | tr '[:upper:]' '[:lower:]')

    if [[ "$actual_checksum" != "$expected_checksum" ]]; then
        error "Docker Compose checksum verification failed."
        return 1
    fi

    if ! chmod 0755 "$temp_file"; then
        error "Failed to make the downloaded binary executable."
        return 1
    fi

    if ! version_output=$("$temp_file" version --short 2>&1); then
        error "The downloaded file failed its Docker Compose version check: $version_output"
        return 1
    fi

    if [[ -z "$version_output" ]]; then
        error "The downloaded file returned an empty Docker Compose version."
        return 1
    fi

    if ! mv -f -- "$temp_file" "$INSTALL_PATH"; then
        error "Failed to install Docker Compose at: $INSTALL_PATH"
        return 1
    fi
    temp_file=""

    echo
    log "Docker Compose $version_output installed successfully."
    log "Installed binary: $INSTALL_PATH"
)

main() {
    local force
    force=false

    while (($#)); do
        case "$1" in
            -f|--force)
                force=true
                ;;
            *)
                error "Unknown option: $1"
                usage >&2
                return 2
                ;;
        esac
        shift
    done

    if [[ $EUID -ne 0 ]]; then
        error "You must execute the script as root or with sudo."
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        error "curl could not be found so it will be downloaded."
        apt update && apt -y full-upgrade
        if ! apt install -y curl; then
            echo "Failed to install curl. Please install it manually."
            sleep 2
            return 1
        else
            echo "curl was successfully installed."
            sleep 2
            return 0
        fi
    fi

    fetch_and_install_docker_compose "$force"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
