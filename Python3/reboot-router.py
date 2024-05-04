#!/usr/bin/env python3

import subprocess
import time
import sys
import os
import argparse

# Check if the user has root privileges
if os.geteuid() != 0:
    print("You must run this script as root or with sudo.")
    sys.exit(1)

# Hardcoded default values
DEFAULT_IP = '192.168.1.1'
DEFAULT_USERNAME = 'admin'
DEFAULT_PASSWORD = 'admin'
DEFAULT_PORT = '22'

def parse_arguments():
    parser = argparse.ArgumentParser(
        description='This script reboots a router via SSH and monitors its status by checking when it comes back online after the reboot.')
    parser.add_argument('-i', '--ip', default=DEFAULT_IP, help='IP address of the router.')
    parser.add_argument('-u', '--username', default=DEFAULT_USERNAME, help='SSH username to log into the router.')
    parser.add_argument('-p', '--password', default=DEFAULT_PASSWORD, help='SSH password for the router.')
    parser.add_argument('-P', '--port', default=DEFAULT_PORT, help='SSH port number.')
    return parser.parse_args()

def clear_screen():
    subprocess.call('clear' if sys.platform == 'linux' else 'cls', shell=True)

def ping_router(ip):
    """Attempt to ping the router once with a timeout to return True if successful."""
    try:
        # Adjust the timeout value to ensure rapid ping checks
        subprocess.run(['ping', '-c', '1', '-W', '1', ip], check=True, stdout=subprocess.DEVNULL)
        return True
    except subprocess.CalledProcessError:
        return False

def reboot_router(ip, username, password, port):
    try:
        subprocess.run(['sshpass', '-p', password, 'ssh', '-o', 'StrictHostKeyChecking=no', '-p', port, f'{username}@{ip}', 'reboot'], check=True)
        return True
    except subprocess.CalledProcessError:
        return False

def countdown_and_monitor(ip, start_time=350, monitor_start=250):
    for i in range(start_time, -1, -1):
        clear_screen()
        print(f"Router will restart in {i} seconds")
        time.sleep(1)
        if i <= monitor_start and ping_router(ip):
            clear_screen()
            print("The router is back online.")
            return
    clear_screen()
    print("Router should be back online now.")

if __name__ == "__main__":
    args = parse_arguments()
    if reboot_router(args.ip, args.username, args.password, args.port):
        print("Reboot command sent successfully. Monitoring for restart...")
        countdown_and_monitor(args.ip)
    else:
        print("Failed to send reboot command. Check your SSH settings and credentials.")
