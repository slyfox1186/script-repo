#!/usr/bin/env python3

import os
import sqlite3
import json
import base64
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
import requests
import re
import win32crypt  # Import for Windows Crypt API
import argparse  # Import argparse for command-line parsing

def decrypt_aes_gcm(key, data):
    """Decrypt data encrypted using AES-GCM."""
    nonce = data[:12]  # Nonce is 12 bytes long
    tag = data[-16:]  # Tag is last 16 bytes
    cipherbytes = data[12:-16]  # The actual encrypted data excludes nonce and tag

    cipher = Cipher(algorithms.AES(key), modes.GCM(nonce, tag), backend=default_backend())
    decryptor = cipher.decryptor()
    return decryptor.update(cipherbytes) + decryptor.finalize()

def get_encryption_key():
    """Retrieve the Chrome's 'Local State' file and extract the encryption key."""
    local_state_path = os.path.join(os.environ['USERPROFILE'], 'AppData', 'Local', 'Google', 'Chrome Beta', 'User Data', 'Local State')
    with open(local_state_path, 'r', encoding='utf-8') as f:
        local_state = json.loads(f.read())
    key = base64.b64decode(local_state['os_crypt']['encrypted_key'])
    key = key[5:]  # Strip the 'DPAPI' prefix
    return win32crypt.CryptUnprotectData(key, None, None, None, 0)[1]  # Decrypt the key using Windows DPAPI

def get_chrome_cookies(url):
    """Retrieve cookies from Chrome for a specific URL."""
    cookies = {}
    path = os.path.join(os.environ['USERPROFILE'], 'AppData', 'Local', 'Google', 'Chrome Beta', 'User Data', 'Default', 'Network', 'Cookies')
    key = get_encryption_key()  # Retrieve the AES encryption key
    conn = sqlite3.connect(path)
    cursor = conn.cursor()
    cursor.execute('SELECT host_key, name, value, encrypted_value FROM cookies WHERE host_key LIKE ?', ('%' + url + '%',))
    for host_key, name, value, encrypted_value in cursor.fetchall():
        if value:
            cookies[name] = value
        elif encrypted_value:
            decrypted_value = decrypt_aes_gcm(key, encrypted_value[3:])  # Ensure encrypted_value is correctly sliced if needed
            cookies[name] = decrypted_value.decode('utf-8')
    cursor.close()
    conn.close()
    return cookies

def save_cookies_to_file(cookies, filename):
    """Save cookies to a file."""
    with open(filename, 'w') as file:
        json.dump(cookies, file, indent=4)

def main():
    parser = argparse.ArgumentParser(description="Extract cookies from Chrome and save them to a file.")
    parser.add_argument('-w', '--web', type=str, required=True, help="Specify the website URL to extract cookies from.")
    parser.add_argument('-o', '--output', type=str, required=True, help="Specify the output file to store cookies.")
    args = parser.parse_args()

    url = args.web
    output_file = args.output
    cookies = get_chrome_cookies(url)
    save_cookies_to_file(cookies, output_file)
    print(f"Cookies have been saved to {output_file}")

if __name__ == "__main__":
    main()
