#!/usr/bin/env python3

import os
import shutil
from datetime import datetime
import subprocess

# Configuration
docker_container_id = 'your_docker_container_id'  # Docker container ID for the Minecraft server
backup_directory = '/path/to/backup/folder'  # Path to the backup directory on local PC
log_file_path = '/path/to/backup.log'  # Path to the log file

def log_message(message):
    with open(log_file_path, 'a') as log_file:
        log_file.write(f"{datetime.now().strftime('%I.%M.%p-%m.%d.%y')} - {message}")

def backup_minecraft_server():
    # Creating a timestamp for the backup
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_folder_name = f'minecraft_backup_{timestamp}'
    backup_path = os.path.join(backup_directory, backup_folder_name)

    # Finding the volume mount point for the Minecraft server in the Docker container
    try:
        volume_info = subprocess.check_output(['docker', 'inspect', '-f', 
                                               '{{ range .Mounts }}{{ .Source }}{{ end }}', 
                                               docker_container_id])
        minecraft_server_directory = volume_info.decode('utf-8').strip()

        if minecraft_server_directory:
            # Copying the Minecraft server directory to the backup directory
            shutil.copytree(minecraft_server_directory, backup_path)
            log_message(f'Backup successful. Backup stored in {backup_path}')
        else:
            log_message('Error: Could not find Minecraft server directory in Docker container.')
    except subprocess.CalledProcessError as e:
        log_message(f'Error during backup: {e}')

if __name__ == '__main__':
    backup_minecraft_server()
