#!/usr/bin/env python3

import curses
import logging
import os
import subprocess
import sys
import time
import threading

IP_ADDRESS = ''
USERNAME = ''
PASSWORD = ''

SHARE_NAMES = [
    "Folder1",
    "Folder2"
]

logging.basicConfig(filename='/tmp/windows_share_manager.log', level=logging.DEBUG)

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
        return "", str(e), e.returncode

def mount_share(share_name):
    mount_point = f"/media/{os.environ['SUDO_USER']}/Win_{share_name}"
    symlink_path = f"/home/{os.environ['SUDO_USER']}/Win_{share_name}"
    
    os.makedirs(mount_point, exist_ok=True)
    
    if os.path.ismount(mount_point):
        run_command(f"umount -f {mount_point}")
    
    command = f"mount -t cifs //{IP_ADDRESS}/{share_name} {mount_point} -o username='{USERNAME}',password='{PASSWORD}',uid=$(id -u {os.environ['SUDO_USER']}),gid=$(id -g {os.environ['SUDO_USER']}),file_mode=0777,dir_mode=0777,noperm,rw,vers=3.0"
    stdout, stderr, returncode = run_command(command)
    if returncode != 0:
        return f"Failed to mount {share_name}: {stderr}"
    
    if not os.path.exists(symlink_path):
        os.symlink(mount_point, symlink_path)
    
    fstab_entry = f"//{IP_ADDRESS}/{share_name} {mount_point} cifs username={USERNAME},password={PASSWORD},uid=$(id -u {os.environ['SUDO_USER']}),gid=$(id -g {os.environ['SUDO_USER']}),file_mode=0777,dir_mode=0777,noperm,rw,vers=3.0,_netdev 0 0"
    with open('/etc/fstab', 'r+') as f:
        content = f.read()
        if mount_point not in content:
            f.write(f"\n{fstab_entry}")
    
    return f"Successfully mounted {share_name}"

def remove_mount(share_name):
    mount_point = f"/media/{os.environ['SUDO_USER']}/Win_{share_name}"
    symlink_path = f"/home/{os.environ['SUDO_USER']}/Win_{share_name}"
    
    if os.path.ismount(mount_point):
        run_command(f"umount -f {mount_point}")
    
    if os.path.exists(symlink_path):
        os.remove(symlink_path)
    
    if os.path.exists(mount_point):
        os.rmdir(mount_point)
    
    # Remove from fstab
    with open('/etc/fstab', 'r') as f:
        lines = f.readlines()
    with open('/etc/fstab', 'w') as f:
        for line in lines:
            if mount_point not in line:
                f.write(line)
    
    return f"Removed mount for {share_name}"

def refresh_nautilus_async():
    user = os.environ['SUDO_USER']
    home = f"/home/{user}"
    
    bookmarks_file = f"{home}/.config/gtk-3.0/bookmarks"
    if os.path.exists(bookmarks_file):
        with open(bookmarks_file, 'r') as f:
            bookmarks = f.readlines()
        with open(bookmarks_file, 'w') as f:
            for bookmark in bookmarks:
                if not any(f"Win_{share}" in bookmark for share in SHARE_NAMES):
                    f.write(bookmark)

    run_command(f"rm -rf {home}/.local/share/gvfs-metadata/*")
    run_command("killall nautilus")
    time.sleep(1)
    run_command(f"su {user} -c 'DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u {user})/bus nautilus --no-desktop'", timeout=5)

def main(stdscr):
    curses.curs_set(0)
    stdscr.clear()

    stdscr.addstr(0, 0, "Windows Share Manager")
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

        stdscr.addstr(len(SHARE_NAMES) + 1, 0, "Refreshing Nautilus...")
        stdscr.refresh()
        
        # Start Nautilus refresh in a separate thread
        threading.Thread(target=refresh_nautilus_async, daemon=True).start()
        
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
        print(f"An error occurred. Please check the log file at /tmp/windows_share_manager.log")
