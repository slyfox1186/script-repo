#!/usr/bin/env python3

import argparse
import multiprocessing
import os
import shutil
import subprocess
import sys

def get_remote_cpu_count(remote_user, remote_ip):
    try:
        result = subprocess.run(
            ["ssh", f"{remote_user}@{remote_ip}", "nproc"],
            capture_output=True,
            text=True,
            check=True
        )
        return int(result.stdout.strip())
    except subprocess.CalledProcessError as e:
        print(f"Failed to get CPU count from remote machine: {e}", file=sys.stderr)
        return None

def distribute_files(image_dir, remote_dir, local_cpu_count, remote_cpu_count, remote_user, remote_ip):
    local_files = []
    remote_files = []

    for root, _, files in os.walk(image_dir):
        for file in files:
            if file.lower().endswith(('.jpg', '.jpeg', '.png', '.bmp', '.gif')):
                file_path = os.path.join(root, file)
                if len(local_files) <= len(remote_files) * local_cpu_count / remote_cpu_count:
                    local_files.append(file_path)
                else:
                    remote_files.append(file_path)

    local_dist_dir = os.path.join(image_dir, "local_dist")
    remote_dist_dir = os.path.join(image_dir, "remote_dist")

    if not os.path.exists(local_dist_dir):
        os.makedirs(local_dist_dir)
    if not os.path.exists(remote_dist_dir):
        os.makedirs(remote_dist_dir)

    for file in local_files:
        shutil.move(file, local_dist_dir)

    for file in remote_files:
        subprocess.run(["scp", file, f"{remote_user}@{remote_ip}:{remote_dir}"])

def main(image_dir, remote_dir, remote_user, remote_ip, script_path):
    # Get local CPU count
    local_cpu_count = multiprocessing.cpu_count()
    print(f"Local CPU count: {local_cpu_count}")

    # Get remote CPU count
    remote_cpu_count = get_remote_cpu_count(remote_user, remote_ip)
    if remote_cpu_count is None:
        print("Failed to get remote CPU count, exiting.", file=sys.stderr)
        sys.exit(1)
    print(f"Remote CPU count: {remote_cpu_count}")

    # Distribute files based on CPU counts
    distribute_files(image_dir, remote_dir, local_cpu_count, remote_cpu_count, remote_user, remote_ip)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Distribute image files for processing.")
    parser.add_argument("image_dir", help="Local image directory")
    parser.add_argument("remote_dir", help="Remote image directory")
    parser.add_argument("remote_user", help="Remote user")
    parser.add_argument("remote_ip", help="Remote IP address")
    parser.add_argument("script_path", help="Path to the directory containing the script")
    args = parser.parse_args()

    main(args.image_dir, args.remote_dir, args.remote_user, args.remote_ip, args.script_path)
