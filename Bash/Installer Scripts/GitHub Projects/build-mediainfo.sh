#!/usr/bin/env bash

# Github: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-mediainfo.sh
# Purpose: Build MediaInfo
# Updated: 07.03.24
# Script version: 1.1

install_dir="/usr/local/programs/mediainfo"

# Function to print help message
print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script dynamically locates the latest release versions of ZenLib, MediaInfoLib, and MediaInfo,"
    echo "downloads the source code, and builds them from source."
    echo ""
    echo "Options:"
    echo "  -h, --help  Display this help message."
}

# Function to set optimization flags
set_optimization_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -march=native -mtune=native"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"
    CPPFLAGS="-I/usr/local/include"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

# Function to get the latest version tag from GitHub
get_latest_version() {
    echo "Fetching the latest release version of MediaInfo..."
    latest_mediainfo_version=$(curl -fsS "https://github.com/MediaArea/MediaInfo/tags" | grep -oP '/tag/v?\K[0-9]+\.[0-9]+' | head -n1)

    if [[ -z "$latest_mediainfo_version" ]]; then
        echo "Failed to fetch the latest version of MediaInfo."
        exit 1
    fi

    echo "Latest MediaInfo version found: $latest_mediainfo_version"

    echo "Fetching the latest release version of ZenLib..."
    latest_zenlib_version=$(curl -fsS "https://github.com/MediaArea/ZenLib/tags" | grep -oP '/tag/v?\K[0-9]+\.[0-9]+\.[0-9]+' | head -n1)

    if [[ -z "$latest_zenlib_version" ]]; then
        echo "Failed to fetch the latest version of ZenLib."
        exit 1
    fi

    echo "Latest ZenLib version found: $latest_zenlib_version"

    echo "Fetching the latest release version of MediaInfoLib..."
    latest_mediainfolib_version=$(curl -fsS "https://github.com/MediaArea/MediaInfoLib/tags" | grep -oP '/tag/v?\K[0-9]+\.[0-9]+' | head -n1)

    if [[ -z "$latest_mediainfolib_version" ]]; then
        echo "Failed to fetch the latest version of MediaInfoLib."
        exit 1
    fi

    echo "Latest MediaInfoLib version found: $latest_mediainfolib_version"
}

# Function to download the source code
download_source_code() {
    local url_zenlib="https://github.com/MediaArea/ZenLib/archive/refs/tags/v${latest_zenlib_version}.tar.gz"
    local url_mediainfo="https://github.com/MediaArea/MediaInfo/archive/refs/tags/v${latest_mediainfo_version}.tar.gz"
    local url_mediainfolib="https://github.com/MediaArea/MediaInfoLib/archive/refs/tags/v${latest_mediainfolib_version}.tar.gz"
    
    echo "Downloading ZenLib source code..."
    if ! curl -Lso "mediainfo-build-script/ZenLib-${latest_zenlib_version}.tar.gz" "$url_zenlib"; then
        echo "Failed to download the source code of ZenLib."
        exit 1
    fi

    echo "Downloading MediaInfoLib source code..."
    if ! curl -Lso "mediainfo-build-script/MediaInfoLib-${latest_mediainfolib_version}.tar.gz" "$url_mediainfolib"; then
        echo "Failed to download the source code of MediaInfoLib."
        exit 1
    fi

    echo "Downloading MediaInfo source code..."
    if ! curl -Lso "mediainfo-build-script/MediaInfo-${latest_mediainfo_version}.tar.gz" "$url_mediainfo"; then
        echo "Failed to download the source code of MediaInfo."
        exit 1
    fi
}

# Function to extract the source code
extract_source_code() {
    echo "Extracting the source code of ZenLib..."
    mkdir -p "mediainfo-build-script/ZenLib-${latest_zenlib_version}"
    if ! tar -xzf "mediainfo-build-script/ZenLib-${latest_zenlib_version}.tar.gz" -C "mediainfo-build-script/ZenLib-${latest_zenlib_version}" --strip-components=1; then
        echo "Failed to extract the source code of ZenLib."
        exit 1
    fi

    echo "Extracting the source code of MediaInfoLib..."
    mkdir -p "mediainfo-build-script/MediaInfoLib-${latest_mediainfolib_version}"
    if ! tar -xzf "mediainfo-build-script/MediaInfoLib-${latest_mediainfolib_version}.tar.gz" -C "mediainfo-build-script/MediaInfoLib-${latest_mediainfolib_version}" --strip-components=1; then
        echo "Failed to extract the source code of MediaInfoLib."
        exit 1
    fi

    echo "Extracting the source code of MediaInfo..."
    mkdir -p "mediainfo-build-script/MediaInfo-${latest_mediainfo_version}"
    if ! tar -xzf "mediainfo-build-script/MediaInfo-${latest_mediainfo_version}.tar.gz" -C "mediainfo-build-script/MediaInfo-${latest_mediainfo_version}" --strip-components=1; then
        echo "Failed to extract the source code of MediaInfo."
        exit 1
    fi
}

