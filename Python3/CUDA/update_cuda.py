#!/usr/bin/env python3

## All Debian packages are officially sourced from: https://developer.nvidia.com/cuda-downloads/
## Execute: python3 update_cuda.py
##
## Optional args:
## [-f | --force] to force a download regardless (even if it overwrites the same version)
## [-o menu_number_here] to bypass the menu

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

# Configuration
LOG_DIR = Path("/tmp/cuda_updater_log")
LOG_FILE = LOG_DIR / "last_installed_version.log"
BASE_URL = "https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution="

# ANSI color codes for better visual presentation
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    END = '\033[0m'

# OS options and their configurations
OS_OPTIONS = {
    1: {
        "name": "Debian 12",
        "url": BASE_URL + "Debian&target_version=12&target_type=deb_local",
        "os_id": "debian12",
        "needs_pin": False,
        "package_suffix": "cuda-toolkit",
    },
    2: {
        "name": "Ubuntu 20.04",
        "url": BASE_URL + "Ubuntu&target_version=20.04&target_type=deb_local",
        "os_id": "ubuntu2004",
        "needs_pin": True,
        "package_suffix": "cuda",
    },
    3: {
        "name": "Ubuntu 22.04",
        "url": BASE_URL + "Ubuntu&target_version=22.04&target_type=deb_local",
        "os_id": "ubuntu2204",
        "needs_pin": True,
        "package_suffix": "cuda",
    },
    4: {
        "name": "Ubuntu 24.04",
        "url": BASE_URL + "Ubuntu&target_version=24.04&target_type=deb_local",
        "os_id": "ubuntu2404",
        "needs_pin": True,
        "package_suffix": "cuda",
    },
    5: {
        "name": "WSL Ubuntu",
        "url": BASE_URL + "WSL-Ubuntu&target_version=2.0&target_type=deb_local",
        "os_id": "wsl-ubuntu",
        "needs_pin": True,
        "package_suffix": "cuda-toolkit",
    }
}

def show_menu():
    """Display OS selection menu with professional formatting."""
    menu_width = 60
    
    print("\n")
    print(f"{Colors.BLUE}{'=' * menu_width}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.YELLOW}{' ' * 5}NVIDIA CUDA INSTALLER - OS Selection Menu{Colors.END}")
    print(f"{Colors.BLUE}{'=' * menu_width}{Colors.END}")
    print()
    
    for key, option in OS_OPTIONS.items():
        print(f"    {Colors.GREEN}{key}{Colors.END})  {Colors.BOLD}{option['name']}{Colors.END}")
    
    print()
    print(f"{Colors.BLUE}{'=' * menu_width}{Colors.END}")
    print(f"    {Colors.CYAN}Command line options:{Colors.END}")
    print(f"    {Colors.YELLOW}-f, --force{Colors.END}    Force installation regardless of version")
    print(f"    {Colors.YELLOW}-o, --os{Colors.END}       Specify OS number directly (1-5)")
    print(f"{Colors.BLUE}{'=' * menu_width}{Colors.END}")
    
    while True:
        try:
            print()
            choice = int(input(f"  {Colors.BOLD}Select your OS (1-5): {Colors.END}"))
            if choice in OS_OPTIONS:
                return choice
            print(f"\n  {Colors.RED}Invalid option. Please enter a number between 1 and 5.{Colors.END}")
        except ValueError:
            print(f"\n  {Colors.RED}Please enter a valid number.{Colors.END}")

def get_last_installed_version(os_id):
    """Read the last installed version from log file."""
    log_file = LOG_DIR / f"{os_id}_version.log"
    if os.path.exists(log_file):
        with open(log_file, 'r') as f:
            return f.read().strip()
    return None

