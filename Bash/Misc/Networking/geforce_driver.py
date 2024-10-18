#!/usr/bin/env python3

"""
Fetch the latest NVIDIA driver version for the current GPU and operating system.
"""

import sys
import platform
import subprocess
import requests
import re
from typing import Dict, Optional

# GPU and OS mappings
GPU_MAPPINGS: Dict[str, Dict[str, str]] = {
    "NVIDIA GeForce RTX 3080 Ti": {"psid": "120", "pfid": "929"},
    "RTX 3090": {"psid": "120", "pfid": "921"},
    "RTX 4090": {"psid": "129", "pfid": "1025"},
    # Add more GPU mappings as needed
}

OS_MAPPINGS: Dict[str, str] = {
    "Windows-10": "57",
    "Windows-11": "135",
    "Linux": "12",
    # Add more OS mappings as needed
}

def is_wsl() -> bool:
    """Check if running on Windows Subsystem for Linux."""
    try:
        with open('/proc/version', 'r') as f:
            return 'microsoft' in f.read().lower()
    except:
        return False

def get_gpu_info() -> Optional[str]:
    """Detect the NVIDIA GPU model."""
    try:
        # Try nvidia-smi first
        output = subprocess.check_output(["nvidia-smi", "--query-gpu=gpu_name", "--format=csv,noheader"], universal_newlines=True)
        return output.strip()
    except subprocess.CalledProcessError:
        # If nvidia-smi fails, try reading from system files
        try:
            with open('/proc/driver/nvidia/gpus/0/information', 'r') as f:
                content = f.read()
                match = re.search(r'Model:\s+(.+)', content)
                if match:
                    return match.group(1).strip()
        except:
            pass
    
    print("Failed to detect GPU using nvidia-smi and system files.", file=sys.stderr)
    return None

def get_os_info() -> str:
    """Detect the operating system."""
    if is_wsl():
        return "Windows-11"  # Assuming Windows 11, adjust if necessary
    system = platform.system()
    if system == "Windows":
        version = platform.release()
        return f"Windows-{version}"
    elif system == "Linux":
        return "Linux"
    else:
        return "Unknown"

def get_latest_driver_version(gpu: str, os: str) -> Optional[str]:
    """Fetch the latest driver version for the specified GPU and OS."""
    url = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php"
    params = {
        "func": "DriverManualLookup",
        "psid": GPU_MAPPINGS[gpu]["psid"],
        "pfid": GPU_MAPPINGS[gpu]["pfid"],
        "osID": OS_MAPPINGS[os],
        "languageCode": "1033",
        "isWHQL": "1",
        "dch": "1",
        "sort1": "0",
        "numberOfResults": "1"
    }

    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()
        if "IDS" in data and data["IDS"]:
            driver_info = data["IDS"][0]
            return driver_info.get("downloadInfo", {}).get("Version")
    except requests.RequestException:
        pass
    return None

def main() -> None:
    """Main function to run the script."""
    gpu = get_gpu_info()
    os = get_os_info()

    if not gpu or gpu not in GPU_MAPPINGS or os not in OS_MAPPINGS:
        sys.exit(1)

    latest_version = get_latest_driver_version(gpu, os)
    
    if latest_version:
        print(latest_version)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
