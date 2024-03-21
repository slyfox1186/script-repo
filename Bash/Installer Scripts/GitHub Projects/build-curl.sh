#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/util-linux/Installer%20Scripts/GNU%20Software/build-curl
##  Purpose: Build cURL with OpenSSL backend
##  Updated: 02.02.24
##  Script version: 1.7

clear

if [ "${EUID}" -eq "0" ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set strict mode for bash
set -euo pipefail

# Define the program name
program="curl"
pem_file="cacert.pem"
install_dir=/usr/local
certs_dir="/etc/ssl/certs"
pem_out="$certs_dir/$pem_file"

# Environment variable settings
CC=gcc
CXX=g++
CFLAGS="-g -O3 -pipe -fno-plt -march=native"
CXXFLAGS="${CFLAGS} -Wno-variadic-macros"
CPPFLAGS="-I/usr/include/openssl -I/usr/local/include -I/usr/include/libxml2 -I/usr/include"
export CC CXX CFLAGS CPPFLAGS CXXFLAGS

PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/share/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/lib/pkgconfig"
export PKG_CONFIG_PATH

# Fail function to handle errors
fail_fn() {
    echo "Error: $1"
    exit 1
}

# Fetch the latest release tag from github tags page
version="$(curl -s "https://github.com/curl/curl/tags" | grep -oP 'curl-[0-9]+_[0-9]+_[0-9]+' | head -n 1)"
if [ -z "$version" ]; then
    printf "Error: Unable to fetch the latest release version of %s.\n" "$program"
    exit 1
fi

# Extract and format the version number
formatted_version="$(echo "$version" | sed "s/curl-//" | sed "s/_/\./g")"

printf "Latest release version of %s is %s.\n" "$program" "$formatted_version"

# Construct the download url and tar file name
download_url="https://github.com/curl/curl/archive/refs/tags/${version}.tar.gz"
tar_file="${program}-${formatted_version}.tar.gz"
extract_dir="${program}-build-script-${formatted_version}"

# Check if the tar file already exists
if [ ! -f "$tar_file" ]; then
    printf "Downloading %s version %s...\n" "$program" "$formatted_version"
    wget "$download_url" -O "$tar_file"
else
    printf "The tar file %s already exists, skipping download.\n" "$tar_file"
fi

# Remove the output directory if it exists
if [ -d "$extract_dir" ]; then
    printf "Removing existing directory %s...\n" "$extract_dir"
    rm -rf "$extract_dir"
fi

# Extract the tar file
printf "Extracting %s...\n" "$tar_file"
mkdir "$extract_dir"
tar -zxf "$tar_file" -C "$extract_dir" --strip-components 1

# Change to the directory
cd "$extract_dir"

libgcc_ver="$(sudo apt list libgcc-* 2>/dev/null | grep -Eo 'libgcc-[0-9]*-dev' | uniq | head -n1)"
libgtk_ver="$(sudo apt list libgtk-* 2>/dev/null | grep -Eo 'libgtk-[0-9]+-doc' | head -n1)"

pkgs_fn() {
    local missing_pkg missing_packages pkg pkgs available_packages unavailable_packages

# Check and install missing packages
    pkgs=(
        apt-transport-https apt-utils autoconf autoconf-archive autogen automake autopoint autotools-dev
        build-essential bzip2 ca-certificates ccache clang cmake curl gfortran git google-perftools graphviz
        jq lcov libaria2-0 libaria2-0-dev libc-ares-dev libcppunit-dev libcunit1-dev libcurl4 libcurl4-openssl-dev
        libdmalloc-dev libec-dev libedit-dev libev-dev libevent-dev libexiv2-27 libexpat1-dev "${libgcc_ver}"
        libgcrypt20-dev libgexiv2-2 libgimp2.0 libgmp3-dev libgpg-error-dev "${libgtk_ver}" libgpgme-dev libicu-dev
        libjemalloc-dev libkrb5-3 libldap2-dev libldap-dev liblttng-ust-dev liblzma-dev libmbedtls-dev libnghttp2-dev
        libnghttp3-dev libntlm0-dev libparted-dev libpng-dev libpsl-dev librtmp-dev librust-bzip2-dev librust-openssl-dev
        libsqlite3-dev libssh2-1-dev libssh-dev libssl-dev libtinfo5 libticonv-dev libtinfo-dev libtool libtool-bin
        libunistring-dev libunwind8 libuv1-dev libxml2-dev libzstd-dev lzip m4 nettle-dev default-jdk-headless openssh-server
        pkg-config python3-dev python3-numpy python3-packaging python3-pip python3-pytest python3-setuptools python3-wheel
        re2c rsync unzip valgrind zip zlib1g-dev
    )

# Initialize arrays for missing, available, and unavailable packages
    missing_packages=()
    available_packages=()
    unavailable_packages=()

# Loop through the array to find missing packages
    for pkg in "${pkgs[@]}"; do
      
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

# Check availability of missing packages and categorize them
    for pkg in "${missing_packages[@]}"; do
      
        if apt-cache show "$pkg" > /dev/null 2>&1; then
            available_packages+=("$pkg")
        else
            unavailable_packages+=("$pkg")
        fi
    done

# Print unavailable packages
    if [[ "${#unavailable_packages[@]}" -gt 0 ]]; then
        echo "Unavailable packages: ${unavailable_packages[*]}"
    fi

# Install available missing packages
    if [[ "${#available_packages[@]}" -gt 0 ]]; then
        echo "Installing available missing packages: ${available_packages[*]}"
        sudo apt install "${available_packages[@]}"
    else
        printf "%s\n\n" "No missing packages to install or all missing packages are unavailable."
    fi
}

# Install required apt packages
pkgs_fn

# Install ca certs from curl's official website
if [ ! -f "${pem_out}" ]; then
    curl -Lso "$pem_file" "https://curl.se/ca/$pem_file"
    sudo cp -f "$pem_file" "${pem_out}"
fi

if type -P update-ca-certificates &>/dev/null; then
    sudo update-ca-certificates
fi

dopts=('--disable-'{get-easy-options,shared,verbose,versioned-symbols})
eopts=('--enable-'{alt-svc,ares=/usr,cookies})
eopts+=('--enable-'{dict,dnsshuffle,doh,file,ftp,gopher})
eopts+=('--enable-'{headers-api,hsts,http,http-auth,imap})
eopts+=('--enable-'{ipv6,ldap,ldaps,libcurl-option,libgcc,manual})
eopts+=('--enable-'{mime,mqtt,netrc,ntlm,ntlm-wb='/usr/bin/ntlm_auth'})
eopts+=('--enable-'{openssl-auto-load-config,optimize,pop3,progress-meter})
eopts+=('--enable-'{proxy,pthreads,rtsp,smb,smtp,socketpair,sspi,static,telnet})
eopts+=('--enable-'{tftp,threaded-resolver,tls-srp,unix-sockets,websockets})
wopts=('--with-'{libssh2,nghttp2='/usr/include',nghttp3='/usr/include',openssl='/usr',ssl,zlib})
wopts+=('--with-'{ca-bundle="${pem_out}",ca-fallback,ca-path="$certs_dir",secure-transport})

# Generate configuration scripts
autoreconf -fi

# Create a build directory if it doesn't exist
mkdir -p build
cd build || fail_fn "Failed to enter the build directory."

# Run the configure script
../configure --prefix="$install_dir" \
            "${dopts[@]}"        \
            "${eopts[@]}"        \
            "${wopts[@]}"        \
            CPPFLAGS="${CPPFLAGS}" || fail_fn "Configuration failed."
# Compile using all available cores
echo "Compiling..."
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
fi

# Install
echo "Installing..."
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: ${LINENO}"
fi

curl_version="$($install_dir/bin/curl --version | head -n 1 | awk '{print $2}')"

printf "\n%s\n\n" "The installed version of cURL is: $curl_version"
sleep 2
echo "CURL installation completed successfully."
