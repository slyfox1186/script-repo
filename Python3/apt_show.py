#!/usr/bin/env python3

import subprocess
import re
from fuzzywuzzy import process

# ANSI color codes
RED = "\033[1;31m"
GREEN = "\033[1;32m"
YELLOW = "\033[1;33m"
WHITE = "\033[1;37m"
BLUE = "\033[1;34m"
RESET = "\033[0m"

def fetch_all_package_names():
    """Fetch all available package names."""
    cmd = ['apt-cache', 'pkgnames']
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, text=True, check=True)
    package_names = proc.stdout.strip().split('\n') if proc.stdout else []
    return package_names

def suggest_close_matches(package_name):
    """Suggest close matches for the given package name using fuzzywuzzy."""
    all_packages = fetch_all_package_names()
    close_matches = process.extractBests(package_name, all_packages, limit=5, score_cutoff=70)
    if close_matches:
        print(f"{YELLOW}Did you mean one of these packages?{RESET}")
        for match, score in close_matches:
            print(f"- {match} (score: {score})")
    else:
        print(f"{RED}No close matches found for '{package_name}'.{RESET}")

def fetch_package_details(package_name):
    """Fetch and display details for a given package."""
    cmd = ['apt-cache', 'show', package_name]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)
    if proc.stdout and proc.stdout.strip():
        details = proc.stdout.strip()
        colorize_and_print_details(details, package_name)
    else:
        print(f"{RED}Package '{package_name}' not found.{RESET}")
        suggest_close_matches(package_name)  # Suggest close matches if no exact match found

def colorize_and_print_details(details, package_name):
    """Colorize and print package details based on predefined rules."""
    for line in details.split('\n'):
        line = colorize_line(line, package_name)
        print(line)

def colorize_line(line, package_name):
    """Apply colorization rules to a single line of package details."""
    line = re.sub(r'([(){}\[\]])', f"{RED}\\1{RESET}", line)
    line = re.sub(f"\\b{package_name}\\b", f"{GREEN}{package_name}{RESET}", line, flags=re.IGNORECASE)
    line = re.sub(r'\<([^>]+)\>', lambda m: f"{RED}<{BLUE}{m.group(1)}{RED}>{RESET}", line)
    if ':' in line:
        key, value = line.split(':', 1)
        line = f"{YELLOW}{key}:{RESET} {value}"
    return line

def main():
    package_name = input("Enter a package name for detailed info, or 'exit' to quit: ").strip()
    while package_name.lower() != 'exit':
        fetch_package_details(package_name)
        package_name = input("\nEnter a package name for detailed info, or 'exit' to quit: ").strip()
    print("Exiting the Package Information Tool.")

if __name__ == "__main__":
    main()
