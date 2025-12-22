#!/usr/bin/env python3

# Execute: python3 source_git_repo_version.py 'https://github.com/ffmpeg/ffmpeg' 2>log.txt
# Execute: python3 source_git_repo_version.py 'https://github.com/REPO/REPO' 2>log.txt

import argparse
import logging
import re
import requests
import sys
import time
from urllib.parse import unquote
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


class ColorFormatter(logging.Formatter):
    """Custom formatter with colors and symbols for better readability."""

    COLORS = {
        'DEBUG': '\033[90m',     # Gray
        'INFO': '\033[94m',      # Blue
        'WARNING': '\033[93m',   # Yellow
        'ERROR': '\033[91m',     # Red
        'RESET': '\033[0m',
    }
    SYMBOLS = {
        'DEBUG': '  ',
        'INFO': '->',
        'WARNING': '!!',
        'ERROR': 'XX',
    }

    def format(self, record):
        color = self.COLORS.get(record.levelname, '')
        symbol = self.SYMBOLS.get(record.levelname, '  ')
        reset = self.COLORS['RESET']
        return f"{color}{symbol} {record.getMessage()}{reset}"


def setup_logging(verbose=False):
    """Configure logging with clean, readable output."""
    level = logging.DEBUG if verbose else logging.INFO
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(ColorFormatter())

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    root_logger.handlers = [handler]

    # Silence noisy libraries
    logging.getLogger('urllib3').setLevel(logging.WARNING)
    logging.getLogger('requests').setLevel(logging.WARNING)

# Compiled regex patterns for better performance
# Matches tag hrefs including /releases/tag/ paths, uses lazy quantifier to reduce backtracking
FIRST_MATCH_RE = re.compile(r'href="[^"]*?/(?:releases/)?tag/([^"]+)"')

# Extracts version numbers with case-insensitive prefix support and common version prefixes (v, V, n, N)
# Now captures suffixes attached without separators (e.g., 3.15.0a3, 1.0.0rc1)
SECOND_MATCH_RE = re.compile(
    r'(?:[a-zA-Z][-a-zA-Z0-9]*-)?[vVnN]?([0-9]+(?:[._-][0-9]+)*(?:[-_.]?[a-zA-Z][a-zA-Z0-9]*)?)'
)

# Filters pre-release versions - includes shorthand notations (a1, b2, rc1) common in Python/semver
EXCLUDE_WORDS_RE = re.compile(
    r'(alpha|beta|dev|early|init|m[0-9]+|next|pending|pre|preview|snapshot|nightly|canary|test|experimental|tentative|unstable|wip|draft'
    r'|a[0-9]+|b[0-9]+|c[0-9]+|rc[0-9]*)',  # a1, b2, c1, rc, rc1, etc.
    re.IGNORECASE
)

# Removes leading and trailing separators (dash, dot, underscore)
TRIM_RE = re.compile(r'^[-._]+|[-._]+$')

# Max retry attempts and retry interval
MAX_ATTEMPTS = 3
INITIAL_RETRY_INTERVAL = 5

# Exponential backoff factor
BACKOFF_FACTOR = 2

# HTTP session with retries
def create_http_session():
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
    try:
        response = session.get(url, timeout=10)
        response.raise_for_status()
        return response.text
    except requests.RequestException as e:
        logging.warning(f"Failed: {url} ({e.__class__.__name__})")
        return None

def parse_latest_version(html_content):
    """Parse the latest version from the HTML content."""
    first_match_results = FIRST_MATCH_RE.findall(html_content)
    if not first_match_results:
        logging.debug("No tag links found in HTML")
        return None

    # URL-decode tag names to handle encoded characters (%2B, %2F, etc.)
    first_match_results = [unquote(m) for m in first_match_results]
    logging.debug(f"Tags found: {first_match_results[:10]}{'...' if len(first_match_results) > 10 else ''}")

    second_match_results = [SECOND_MATCH_RE.search(match) for match in first_match_results]
    versions = [match.group(1) for match in second_match_results if match]

    # Filter versions, remove excluded words, sort by version, and trim separators
    versions = [TRIM_RE.sub("", v) for v in versions if not EXCLUDE_WORDS_RE.search(v)]
    logging.debug(f"Valid versions: {versions[:10]}{'...' if len(versions) > 10 else ''}")

    return sorted(versions, key=lambda s: list(map(int, re.findall(r'\d+', s))), reverse=True)[0] if versions else None

def get_latest_release_version(session, url):
    """Fetch the latest release version from the GitHub repository."""
    base_url = url.rstrip('/')
    urls_to_fetch = [base_url, f"{base_url}/releases", f"{base_url}/tags"]

    html_content = ""
    for sub_url in urls_to_fetch:
        # Show just the path portion for cleaner output
        path = sub_url.replace(base_url, '') or '/'
        logging.info(f"Fetching {path}")
        sub_html = get_html_content(session, sub_url)
        if sub_html:
            html_content += sub_html

    return parse_latest_version(html_content)

def retry_version_fetch(session, url):
    """Retry mechanism to fetch the latest version with exponential backoff."""
    interval = INITIAL_RETRY_INTERVAL
    repo_name = url.rstrip('/').split('/')[-1]

    logging.info(f"Checking {repo_name} ({url})")
    for attempt in range(1, MAX_ATTEMPTS + 1):
        if attempt > 1:
            logging.info(f"Retry {attempt}/{MAX_ATTEMPTS}")

        version = get_latest_release_version(session, url)
        if version:
            logging.info(f"Found: {version}")
            return version

        if attempt < MAX_ATTEMPTS:
            logging.warning(f"No version found, retrying in {interval}s...")
            time.sleep(interval)
            interval *= BACKOFF_FACTOR

    logging.error("Failed to fetch version after all attempts")
    return None

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Fetch the latest release version from a GitHub repository.",
        epilog="Example: python3 source_git_repo_version.py 'https://github.com/ffmpeg/ffmpeg'"
    )
    parser.add_argument(
        "url",
        help="GitHub repository URL (e.g., https://github.com/owner/repo)"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose debug output"
    )
    parser.add_argument(
        "-q", "--quiet",
        action="store_true",
        help="Suppress all log output"
    )
    args = parser.parse_args()

    if not args.quiet:
        setup_logging(verbose=args.verbose)
    else:
        logging.disable(logging.CRITICAL)

    session = create_http_session()
    version = retry_version_fetch(session, args.url)

    if version:
        print(version)
    else:
        sys.exit(1)