def get_system_cuda_version():
    """Check the actual installed CUDA version on the system."""
    try:
        # Try using nvcc to get the version
        result = subprocess.run("nvcc --version", shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            # Extract version from nvcc output (e.g., "release 12.9.0")
            match = re.search(r'release\s+(\d+\.\d+\.\d+)', result.stdout)
            if match:
                return match.group(1)
        
        # Alternative check for CUDA libraries
        result = subprocess.run("dpkg -l | grep -E 'cuda-[0-9]+'", shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            # Look for cuda-12-9 or similar pattern
            match = re.search(r'cuda-(\d+)-(\d+)', result.stdout)
            if match:
                major = match.group(1)
                minor = match.group(2)
                return f"{major}.{minor}.0"  # Approximate version
                
        return None
    except Exception:
        return None

def save_version(os_id, version):
    """Save version to log file."""
    os.makedirs(LOG_DIR, exist_ok=True)
    log_file = LOG_DIR / f"{os_id}_version.log"
    with open(log_file, 'w') as f:
        f.write(version)
    print(f"Updated log file with version: {version} for {os_id}")

def get_cuda_version(url):
    """Get the latest CUDA version information using curl and grep."""
    try:
        cmd = f"curl -sSL '{url}' | grep -oP '1[2-3]\\.\\d\\.\\d-\\d{{3}}\\.\\d+\\.\\d+-\\d_amd64\\.deb|1[2-3]\\.\\d\\.\\d-\\d_amd64\\.deb' | head -n1"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        version_str = result.stdout.strip()
        
        if not version_str:
            # Try a less strict pattern if first attempt fails
            cmd = f"curl -sSL '{url}' | grep -oP '1[2-3]\\.\\d\\.\\d[^\"]+_amd64\\.deb' | head -n1"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            version_str = result.stdout.strip()
        
        # Extract CUDA version (e.g., 12.9.0) from the version string
        match = re.search(r'(1[2-3]\.\d\.\d)', version_str)
        if match:
            cuda_version = match.group(1)
            return cuda_version, version_str
        return None, None
    except Exception as e:
        print(f"Error getting version: {e}")
        return None, None

def run_command(cmd, exit_on_error=True):
    """Run a shell command and exit on error if specified."""
    print(f"{Colors.CYAN}Running: {cmd}{Colors.END}")
    result = subprocess.run(cmd, shell=True)
    if result.returncode != 0 and exit_on_error:
        print(f"{Colors.RED}Command failed with exit code {result.returncode}{Colors.END}")
        sys.exit(result.returncode)
    return result.returncode == 0

def install_cuda(os_config, version_str, cuda_version):
    """Execute CUDA installation commands based on OS."""
    os_id = os_config["os_id"]
    needs_pin = os_config["needs_pin"]
    package_suffix = os_config["package_suffix"]
    
    # Parse major-minor for URL path (e.g., "12-9" from "12.9.0")
    major, minor = cuda_version.split('.')[:2]
    major_minor = f"{major}-{minor}"
    
    print(f"\n{Colors.BOLD}{Colors.GREEN}=== Installing CUDA {cuda_version} for {os_config['name']} ==={Colors.END}")
    
    # Step 1: Download and setup pin if needed
    if needs_pin:
        print(f"\n{Colors.YELLOW}>> Setting up pin file...{Colors.END}")
        run_command(f"wget --show-progress -cq https://developer.download.nvidia.com/compute/cuda/repos/{os_id}/x86_64/cuda-{os_id}.pin")
        run_command(f"sudo mv cuda-{os_id}.pin /etc/apt/preferences.d/cuda-repository-pin-600")
    
    # Step 2: Download and install repo package
    print(f"\n{Colors.YELLOW}>> Downloading CUDA repository package...{Colors.END}")
    deb_file = ""
    if "wsl" in os_id.lower():
        # Special case for WSL
        deb_file = f"cuda-repo-{os_id}-{major_minor}-local_{cuda_version}-1_amd64.deb"
        run_command(f"wget --show-progress -cq https://developer.download.nvidia.com/compute/cuda/{cuda_version}/local_installers/{deb_file}")
    elif "-" in version_str:
        # For version strings with build numbers
        deb_file = f"cuda-repo-{os_id}-{major_minor}-local_{version_str}"
        run_command(f"wget --show-progress -cq https://developer.download.nvidia.com/compute/cuda/{cuda_version}/local_installers/{deb_file}")
    else:
        # For simple version strings
        deb_file = f"cuda-repo-{os_id}-{major_minor}-local_{cuda_version}-1_amd64.deb"
        run_command(f"wget --show-progress -cq https://developer.download.nvidia.com/compute/cuda/{cuda_version}/local_installers/{deb_file}")
    
    # Install the deb package
    print(f"\n{Colors.YELLOW}>> Installing repository package...{Colors.END}")
    run_command(f"sudo dpkg -i {deb_file}")
    
    # Step 3: Copy key
    print(f"\n{Colors.YELLOW}>> Setting up repository keys...{Colors.END}")
    run_command(f"sudo cp /var/cuda-repo-{os_id}-*/cuda-*-keyring.gpg /usr/share/keyrings/")
    
    # Step 4: Update and install
    print(f"\n{Colors.YELLOW}>> Updating package information...{Colors.END}")
    run_command("sudo apt update")
    
    # Install the appropriate package
    print(f"\n{Colors.YELLOW}>> Installing CUDA packages...{Colors.END}")
    if package_suffix == "cuda-toolkit":
        run_command(f"sudo apt -y install {package_suffix}-{major_minor}")
    else:
        run_command(f"sudo apt -y install {package_suffix}")
    
    print(f"\n{Colors.BOLD}{Colors.GREEN}=== CUDA {cuda_version} Installation Complete ==={Colors.END}\n")

def main():
    parser = argparse.ArgumentParser(description="CUDA Updater for multiple Linux distributions")
    parser.add_argument("-f", "--force", action="store_true", help="Force installation regardless of version")
    parser.add_argument("-o", "--os", type=int, choices=range(1, 6), help="OS selection (1=Debian 12, 2=Ubuntu 20.04, 3=Ubuntu 22.04, 4=Ubuntu 24.04, 5=WSL Ubuntu)")
    args = parser.parse_args()
    
    # OS selection
    os_choice = args.os if args.os else show_menu()
    os_config = OS_OPTIONS[os_choice]
    
    print(f"\n{Colors.BOLD}Selected OS: {Colors.YELLOW}{os_config['name']}{Colors.END}")
    
    # Get the latest version for selected OS
    cuda_version, version_str = get_cuda_version(os_config['url'])
    if not cuda_version or not version_str:
        print(f"{Colors.RED}Error: Could not detect latest CUDA version{Colors.END}")
        return
    
    # Actually check what's installed on the system
    system_version = get_system_cuda_version()
    log_version = get_last_installed_version(os_config['os_id'])
    
    # Use system version if available, otherwise fallback to log
    installed_version = system_version or log_version
    
    print(f"{Colors.CYAN}Installed CUDA version: {Colors.BOLD}{installed_version or 'None'}{Colors.END}")
    print(f"{Colors.CYAN}Latest available version: {Colors.BOLD}{cuda_version}{Colors.END}")
    
    # Skip installation if same version is already installed AND force flag isn't used
    if installed_version == cuda_version and not args.force:
        print(f"{Colors.YELLOW}Already using latest version {cuda_version}. Use -f or --force to reinstall anyway.{Colors.END}")
        return
        
    # If we get here, either it's a new version or force flag is used
    if installed_version != cuda_version:
        print(f"{Colors.GREEN}New version {cuda_version} available - installing{Colors.END}")
    else: # Must be force flag
        print(f"{Colors.YELLOW}Force reinstallation of current version {cuda_version}{Colors.END}")
        
    install_cuda(os_config, version_str, cuda_version)
    save_version(os_config['os_id'], cuda_version)

if __name__ == "__main__":
    main()
