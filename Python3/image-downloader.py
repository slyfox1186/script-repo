#!/usr/bin/env python3

import os
import re
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse
from fuzzywuzzy import fuzz, process
import spacy

# Load spaCy model for NER
nlp = spacy.load("en_core_web_sm")

def sanitize_filename(filename):
    # Replace invalid characters and clean up filename
    filename = re.sub(r'[<>:"/\\|?*]', '', filename)  # Remove invalid characters
    filename = re.sub(r'_{2,}', '_', filename)  # Replace multiple underscores with a single underscore
    filename = filename.strip('_')  # Remove leading/trailing underscores
    return filename

def download_image(url, folder):
    try:
        response = requests.get(url, stream=True)
        if response.status_code == 200:
            # Extract filename from URL
            filename = os.path.basename(urlparse(url).path)
            if not filename:
                filename = "image.jpg"  # Fallback if filename is empty
            filename = sanitize_filename(filename)
            file_path = os.path.join(folder, filename)
            with open(file_path, 'wb') as file:
                for chunk in response.iter_content(1024):
                    file.write(chunk)
            print(f"Downloaded: {filename}")
        else:
            print(f"Failed to retrieve {url}. Status code: {response.status_code}")
    except Exception as e:
        print(f"Error downloading {url}: {e}")

def extract_image_links(page_url):
    try:
        response = requests.get(page_url)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')
        
        image_urls = []
        for a_tag in soup.find_all('a'):
            href = a_tag.get('href')
            if href:
                img_tag = a_tag.find('img')
                if img_tag and re.search(r'\.(jpg|jpeg|png)$', href, re.IGNORECASE):
                    full_url = urljoin(page_url, href)
                    image_urls.append(full_url)
        
        return image_urls
    except Exception as e:
        print(f"Error fetching image links: {e}")
        return []

def main():
    url = input("Enter the URL of the website to scan: ").strip()
    if not url.startswith(('http://', 'https://')):
        print("Invalid URL. Please ensure it starts with 'http://' or 'https://'.")
        return
    
    output_folder = 'output_pics'
    os.makedirs(output_folder, exist_ok=True)
    
    print("Extracting image links...")
    image_links = extract_image_links(url)
    
    if not image_links:
        print("No images found or error occurred.")
        return
    
    print("Downloading images...")
    for img_url in image_links:
        download_image(img_url, output_folder)

if __name__ == "__main__":
    main()
