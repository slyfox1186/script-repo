#!/usr/bin/env python3

# Author: SlyFox1186
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Python3/Networking/port_checker.py

import argparse
import ipaddress
import logging
import os
import socket
import subprocess
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
unreachable_ips = []

def is_reachable(ip, timeout=1):
    """
    Check if an IP address is reachable by trying to connect to TCP port 80.
    If that fails, try to ping the IP address.
    """
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect((ip, 80))
            s.close()
            return True
    except (socket.timeout, socket.error):
        pass
    
    # Fallback to ping if TCP port 80 check fails
    try:
        output = subprocess.run(
            ["ping", "-c", "1", "-W", str(timeout), ip],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        return output.returncode == 0
    except Exception as e:
        logging.error(f"Error pinging {ip} - {e}")
        return False

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

def ip_range(start_ip, end_ip):
    start = ipaddress.IPv4Address(start_ip)
    end = ipaddress.IPv4Address(end_ip)
    return [str(ipaddress.IPv4Address(ip)) for ip in range(int(start), int(end) + 1)]

def parse_cidr(cidr):
    network = ipaddress.ip_network(cidr, strict=False)
    return [str(ip) for ip in network.hosts()]

def parse_targets(targets):
    """
    Parse target IP addresses. Handles single IPs, ranges, and CIDR notation.
    """
    valid_targets = []
    for target in targets.split(','):
        target = target.strip()
        if '/' in target:
            try:
                cidr_ips = parse_cidr(target)
                valid_targets.extend(cidr_ips)
                logging.info(f"Parsed CIDR {target} into IPs: {cidr_ips}")
            except ValueError:
                logging.error(f"Invalid CIDR format: {target}")
                print(f"{Fore.RED}Invalid CIDR format: {target}{Style.RESET_ALL}")
        elif '-' in target:
            try:
                start_ip, end_ip = target.split('-')
                range_ips = ip_range(start_ip, end_ip)
                valid_targets.extend(range_ips)
                logging.info(f"Parsed range {target} into IPs: {range_ips}")
            except ValueError:
                logging.error(f"Invalid IP range format: {target}")
                print(f"{Fore.RED}Invalid IP range format: {target}{Style.RESET_ALL}")
        else:
            try:
                ip = ipaddress.ip_address(target)
                valid_targets.append(str(ip))
                logging.info(f"Added single IP address: {ip}")
            except ValueError:
                logging.error(f"Invalid IP address: {target}")
                print(f"{Fore.RED}Invalid IP address: {target}{Style.RESET_ALL}")
    return valid_targets

def threader(protocol, verbose):
    while True:
        ip, port = queue.get()
        try:
            port_scan(ip, port, protocol, verbose)
        except Exception as e:
            logging.error(f"Error scanning {ip}:{port} - {e}")
        queue.task_done()

def main(targets, ports, num_threads, protocol, verbose, output_file):
    for _ in range(num_threads):
        t = threading.Thread(target=threader, args=(protocol, verbose))
        t.daemon = True
        t.start()

    for target in targets:
        if is_reachable(target):
            if isinstance(ports, range):
                print(f"\n{Fore.GREEN}Scanning for open:{Style.RESET_ALL} {Fore.YELLOW}{target}{Style.RESET_ALL} {Fore.RED}port{Style.RESET_ALL} {Fore.YELLOW}{ports.start} - {ports.stop - 1}{Style.RESET_ALL}")
                for port in ports:
                    queue.put((target, port))
            else:
                print(f"\n{Fore.GREEN}Scanning for open:{Style.RESET_ALL} {Fore.YELLOW}{target}{Style.RESET_ALL} {Fore.RED}port{Style.RESET_ALL} {Fore.YELLOW}{ports}{Style.RESET_ALL}")
                queue.put((target, ports))
        else:
            unreachable_ips.append(target)
            logging.warning(f"{Fore.RED}Host {target} is not reachable. Skipping...{Style.RESET_ALL}")

    queue.join()
    print("\nScanning completed.")
    print_results(output_file)

def print_results(output_file):
    if results:
        headers = [
            f"{Fore.CYAN}Host{Style.RESET_ALL}",
            f"{Fore.CYAN}Port{Style.RESET_ALL}",
            f"{Fore.CYAN}Protocol{Style.RESET_ALL}",
            f"{Fore.CYAN}Status{Style.RESET_ALL}"
        ]
        
        sorted_results = sorted(results.items(), key=lambda x: (x[0][0], x[0][1]))
        ip_groups = {}
        
        for (host, port, proto), status in sorted_results:
            if host not in ip_groups:
                ip_groups[host] = []
            ip_groups[host].append([
                f"{Fore.YELLOW}{port}{Style.RESET_ALL}",
                f"{Fore.YELLOW}{proto}{Style.RESET_ALL}",
                f"{Fore.GREEN}{status}{Style.RESET_ALL}" if status == 'open' else f"{Fore.RED}{status}{Style.RESET_ALL}"
            ])
        
        for ip, data in ip_groups.items():
            print(f"\n{Fore.GREEN}Results for IP: {Fore.YELLOW}{ip}{Style.RESET_ALL}")
            print(tabulate(data, headers[1:], tablefmt="pretty"))

    else:
        print(f"{Fore.YELLOW}No open ports found.{Style.RESET_ALL}")
    
    if unreachable_ips:
        unreachable_ips.sort(key=lambda ip: ipaddress.ip_address(ip))
        headers = [f"{Fore.CYAN}Number{Style.RESET_ALL}", f"{Fore.CYAN}Address{Style.RESET_ALL}"]
        data = [[f"{Fore.YELLOW}{idx + 1}{Style.RESET_ALL}", f"{Fore.YELLOW}{ip}{Style.RESET_ALL}"] for idx, ip in enumerate(unreachable_ips)]
        print(f"\n{Fore.RED}Unreachable IP Addresses:{Style.RESET_ALL}")
        print(tabulate(data, headers, tablefmt="pretty"))

    if output_file:
        with open(output_file, 'w') as f:
            if results:
                headers = ["Host", "Port", "Protocol", "Status"]
                sorted_results = sorted(results.items(), key=lambda x: (x[0][0], x[0][1]))
                ip_groups = {}
                
                for (host, port, proto), status in sorted_results:
                    if host not in ip_groups:
                        ip_groups[host] = []
                    ip_groups[host].append([port, proto, status])
                
                for ip, data in ip_groups.items():
                    f.write(f"Results for IP: {ip}\n")
                    f.write(tabulate(data, headers[1:], tablefmt="plain"))
                    f.write("\n\n")
            
            if unreachable_ips:
                headers = ["Number", "Address"]
                data = [[idx + 1, ip] for idx, ip in enumerate(unreachable_ips)]
                f.write("Unreachable IP Addresses:\n")
                f.write(tabulate(data, headers, tablefmt="plain"))
                f.write("\n\n")

def get_args():
    parser = argparse.ArgumentParser(description="The best Python Port Open Checker in the World!")
    parser.add_argument(
        '-t', '--targets',
        type=str,
        required=True,
        help='Target host(s) or IP range to scan. Use comma-separated list for multiple targets. Supports single IP, IP range (start-end), and CIDR notation.'
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
    parser.add_argument(
        '-o', '--output',
        type=str,
        help='File to store the scan results.'
    )
    return parser.parse_args()

if __name__ == '__main__':
    args = get_args()
    valid_targets = parse_targets(args.targets)

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
    main(valid_targets, ports, num_threads, args.protocol, args.verbose, args.output)
