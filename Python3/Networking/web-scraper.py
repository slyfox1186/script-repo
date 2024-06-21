#!/usr/bin/env python3

import requests
from bs4 import BeautifulSoup
import sys
import argparse
import time

def fetch_url(url, retries=3):
    for attempt in range(retries):
        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            return response.content
        except requests.RequestException as e:
            print(f"Error fetching {url} (attempt {attempt + 1}/{retries}): {e}")
            time.sleep(2)  # wait before retrying
    return None

def scrape_website(url):
    try:
        content = fetch_url(url)
        if not content:
            return

        soup = BeautifulSoup(content, 'html.parser')
        # Adjust the selector based on the website structure
        articles = soup.find_all('h3')

        for article in articles:
            title = article.get_text(strip=True)
            link = article.find('a')
            if link:
                link = link.get('href')
                print(f"Title: {title}")
                print(f"Link: {link}")
                print()
    except Exception as e:
        print(f"Error parsing content: {e}")

def main():
    parser = argparse.ArgumentParser(description="Scrape the titles and links of articles from a given news website.")
    parser.add_argument('url', help='URL of the website to scrape')
    args = parser.parse_args()

    scrape_website(args.url)

def print_help():
    print("Usage: scrape_website.py <url>")
    print("Scrapes the titles and links of articles from the given news website.")
    print("Arguments:")
    print("  <url> URL of the website to scrape")

if __name__ == "__main__":
    main()