# Function to configure and build ZenLib
build_zenlib() {
    cd "mediainfo-build-script/ZenLib-${latest_zenlib_version}/Project/GNU/Library" || exit 1

    autoreconf -fi

    echo "Configuring the build of ZenLib..."
    if ! ./configure --prefix="$install_dir" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" CPPFLAGS="$CPPFLAGS" PKG_CONFIG_PATH="$PKG_CONFIG_PATH"; then
        echo "Configuration of ZenLib failed."
        exit 1
    fi

    echo "Building ZenLib..."
    if ! make "-j$(nproc --all)"; then
        echo "Build of ZenLib failed."
        exit 1
    fi

    echo "Installing ZenLib..."
    if ! sudo make install; then
        echo "Installation of ZenLib failed."
        exit 1
    fi

    cd ../../../../..
}

# Function to configure and build MediaInfoLib
build_mediainfolib() {
    cd "mediainfo-build-script/MediaInfoLib-${latest_mediainfolib_version}/Project/GNU/Library" || exit 1

    autoreconf -fi

    echo "Configuring the build of MediaInfoLib..."
    if ! ./configure CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" CPPFLAGS="$CPPFLAGS" PKG_CONFIG_PATH="$PKG_CONFIG_PATH" --with-libzen=/usr/local --prefix=/usr/local; then
        echo "Configuration of MediaInfoLib failed."
        exit 1
    fi

    echo "Building MediaInfoLib..."
    if ! make "-j$(nproc --all)"; then
        echo "Build of MediaInfoLib failed."
        exit 1
    fi

    echo "Installing MediaInfoLib..."
    if ! sudo make install; then
        echo "Installation of MediaInfoLib failed."
        exit 1
    fi

    cd ../../../../..
}

# Function to configure and build MediaInfo
build_mediainfo() {
    cd "mediainfo-build-script/MediaInfo-${latest_mediainfo_version}/Project/GNU/CLI" || exit 1

    autoreconf -fi

    echo "Configuring the build of MediaInfo..."
    if ! ./configure CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" CPPFLAGS="$CPPFLAGS" PKG_CONFIG_PATH="$PKG_CONFIG_PATH" --with-libzen=/usr/local --with-libmediainfo=/usr/local; then
        echo "Configuration of MediaInfo failed."
        exit 1
    fi

    echo "Building MediaInfo..."
    if ! make "-j$(nproc --all)"; then
        echo "Build of MediaInfo failed."
        exit 1
    fi

    echo "Installing MediaInfo..."
    if ! sudo make install; then
        echo "Installation of MediaInfo failed."
        exit 1
    fi

    cd ../../../../..
}

# Function to clean up
clean_up() {
    rm -rf "mediainfo-build-script/ZenLib-${latest_zenlib_version}" "mediainfo-build-script/ZenLib-${latest_zenlib_version}.tar.gz"
    rm -rf "mediainfo-build-script/MediaInfoLib-${latest_mediainfolib_version}" "mediainfo-build-script/MediaInfoLib-${latest_mediainfolib_version}.tar.gz"
    rm -rf "mediainfo-build-script/MediaInfo-${latest_mediainfo_version}" "mediainfo-build-script/MediaInfo-${latest_mediainfo_version}.tar.gz"
    echo "Cleanup completed."
}

# Main script
main() {
    # Parse command-line arguments
    for arg in "$@"; do
        case $arg in
            -h|--help)
                print_help
                exit 0
                ;;
            *)
                echo "Unknown option: $arg"
                print_help
                exit 1
                ;;
        esac
    done

    mkdir -p mediainfo-build-script

    set_optimization_flags
    get_latest_version
    download_source_code
    extract_source_code
    build_zenlib
    build_mediainfolib
    build_mediainfo
    clean_up

    echo "ZenLib, MediaInfoLib, and MediaInfo have been successfully installed."
}

main "$@"
