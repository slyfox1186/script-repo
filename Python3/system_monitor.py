#!/usr/bin/env python3

"""Periodically log CPU, memory, and (optional) NVIDIA GPU usage."""

import argparse
import re
import sys
import time
from pathlib import Path

import psutil
from termcolor import colored

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

try:
    import pynvml

    pynvml.nvmlInit()
    GPU_ENABLED = True
except Exception:
    GPU_ENABLED = False
    print(
        colored(
            "GPU monitoring is disabled. pynvml could not be initialized.", "yellow"
        )
    )


def strip_ansi(s: str) -> str:
    return ANSI_RE.sub("", s)


def get_gpu_usage() -> list[dict]:
    stats = []
    for i in range(pynvml.nvmlDeviceGetCount()):
        handle = pynvml.nvmlDeviceGetHandleByIndex(i)
        memory = pynvml.nvmlDeviceGetMemoryInfo(handle)
        util = pynvml.nvmlDeviceGetUtilizationRates(handle)
        stats.append(
            {
                "gpu_id": i,
                "gpu_util": util.gpu,
                "memory_used_mb": memory.used / (1024**2),
                "memory_total_mb": memory.total / (1024**2),
            }
        )
    return stats


def build_log_entry() -> str:
    cpu = psutil.cpu_percent()
    memory = psutil.virtual_memory().percent
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    parts = [
        timestamp,
        f"CPU: {colored(f'{cpu}%', 'green')}",
        f"Memory: {colored(f'{memory}%', 'blue')}",
    ]
    if GPU_ENABLED:
        for gpu in get_gpu_usage():
            util = f"{gpu['gpu_util']}%"
            mem = f"{gpu['memory_used_mb']:.0f}MB/{gpu['memory_total_mb']:.0f}MB"
            parts.append(
                f"GPU{gpu['gpu_id']}: {colored(util, 'red')}, "
                f"Memory: {colored(mem, 'magenta')}"
            )
    return " | ".join(parts)


def monitor_resources(logfile: Path, interval: int) -> None:
    with logfile.open("a", encoding="utf-8") as fh:
        while True:
            entry = build_log_entry()
            print(entry)
            fh.write(strip_ansi(entry) + "\n")
            fh.flush()
            time.sleep(interval)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-l",
        "--logfile",
        type=Path,
        default=Path("system_resources.log"),
        help="Path to the log file (default: system_resources.log)",
    )
    parser.add_argument(
        "-i",
        "--interval",
        type=int,
        default=60,
        help="Sample interval in seconds (default: 60)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.interval <= 0:
        print("Interval must be a positive integer.", file=sys.stderr)
        return 1
    try:
        monitor_resources(args.logfile, args.interval)
    except KeyboardInterrupt:
        print("\nStopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
