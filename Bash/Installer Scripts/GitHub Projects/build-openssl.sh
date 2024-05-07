#!/usr/bin/env bash

# Build OpenSSL
# Updated: 04.30.24
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-openssl.sh
# Script Version: 1.5

# Function to display the usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -6, --enable-ipv6          Enable IPv6 support (default: disabled)"
    echo "  -c, --command <command>    Specify the command(s) to use with 'sudo make install' (default: install_sw, comma-separated)"
    echo "  -h, --help                 Display this help message and exit"
    echo "  -j, --jobs <n>             Set the number of parallel jobs for compilation (default: number of CPU cores)"
    echo "  -k, --keep-build           Keep the build directory after installation"
    echo "  -l, --list                 List all available OpenSSL versions"
    echo "  -m, --list-commands        List available 'make install' commands and their descriptions"
    echo "  -p, --prefix <path>        Set the installation prefix (default: /usr/local/ssl)"
    echo "  -v, --version <version>    Specify the OpenSSL version to install (default: latest 3.2.x)"
    exit 0
}

list_versions_flag=0
list_commands_flag=0

# Function to parse command-line arguments
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -6|--enable-ipv6)
                enable_ipv6="true"
                shift
                ;;
            -c|--command)
                IFS=',' read -ra make_install_command <<< "$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            -j|--jobs)
                jobs="$2"
                shift 2
                ;;
            -k|--keep-build)
                keep_build="true"
                shift
                ;;
            -l|--list)
                list_versions_flag=1
                shift
                ;;
            -m|--list-commands)
                list_commands_flag=1
                shift
                ;;
            -p|--prefix)
                install_dir="$2"
                shift 2
                ;;
            -v|--version)
                version="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Function to handle failure and display an error message
fail() {
    echo
    echo "$1"
    echo "Please report errors at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Function to install required packages
install_required_packages() {
    local -a missing_packages pkgs
    pkgs=(
        autoconf autogen automake build-essential ca-certificates
        checkinstall clang curl libc-ares-dev libcurl4-openssl-dev
        libdmalloc-dev libgcrypt20-dev libgmp-dev libgpg-error-dev
        libjemalloc-dev libmbedtls-dev libsctp-dev libssh2-1-dev
        libssh-dev libssl-dev libtool libtool-bin libxml2-dev m4
        ccache perl zlib1g-dev
    )

    missing_packages=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='$Status' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ "${#missing_packages[@]}" -gt 0 ]]; then
        echo "Installing missing packages: ${missing_packages[*]}"
        sudo apt install "${missing_packages[@]}"
        echo
    else
        echo "No missing packages to install."
        echo
    fi
}

get_highest_clang_version() {
    local version
    for version in 13 14 15 16; do
        if command -v "clang-$version" &>/dev/null; then
            compiler_cc="clang-$version"
        fi
    done
    compiler_cxx=${compiler_cc//clang/}
    compiler_cxx="clang++${compiler_cxx}"
}

# Function to set compiler flags
set_compiler_flags() {
    CC="$compiler_cc"
    CXX="$compiler_cxx"
    CFLAGS="-O2 -pipe -fstack-protector-strong -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro,-z,now"
    export CC CFLAGS CPPFLAGS CXX CXXFLAGS LDFLAGS
}

# Function to update the shared library cache
update_shared_library_cache() {
    sudo ldconfig
}

# Function to add OpenSSL to the system path
add_openssl_to_path() {
    sudo ln -sf "$install_dir/bin/"{c_rehash,openssl} "/usr/local/bin/"
}

# Function to create softlinks for pkgconfig files
create_pkgconfig_softlinks() {
    local openssl_pkgconfig_dir pkgconfig_dir
    pkgconfig_dir="/usr/local/lib/pkgconfig"
    openssl_pkgconfig_dir="$install_dir/lib64/pkgconfig"

    sudo mkdir -p "$pkgconfig_dir"

    for pc_file in "$openssl_pkgconfig_dir"/*.pc; do
        if [[ -e "$pc_file" ]]; then
            local pc_filename="${pc_file##*/}"
            sudo ln -sf "$pc_file" "$pkgconfig_dir/$pc_filename"
        fi
    done
}

