#!/usr/bin/env python

import argparse
import concurrent.futures
import logging
import os
import socket
import struct
import requests
from urllib.parse import urlparse

def setup_logging(verbose):
    log_format = '%(asctime)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.DEBUG if verbose else logging.INFO, format=log_format)

def parse_arguments():
    parser = argparse.ArgumentParser(description='Check the status of torrent trackers.')
    parser.add_argument('file', type=str, help='Relative or full path to the text file containing the list of torrent trackers.')
    parser.add_argument('-o', '--output', type=str, help='File to save the results.')
    parser.add_argument('-r', '--retries', type=int, default=3, help='Number of retries for each tracker (default: 3).')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose mode.')
    parser.add_argument('--pass-only', '-p', action='store_true', help='Output only the passed trackers to the output file.')
    parser.add_argument('--timeout', type=int, default=3, help='Maximum time in seconds to wait for a tracker response (default: 3 seconds).')
    return parser.parse_args()

def is_valid_url(url):
    try:
        result = urlparse(url)
        return all([result.scheme, result.netloc])
    except ValueError:
        return False

def check_http_tracker(tracker_url, retries, timeout):
    attempt = 0
    while attempt < retries:
        try:
            response = requests.get(tracker_url, timeout=(timeout, timeout), allow_redirects=False)
            if response.status_code == 200:
                return tracker_url, 'Passed'
            elif response.status_code == 302:
                redirect_url = response.headers.get('Location')
                if redirect_url and redirect_url.startswith('udp:'):
                    return check_udp_tracker(redirect_url, retries - attempt, timeout)
                else:
                    return tracker_url, 'Failed'
            else:
                return tracker_url, 'Failed'
        except requests.RequestException as e:
            logging.debug(f"Attempt {attempt + 1} for {tracker_url} failed: {e}")
            attempt += 1
    return tracker_url, 'Failed'

def check_udp_tracker(tracker_url, retries, timeout):
    attempt = 0
    parsed_url = urlparse(tracker_url)
    host = parsed_url.hostname
    port = parsed_url.port if parsed_url.port else 6969

    while attempt < retries:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(timeout)
            transaction_id = os.urandom(4)

            # Connect request
            req = struct.pack("!QLL", 0x41727101980, 0, int.from_bytes(transaction_id, 'big'))
            sock.sendto(req, (host, port))

            # Receive response
            try:
                res = sock.recv(16)
                if len(res) < 16:
                    return tracker_url, 'Failed'
                action, transaction_id_res, conn_id = struct.unpack("!LLQ", res)
                if action == 0 and transaction_id == transaction_id_res.to_bytes(4, 'big'):
                    return tracker_url, 'Passed'
            except socket.timeout:
                return tracker_url, 'Failed'
        except Exception as e:
            logging.debug(f"Attempt {attempt + 1} for {tracker_url} failed: {e}")
        finally:
            sock.close()
        attempt += 1
    return tracker_url, 'Failed'

def check_tracker(tracker_url, retries, timeout):
    parsed_url = urlparse(tracker_url)
    if parsed_url.scheme in ['http', 'https']:
        return check_http_tracker(tracker_url, retries, timeout)
    elif parsed_url.scheme == 'udp':
        return check_udp_tracker(tracker_url, retries, timeout)
    else:
        return tracker_url, 'Invalid Scheme'

def print_results(results):
    header = f"{'Tracker URL':<60} {'Status':<15}"
    print(header)
    print("=" * len(header))
    for tracker_url, status in results:
        print(f"{tracker_url:<60} {status:<15}")

def main():
    args = parse_arguments()
    setup_logging(args.verbose)

    if not os.path.isfile(args.file):
        logging.error(f"File not found: {args.file}")
        return

    with open(args.file, 'r') as file:
        trackers = [line.strip() for line in file if line.strip()]

    if not trackers:
        logging.error("No trackers found in the file.")
        return

    valid_trackers = [tracker for tracker in trackers if is_valid_url(tracker)]
    if not valid_trackers:
        logging.error("No valid trackers found in the file.")
        return

    max_workers = os.cpu_count()

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_tracker = {executor.submit(check_tracker, tracker, args.retries, args.timeout): tracker for tracker in valid_trackers}

        for future in concurrent.futures.as_completed(future_to_tracker):
            tracker = future_to_tracker[future]
            try:
                tracker_url, status = future.result()
                results.append((tracker_url, status))
                logging.info(f"{tracker_url}: {status}")
            except concurrent.futures.TimeoutError:
                logging.error(f"{tracker}: Timed out.")
                results.append((tracker, 'Failed'))
            except Exception as exc:
                logging.error(f"{tracker}: Generated an exception: {exc}")
                results.append((tracker, 'Failed'))

    print_results(results)

    if args.output:
        with open(args.output, 'w') as output_file:
            if args.pass_only:
                for tracker_url, status in results:
                    if status == 'Passed':
                        output_file.write(f"{tracker_url}\n")
            else:
                output_file.write(f"{'Tracker URL':<60} {'Status':<15}\n")
                output_file.write("=" * 75 + "\n")
                for tracker_url, status in results:
                    output_file.write(f"{tracker_url:<60} {status:<15}\n")
        logging.info(f"Results saved to {args.output}")

if __name__ == '__main__':
    main()
