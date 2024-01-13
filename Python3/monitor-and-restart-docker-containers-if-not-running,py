#!/usr/bin/env python3

import subprocess
import logging
import os

def setup_logger():
    """Setup a logger for the script."""
    logger = logging.getLogger('DockerMonitor')
    logger.setLevel(logging.INFO)
    handler = logging.FileHandler(os.path.join(os.path.dirname(__file__), 'monitor.log'))
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    return logger

def get_non_running_containers(logger):
    """
    Get a list of all Docker containers that exist but are not running.
    
    :param logger: Logger object for logging messages.
    :return: A list of container names that are not running.
    """
    try:
        # Get all container names
        all_containers = subprocess.check_output(["docker", "ps", "-a", "--format", "{{.Names}}"]).decode().splitlines()
        
        # Filter out the running containers
        non_running_containers = []
        for container in all_containers:
            status = subprocess.check_output(["docker", "inspect", "-f", "{{.State.Running}}", container]).strip()
            if status == b'false':
                non_running_containers.append(container)
        
        return non_running_containers
    except subprocess.CalledProcessError as e:
        logger.error(f"Error: {e}")
        return []

def restart_containers(containers, logger):
    """
    Restart a list of Docker containers.

    :param containers: A list of container names to restart.
    :param logger: Logger object for logging messages.
    """
    for container in containers:
        try:
            logger.info(f"Attempting to restart container '{container}'.")
            subprocess.check_output(["docker", "restart", container])
            logger.info(f"Container '{container}' has been restarted.")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to restart container '{container}'. Error: {e}")

def monitor_and_restart_containers(logger):
    """
    Monitor all Docker containers and restart them if they are not running.
    :param logger: Logger object for logging messages.
    """
    non_running_containers = get_non_running_containers(logger)
    if non_running_containers:
        restart_containers(non_running_containers, logger)
    else:
        logger.info("All containers are running.")

# Setup logger
logger = setup_logger()

# Run the monitor and restart function once
monitor_and_restart_containers(logger)
