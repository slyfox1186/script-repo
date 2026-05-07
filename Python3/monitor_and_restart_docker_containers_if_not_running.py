#!/usr/bin/env python3

"""Restart any Docker container that exists but is no longer running."""

import logging
import subprocess
from pathlib import Path

LOG_FILE = Path(__file__).resolve().parent / "monitor.log"


def setup_logger() -> logging.Logger:
    logger = logging.getLogger("DockerMonitor")
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        handler = logging.FileHandler(LOG_FILE)
        handler.setFormatter(
            logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
        )
        logger.addHandler(handler)
    return logger


def get_non_running_containers(logger: logging.Logger) -> list[str]:
    """Return container names that exist but are not in 'running' state."""
    try:
        output = subprocess.check_output(
            ["docker", "ps", "-a", "--format", "{{.Names}}\t{{.State}}"],
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        logger.error("Failed to list containers: %s", exc)
        return []

    not_running: list[str] = []
    for line in output.splitlines():
        name, _, state = line.partition("\t")
        if name and state and state != "running":
            not_running.append(name)
    return not_running


def restart_containers(containers: list[str], logger: logging.Logger) -> None:
    for container in containers:
        try:
            subprocess.check_output(
                ["docker", "restart", container], stderr=subprocess.STDOUT
            )
            logger.info("Restarted container '%s'.", container)
        except subprocess.CalledProcessError as exc:
            logger.error(
                "Failed to restart container '%s': %s",
                container,
                exc.output.decode(errors="replace") if exc.output else exc,
            )


def main() -> None:
    logger = setup_logger()
    not_running = get_non_running_containers(logger)
    if not_running:
        restart_containers(not_running, logger)
    else:
        logger.info("All containers are running.")


if __name__ == "__main__":
    main()
