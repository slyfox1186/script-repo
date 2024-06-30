#!/usr/bin/env python3

import argparse
import curses
import logging
import os
import shlex
import subprocess
import sys
import time
import threading

# Share names to mount
SHARE_NAMES = [
    "Documents",
    "NP",
    "Users",
    "Youtube-Download"
]

# Hardcoded default values
DEFAULT_IP_ADDRESS = ''
DEFAULT_USERNAME = ''
DEFAULT_PASSWORD = ''
DEFAULT_FOLDER_PREFIX = 'Share_'

# Argument parser setup
parser = argparse.ArgumentParser(description='Shared Folder Manager')
parser.add_argument('-u', '--username', type=str, required=True, help='Username for the share')
parser.add_argument('-p', '--password', type=str, required=True, help='Password for the share')
parser.add_argument('-ip', '--ip_address', type=str, required=True, help='IP address of the share')
parser.add_argument('-fp', '--folder_prefix', type=str, help='Folder prefix for mounts (optional)')
parser.add_argument('-n', '--no-fstab', action='store_true', help='Do not modify /etc/fstab for persistent mounting')

args = parser.parse_args()

# Use the parsed arguments or default values
IP_ADDRESS = args.ip_address if args.ip_address else DEFAULT_IP_ADDRESS
USERNAME = args.username if args.username else DEFAULT_USERNAME
PASSWORD = args.password if args.password else DEFAULT_PASSWORD
FOLDER_PREFIX = args.folder_prefix if args.folder_prefix else DEFAULT_FOLDER_PREFIX
NO_FSTAB = args.no_fstab

# Check if required values are set
missing_values = []
if not IP_ADDRESS:
    missing_values.append("IP_ADDRESS")
if not USERNAME:
    missing_values.append("USERNAME")
if not PASSWORD:
    missing_values.append("PASSWORD")

if missing_values:
    print(f"Error: Missing required values: {', '.join(missing_values)}")
    sys.exit(1)

logging.basicConfig(filename='/tmp/shared_folder_manager.log', level=logging.DEBUG)

def run_command(command, timeout=30):
    logging.debug(f"Running command: {command}")
    try:
        process = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        logging.debug(f"Command output: {process.stdout.decode()}")
        return process.stdout.decode(), process.stderr.decode(), process.returncode
    except subprocess.TimeoutExpired:
        logging.error(f"Command timed out: {command}")
        return "", "Command timed out", 1
    except subprocess.CalledProcessError as e:
        logging.error(f"Command failed: {e}")
        return "", e.stderr.decode(), e.returncode

def mount_share(share_name):
    mount_point = f"/media/{os.environ['SUDO_USER']}/{FOLDER_PREFIX}{share_name}"
    symlink_path = f"/home/{os.environ['SUDO_USER']}/{FOLDER_PREFIX}{share_name}"
    
    os.makedirs(mount_point, exist_ok=True)
    
    if os.path.ismount(mount_point):
        run_command(f"umount -f {shlex.quote(mount_point)}")
    
    command = (
        f"mount -t cifs //{IP_ADDRESS}/{share_name} {shlex.quote(mount_point)} "
        f"-o username={shlex.quote(USERNAME)},password={shlex.quote(PASSWORD)},"
        f"uid=$(id -u {shlex.quote(os.environ['SUDO_USER'])}),"
        f"gid=$(id -g {shlex.quote(os.environ['SUDO_USER'])}),"
        f"file_mode=0777,dir_mode=0777,noperm,rw,vers=3.0"
    )
    stdout, stderr, returncode = run_command(command)
    if returncode != 0:
        return f"Failed to mount {share_name}: {stderr}"
    
    if not os.path.exists(symlink_path):
        os.symlink(mount_point, symlink_path)
    
    if not NO_FSTAB:
        fstab_entry = (
            f"//{IP_ADDRESS}/{share_name} {mount_point} cifs "
            f"username={USERNAME},password={PASSWORD},"
            f"uid=$(id -u {os.environ['SUDO_USER']}),"
            f"gid=$(id -g {os.environ['SUDO_USER']}),"
            f"file_mode=0777,dir_mode=0777,noperm,rw,vers=3.0,_netdev 0 0"
        )
        with open('/etc/fstab', 'r+') as f:
            content = f.read()
            if mount_point not in content:
                f.write(f"\n{fstab_entry}")
    
    return f"Successfully mounted {share_name}"

