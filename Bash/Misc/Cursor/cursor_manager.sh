#!/usr/bin/env bash

# Define the paths
BASE_DIR="$HOME/apps"
CURSOR_PATH="$BASE_DIR/cursor.AppImage"
DOWNLOAD_URL="https://downloader.cursor.sh/linux/appImage/x64"

# Create BASE_DIR
mkdir -p "$BASE_DIR"

# Check if Cursor is already running
if pgrep -f "cursor.AppImage" > /dev/null; then
    read -rp "Cursor is already running. Would you like to kill the existing process? (y/n): " kill_answer
    if [[ "$kill_answer" =~ ^[Yy]$ ]]; then
        printf "\n%s" "Killing existing Cursor process..."
        pkill -f "cursor.AppImage"
        sleep 1  # Give it a moment to fully terminate
    else
        printf "\n%s\n" "Exiting without launching a new instance."
        exit 0
    fi
fi

# Create apps directory if it doesn't exist
mkdir -p "$HOME/apps"

# Prompt user for download
read -rp "Would you like to download the latest version of Cursor? (y/n): " answer

if [[ "$answer" =~ ^[Yy]$ ]]; then
    printf "\n%s" "Downloading latest Cursor AppImage..."
    wget -O "$CURSOR_PATH" "$DOWNLOAD_URL" || {
        printf "\n%s\n" "Error: Download failed"
        exit 1
    }
    printf "\n%s" "Download completed successfully"
    chmod +x "$CURSOR_PATH"
fi

# Check if the AppImage exists
if [[ ! -f "$CURSOR_PATH" ]]; then
    printf "\n%s\n" "Error: Cursor AppImage not found at $CURSOR_PATH"
    exit 1
fi

# Check if the AppImage is executable
if [[ ! -x "$CURSOR_PATH" ]]; then
    printf "\n%s" "Making Cursor AppImage executable..."
    chmod +x "$CURSOR_PATH"
fi

# Launch Cursor silently in the background
nohup "$CURSOR_PATH" >/dev/null 2>&1 &

# Optional: Create desktop entry if it doesn't exist
DESKTOP_ENTRY="$HOME/.local/share/applications/cursor.desktop"
if [[ ! -f "$DESKTOP_ENTRY" ]]; then
    printf "\n%s" "Creating desktop entry..."
    cat > "$DESKTOP_ENTRY" << EOL
[Desktop Entry]
Name=Cursor
Exec=bash -c 'nohup "$HOME/apps/cursor.AppImage" >/dev/null 2>&1 &'
Type=Application
Categories=Development;IDE;
Comment=Cursor IDE
EOL
    chmod +x "$DESKTOP_ENTRY"
    printf "\n%s" "Desktop entry created at $DESKTOP_ENTRY"
fi

printf "\n%s\n" "Cursor launched successfully!"
