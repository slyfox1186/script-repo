#!/usr/bin/env python3

import os
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

def is_nas_available(path):
    # Check if the directory exists and we have read access
    available = os.path.isdir(path) and os.access(path, os.R_OK)
    if not available:
        error_message = "NAS drive is not available or not accessible. Please check the connection and permissions."
        return available

# Variables
container_id = "replace-this"
backup_folder = "/path/to/your/minecraft/backup/folder"
server_files_path = "/path/to/your/logs/folder"
log_file_path = os.path.join(server_files_path, "backup_log.txt")

# Twilio configuration
twilio_account_sid = 'replace_this'
twilio_auth_token = 'replace_this'
twilio_phone_number = 'replace_this'  # Twilio provided phone number
my_phone_number = 'replace_this'  # Your personal phone number to receive SMS

# Email configuration
email_sender = 'replace_this'
email_password = 'replace_this'  # Use the App-Specific Password here
email_receiver = 'replace_this'
smtp_server = 'replace_this'
smtp_port = replace_this  # 587 or 465 for SSL

def get_timestamped_backup_folder(base_path):
    timestamp = datetime.now().strftime("%I.%M.%p-%m.%d.%y")
    return os.path.join(base_path, f"minecraft-forge-{timestamp}")

def backup_files_with_rsync(source, destination):
    try:
        subprocess.run([
            "rsync", "-avz", "--info=progress2", "--progress",
            source, destination
        ], check=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
        log_message(f"Files from {source} backed up to {destination} successfully.")
    except subprocess.CalledProcessError as e:
        error_message = f"Error during backup: {e}"
        log_message(error_message)
        send_email("Backup Script Error", error_message)
        send_sms(error_message)

def send_email(subject, body):
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = email_sender
    msg['To'] = email_receiver

    try:
        server = smtplib.SMTP(smtp_server, smtp_port)
        server.starttls()
        server.login(email_sender, email_password)
        server.sendmail(email_sender, email_receiver, msg.as_string())
        server.quit()
        print("Email sent successfully")
    except Exception as e:
        print(f"Error sending email: {e}")

def send_sms(message):
    client = Client(twilio_account_sid, twilio_auth_token)
    try:
        client.messages.create(to=my_phone_number, from_=twilio_phone_number, body=message)
        print("SMS sent successfully")
    except Exception as e:
        print(f"Error sending SMS: {e}")

def log_message(message):
    timestamp = datetime.now().strftime("%I.%M.%p-%m.%d.%y")
    with open(log_file_path, "a") as log_file:
        log_file.write(f"{timestamp} - {message}\n")
    print(message)

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

def main():
    import sys
    print(f"Running with Python interpreter: {sys.executable}")
    log_message("Backup script started.")

    timestamped_backup_folder = get_timestamped_backup_folder(backup_folder)

    if is_nas_available(backup_folder):
        backup_files_with_rsync(server_files_path, timestamped_backup_folder)
    
    log_message("Backup script finished.")

if __name__ == "__main__":
    main()
