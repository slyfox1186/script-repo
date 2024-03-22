#!/usr/bin/env python3

import re
import argparse
import os
import shutil
import subprocess
import sys
import json
from termcolor import colored

def log_verbose(message, verbose):
    if verbose:
        print(colored(message, "yellow"))

def install_shellcheck(verbose):
    log_verbose("Installing ShellCheck...", verbose)
    try:
        subprocess.run(["apt-get", "update"], check=True)
        subprocess.run(["apt-get", "install", "-y", "shellcheck"], check=True)
        print(colored("ShellCheck installed successfully.", "green"))
    except subprocess.CalledProcessError as e:
        print(colored(f"Error installing ShellCheck: {e}", "red"))
        sys.exit(1)

def run_shellcheck(target_files, directory, recursive, exclusions, color, verbose):
    command = ["shellcheck"]

    if color:
        command.append("--color=always")

    if directory:
        command.extend(["-D", directory])

    if recursive:
        command.append("-R")

    if exclusions:
        command.extend(["-e", exclusions])

    if verbose:
        command.append("--format=tty")
    else:
        command.append("--format=json")

    success_count = 0
    error_count = 0
    warning_count = 0
    info_count = 0
    style_count = 0
    error_free_files = []
    seen_issues = set()

    def colorize_path(match):
        slash1, text, slash2 = match.groups()
        colored_text = f"{colored(slash1, 'red') if slash1 else ''}"\
                       f"{colored(text, 'green')}"\
                       f"{colored(slash2, 'red') if slash2 else ''}"
        return colored_text

    for target_file in target_files:
        log_verbose(f"Checking {target_file}...", verbose)
        try:
            result = subprocess.run(command + [target_file], capture_output=True, text=True)
            output = result.stdout.strip()
            return_code = result.returncode

            if return_code == 0:
                success_count += 1
                error_free_files.append(target_file)
                print(colored(f"No issues found in {target_file}.", "green"))
            else:
                file_error_count = 0
                if verbose:
                    print(colored("=" * 80, "cyan"))
                    print(colored(f"ShellCheck Results for {target_file}:", "cyan"))
                    print(colored("=" * 80, "cyan"))

                    lines = output.split("\n")
                    for line in lines:
                        if line.startswith("In "):
                            print(colored(line, "magenta"))
                        elif "^" in line:
                            line = re.sub(r'((?<=\/)[a-zA-Z0-9]+|[a-zA-Z0-9]+(?=\/))', lambda m: colored(m.group(1), 'cyan'), line)
                            line = re.sub(r'(-)([a-zA-Z])', lambda m: colored(m.group(1), 'red') + colored(m.group(2), 'cyan'), line)
                            line = re.sub(r'(\^[\-]+\^)', lambda x: colored(x.group(1), 'red'), line)
                            line = re.sub(r'(\()([a-zA-Z]+)(\))', lambda m: colored(m.group(1), 'red') + colored(m.group(2), 'cyan') + colored(m.group(3), 'red'), line)
                            line = re.sub(r'(:|\(|\)|\.+)', lambda x: colored(x.group(1), 'red'), line)
                            line = re.sub(r'(SC[0-9]+)', lambda x: colored(x.group(1), 'green'), line)
                            line = re.sub(r'([\/])', lambda x: colored(x.group(1), 'yellow'), line)
                            line = re.sub(r'((see)|shellcheck)', lambda x: colored(x.group(1), 'yellow'), line)
                            line = re.sub(r'([nN]ot)', lambda x: colored(x.group(1), 'red'), line)
                            print(line)
                        elif " SC" in line:
                            code_start = line.find(" SC")
                            code_end = line.find(" ", code_start + 1)
                            severity_start = line.find("(", code_end)
                            severity_end = line.find(")", severity_start)
                            print(line[:code_start], colored(line[code_start:code_end], "green"), colored(line[severity_start:severity_end+1], "blue"), line[severity_end+1:])
                        elif "http" in line:
                            url_start = line.find("http")
                            url_end = line.find(" ", url_start)
                            if url_end == -1:
                                url_end = len(line)
                            text_start = line.find("--", url_end)
                            if text_start != -1:
                                text_start += 2
                                print(colored(line[url_start:url_end], "blue"), colored("--", "red"), colored(line[text_start:], "white"))
                            else:
                                print(colored(line[url_start:url_end], "blue"))
                        else:
                            line = re.sub(r'((?<=\/)[a-zA-Z0-9]+|[a-zA-Z0-9]+(?=\/))', lambda m: colored(m.group(1), 'cyan'), line)
                            line = re.sub(r'([\/])', lambda m: colored(m.group(1), 'yellow'), line)
                            line = re.sub(r'\b(no|yes)\b', lambda m: colored(m.group(1), 'cyan'), line)
                            line = re.sub(r'(SC\d+)', lambda m: colored(m.group(1), 'green'), line)
                            line = re.sub(r'("|\.|\(|\)|:|<|>|\?)', lambda m: colored(m.group(1), 'red'), line)
                            line = re.sub(r'(-)([a-zA-Z])', lambda m: colored(m.group(1), 'red') + colored(m.group(2), 'cyan'), line)
                            print(line)

                    print(colored("=" * 80, "cyan"))
                else:
                    issues = json.loads(output)
                    print(colored(f"\nShellCheck Results for {target_file}:", "cyan"))
                    for issue in issues:
                        file_path = colored(issue["file"], "magenta")
                        line_number = colored(str(issue["line"]), "yellow")
                        severity = colored(issue["level"], "red")
                        message = colored(issue["message"], "white")
                        code = colored(issue["code"], "green")

                        issue_key = (file_path, line_number, severity, message, code)
                        if issue_key not in seen_issues:
                            seen_issues.add(issue_key)
                            print(colored("-" * 80, "cyan"))
                            print(f"In {file_path} line {line_number}:")
                            print(f"{severity}: {message} [{code}]")
                            if issue["level"] == "error":
                                error_count += 1
                                file_error_count += 1
                            elif issue["level"] == "warning":
                                warning_count += 1
                            elif issue["level"] == "info":
                                info_count += 1
                            elif issue["level"] == "style":
                                style_count += 1
                    print(colored("-" * 80, "cyan"))

                if file_error_count == 0:
                    error_free_files.append(target_file)

        except subprocess.CalledProcessError as e:
            error_count += 1
            print(colored(f"Error running ShellCheck on {target_file}: {e}", "red"))

    total_issues = error_count + warning_count + info_count + style_count
    print("\nShellCheck Summary:")
    print(colored(f"Errors: {error_count}", "red"))
    print(colored(f"Warnings: {warning_count}", "yellow"))
    print(colored(f"Info: {info_count}", "blue"))
    print(colored(f"Style: {style_count}", "cyan"))

    return error_free_files