def remove_mount(share_name):
    mount_point = f"/media/{os.environ['SUDO_USER']}/{FOLDER_PREFIX}{share_name}"
    symlink_path = f"/home/{os.environ['SUDO_USER']}/{FOLDER_PREFIX}{share_name}"
    
    if os.path.ismount(mount_point):
        run_command(f"umount -f {shlex.quote(mount_point)}")
    
    if os.path.exists(symlink_path):
        os.remove(symlink_path)
    
    if os.path.exists(mount_point):
        os.rmdir(mount_point)
    
    if not NO_FSTAB:
        # Remove from fstab
        with open('/etc/fstab', 'r') as f:
            lines = f.readlines()
        with open('/etc/fstab', 'w') as f:
            for line in lines:
                if mount_point not in line:
                    f.write(line)
    
    return f"Removed mount for {share_name}"

def detect_file_manager():
    file_managers = ["nautilus", "dolphin", "nemo", "thunar", "pcmanfm"]
    for fm in file_managers:
        try:
            output = subprocess.check_output(["pgrep", "-l", fm])
            if fm in output.decode():
                return fm
        except subprocess.CalledProcessError:
            continue
    return None

def refresh_file_manager_async():
    file_manager = detect_file_manager()
    user = os.environ['SUDO_USER']
    if file_manager:
        run_command(f"pkill {shlex.quote(file_manager)}")
        time.sleep(1)
    if file_manager:
        run_command(f"su {shlex.quote(user)} -c 'DISPLAY=:0 {shlex.quote(file_manager)} --no-desktop & disown'", timeout=5)
    else:
        print("No file manager detected.")

def main(stdscr):
    curses.curs_set(0)
    stdscr.clear()

    stdscr.addstr(0, 0, "Shared Folder Manager")
    stdscr.addstr(2, 0, "1. Add Mounts")
    stdscr.addstr(3, 0, "2. Remove Mounts")
    stdscr.addstr(4, 0, "3. Exit")
    stdscr.addstr(6, 0, "Enter your choice: ")
    stdscr.refresh()

    choice = stdscr.getch()

    if choice == ord('3') or choice == ord('q'):
        return

    if chr(choice) in ['1', '2']:
        selected = [True] * len(SHARE_NAMES)  # All shares are selected by default
        current_selection = 0

        while True:
            stdscr.clear()
            stdscr.addstr(0, 0, "Select shares to process (press Enter to confirm):")
            for i, share in enumerate(SHARE_NAMES):
                if i == current_selection:
                    stdscr.addstr(i+2, 0, f"> [{' x' if selected[i] else '  '}] {share}")
                else:
                    stdscr.addstr(i+2, 0, f"  [{'x ' if selected[i] else '  '}] {share}")
            stdscr.addstr(len(SHARE_NAMES)+3, 0, "Use arrow keys to move, Space to select/deselect, Enter to confirm")
            stdscr.refresh()

            key = stdscr.getch()

            if key == ord(' '):
                selected[current_selection] = not selected[current_selection]
            elif key == 10:  # Enter key
                break
            elif key == curses.KEY_UP and current_selection > 0:
                current_selection -= 1
            elif key == curses.KEY_DOWN and current_selection < len(SHARE_NAMES) - 1:
                current_selection += 1

        stdscr.clear()
        for i, share in enumerate(SHARE_NAMES):
            if selected[i]:
                if chr(choice) == '1':
                    result = mount_share(share)
                else:
                    result = remove_mount(share)
                stdscr.addstr(i, 0, result)

        stdscr.addstr(len(SHARE_NAMES) + 1, 0, "Refreshing file manager...")
        stdscr.refresh()
        
        # Start file manager refresh in a separate thread
        threading.Thread(target=refresh_file_manager_async, daemon=True).start()
        
        stdscr.addstr(len(SHARE_NAMES) + 2, 0, "Operation completed. Exiting...")
        stdscr.refresh()
        time.sleep(2)  # Give user a moment to see the completion message

if __name__ == "__main__":
    if os.geteuid() != 0:
        print("This script must be run as root. Please use sudo.")
        sys.exit(1)
    
    try:
        curses.wrapper(main)
    except Exception as e:
        logging.exception("An error occurred")
        print(f"An error occurred. Please check the log file at /tmp/shared_folder_manager.log")
