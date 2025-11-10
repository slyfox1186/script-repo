#!/usr/bin/env python3
"""
ChromeDriver Installer & Manager

This script provides comprehensive ChromeDriver management:
- Download and install latest ChromeDriver
- Auto-detect Chrome browser version and install matching ChromeDriver
- Update existing installations
- Support for system-wide and user installations
- Command-line interface with multiple options

Usage:
    python3 chromedriver_installer.py [options]
"""

import os
import sys
import json
import zipfile
import tempfile
import requests
import subprocess
import re
import argparse
import shutil
from pathlib import Path


def get_chrome_version():
    """Get the installed Chrome browser version."""
    chrome_commands = [
        "google-chrome",
        "google-chrome-stable",
        "chromium-browser",
        "chromium"
    ]

    for cmd in chrome_commands:
        try:
            result = subprocess.run(
                [cmd, "--version"],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                # Extract version number
                version_match = re.search(r'(\d+\.\d+\.\d+\.\d+)', result.stdout)
                if version_match:
                    return version_match.group(1)
        except (subprocess.TimeoutExpired, FileNotFoundError):
            continue

    return None


def get_chromedriver_version_for_chrome(chrome_version):
    """Get the matching ChromeDriver version for a Chrome version."""
    try:
        response = requests.get(
            "https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json",
            timeout=30
        )
        response.raise_for_status()
        data = response.json()

        versions = data.get("versions", [])
        if not versions:
            return None

        # Find the closest ChromeDriver version
        best_match = None
        best_match_score = float('inf')

        for version_info in versions:
            version = version_info.get("version", "")
            if not version:
                continue

            # Calculate version difference score
            version_parts = list(map(int, version.split('.')))
            chrome_parts = list(map(int, chrome_version.split('.')))

            # Simple version matching - prioritize major.minor version
            score = 0
            for i in range(min(len(version_parts), len(chrome_parts))):
                if i < 2:  # Major and minor versions are most important
                    score += abs(version_parts[i] - chrome_parts[i]) * 1000
                else:
                    score += abs(version_parts[i] - chrome_parts[i])

            if score < best_match_score:
                # Check if Linux download is available
                downloads = version_info.get("downloads", {}).get("chromedriver", [])
                linux_url = None
                for download in downloads:
                    if download.get("platform") == "linux64":
                        linux_url = download.get("url")
                        break

                if linux_url:
                    best_match = {
                        "version": version,
                        "revision": version_info.get("revision"),
                        "download_url": linux_url
                    }
                    best_match_score = score

        return best_match

    except Exception as e:
        print(f"Error finding ChromeDriver version: {e}")
        return None


def get_latest_chromedriver_info():
    """Get the absolute latest ChromeDriver version."""
    try:
        response = requests.get(
            "https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json",
            timeout=30
        )
        response.raise_for_status()
        data = response.json()

        versions = data.get("versions", [])

        for version_info in versions:
            downloads = version_info.get("downloads", {}).get("chromedriver", [])
            for download in downloads:
                if download.get("platform") == "linux64":
                    return {
                        "version": version_info.get("version"),
                        "revision": version_info.get("revision"),
                        "download_url": download.get("url")
                    }

        return None

    except Exception as e:
        print(f"Error getting latest ChromeDriver info: {e}")
        return None


def download_file(url, destination):
    """Download a file with progress indication."""
    try:
        response = requests.get(url, stream=True, timeout=60)
        response.raise_for_status()

        total_size = int(response.headers.get('content-length', 0))
        downloaded = 0

        with open(destination, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total_size > 0:
                        percent = (downloaded / total_size) * 100
                        print(f"\rDownloading... {percent:.1f}%", end='', flush=True)

        print(f"\nDownloaded: {destination}")
        return True

    except Exception as e:
        print(f"\nDownload failed: {e}")
        return False


def extract_chromedriver(zip_path, extract_to):
    """Extract ChromeDriver from zip file."""
    try:
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_to)

        # Find the extracted chromedriver binary
        # ChromeDriver zip contains a directory with the binary inside
        for file_path in extract_to.rglob("*"):
            if file_path.name == "chromedriver" and file_path.is_file():
                return file_path

        # If not found, try other patterns
        for file_path in extract_to.rglob("*"):
            if file_path.name.startswith("chromedriver") and file_path.is_file():
                return file_path

        raise Exception("ChromeDriver binary not found in extracted files")

    except Exception as e:
        print(f"Extraction failed: {e}")
        return None


def install_chromedriver(source_path, install_path):
    """Install ChromeDriver to target location."""
    try:
        # Create parent directory if needed
        install_path.parent.mkdir(parents=True, exist_ok=True)

        # Remove existing installation
        if install_path.exists():
            print(f"Removing existing ChromeDriver at {install_path}")
            install_path.unlink()

        # Copy new version
        shutil.copy2(source_path, install_path)

        # Make executable
        install_path.chmod(0o755)

        print(f"ChromeDriver installed to: {install_path}")
        return True

    except Exception as e:
        print(f"Installation failed: {e}")
        return False


def get_current_chromedriver_version(chromedriver_path):
    """Get version of currently installed ChromeDriver."""
    try:
        result = subprocess.run(
            [str(chromedriver_path), "--version"],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            version_match = re.search(r'ChromeDriver (\d+\.\d+\.\d+\.\d+)', result.stdout)
            if version_match:
                return version_match.group(1)
    except Exception:
        pass
    return None


def verify_installation(chromedriver_path):
    """Verify that ChromeDriver is working correctly."""
    try:
        result = subprocess.run(
            [str(chromedriver_path), "--version"],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            print(f"ChromeDriver version: {result.stdout.strip()}")
            return True
        else:
            print(f"ChromeDriver verification failed: {result.stderr}")
            return False
    except Exception as e:
        print(f"Failed to verify ChromeDriver: {e}")
        return False


def check_dependencies():
    """Check if required dependencies are available."""
    try:
        import requests
        return True
    except ImportError:
        print("Error: 'requests' library is required. Install it with:")
        print("pip install requests")
        return False


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="ChromeDriver Installer & Manager",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                          # Auto-detect Chrome and install matching ChromeDriver
  %(prog)s --latest                 # Install latest ChromeDriver version
  %(prog)s --path /usr/bin/chromedriver  # Install to custom path
  %(prog)s --force                  # Force reinstall even if same version exists

For system-wide installation (requires root):
  sudo python3 %(prog)s

For user installation:
  python3 %(prog)s
        """
    )

    parser.add_argument("--latest", action="store_true",
                       help="Download latest ChromeDriver instead of Chrome-matching version")
    parser.add_argument("--path", type=str,
                       help="Custom installation path (default: /usr/local/bin/chromedriver or ~/.local/bin/chromedriver)")
    parser.add_argument("--force", action="store_true",
                       help="Force installation even if same version exists")
    parser.add_argument("--version", action="store_true",
                       help="Show current ChromeDriver version and exit")
    parser.add_argument("--chrome-version", action="store_true",
                       help="Show detected Chrome browser version and exit")

    args = parser.parse_args()

    print("ChromeDriver Installer & Manager")
    print("=" * 35)

    # Check dependencies
    if not check_dependencies():
        sys.exit(1)

    # Determine installation path
    if args.path:
        install_path = Path(args.path)
    elif os.geteuid() == 0:
        install_path = Path("/usr/local/bin/chromedriver")
    else:
        install_path = Path.home() / ".local" / "bin" / "chromedriver"

    # Handle version queries
    if args.version:
        if install_path.exists():
            current_version = get_current_chromedriver_version(install_path)
            if current_version:
                print(f"Current ChromeDriver version: {current_version}")
            else:
                print("ChromeDriver not found or version unknown")
        else:
            print("ChromeDriver not installed")
        sys.exit(0)

    if args.chrome_version:
        chrome_version = get_chrome_version()
        if chrome_version:
            print(f"Chrome browser version: {chrome_version}")
        else:
            print("Chrome browser not found")
        sys.exit(0)

    print(f"Installation path: {install_path}")

    # Check current installation
    current_version = None
    if install_path.exists():
        current_version = get_current_chromedriver_version(install_path)
        if current_version:
            print(f"Current ChromeDriver version: {current_version}")
        else:
            print("Current ChromeDriver version unknown")

    # Get Chrome version and matching ChromeDriver
    chrome_version = get_chrome_version()
    if chrome_version:
        print(f"Chrome browser version: {chrome_version}")

        if not args.latest:
            print("Finding matching ChromeDriver version...")
            chromedriver_info = get_chromedriver_version_for_chrome(chrome_version)
        else:
            print("Getting latest ChromeDriver version...")
            chromedriver_info = get_latest_chromedriver_info()
    else:
        print("Chrome browser not found, getting latest ChromeDriver...")
        chromedriver_info = get_latest_chromedriver_info()

    if not chromedriver_info:
        print("Failed to get ChromeDriver information")
        sys.exit(1)

    new_version = chromedriver_info["version"]
    print(f"ChromeDriver version to install: {new_version}")

    # Check if update is needed
    if current_version == new_version and not args.force:
        print("ChromeDriver is already up to date")
        print("Use --force to reinstall")
        sys.exit(0)

    # Download and install
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        zip_path = temp_path / "chromedriver.zip"

        print(f"Downloading from: {chromedriver_info['download_url']}")
        if not download_file(chromedriver_info['download_url'], zip_path):
            sys.exit(1)

        print("Extracting ChromeDriver...")
        chromedriver_path = extract_chromedriver(zip_path, temp_path)
        if not chromedriver_path:
            sys.exit(1)

        print("Installing ChromeDriver...")
        if not install_chromedriver(chromedriver_path, install_path):
            sys.exit(1)

        # Verify installation
        print("Verifying installation...")
        if verify_installation(install_path):
            print("✓ Installation successful!")
            print(f"Version: {new_version}")
            print(f"Location: {install_path}")

            # Add to PATH reminder if using user directory
            if not os.geteuid() and "/.local/bin" in str(install_path):
                print("\nNote: Make sure ~/.local/bin is in your PATH:")
                print('export PATH="$PATH:~/.local/bin"')
                print("Or add this to your ~/.bashrc or ~/.zshrc")
        else:
            print("✗ Installation verification failed")
            sys.exit(1)


if __name__ == "__main__":
    main()
