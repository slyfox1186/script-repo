#!/usr/bin/env python3

"""Stop a Minecraft Docker container, rsync its files to a backup folder,
restart it, prune old backups, and notify on failures via SMTP and Twilio.

Configuration is read from environment variables; see CONFIG section below.
"""

import os
import shutil
import smtplib
import subprocess
import sys
from datetime import datetime
from email.mime.text import MIMEText
from pathlib import Path

# ----- CONFIG (override via environment) -----
MAX_BACKUPS = int(os.environ.get("MC_MAX_BACKUPS", "4"))
CONTAINER_ID = os.environ.get("MC_CONTAINER_ID", "")
BACKUP_FOLDER = Path(os.environ.get("MC_BACKUP_FOLDER", "/path/to/backup/folder"))
SERVER_FILES_PATH = Path(os.environ.get("MC_SERVER_FILES", "/path/to/minecraft/server/files"))
LOG_FILE_PATH = Path(os.environ.get("MC_LOG_FILE", str(SERVER_FILES_PATH / "backup_log.txt")))

# Twilio
TWILIO_ACCOUNT_SID = os.environ.get("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.environ.get("TWILIO_AUTH_TOKEN", "")
TWILIO_PHONE_NUMBER = os.environ.get("TWILIO_PHONE_NUMBER", "")
NOTIFY_PHONE_NUMBER = os.environ.get("NOTIFY_PHONE_NUMBER", "")

# Email (use an app-specific password)
EMAIL_SENDER = os.environ.get("MC_EMAIL_SENDER", "")
EMAIL_PASSWORD = os.environ.get("MC_EMAIL_PASSWORD", "")
EMAIL_RECEIVER = os.environ.get("MC_EMAIL_RECEIVER", "")
SMTP_SERVER = os.environ.get("MC_SMTP_SERVER", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("MC_SMTP_PORT", "587"))
# ---------------------------------------------


def timestamp() -> str:
    return datetime.now().strftime("%Y-%m-%d_%H-%M-%S")


def log_message(message: str) -> None:
    line = f"{timestamp()} - {message}"
    print(line)
    try:
        LOG_FILE_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_FILE_PATH.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError as exc:
        print(f"(could not write log file {LOG_FILE_PATH}: {exc})", file=sys.stderr)


def send_email(subject: str, body: str) -> None:
    if not (EMAIL_SENDER and EMAIL_PASSWORD and EMAIL_RECEIVER):
        log_message("Email not configured; skipping email notification.")
        return
    message = MIMEText(body)
    message["Subject"] = subject
    message["From"] = EMAIL_SENDER
    message["To"] = EMAIL_RECEIVER
    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as smtp:
            smtp.starttls()
            smtp.login(EMAIL_SENDER, EMAIL_PASSWORD)
            smtp.send_message(message)
        log_message(f"Sent email notification: {subject!r}")
    except (smtplib.SMTPException, OSError) as exc:
        log_message(f"Failed to send email: {exc}")


def send_sms(body: str) -> None:
    if not (TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN and TWILIO_PHONE_NUMBER and NOTIFY_PHONE_NUMBER):
        log_message("Twilio not configured; skipping SMS notification.")
        return
    try:
        from twilio.rest import Client
    except ImportError:
        log_message(
            "twilio package not installed (pip install twilio); skipping SMS."
        )
        return
    try:
        Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN).messages.create(
            body=body[:1500],
            from_=TWILIO_PHONE_NUMBER,
            to=NOTIFY_PHONE_NUMBER,
        )
        log_message("Sent SMS notification.")
    except Exception as exc:
        log_message(f"Failed to send SMS: {exc}")


def notify(subject: str, body: str) -> None:
    send_email(subject, body)
    send_sms(body)


def is_nas_available(path: Path) -> bool:
    if path.is_dir() and os.access(path, os.R_OK | os.W_OK):
        return True
    msg = f"NAS path is not available or not accessible: {path}"
    log_message(msg)
    notify("Backup Script Error", msg)
    return False


def backup_files_with_rsync(source: Path, destination: Path) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            ["rsync", "-avz", "--info=progress2", f"{source}/", str(destination)],
            check=True,
        )
        log_message(f"Backup completed successfully to {destination}")
        return True
    except subprocess.CalledProcessError as exc:
        msg = f"Error during rsync: {exc}"
        log_message(msg)
        notify("Backup Script Error", msg)
        return False


def limit_backups(folder: Path) -> None:
    if not folder.is_dir():
        return
    candidates = sorted(
        (p for p in folder.iterdir() if p.is_dir()),
        key=lambda p: p.stat().st_ctime,
    )
    while len(candidates) > MAX_BACKUPS:
        oldest = candidates.pop(0)
        try:
            shutil.rmtree(oldest)
            log_message(f"Deleted old backup: {oldest}")
        except OSError as exc:
            log_message(f"Failed to delete {oldest}: {exc}")


def get_timestamped_backup_folder(base: Path) -> Path:
    return base / f"mc-server-backup-{timestamp()}"


def docker_action(action: str, container: str) -> bool:
    try:
        subprocess.run(["docker", action, container], check=True)
        log_message(f"docker {action} {container} succeeded.")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        log_message(f"docker {action} {container} failed: {exc}")
        return False


def main() -> int:
    if not CONTAINER_ID:
        print("MC_CONTAINER_ID is not set.", file=sys.stderr)
        return 1

    log_message("Backup script started.")
    docker_action("stop", CONTAINER_ID)
    try:
        if is_nas_available(BACKUP_FOLDER):
            target = get_timestamped_backup_folder(BACKUP_FOLDER)
            backup_files_with_rsync(SERVER_FILES_PATH, target)
            limit_backups(BACKUP_FOLDER)
    finally:
        docker_action("start", CONTAINER_ID)
    log_message("Backup script finished.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