create_linker_config_file() {
    echo "$install_dir/lib64" | sudo tee "/etc/ld.so.conf.d/custom_openssl_$version.conf" >/dev/null
    sudo ldconfig
}

# Function to list available OpenSSL versions
list_versions() {
    echo "Available OpenSSL versions:"
    echo
    curl -fsS "https://www.openssl.org/source/" | grep -oP 'openssl-\d+\.\d+\.\d+\.tar\.gz' | sed 's/openssl-//;s/\.tar\.gz//' | sort -uV
}

# Function to list available 'make install' commands
list_commands() {
    echo "Available 'make install' commands:"
    echo
    echo "  all                   Build all the software components and documentation"
    echo "  build_sw              Build all the software components (DEFAULT)"
    echo "  build_docs            Build all documentation components"
    echo "  clean                 Remove all build artifacts and return the directory to a clean state"
    echo "  depend                Rebuild the dependencies in the Makefiles (legacy option, not needed since OpenSSL 1.1.0)"
    echo "  install               Install all OpenSSL components"
    echo "  install_sw            Only install the OpenSSL software components"
    echo "  install_docs          Only install the OpenSSL documentation components"
    echo "  install_man_docs      Only install the OpenSSL man pages (Unix only)"
    echo "  install_html_docs     Only install the OpenSSL HTML documentation"
    echo "  install_fips          Install the FIPS provider module configuration file"
    echo "  list-tests            Print a list of all the self test names"
    echo "  test                  Build and run the OpenSSL self tests"
    echo "  uninstall             Uninstall all OpenSSL components"
}

# Function to download OpenSSL
download_openssl() {
    local max_retries openssl_url retry_count tar_file
    openssl_url="https://www.openssl.org/source/openssl-$version.tar.gz"
    tar_file="$cwd/openssl-$version.tar.gz"
    max_retries=3
    retry_count=0

    echo "Targeting tar file: $tar_file"

    while [[ ! -f "$tar_file" ]] && [[ "$retry_count" -lt "$max_retries" ]]; do
        echo "Downloading OpenSSL $version... (Attempt $((retry_count + 1))/$max_retries)"
        echo
        if wget --show-progress -cqO "$tar_file" "$openssl_url"; then
            echo
            break
        else
            echo "Download failed. Retrying in 5 seconds..."
            echo
            sleep 5
            ((retry_count++))
        fi
    done

    if [[ $retry_count -eq $max_retries ]]; then
        fail "Failed to download the tar file after $max_retries attempts. Line: $LINENO"
    fi
}

# Function to extract OpenSSL
extract_openssl() {
    local extracted_dir tar_file
    tar_file="$cwd/openssl-$version.tar.gz"

    if [[ -d "$src_dir" ]]; then
        printf "\n%s\n\n" "OpenSSL $version source directory already exists, skipping extraction."
    else
        if [[ -f "$tar_file" ]]; then
            echo "Verifying OpenSSL $version archive integrity..."
            if gzip -t "$tar_file"; then
                echo "Extracting OpenSSL $version..."
                if tar -xzf "$tar_file" -C "$cwd"; then
                    echo "Extraction completed successfully."
                    echo
                    extracted_dir="${tar_file##*/}"
                    extracted_dir="${extracted_dir%.tar.gz}"
                    if [[ "$extracted_dir" != "$version" ]]; then
                        echo "Renaming extracted directory from $extracted_dir to $version..."
                        mv "$cwd/$extracted_dir" "$src_dir"
                        echo
                    fi
                else
                    echo "Extraction failed. Removing the corrupted archive and retrying..."
                    echo
                    sudo rm "$tar_file"
                    download_openssl
                    extract_openssl
                fi
            else
                echo "OpenSSL $version archive is corrupted. Removing the archive and retrying..."
                echo
                sudo rm "$tar_file"
                download_openssl
                extract_openssl
            fi
        else
            echo "OpenSSL $version archive does not exist. Downloading..."
            echo
            download_openssl
            extract_openssl
        fi
    fi
}

