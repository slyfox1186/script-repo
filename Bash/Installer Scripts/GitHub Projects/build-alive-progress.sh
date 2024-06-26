#!/usr/bin/env bash

# Repository details
NAME="alive-progress"
REPO="rsalmei/$NAME"
RELEASE_API_URL="https://github.com/$REPO/tags"

# Fetch the latest release data
RELEASE_DATA=$(curl -fsS "$RELEASE_API_URL")

# Extract the tag name (version) and tarball url
TAG_NAME=$(echo $RELEASE_DATA | grep -oP 'href="[^"]*/tag/v?\K([0-9.])+' | head -n1)
TARBALL_URL="https://codeload.github.com/$REPO/tar.gz/refs/tags/v$TAG_NAME"
 
get_latest_release_version() {
    latest_release_tag=$(curl -fsS "https://github.com/$REPO/tags")
    echo "$latest_release_tag"
}

# Install alive-progress using pip
pip install --user alive-progress

# Confirm installation
if pip show alive-progress >/dev/null; then
    echo "alive-progress successfully installed."
else
    echo "Installation failed."
fi

mkdir -p "$NAME-$TAG_NAME-build-script"

# Download and extract the latest release
curl -LSso "$NAME-$TAG_NAME-build-script.tar.gz" "$TARBALL_URL"
tar -zxf "$NAME-$TAG_NAME-build-script.tar.gz" -C "$NAME-$TAG_NAME-build-script" --strip-components 1

# Change to the extracted directory (modify this according to the actual directory structure)
cd "$NAME-$TAG_NAME-build-script" || exit 1

# Installation commands (modify this according to the actual installation steps)
# For python packages, it's often as simple as:
if ! python3 setup.py build; then
    echo "[ERROR] python3 setup.py build"
    exit 1
fi
if ! pip install --user .; then
    echo "[ERROR] pip install --user."
    exit 1
fi

# Clean up
cd ../
sudo rm -rf "$NAME-$TAG_NAME-build-script"
sudo rm "$NAME-$TAG_NAME-build-script.tar.gz"

echo "Installation of $REPO $TAG_NAME completed."
