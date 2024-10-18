#!/usr/bin/env python3

"""
Python script to fetch the latest NVIDIA driver version for RTX 3080 Ti using the NVIDIA Driver API.
"""

import sys
import requests

def get_latest_driver_version():
    url = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php"
    params = {
        "func": "DriverManualLookup",
        "psid": "120",  # GeForce RTX 30 Series (Notebooks)
        "pfid": "929",  # RTX 3080 Ti
        "osID": "57",   # Windows 10 64-bit
        "languageCode": "1033",  # English (US)
        "isWHQL": "1",
        "dch": "1",
        "sort1": "0",
        "numberOfResults": "1"
    }

    try:
        response = requests.get(url, params=params)
        response.raise_for_status()
        data = response.json()

        if "IDS" in data and len(data["IDS"]) > 0:
            driver_info = data["IDS"][0]
            if "downloadInfo" in driver_info and "Version" in driver_info["downloadInfo"]:
                return driver_info["downloadInfo"]["Version"]
    except requests.RequestException:
        pass
    return None

def main():
    latest_version = get_latest_driver_version()
    if latest_version:
        print(latest_version)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
