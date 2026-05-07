#!/usr/bin/env python3

import csv
import json
import sys

def csv_to_json(csv_file_path, json_file_path):
    try:
        with open(csv_file_path, mode='r') as csv_file:
            csv_reader = csv.DictReader(csv_file)
            data = [row for row in csv_reader]

        with open(json_file_path, mode='w') as json_file:
            json.dump(data, json_file, indent=4)
        
        print("CSV converted to JSON successfully.")
    except Exception as e:
        print(f"Error: {e}")

def main():
    if len(sys.argv) != 3:
        print_help()
        sys.exit(1)

    csv_file_path = sys.argv[1]
    json_file_path = sys.argv[2]

    csv_to_json(csv_file_path, json_file_path)

def print_help():
    print("Usage: csv_to_json.py <csv_file> <json_file>")
    print("Converts a CSV file to a JSON file.")
    print("Arguments:")
    print("  <csv_file>  Path to the input CSV file")
    print("  <json_file> Path to the output JSON file")

if __name__ == "__main__":
    main()
