#!/usr/bin/env python3

import argparse
import ipaddress
import logging
import os
import socket
import threading
from colorama import Fore, Style, init
from queue import Queue
from tabulate import tabulate

# Initialize colorama
init(autoreset=True)

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Thread lock for printing
print_lock = threading.Lock()
queue = Queue()

results = {}

def port_scan(ip, port, protocol, verbose=False):
    tcp_status, udp_status = None, None

    if protocol in ['tcp', 'both']:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)  # Reduce timeout to 0.5 seconds for faster response
            try:
                s.connect((ip, port))
                tcp_status = 'open'
                if verbose:
                    logging.info(f"{ip}:{port} (TCP) is open.")
            except (socket.timeout, socket.error) as e:
                tcp_status = 'closed or filtered'
                if verbose:
                    logging.info(f"{ip}:{port} (TCP) is closed or filtered. Reason: {e}")

    if protocol in ['udp', 'both']:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(0.5)  # Reduce timeout to 0.5 seconds for faster response
            try:
                s.sendto(b'', (ip, port))
                s.recvfrom(1024)
                udp_status = 'open'
                if verbose:
                    logging.info(f"{ip}:{port} (UDP) is open.")
            except (socket.timeout, socket.error) as e:
                udp_status = 'closed or filtered'
                if verbose:
                    logging.info(f"{ip}:{port} (UDP) is closed or filtered. Reason: {e}")

    with print_lock:
        if protocol == 'both':
            if tcp_status == udp_status:
                results[(ip, port, 'both')] = tcp_status
            else:
                results[(ip, port, 'TCP')] = tcp_status
                results[(ip, port, 'UDP')] = udp_status
        elif protocol == 'tcp':
            results[(ip, port, 'TCP')] = tcp_status
        elif protocol == 'udp':
            results[(ip, port, 'UDP')] = udp_status

def threader(protocol, verbose):
    while True:
        ip, port = queue.get()
        try:
            port_scan(ip, port, protocol, verbose)
        except Exception as e:
            logging.error(f"Error scanning {ip}:{port} - {e}")
        queue.task_done()

def main(targets, ports, num_threads, protocol, verbose):
    for _ in range(num_threads):
        t = threading.Thread(target=threader, args=(protocol, verbose))
        t.daemon = True
        t.start()

    for target in targets:
        if isinstance(ports, range):
            print(f"\n{Fore.GREEN}Scanning for open:{Style.RESET_ALL} {Fore.YELLOW}{target}{Style.RESET_ALL} {Fore.RED}port{Style.RESET_ALL} {Fore.YELLOW}{ports.start} - {ports.stop - 1}{Style.RESET_ALL}")
            for port in ports:
                queue.put((target, port))
        else:
            print(f"\n{Fore.GREEN}Scanning for open:{Style.RESET_ALL} {Fore.YELLOW}{target}{Style.RESET_ALL} {Fore.RED}port{Style.RESET_ALL} {Fore.YELLOW}{ports}{Style.RESET_ALL}")
            queue.put((target, ports))

    queue.join()
    print("\nScanning completed.\n")
    print_results()

def print_results():
    if results:
        headers = [
            f"{Fore.CYAN}Host{Style.RESET_ALL}",
            f"{Fore.CYAN}Port{Style.RESET_ALL}",
            f"{Fore.CYAN}Protocol{Style.RESET_ALL}",
            f"{Fore.CYAN}Status{Style.RESET_ALL}"
        ]
        sorted_results = sorted(results.items(), key=lambda x: (x[0][0], x[0][1]))
        table = [
            [
                f"{Fore.YELLOW}{host}{Style.RESET_ALL}",
                f"{Fore.YELLOW}{port}{Style.RESET_ALL}",
                f"{Fore.YELLOW}{proto}{Style.RESET_ALL}",
                f"{Fore.YELLOW}{status}{Style.RESET_ALL}" if status == 'open' else status
            ]
            for (host, port, proto), status in sorted_results
        ]
        print(tabulate(table, headers, tablefmt="pretty"))
    else:
        print(f"{Fore.YELLOW}No open ports found.{Style.RESET_ALL}")

def get_args():
    parser = argparse.ArgumentParser(description="The best Python Port Open Checker in the World!")
    parser.add_argument(
        '-t', '--targets',
        type=str,
        nargs='+',
        required=True,
        help='Target host(s) to scan, separated by space.'
    )
    parser.add_argument(
        '-p', '--ports',
        type=str,
        help='Port or port range to scan. Use format start-end for a range or a single port number.'
    )
    parser.add_argument(
        '-P', '--protocol',
        type=str,
        choices=['tcp', 'udp', 'both'],
        default='both',
        help='Specify protocol: tcp, udp, or both (default: both)'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose mode to display closed or filtered ports.'
    )
    return parser.parse_args()

if __name__ == '__main__':
    args = get_args()
    valid_targets = []
    for target in args.targets:
        try:
            ip = ipaddress.ip_address(target)
            valid_targets.append(str(ip))
        except ValueError:
            logging.error(f"Invalid IP address: {target}")
            print(f"{Fore.RED}Invalid IP address: {target}{Style.RESET_ALL}")

    if not valid_targets:
        logging.error("No valid IP addresses provided. Exiting.")
        print(f"{Fore.RED}No valid IP addresses provided. Exiting.{Style.RESET_ALL}")
        exit(1)

    if args.ports:
        if '-' in args.ports:
            try:
                start_port, end_port = map(int, args.ports.split('-'))
                ports = range(start_port, end_port + 1)
            except ValueError:
                logging.error("Invalid port range format. Use start-end.")
                print(f"{Fore.RED}Invalid port range format. Use start-end.{Style.RESET_ALL}")
                exit(1)
        else:
            try:
                ports = int(args.ports)
            except ValueError:
                logging.error("Invalid port format. Provide a single port number or a range.")
                print(f"{Fore.RED}Invalid port format. Provide a single port number or a range.{Style.RESET_ALL}")
                exit(1)
    else:
        # Default port range
        ports = range(1, 1024)  # Default to well-known ports (1-1023)

    num_threads = min(os.cpu_count() * 5, 100)  # Increase thread count for faster scanning
    main(valid_targets, ports, num_threads, args.protocol, args.verbose)
