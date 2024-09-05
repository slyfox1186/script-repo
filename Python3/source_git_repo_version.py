#!/usr/bin/env python3

# Execute: python3 source_git_repo_version.py 'https://github.com/ffmpeg/ffmpeg' 2>log.txt
# Execute: python3 source_git_repo_version.py 'https://github.com/REPO/REPO' 2>log.txt

import requests
import re
import sys
import time
import logging
from tqdm import tqdm
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Set up logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')

# Regex patterns
FIRST_MATCH = r'href="[^"]*/tag/([^"]*)"'
SECOND_MATCH = r'(?:[a-z-]+-)?((?:[0-9]+(?:[._-][0-9]+)*(?:-[a-zA-Z0-9]+)?))'
EXCLUDE_WORDS = r'alpha|beta|dev|early|init|m[0-9]+|next|pending|pre|rc|tentative|^.$'
TRIM_THIS = r'-$'

# Max retry attempts and retry interval
MAX_ATTEMPTS = 3
INITIAL_RETRY_INTERVAL = 5

# Exponential backoff factor
BACKOFF_FACTOR = 2

# HTTP session with retries
def create_http_session():
    logging.debug("Creating HTTP session")
    session = requests.Session()
    retry_strategy = Retry(
        total=MAX_ATTEMPTS,
        backoff_factor=BACKOFF_FACTOR,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"]
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session

def get_html_content(session, url):
    """Fetch HTML content from the URL with proper error handling."""
    logging.debug(f"Attempting to fetch HTML content from: {url}")
    try:
        response = session.get(url, timeout=10)
        response.raise_for_status()
        logging.debug(f"Successfully fetched content from: {url}")
        return response.text
    except requests.RequestException as e:
        logging.error(f"Error fetching data from {url}: {e}")
        return None

def parse_latest_version(html_content):
    """Parse the latest version from the HTML content."""
    logging.debug("Parsing latest version from HTML content")
    first_match_results = re.findall(FIRST_MATCH, html_content)
    if not first_match_results:
        logging.warning("No matches found in HTML content")
        return None

    logging.debug(f"First match results: {first_match_results}")
    second_match_results = [re.search(SECOND_MATCH, match) for match in first_match_results]
    versions = [match.group(1) for match in second_match_results if match]

    logging.debug(f"Extracted versions: {versions}")
    # Filter versions, remove excluded words, sort by version, and trim suffix
    versions = [re.sub(TRIM_THIS, "", v) for v in versions if not re.search(EXCLUDE_WORDS, v)]
    logging.debug(f"Filtered versions: {versions}")
    return sorted(versions, key=lambda s: list(map(int, re.findall(r'\d+', s))), reverse=True)[0] if versions else None

def get_latest_release_version(session, url):
    """Fetch the latest release version from the GitHub repository."""
    logging.debug(f"Getting latest release version for URL: {url}")
    # Remove trailing slash if present, but keep the .git if it exists
    base_url = url.rstrip('/')
    
    # Create URLs for releases and tags
    releases_url = f"{base_url}/releases"
    tags_url = f"{base_url}/tags"

    logging.debug(f"Base URL: {base_url}")
    logging.debug(f"Releases URL: {releases_url}")
    logging.debug(f"Tags URL: {tags_url}")

    html_content = ""
    for sub_url in [base_url, releases_url, tags_url]:
        logging.info(f"Fetching from: {sub_url}")
        sub_html = get_html_content(session, sub_url)
        if sub_html:
            html_content += sub_html

    version = parse_latest_version(html_content)
    if not version:
        logging.warning(f"No version found for {url}")
    else:
        logging.info(f"Latest version found: {version}")
    return version

def retry_version_fetch(session, url):
    """Retry mechanism to fetch the latest version with exponential backoff."""
    interval = INITIAL_RETRY_INTERVAL

    url = debug_url(url, "start of retry_version_fetch")
    logging.info(f"Fetching version for URL: {url}")
    for attempt in range(1, MAX_ATTEMPTS + 1):
        logging.debug(f"Attempt {attempt}/{MAX_ATTEMPTS}")
        url = debug_url(url, f"before get_latest_release_version (attempt {attempt})")
        version = get_latest_release_version(session, url)
        url = debug_url(url, f"after get_latest_release_version (attempt {attempt})")
        if version:
            logging.info(f"Latest version found: {version}")
            return version
        logging.warning(f"Failed to fetch version (Attempt {attempt}/{MAX_ATTEMPTS}). Retrying in {interval} seconds...")
        if attempt < MAX_ATTEMPTS:
            time.sleep(interval)
            interval *= BACKOFF_FACTOR  # Exponential backoff

    logging.error("Unable to fetch the latest version after multiple attempts.")
    return None

def debug_url(url, location):
    logging.debug(f"URL at {location}: {url}")
    return url

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 source_git_repo_version.py <url>")
        sys.exit(1)
    
    url = sys.argv[1]
    session = create_http_session()
    version = retry_version_fetch(session, url)
    
    if version:
        print(version)
    else:
        sys.exit(1)
