#!/usr/bin/env python3

import subprocess
import re

# ANSI color codes
RED = "\033[1;31m"
GREEN = "\033[1;32m"
YELLOW = "\033[1;33m"
WHITE = "\033[1;37m"
BLUE = "\033[1;34m"
RESET = "\033[0m"

def fetch_package_details(package_name):
    """Fetch and display details for a given package."""
    cmd = ['apt-cache', 'show', package_name]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)
    if proc.stdout:
        details = proc.stdout.strip()
        colorize_and_print_details(details, package_name)
    else:
        print(f"{RED}Package '{package_name}' not found.{RESET}")

def colorize_and_print_details(details, package_name):
    """Colorize and print package details based on predefined rules."""
    for line in details.split('\n'):
        line = colorize_line(line, package_name)
        print(line)

def colorize_line(line, package_name):
    """Apply colorization rules to a single line of package details."""
    # Correctly escape and colorize brackets
    line = re.sub(r'([(){}\[\]])', f"{RED}\\1{RESET}", line)

    # Colorize package name occurrences
    line = re.sub(f"\\b{package_name}\\b", f"{GREEN}{package_name}{RESET}", line, flags=re.IGNORECASE)

    # Colorize email addresses within <>
    # Ensuring the angle brackets and the email itself are correctly escaped and processed
    line = re.sub(r'\<([^>]+)\>', lambda m: f"{RED}<{BLUE}{m.group(1)}{RED}>{RESET}", line)

    # Colorize key names before ':'
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