# Function to configure OpenSSL
configure_openssl() {
    echo "Configuring OpenSSL..."
    local config_options
    config_options=(
        "linux-x86_64-clang"
        "-DOPENSSL_USE_IPV6=$([[ "$enable_ipv6" == true ]] && echo 1 || echo 0)"
        "-Wl,-rpath=$install_dir/lib64"
        "-Wl,--enable-new-dtags"
        "--prefix=$install_dir"
        "--openssldir=$install_dir"
        "--release"
        "--with-zlib-include=/usr/include"
        "--with-zlib-lib=/usr/lib/x86_64-linux-gnu"
        "enable-ec_nistp_64_gcc_128"
        "enable-egd"
        "enable-fips"
        "enable-pic"
        "enable-shared"
        "enable-threads"
        "enable-zlib-dynamic"
        "no-async"
        "no-comp"
        "no-dso"
        "no-engine"
        "no-weak-ssl-ciphers"
    )

    if [[ "$version" =~ ^3\.2\. ]]; then
        config_options+=("enable-"{ktls,psk})
    fi

    if "$src_dir/Configure" "${config_options[@]}"; then
        echo "OpenSSL configuration completed successfully."
        echo
    else
        fail "OpenSSL configuration failed. Line: $LINENO"
    fi
}

# Function to build and install OpenSSL
build_and_install_openssl() {
    echo "Compiling OpenSSL..."
    make "-j${jobs:-$(nproc --all)}" || fail "Failed to execute: make -j${jobs:-$(nproc --all)}. Line: $LINENO"
    echo
    echo "Installing OpenSSL..."
    echo
    sudo make install "${make_install_command[@]}" || fail "Failed to execute: make install ${make_install_command[*]}. Line: $LINENO"
    echo
    sudo openssl fipsinstall
}

# Function to create and prepare the certificates directory
prepare_certificates_directory() {
    local certs_dir
    certs_dir="$install_dir/certs"
    echo "Creating and preparing the certificates directory at $certs_dir..."
    sudo mkdir -p "$certs_dir"
    sudo ln -sf /etc/ssl/certs/* "$certs_dir"
    sudo "$install_dir/bin/c_rehash" "$certs_dir"
    echo "Certificates directory is ready."
}

# Main function
main() {
    local cwd enable_ipv6 install_dir jobs keep_build make_install_command src_dir tar_file temp_dir version

    parse_arguments "$@"

    if [[ "$list_versions_flag" == "1" ]]; then
        list_versions
        exit 0
    fi

    if [[ "$list_commands_flag" == "1" ]]; then
        list_commands
        exit 0
    fi

    clear
    temp_dir=$(mktemp -d)
    cwd="$temp_dir/openssl-build"
    enable_ipv6="false"
    install_dir="/usr/local/ssl"
    keep_build="false"
    make_install_command=("${make_install_command[@]:-install_sw}")
    tar_file="$cwd/openssl-$version.tar.gz"

    if [[ "$EUID" -eq 0 ]]; then
        echo "You must run this script without root or with sudo."
        exit 1
    fi

    if [[ -z "$version" ]]; then
        version=$(curl -fsS "https://www.openssl.org/source/" | grep -oP 'openssl-3\.2\.\d+\.tar\.gz' | head -n1 | sed 's/openssl-//;s/\.tar\.gz//')
        [[ -z "$version" ]] && fail "Failed to detect the latest OpenSSL 3.2.x version. Line: $LINENO"
    fi

    install_dir="${install_dir:-/usr/local/ssl}"
    src_dir="$cwd/$version"

    echo
    get_highest_clang_version
    set_compiler_flags
    mkdir -p "$cwd"
    install_required_packages
    echo "Targeting OpenSSL version $version"
    download_openssl
    extract_openssl

    if [[ -d "$src_dir" ]]; then
        cd "$src_dir" || fail "Failed to change directory to $src_dir. Line: $LINENO"
        configure_openssl
        build_and_install_openssl
        prepare_certificates_directory
        add_openssl_to_path
        update_shared_library_cache
        create_pkgconfig_softlinks
        create_linker_config_file
    else
        fail "OpenSSL source directory $src_dir does not exist. Line: $LINENO"
    fi

    [[ "$keep_build" == "false" ]] && sudo rm -fr "$cwd"

    echo
    echo "OpenSSL installation completed."
}

main "$@"
