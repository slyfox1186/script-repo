#!/usr/bin/env python3

import os
from datetime import datetime
import subprocess

# Configuration
docker_container_id = 'replace_with_docker_container_id'  # Docker container ID for the Minecraft server
backup_directory = '/path/to/backup/folder'  # Path to the backup directory on local PC
log_file_path = '/path/to/backup.log'  # Path to the log file
max_backups = 3  # Maximum number of backups to keep

def log_message(message):
    print(message)  # Print to console for immediate feedback
    try:
        with open(log_file_path, 'a') as log_file:
            log_file.write(f"{datetime.now().strftime('%I.%M.%p-%m.%d.%Y')} - {message}\n")
    except Exception as e:
        print(f"Logging Error: {e}")

def run_command(command):
    try:
        log_message(f"Running command: {' '.join(command)}")
        output = subprocess.check_output(command, stderr=subprocess.STDOUT).decode()
        log_message(f"Command output: {output}")
        return output
    except subprocess.CalledProcessError as e:
        log_message(f"Command error: {e.output.decode()}")
        raise

def manage_backups():
    try:
        backups = [os.path.join(backup_directory, d) for d in os.listdir(backup_directory) if os.path.isdir(os.path.join(backup_directory, d))]
        backups.sort(key=lambda x: os.path.getmtime(x))

        while len(backups) > max_backups:
            oldest_backup = backups.pop(0)
            run_command(['rm', '-rf', oldest_backup])
            log_message(f'Removed old backup: {oldest_backup}')
    except Exception as e:
        log_message(f'Error managing backups: {e}')

def backup_minecraft_server():
    log_message("Starting Minecraft server backup script.")

    # Check and create backup directory if it doesn't exist
    if not os.path.exists(backup_directory):
        try:
            os.makedirs(backup_directory)
            log_message(f'Created backup directory at {backup_directory}')
        except OSError as e:
            log_message(f"Error creating backup directory: {e}")
            return

    # Stop the Minecraft server Docker container
    try:
        run_command(['docker', 'stop', docker_container_id])
        log_message('Minecraft server stopped for backup.')
    except Exception as e:
        log_message(f'Error stopping Docker container: {e}')
        return

    # Creating a timestamp for the backup
    timestamp = datetime.now().strftime('%I.%M.%p-%m.%d.%Y')
    backup_folder_name = f'{timestamp}'
    backup_path = os.path.join(backup_directory, backup_folder_name)

    # Finding the volume mount point for the Minecraft server in the Docker container
    try:
        volume_info = run_command(['docker', 'inspect', '-f', '{{ range .Mounts }}{{ println .Source }}{{ end }}', docker_container_id])
        # Splitting the output into lines and selecting the correct one
        volume_lines = volume_info.strip().split('\n')
        minecraft_server_directory = None
        for line in volume_lines:
            if '/minecraft-forge' in line:  # Adjust this condition to correctly identify the desired path
                minecraft_server_directory = line.strip()
                break

        if not minecraft_server_directory:
            raise Exception('Minecraft server directory not found or does not exist')

        if os.path.exists(minecraft_server_directory):
            # Using rsync for efficient copying
            run_command(['rsync', '-avz', '--info=progress2', minecraft_server_directory, backup_path])
            log_message(f'Backup successful. Backup stored in {backup_path}')

            # Manage old backups
            manage_backups()
        else:
            log_message(f'Error: Minecraft server directory does not exist or not found in Docker container. Path: {minecraft_server_directory}')
            raise Exception('Minecraft server directory not found or does not exist')
    except Exception as e:
        log_message(f'Error during backup: {e}')
        run_command(['docker', 'start', docker_container_id])  # Attempt to restart even in case of failure
        log_message('Minecraft server attempted to restart after failed backup.')
        return

if __name__ == '__main__':
    backup_minecraft_server()
