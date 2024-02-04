#!/usr/bin/env python3

# Requires - pynvml
# sudo apt install python3-pynvml

import psutil
import time
import sys
from termcolor import colored

# Attempt to import pynvml for NVIDIA GPU monitoring
try:
    import pynvml
    pynvml.nvmlInit()
    gpu_monitoring_enabled = True
except Exception:
    gpu_monitoring_enabled = False
    print(colored("GPU monitoring is disabled. pynvml cannot be initialized.", "yellow"))

def get_gpu_usage():
    """Returns the usage stats for NVIDIA GPUs."""
    gpu_stats = []
    device_count = pynvml.nvmlDeviceGetCount()
    for i in range(device_count):
        handle = pynvml.nvmlDeviceGetHandleByIndex(i)
        memory_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
        utilization = pynvml.nvmlDeviceGetUtilizationRates(handle)
        gpu_stats.append({
            'gpu_id': i,
            'gpu_util': utilization.gpu,
            'memory_used': memory_info.used / 1024**2,  # Convert to MB
            'memory_total': memory_info.total / 1024**2,  # Convert to MB
        })
    return gpu_stats

def monitor_resources(logfile='system_resources.log', interval=60):
    with open(logfile, 'a') as f:
        while True:
            cpu = psutil.cpu_percent()
            memory = psutil.virtual_memory().percent
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
            log_entry = f"{timestamp} | CPU: {colored(f'{cpu}%', 'green')} | Memory: {colored(f'{memory}%', 'blue')}"
            if gpu_monitoring_enabled:
                gpu_stats = get_gpu_usage()
            for gpu in gpu_stats:
                gpu_util = f"{gpu['gpu_util']}%"
                memory_usage = f"{gpu['memory_used']}MB/{gpu['memory_total']}MB"
                log_entry += f" | GPU{gpu['gpu_id']}: {colored(gpu_util, 'red')}, Memory: {colored(memory_usage, 'magenta')}"
            log_entry += "\n"
            print(log_entry, end='')
            f.write(log_entry.replace(colored('', 'red'), '').replace(colored('', 'green'), '').replace(colored('', 'blue'), '').replace(colored('', 'magenta'), ''))
            time.sleep(interval)

if __name__ == "__main__":
    logfile = input("Enter logfile path (default: system_resources.log): ") or 'system_resources.log'
    try:
        interval = int(input("Enter monitoring interval in seconds (default: 60): ") or 60)
    except ValueError:
        print(colored("Invalid interval. Using default of 60 seconds.", "red"))
        interval = 60
    monitor_resources(logfile, interval)
