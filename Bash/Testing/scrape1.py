#!/usr/bin/env python3

import sys
import difflib
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm

def read_packages(package_list):
    """ Split package list into an array """
    return package_list.split(',')

def fetch_url_content(url, user_agent):
    """ Fetch the content of a URL using the specified user agent """
    headers = {'User-Agent': user_agent}
    response = requests.get(url, headers=headers)
    return response.text

def extract_package_names(content):
    """ Extract package names from the HTML content """
    soup = BeautifulSoup(content, 'html.parser')
    return [dt.a.get_text() for dt in soup.find_all('dt')]

def find_matches(package_list, extracted_names, url):
    """ Find exact matches, close matches, and non-matches """
    matches = set()
    close_matches = set()
    non_matches = set(package_list)

    for package in package_list:
        if package in extracted_names:
            matches.add((package, url))
        else:
            found_close_matches = difflib.get_close_matches(package, extracted_names, n=1, cutoff=0.7)
            for match in found_close_matches:
                close_matches.add((package, match, url))

        non_matches.discard(package)

    return matches, close_matches, non_matches

def write_results(file_name, results):
    """ Write results to a file """
    with open(file_name, 'a') as file:
        for result in results:
            if len(result) == 2:  # matches and non-matches
                file.write(f"{result[0]}: {result[1]}\n")
            else:  # close matches
                file.write(f"Input: {result[0]}, Close Match: {result[1]}, URL: {result[2]}\n")

def sort_and_deduplicate(file_name):
    """ Sort the contents of a file alphabetically and remove duplicates """
    with open(file_name, 'r') as file:
        lines = file.readlines()
    unique_lines = sorted(set(lines))
    with open(file_name, 'w') as file:
        file.writelines(unique_lines)

def print_file_contents(file_name):
    """ Print the contents of a file to the terminal """
    print(f"\nContents of {file_name}:")
    with open(file_name, 'r') as file:
        print(file.read())

def main(url_file, package_list, user_agents):
    """ Main function to process URLs and packages """
    packages = read_packages(package_list)

    with open(url_file, 'r') as file:
        urls = file.readlines()

    pbar = tqdm(total=len(urls), desc="Processing URLs", ncols=100)

    all_matches = set()
    all_close_matches = set()
    all_non_matches = set()

    for i, url in enumerate(urls):
        url = url.strip()
        user_agent = user_agents[i % len(user_agents)]
        content = fetch_url_content(url, user_agent)
        extracted_names = extract_package_names(content)
        matches, close_matches, non_matches = find_matches(packages, extracted_names, url)
        
        all_matches.update(matches)
        all_close_matches.update(close_matches)
        all_non_matches.update(non_matches)

        pbar.update(1)

    pbar.close()

    write_results('exact-matches.txt', all_matches)
    write_results('close-exact-matches.txt', all_close_matches)
    write_results('non-exact-matches.txt', [(pkg, '') for pkg in all_non_matches])

    # Sort and deduplicate the contents of output files
    for file_name in ['exact-matches.txt', 'close-exact-matches.txt', 'non-exact-matches.txt']:
        sort_and_deduplicate(file_name)

    # Ask the user if they want to view the output files
    view = input("Do you want to view the contents of the output files? (yes/no) ")
    if view.lower() == 'yes':
        for file_name in ['exact-matches.txt', 'close-exact-matches.txt', 'non-exact-matches.txt']:
            print_file_contents(file_name)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python3 search_packages.py <url_file> <package_list>")
        sys.exit(1)

    user_agents = [
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15'
    ]

    main(sys.argv[1], sys.argv[2], user_agents)
