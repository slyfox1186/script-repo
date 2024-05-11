## Important Information ##

# This script is designed to be run on native Windows using its Python installation through 'CMD' or 'powershell/pwsh'.

# The reason for this is that the script deals with timestamps that are counted since the year 1601, also known as the "Windows Epoch."

# When using Linux and Windows together, such as in a WSL (Windows Subsystem for Linux) environment, there are differences in how timestamps are handled.
# If you use this script in WSL or native Linux and point it to a Chrome or Firefox installation located on a native Windows environment, the script may
# appear to work, but the information stored in the output file may not be correct.

# To ensure accurate results and avoid any issues related to timestamp conversions between Windows and Linux, it is recommended to run this script using
# the Windows version of Python. This will save you from potential inaccuracies and inconsistencies in the extracted cookie data.

import os
import json
import base64
import sqlite3
import shutil
import argparse
from datetime import datetime, timedelta
import win32crypt
from Crypto.Cipher import AES

def get_chrome_datetime(chromedate):
    if chromedate != 86400000000 and chromedate:
        try:
            return datetime(1601, 1, 1) + timedelta(microseconds=chromedate)
        except Exception as e:
            print(f"Error: {e}, chromedate: {chromedate}")
            return chromedate
    else:
        return ""

def get_encryption_key(browser, local_state_path):
    if browser == "chrome":
        with open(local_state_path, "r", encoding="utf-8") as f:
            local_state = f.read()
            local_state = json.loads(local_state)
        key = base64.b64decode(local_state["os_crypt"]["encrypted_key"])
        key = key[5:]
        return win32crypt.CryptUnprotectData(key, None, None, None, 0)[1]
    elif browser == "firefox":
        if not os.path.exists(local_state_path):
            raise FileNotFoundError(f"Firefox key4.db not found at path: {local_state_path}")
        conn = sqlite3.connect(local_state_path)
        c = conn.cursor()
        c.execute("SELECT item1, item2 FROM metadata WHERE id = 'password'")
        key = c.fetchone()
        return key[1]

def decrypt_data(data, key, browser):
    if browser == "chrome":
        try:
            iv = data[3:15]
            data = data[15:]
            cipher = AES.new(key, AES.MODE_GCM, iv)
            return cipher.decrypt(data)[:-16].decode()
        except:
            try:
                return str(win32crypt.CryptUnprotectData(data, None, None, None, 0)[1])
            except:
                return ""
    elif browser == "firefox":
        try:
            iv = data[3:15]
            data = data[15:]
            cipher = AES.new(key, AES.MODE_CBC, iv)
            return cipher.decrypt(data)[:-16].decode()
        except:
            return ""

def extract_cookies(browser, db_path, local_state_path, key):
    if browser == "chrome":
        filename = os.path.join(os.environ["TEMP"], "Cookies.db")
    elif browser == "firefox":
        filename = os.path.join(os.environ["TEMP"], "firefox_cookies.sqlite")

    if not os.path.isfile(db_path):
        raise FileNotFoundError(f"{browser.capitalize()} cookie database not found at path: {db_path}")

    if not os.path.isfile(filename):
        shutil.copyfile(db_path, filename)

    db = sqlite3.connect(filename)
    cursor = db.cursor()

    if browser == "chrome":
        cursor.execute("""
        SELECT host_key, name, value, creation_utc, last_access_utc, expires_utc, encrypted_value
        FROM cookies""")
    elif browser == "firefox":
        cursor.execute("""
        SELECT host, name, value, creationTime, lastAccessed, expiry, isSecure, isHttpOnly, path 
        FROM moz_cookies""")

    cookies = []

    if browser == "chrome":
        for host_key, name, value, creation_utc, last_access_utc, expires_utc, encrypted_value in cursor.fetchall():
            if not value:
                decrypted_value = decrypt_data(encrypted_value, key, browser)
            else:
                decrypted_value = value

            cookie_data = {
                "domain": host_key,
                "expirationDate": expires_utc,
                "hostOnly": not host_key.startswith('.'),
                "httpOnly": 'httponly' in host_key,
                "name": name,
                "path": host_key.lstrip('.'),
                "sameSite": "no_restriction",
                "secure": 'secure' in host_key,
                "session": False,
                "storeId": "0",
                "value": decrypted_value
            }
            cookies.append(cookie_data)
    elif browser == "firefox":
        for host, name, value, creationTime, lastAccessed, expiry, isSecure, isHttpOnly, path in cursor.fetchall():
            decrypted_value = decrypt_data(value, key, browser)

            cookie_data = {
                "domain": host,
                "expirationDate": expiry,
                "hostOnly": not host.startswith('.'),
                "httpOnly": isHttpOnly,
                "name": name,
                "path": path,
                "sameSite": "no_restriction",
                "secure": isSecure,
                "session": False,
                "storeId": "0",
                "value": decrypted_value
            }
            cookies.append(cookie_data)

    db.close()
    os.remove(filename)

    return cookies

