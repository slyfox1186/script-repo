#!/usr/bin/env python3

import requests
from bs4 import BeautifulSoup
import sys
from concurrent.futures import ThreadPoolExecutor

def fetch_url(url):
    try:
        response = requests.get(url)
        response.raise_for_status()
        return response.content
    except Exception as e:
        print(f"Error fetching {url}: {e}")
        return None

def scrape_website(url):
    try:
        content = fetch_url(url)
        if not content:
            return

        soup = BeautifulSoup(content, 'html.parser')
        articles = soup.find_all('h2', class_='title')

        for article in articles:
            title = article.get_text()
            link = article.find('a')['href']
            print(f"Title: {title}")
            print(f"Link: {link}")
            print()
    except Exception as e:
        print(f"Error: {e}")

def main():
    if len(sys.argv) != 2:
        print_help()
        sys.exit(1)

    url = sys.argv[1]

    scrape_website(url)

def print_help():
    print("Usage: scrape_website.py <url>")
    print("Scrapes the titles and links of articles from the given news website.")
    print("Arguments:")
    print("  <url> URL of the website to scrape")

if __name__ == "__main__":
    main()
