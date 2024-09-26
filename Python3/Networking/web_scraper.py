#!/usr/bin/env python3

import argparse
import csv
import json
import logging
import multiprocessing
import requests
import time
import warnings
import re
from bs4 import BeautifulSoup, XMLParsedAsHTMLWarning
from concurrent.futures import ThreadPoolExecutor, as_completed
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry
from urllib.parse import urljoin
from urllib3 import connectionpool

# Suppress XMLParsedAsHTMLWarning
warnings.filterwarnings("ignore", category=XMLParsedAsHTMLWarning)

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s - %(name)s - %(message)s')
logger = logging.getLogger(__name__)

DEFAULT_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0'
DEFAULT_POOL_SIZE = 100

def create_session(user_agent, pool_size):
    session = requests.Session()
    retries = Retry(total=3, backoff_factor=0.5, status_forcelist=[500, 502, 503, 504])
    adapter = HTTPAdapter(max_retries=retries, pool_connections=pool_size, pool_maxsize=pool_size)
    session.mount('http://', adapter)
    session.mount('https://', adapter)
    session.headers.update({'User-Agent': user_agent})
    return session

def fetch_url(session, url):
    try:
        response = session.get(url, timeout=10)
        response.raise_for_status()
        return response.content, url
    except requests.RequestException as e:
        logger.error(f"Error fetching {url}: {e}")
        return None, url

def extract_main_content(content, url):
    soup = BeautifulSoup(content, 'lxml')
    
    # Remove unwanted elements
    for element in soup(['script', 'style', 'nav', 'header', 'footer']):
        element.decompose()
    
    # Try to find the main content
    main_content = soup.find('main') or soup.find('article') or soup.find('div', class_='content')
    
    if not main_content:
        # If no specific content container is found, use the body
        main_content = soup.body
    
    if main_content:
        # Extract text and links
        text = main_content.get_text(strip=True)
        # Remove '\r' characters and normalize line endings
        text = re.sub(r'\r\n?', '\n', text)
        links = [{'text': a.get_text(strip=True), 'href': urljoin(url, a.get('href'))} 
                 for a in main_content.find_all('a', href=True)]
        
        # Limit text to 1000 characters
        text = text[:1000] + '...' if len(text) > 1000 else text
        
        return {
            'url': url,
            'title': soup.title.string if soup.title else 'No title',
            'content': text,
            'links': links[:10]  # Limit to 10 links
        }
    else:
        return {
            'url': url,
            'title': 'Failed to extract content',
            'content': '',
            'links': []
        }

def scrape_websites(urls, max_workers, user_agent, pool_size):
    session = create_session(user_agent, pool_size)
    results = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_url = {executor.submit(fetch_url, session, url): url for url in urls}
        for future in as_completed(future_to_url):
            url = future_to_url[future]
            try:
                content, _ = future.result()
                if content:
                    result = extract_main_content(content, url)
                    results.append(result)
            except Exception as e:
                logger.error(f"Error processing {url}: {e}")
    return results

def save_results_json(results, filename, minimize=False):
    with open(filename, 'w', encoding='utf-8') as f:
        if minimize:
            json.dump(results, f, ensure_ascii=False, separators=(',', ':'))
        else:
            json.dump(results, f, ensure_ascii=False, indent=2)

def save_results_csv(results, filename, minimize=False):
    with open(filename, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['URL', 'Title', 'Content', 'Links'])
        for result in results:
            links = json.dumps(result['links'], ensure_ascii=False, separators=(',', ':')) if minimize else json.dumps(result['links'])
            writer.writerow([
                result['url'],
                result['title'],
                result['content'],
                links
            ])

def read_urls_from_file(file_path):
    with open(file_path, 'r') as f:
        return [line.strip() for line in f if line.strip()]

def main():
    default_max_workers = max(multiprocessing.cpu_count() * 2, 5)

    parser = argparse.ArgumentParser(description="Scrape the main content from multiple websites in parallel.",
                                     formatter_class=argparse.RawDescriptionHelpFormatter,
                                     epilog='''
Examples:
  python script.py https://www.example1.com https://www.example2.com
  python script.py --output results.json --format json https://www.example.com
  python script.py --max-workers 5 --verbose https://www.example1.com https://www.example2.com
  python script.py --input-file urls.txt
  python script.py --output results.json --format json --minimize https://www.example.com
''')
    
    parser.add_argument('urls', nargs='*', help='URLs of the websites to scrape')
    parser.add_argument('-i', '--input-file', help='Path to a file containing URLs to scrape (one per line)')
    parser.add_argument('-o', '--output', help='Output file to save results')
    parser.add_argument('-f', '--format', choices=['json', 'csv'], default='json', help='Output format (default: json)')
    parser.add_argument('-w', '--max-workers', type=int, default=default_max_workers, 
                        help=f'Maximum number of worker threads (default: {default_max_workers})')
    parser.add_argument('-v', '--verbose', action='store_true', help='Increase output verbosity')
    parser.add_argument('--user-agent', default=DEFAULT_USER_AGENT, help='Custom User-Agent string')
    parser.add_argument('--pool-size', type=int, default=DEFAULT_POOL_SIZE, help='Connection pool size')
    parser.add_argument('-m', '--minimize', action='store_true', help='Minimize output file size')
    
    args = parser.parse_args()

    if args.verbose:
        logger.setLevel(logging.DEBUG)

    if args.input_file:
        urls = read_urls_from_file(args.input_file)
    elif args.urls:
        urls = args.urls
    else:
        parser.error("Either provide URLs as arguments or use the --input-file option.")

    start_time = time.time()
    results = scrape_websites(urls, args.max_workers, args.user_agent, args.pool_size)
    
    if args.output:
        if args.format == 'json':
            save_results_json(results, args.output, args.minimize)
        elif args.format == 'csv':
            save_results_csv(results, args.output, args.minimize)
        logger.info(f"Results saved to {args.output}")
    else:
        if args.minimize:
            print(json.dumps(results, ensure_ascii=False, separators=(',', ':')))
        else:
            print(json.dumps(results, ensure_ascii=False, indent=2))
    
    end_time = time.time()
    logger.info(f"Scraping completed in {end_time - start_time:.2f} seconds")

if __name__ == "__main__":
    main()
