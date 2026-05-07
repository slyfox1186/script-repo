#!/usr/bin/env python3

import json
import os
import sys

# Check if the correct number of arguments is provided
if len(sys.argv) != 5:
    print("Usage: python add_video_to_json.py <filename> <extension> <path> <url>")
    sys.exit(1)

# Get the command-line arguments
filename = sys.argv[1]
extension = sys.argv[2]
path = sys.argv[3]
url = sys.argv[4]

# JSON file path
json_file = "video_data.json"

# Create the JSON object for the video
video_json = {
    "filename": filename,
    "path": path,
    "url": url,
    "extension": extension
}

# Read the existing JSON data from the file
existing_data = []
if os.path.exists(json_file):
    try:
        with open(json_file, "r") as file:
            existing_data = json.load(file)
    except json.JSONDecodeError:
        print(f"Error: The JSON file '{json_file}' is not properly formatted. Creating a new file.")
        existing_data = []

# Append the new video JSON object to the existing data
existing_data.append(video_json)

# Write the updated JSON data back to the file with indentation
with open(json_file, "w") as file:
    json.dump(existing_data, file, indent=2)

print(f"Video details added to {json_file}.")