def main(args):
    if args.combine:
        chrome_db_path, firefox_db_path = args.combine
        chrome_local_state_path = os.path.join(os.path.dirname(chrome_db_path), os.pardir, os.pardir, "Local State")
        firefox_profiles_path = os.path.dirname(firefox_db_path)
        firefox_local_state_path = os.path.join(firefox_profiles_path, "key4.db")

        if not os.path.isfile(chrome_local_state_path):
            raise FileNotFoundError(f"Chrome Local State file not found at path: {chrome_local_state_path}")
        if not os.path.isfile(firefox_local_state_path):
            raise FileNotFoundError(f"Firefox key4.db not found at path: {firefox_local_state_path}")

        chrome_key = get_encryption_key("chrome", chrome_local_state_path)
        firefox_key = get_encryption_key("firefox", firefox_local_state_path)

        chrome_cookies = extract_cookies("chrome", chrome_db_path, chrome_local_state_path, chrome_key)
        firefox_cookies = extract_cookies("firefox", firefox_db_path, firefox_local_state_path, firefox_key)

        cookies = chrome_cookies + firefox_cookies
    else:
        browser = args.browser
        db_path = args.input

        if browser == "chrome":
            local_state_path = os.path.join(os.path.dirname(db_path), os.pardir, os.pardir, "Local State")
        elif browser == "firefox":
            profiles_path = os.path.dirname(db_path)
            local_state_path = os.path.join(profiles_path, "key4.db")

        if not os.path.isfile(local_state_path):
            raise FileNotFoundError(f"{'Chrome Local State' if browser == 'chrome' else 'Firefox key4.db'} file not found at path: {local_state_path}")

        key = get_encryption_key(browser, local_state_path)
        cookies = extract_cookies(browser, db_path, local_state_path, key)

    cookies.sort(key=lambda x: x['domain'])

    if args.format == "json":
        with open(args.output, "w") as cookie_file:
            json_output = json.dumps(cookies, indent=4)
            cookie_file.write(json_output)
    elif args.format == "netscape":
        with open(args.output, "w") as cookie_file:
            for cookie in cookies:
                cookie_file.write(f"{cookie['domain']}\t{'TRUE' if cookie['hostOnly'] else 'FALSE'}\t{cookie['path']}\t{'TRUE' if cookie['secure'] else 'FALSE'}\t{cookie['expirationDate']}\t{cookie['name']}\t{cookie['value']}\n")
    else:
        with open(args.output, "w") as cookie_file:
            for cookie in cookies:
                cookie_file.write(f"""
                Host: {cookie['domain']}
                Cookie name: {cookie['name']}
                Cookie value (decrypted): {cookie['value']}
                Creation datetime (UTC): {get_chrome_datetime(cookie['creationTime'] if 'creationTime' in cookie else cookie['expirationDate'])}
                Expires datetime (UTC): {get_chrome_datetime(cookie['expirationDate'])}
                Path: {cookie['path']}
                Secure: {cookie['secure']}
                HttpOnly: {cookie['httpOnly']}
    ===============================================================""")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Chrome/Firefox Cookie Extractor")
    parser.add_argument("-f", "--format", type=str, default="netscape", choices=["netscape", "json", "plain"], help="Output format for the cookie data. Choose between 'netscape', 'json', and 'plain'. Default is 'netscape'.")
    parser.add_argument("-b", "--browser", type=str, choices=["chrome", "firefox"], help="Browser to extract cookies from. Choose between 'chrome' and 'firefox'.")
    parser.add_argument("-i", "--input", type=str, help="Path to the browser's cookie database file.")
    parser.add_argument("-o", "--output", type=str, required=True, help="Output file path for the extracted cookie data.")
    parser.add_argument("-c", "--combine", nargs=2, metavar=('CHROME_DB', 'FIREFOX_DB'), help="Combine cookies from both Chrome and Firefox. Specify the paths to the Chrome and Firefox cookie database files.")

    args = parser.parse_args()

    if not args.combine and not (args.browser and args.input):
        parser.error("You must provide either the --combine argument or both the --browser and --input arguments.")

    try:
        main(args)
    except FileNotFoundError as e:
        print(f"Error: {str(e)}")
        print("Please make sure you provide the correct path(s) to the browser's cookie database file(s).")
    except Exception as e:
        print(f"An error occurred: {str(e)}")
