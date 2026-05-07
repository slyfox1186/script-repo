#!/usr/bin/env python3

import os
import shutil
import subprocess
from datetime import datetime
import smtplib
from email.mime.text import MIMEText
import subprocess
import sys

def is_package_installed(package_name):
    try:
        subprocess.run(["dpkg", "-s", package_name], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True
    except subprocess.CalledProcessError:
        return False

def install_package_interactively(package_name):
    command = f"gnome-terminal -- /bin/sh -c 'sudo apt-get install {package_name}; read -p \"Press Enter to continue...\"'"
    subprocess.run(command, shell=True)

if not is_package_installed("python3-twilio"):
    print("The package 'python3-twilio' is not installed.")
    install_package_interactively("python3-twilio")
    sys.exit("Please rerun the script after installing 'python3-twilio'.")

from twilio.rest import Client

# Variables
max_backups = 4  # Maximum number of backups to keep
container_id = "docker_container_id"
backup_folder = "/path/to/backup/folder"
server_files_path = "/path/to/minecraft/server/files"
log_file_path = os.path.join(server_files_path, "backup_log.txt")

# Twilio configuration
twilio_account_sid = 'change-this'
twilio_auth_token = 'change-this'
twilio_phone_number = '+1xxxxxxxxxx'  # Twilio provided phone number ( +1 is for USA )
my_phone_number = '+1xxxxxxxxxx'  # Your personal phone number to receive SMS ( +1 is for USA )

# Email configuration
email_sender = 'an-email-address-that-sends-the-email'
email_password = 'email-password'  # Use the App-Specific Password here
email_receiver = 'an-email-address-that-receives-the-email'
smtp_server = 'smtp.email.com'
smtp_port = 587

# Function definitions and rest of the script...

def is_nas_available(path):
    # Check if the directory exists and we have read access
    available = os.path.isdir(path) and os.access(path, os.R_OK)
    if not available:
        error_message = "NAS drive is not available or not accessible. Please check the connection and permissions."
        log_message(error_message)
        send_email("Backup Script Error", error_message)
        send_sms(error_message)
    return available

def backup_files_with_rsync(source, destination):
    try:
        subprocess.run([
            "rsync", "-avz", "--progress",
            source, destination
        ], check=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
        log_message(f"Backup completed successfully to {destination}")
    except subprocess.CalledProcessError as e:
        error_message = f"Error during backup: {e}"
        log_message(error_message)
        send_email("Backup Script Error", error_message)
        send_sms(error_message)

def limit_backups(backup_folder):
    # Get all directories in the backup folder
    backup_dirs = [os.path.join(backup_folder, d) for d in os.listdir(backup_folder) if os.path.isdir(os.path.join(backup_folder, d))]
    # Sort directories by creation time
    backup_dirs.sort(key=lambda x: os.path.getctime(x))

    # Remove the oldest backups if there are more than max_backups
    while len(backup_dirs) > max_backups:
        oldest_backup = backup_dirs.pop(0)
        shutil.rmtree(oldest_backup)
        log_message(f"Deleted old backup: {oldest_backup}")

def get_timestamped_backup_folder(base_folder):
    timestamp = datetime.now().strftime('%I.%M.%p-%m.%d.%y')
    return os.path.join(base_folder, f"mc-server-backup-{timestamp}")

def log_message(message):
    timestamp = datetime.now().strftime('%I.%M.%p-%m.%d.%y')
    formatted_message = f"{timestamp} - {message}"
    print(formatted_message)  # Print to console
    with open(log_file_path, "a") as log_file:  # Append to the log file
        log_file.write(formatted_message + "\n")

def stop_docker_container(container_id):
    try:
        subprocess.run(["docker", "stop", container_id], check=True)
        log_message(f"Docker container {container_id} stopped successfully.")
    except subprocess.CalledProcessError as e:
        log_message(f"Failed to stop Docker container {container_id}: {e}")

def start_docker_container(container_id):
    try:
        subprocess.run(["docker", "start", container_id], check=True)
        log_message(f"Docker container {container_id} started successfully.")
    except subprocess.CalledProcessError as e:
        log_message(f"Failed to start Docker container {container_id}: {e}")

def main():
    import sys
    log_message("Backup script started.")

    # Stop the Docker container before backup
    stop_docker_container(container_id)

    try:
        timestamped_backup_folder = get_timestamped_backup_folder(backup_folder)

        if is_nas_available(backup_folder):
            backup_files_with_rsync(server_files_path, timestamped_backup_folder)
        limit_backups(backup_folder)
    finally:
        # Start the Docker container after backup, regardless of success
        start_docker_container(container_id)
    
    log_message("Backup script finished.")

if __name__ == "__main__":
    main()
