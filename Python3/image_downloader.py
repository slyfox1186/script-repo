#!/usr/bin/env python3

"""Download every linked image (.jpg/.jpeg/.png) on a single web page."""

import argparse
import os
import re
import sys
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:150.0) Gecko/20100101 Firefox/150.0"
IMAGE_EXTENSIONS_RE = re.compile(r"\.(jpg|jpeg|png)$", re.IGNORECASE)
INVALID_NAME_RE = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
COLLAPSE_UNDERSCORES_RE = re.compile(r"_{2,}")


def sanitize_filename(filename: str) -> str:
    cleaned = INVALID_NAME_RE.sub("", filename)
    cleaned = COLLAPSE_UNDERSCORES_RE.sub("_", cleaned).strip("_")
    return cleaned or "image.jpg"


def download_image(session: requests.Session, url: str, folder: Path) -> bool:
    try:
        response = session.get(url, stream=True, timeout=30)
        response.raise_for_status()
    except requests.RequestException as exc:
        print(f"Error downloading {url}: {exc}", file=sys.stderr)
        return False

    name = os.path.basename(urlparse(url).path) or "image.jpg"
    target = folder / sanitize_filename(name)
    with target.open("wb") as fh:
        for chunk in response.iter_content(8192):
            fh.write(chunk)
    print(f"Downloaded: {target.name}")
    return True


def extract_image_links(session: requests.Session, page_url: str) -> list[str]:
    try:
        response = session.get(page_url, timeout=30)
        response.raise_for_status()
    except requests.RequestException as exc:
        print(f"Error fetching page: {exc}", file=sys.stderr)
        return []

    soup = BeautifulSoup(response.text, "html.parser")
    urls: list[str] = []
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if a.find("img") and IMAGE_EXTENSIONS_RE.search(href):
            urls.append(urljoin(page_url, href))
    return urls


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", help="Page URL to scan.")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("output_pics"),
        help="Folder to save images into (default: ./output_pics).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    url = args.url or input("Enter the URL of the website to scan: ").strip()
    if not url.startswith(("http://", "https://")):
        print("URL must start with http:// or https://", file=sys.stderr)
        return 1

    args.output.mkdir(parents=True, exist_ok=True)

    with requests.Session() as session:
        session.headers["User-Agent"] = USER_AGENT
        print("Extracting image links...")
        links = extract_image_links(session, url)
        if not links:
            print("No images found.")
            return 0
        print(f"Found {len(links)} image link(s); downloading...")
        succeeded = sum(download_image(session, u, args.output) for u in links)
    print(f"Done. {succeeded}/{len(links)} downloaded into {args.output}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
