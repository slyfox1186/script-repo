#!/usr/bin/env python3

from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException
import json
import argparse

def simulate_user_interaction(driver, username, password):
    """Function to simulate user interaction for login."""
    driver.get("https://members.com/login")
    wait = WebDriverWait(driver, 10)

    username_field = wait.until(EC.presence_of_element_located((By.ID, "username")))
    password_field = wait.until(EC.presence_of_element_located((By.ID, "password")))
    login_button = wait.until(EC.element_to_be_clickable((By.ID, "submit")))

    username_field.send_keys(username)
    password_field.send_keys(password)
    login_button.click()

    # Wait for the "All Videos" link to appear, indicating a successful login
    WebDriverWait(driver, 10).until(
        EC.visibility_of_element_located((By.LINK_TEXT, "All Videos"))
    )
    print("Login successful, 'All Videos' link found.")

def get_cookies_from_chrome(url, chrome_driver_path, profile_path, username=None, password=None):
    """Fetch cookies from a given URL using Chrome with Selenium."""
    options = webdriver.ChromeOptions()
    options.add_argument(f"user-data-dir={profile_path}")
    service = Service(executable_path=chrome_driver_path)
    driver = webdriver.Chrome(service=service, options=options)
    
    # Attempt to log in only if username and password are provided
    if username and password:
        simulate_user_interaction(driver, username, password)

    driver.get(url)
    try:
        # Check if 'All Videos' link is visible to confirm logged-in status
        WebDriverWait(driver, 10).until(
            EC.visibility_of_element_located((By.LINK_TEXT, "All Videos"))
        )
        print("Confirmed logged in via 'All Videos' link.")
    except TimeoutException:
        print("Login check failed; 'All Videos' link not found.")
        driver.quit()
        return []

    cookies = driver.get_cookies()
    driver.quit()
    return cookies

def save_cookies_to_file(cookies, filename):
    """Save the cookie data to a file in Netscape cookie file format."""
    with open(filename, 'w') as file:
        for cookie in cookies:
            file.write(
                f"{cookie.get('domain')}\t"  # Domain
                f"{'TRUE' if cookie.get('domain').startswith('.') else 'FALSE'}\t"  # Flag
                f"{cookie.get('path')}\t"  # Path
                f"{'TRUE' if cookie.get('secure') else 'FALSE'}\t"  # Secure
                f"{int(cookie.get('expiry', 0)) if 'expiry' in cookie else '0'}\t"  # Expiration
                f"{cookie.get('name')}\t"  # Name
                f"{cookie.get('value')}\n"  # Value
            )

def main():
    parser = argparse.ArgumentParser(description="Extract cookies from Chrome using Selenium and save them to a file.")
    parser.add_argument('-w', '--web', type=str, required=True, help="Website URL to extract cookies from.")
    parser.add_argument('-o', '--output', type=str, required=True, help="Output file path to store cookies.")
    parser.add_argument('-d', '--driver', type=str, required=True, help="Path to Chromedriver.")
    parser.add_argument('-p', '--profile', type=str, required=True, help="Path to Chrome user profile.")
    parser.add_argument('-u', '--username', type=str, help="Username for login (optional).")
    parser.add_argument('-pw', '--password', type=str, help="Password for login (optional).")
    args = parser.parse_args()

    cookies = get_cookies_from_chrome(args.web, args.driver, args.profile, args.username, args.password)
    save_cookies_to_file(cookies, args.output)
    print(f"Cookies have been saved to {args.output}")

if __name__ == "__main__":
    main()
