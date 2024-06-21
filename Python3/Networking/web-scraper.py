#!/usr/bin/env python3

import requests
from bs4 import BeautifulSoup
import sys
import argparse
import time
import logging
from urllib.parse import urljoin
from concurrent.futures import ThreadPoolExecutor

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def fetch_url(url, retries=3, backoff_factor=2):
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    for attempt in range(retries):
        try:
            response = requests.get(url, headers=headers, timeout=10)
            response.raise_for_status()
            return response.content, url
        except requests.RequestException as e:
            logging.error(f"Error fetching {url} (attempt {attempt + 1}/{retries}): {e}")
            sleep_time = backoff_factor ** attempt
            logging.info(f"Retrying in {sleep_time} seconds...")
            time.sleep(sleep_time)
    return None, url

def scrape_content(content, base_url):
    try:
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
                full_link = urljoin(base_url, link)
                print(f"Title: {title}")
                print(f"Link: {full_link}")
                print()
    except Exception as e:
        logging.error(f"Error parsing content from {base_url}: {e}")

def scrape_websites(urls):
    try:
        with ThreadPoolExecutor() as executor:
            contents_and_urls = list(executor.map(fetch_url, urls))
            for content, url in contents_and_urls:
                scrape_content(content, url)
    except Exception as e:
        logging.error(f"Error: {e}")

def main():
    parser = argparse.ArgumentParser(description="Scrape the titles and links of articles from multiple news websites in parallel.")
    parser.add_argument('urls', nargs='+', help='URLs of the websites to scrape')
    args = parser.parse_args()

    scrape_websites(args.urls)

if __name__ == "__main__":
    main()
