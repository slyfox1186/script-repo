#!/usr/bin/env python3

import os
import sys
import argparse
import pandas as pd
import sqlite3
import tempfile
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def extract_chrome_cookies(db_path):
    """Extract cookies from the Chrome SQLite database."""
    if not os.path.exists(db_path):
        logging.error(f"The specified database path does not exist: {db_path}")
        sys.exit("Error: The specified database path does not exist.")
    try:
        conn = sqlite3.connect(db_path)
        query = "SELECT host_key, name, value, path, expires_utc, is_secure, is_httponly FROM cookies"
        df = pd.read_sql_query(query, conn)
        conn.close()
        logging.info("Cookies successfully extracted from Chrome's SQLite database.")
        return df
    except Exception as e:
        logging.error(f"Failed to extract cookies: {e}")
        sys.exit(f"Failed to extract cookies: {e}")

def extract_firefox_cookies(db_path):
    """Extract cookies from the Firefox SQLite database."""
    if not os.path.exists(db_path):
        logging.error(f"The specified database path does not exist: {db_path}")
        sys.exit("Error: The specified database path does not exist.")
    try:
        conn = sqlite3.connect(db_path)
        query = "SELECT host as host_key, name, value, path, expiry as expires_utc, isSecure as is_secure, isHttpOnly as is_httponly FROM moz_cookies"
        df = pd.read_sql_query(query, conn)
        conn.close()
        logging.info("Cookies successfully extracted from Firefox's SQLite database.")
        return df
    except Exception as e:
        logging.error(f"Failed to extract cookies: {e}")
        sys.exit(f"Failed to extract cookies: {e}")

def convert_to_netscape_format(cookies_df, output_file):
    """Convert cookies data to Netscape cookie file format and save it."""
    try:
        with open(output_file, 'a') as file:  # Change to append mode
            for index, row in cookies_df.iterrows():
                file.write(
                    f"{row['host_key']}\t"  # domain
                    "TRUE\t"  # flag
                    f"{row['path']}\t"
                    f"{'TRUE' if row['is_secure'] else 'FALSE'}\t"
                    f"{int(row['expires_utc'])}\t"  # Convert to Unix time
                    f"{row['name']}\t"
                    f"{row['value']}\n"
                )
        logging.info("Cookies have been converted to Netscape format and saved.")
    except Exception as e:
        logging.error(f"Failed to write Netscape cookie file: {e}")
        sys.exit(f"Failed to write Netscape cookie file: {e}")

def convert_to_javascript_format(cookies_df, output_file):
    """Convert cookies data to JavaScript cookie creation script and save it."""
    try:
        with open(output_file, 'w') as file:
            file.write("function setCookies() {\n")
            for index, row in cookies_df.iterrows():
                expires = pd.Timestamp(row['expires_utc'], unit='s')
                if expires.year < 1900 or expires.year > 9999:
                    expires_str = 'expires=Fri, 31 Dec 9999 23:59:59 GMT;'
                else:
                    expires_str = f" expires={expires.strftime('%a, %d %b %Y %H:%M:%S GMT')};"
                file.write(
                    f"  document.cookie = '{row['name']}={row['value']}; path={row['path']}; domain={row['host_key']};"
                )
                if row['is_secure']:
                    file.write(" secure;")
                file.write(expires_str + "'\n")
            file.write("}\n")
        logging.info("Cookies have been converted to JavaScript format and saved.")
    except Exception as e:
        logging.error(f"Failed to write JavaScript cookie file: {e}")
        sys.exit(f"Failed to write JavaScript cookie file: {e}")

def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Process cookies for Netscape cookie file format or JavaScript from various browsers. Use the combine flag to append cookies from multiple browsers into a single file.')
    parser.add_argument('-b', '--browser', required=True, choices=['chrome', 'firefox'], help='Browser from which to extract cookies.')
    parser.add_argument('-i', '--input', required=True, help='Input path for the browser cookies file.')
    parser.add_argument('-o', '--output', required=True, help='Output path for cookies file.')
    parser.add_argument('-f', '--format', required=True, choices=['netscape', 'javascript'], help='Output file format. Options are "netscape" or "javascript".')
    parser.add_argument('-c', '--combine', action='store_true', help='Combine cookies from multiple runs into the same output file. Only valid for Netscape format.')
    return parser.parse_args()

def main():
    args = parse_arguments()
    output_dir = os.path.dirname(args.output)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    logging.info(f"Starting the cookie conversion process from {args.browser} at {args.input} to {args.output} in {args.format} format.")
    if args.browser == 'chrome':
        cookies_df = extract_chrome_cookies(args.input)
    elif args.browser == 'firefox':
        cookies_df = extract_firefox_cookies(args.input)

    with tempfile.NamedTemporaryFile(dir='/tmp', mode='w+', delete=False) as temp_file:
        if args.format == 'netscape':
            convert_to_netscape_format(cookies_df, args.output if args.combine else temp_file.name)
        else:
            convert_to_javascript_format(cookies_df, temp_file.name)
        if not args.combine or args.format == 'javascript':
            os.replace(temp_file.name, args.output)  # Move the temporary file to the desired output location
    logging.info(f"Cookies have been successfully converted to {args.format} format and saved to {args.output}")

if __name__ == '__main__':
    main()