def move_files(target_files, move_directory, verbose):
    if not move_directory:
        print(colored("Error: Move directory not specified. Please provide a full path.", "red"))
        sys.exit(1)

    if not os.path.isabs(move_directory):
        print(colored("Error: Move directory must be a full path.", "red"))
        sys.exit(1)

    os.makedirs(move_directory, exist_ok=True)

    for target_file in target_files:
        log_verbose(f"Moving {target_file} to {move_directory}", verbose)
        try:
            shutil.move(target_file, move_directory)
            print(colored(f"File {target_file} moved successfully.", "green"))
        except Exception as e:
            print(colored(f"Error moving {target_file}: {e}", "red"))

def display_summary(target_files, verbose):
    print(colored("Summary:", "magenta"))
    print(colored(f"Total files checked: {len(target_files)}", "magenta"))
    log_verbose(f"Target files: {', '.join(target_files)}", verbose)
    print(colored(f"ShellCheck version: {subprocess.run(['shellcheck', '--version'], capture_output=True, text=True).stdout.strip()}", "magenta"))

def get_default_target(verbose, recursive):
    script_directory = os.path.dirname(os.path.abspath(__file__))
    log_verbose(f"Scanning directory: {script_directory}", verbose)
    target_files = []

    if recursive:
        for root, dirs, files in os.walk(script_directory):
            for file_name in files:
                file_path = os.path.join(root, file_name)
                if os.path.isfile(file_path) and (os.path.splitext(file_name)[1] in ['.sh', ''] or '.' not in file_name):
                    target_files.append(file_path)
    else:
        for file_name in os.listdir(script_directory):
            file_path = os.path.join(script_directory, file_name)
            if os.path.isfile(file_path) and (os.path.splitext(file_name)[1] in ['.sh', ''] or '.' not in file_name):
                target_files.append(file_path)

    return target_files

def main():
    parser = argparse.ArgumentParser(
        description="ShellCheck Execution Script",
        formatter_class=argparse.RawTextHelpFormatter,
        add_help=False  # Disable the default help option
    )
    parser.add_argument("-h", "--help", action="help", help="Show this help message and exit")
    parser.add_argument("-c", "--color", action="store_true", help="Enable colored output")
    parser.add_argument("-d", "--directory", help="Specify the directory to check")
    parser.add_argument("-e", "--exclusions", help="Specify exclusion patterns")
    parser.add_argument("-i", "--install", action="store_true", help="Install ShellCheck")
    parser.add_argument("-m", "--move", help="Move error-free files to the specified directory (full path)")
    parser.add_argument("-r", "--recursive", action="store_true", help="Recursively check directories")
    parser.add_argument("-s", "--summary", action="store_true", help="Display a summary of the execution")
    parser.add_argument("-t", "--target", nargs='+', help="Specify the target files or directories")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose logging")

    parser.epilog = """
Examples:
  python sc.py -i                             Install ShellCheck
  python sc.py -t script1.sh script2.sh       Check specific files
  python sc.py -d /path/to/directory          Check files in a directory
  python sc.py -r -d /path/to/directory       Recursively check files in a directory
  python sc.py -e SC1090,SC2034               Exclude specific ShellCheck rules
  python sc.py -m /path/to/directory          Move error-free files to a directory
  python sc.py -s                             Display a summary of the execution
  python sc.py -v                             Enable verbose logging
"""

    def custom_error_handler(message):
        print(colored("Error: " + message, "red"))
        print()
        parser.print_help()
        sys.exit(2)

    parser.error = custom_error_handler

    args = parser.parse_args()

    if args.install:
        install_shellcheck(args.verbose)
    else:
        target_files = args.target or get_default_target(args.verbose, args.recursive)
        error_free_files = run_shellcheck(target_files, args.directory, args.recursive, args.exclusions, args.color, args.verbose)

        if args.move:
            move_files(error_free_files, args.move, args.verbose)

        if args.summary:
            display_summary(target_files, args.verbose)

if __name__ == "__main__":
    main()
