#!/usr/bin/env python3

import argparse
import logging
import nltk
import os
import random
import re
import requests
import string
import subprocess
import sys
import time
from bs4 import BeautifulSoup
from urllib.parse import quote_plus, urlparse
from termcolor import colored
from nltk.stem import WordNetLemmatizer
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium_stealth import stealth
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import NoSuchElementException, TimeoutException

# Uncomment these lines if nltk resources haven't been downloaded yet
# nltk.download('wordnet')
# nltk.download('omw-1.4')

lemmatizer = WordNetLemmatizer()

# Configuration Variables
BROWSER = 'chromium'  # Adjust based on your environment. Use full path if needed.
## This can be used in Windows WSL like the below comment:
## BROWSER = 'chrome.exe'  # Adjust based on your environment. Use full path if needed.

DESIRED_WORDS = [
    'walmart.com',
    'ebay.com',
    'amazon.com'
]

EXCLUDE_WORDS = [
    'advertisement',
    'benchmark',
    'news',
    'offer',
    'sponsor',
    'review',
    '.online'
]

# Added variables for minimum and maximum price
MINIMUM_PRICE = 2000
MAXIMUM_PRICE = float('inf')

# Define color variables for customization
SEARCH_STARTING_COLOR = 'yellow'
SEARCH_STARTING_BG_COLOR = None
SEARCH_QUERY_COLOR = 'green'
SEARCH_QUERY_BG_COLOR = None
FETCHING_URL_COLOR = 'yellow'
FETCHING_URL_BG_COLOR = None
FETCHING_URL_LINK_COLOR = 'cyan'
FETCHING_URL_LINK_BG_COLOR = None
PARSING_RESULTS_COLOR = 'cyan'
RESULTS_FOUND_COLOR = 'green'
NO_RESULTS_COLOR = 'red'
RESULT_NUMBER_COLOR = 'yellow'
RESULT_TITLE_COLOR = 'magenta'
RESULT_TITLE_BG_COLOR = None
RESULT_PRICE_COLOR = 'green'
RESULT_URL_COLOR = 'cyan'
RESULT_URL_BG_COLOR = None
MENU_COLOR = 'magenta'
WRITING_RESULTS_COLOR = 'blue'
RESULTS_WRITTEN_COLOR = 'green'
OPENING_URL_COLOR = 'green'
FAILED_URL_COLOR = 'red'
EXITING_COLOR = 'red'

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.212 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1 Safari/605.1.15",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 Edg/122.0.2365.92",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 OPR/108.0.0.0"
]

def clear_screen():
    """Clears the console screen."""
    os.system('cls' if os.name == 'nt' else 'clear')

def fetch_url_headless(url):
    """Fetches content from URL using a headless Chrome browser."""
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--window-size=1920,1080")
    chrome_options.add_argument("--disable-gpu")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")

    user_agent = random.choice(USER_AGENTS)
    chrome_options.add_argument(f"user-agent={user_agent}")

    driver = webdriver.Chrome(options=chrome_options)

    stealth(driver,
            languages=["en-US", "en"],
            vendor="Google Inc.",
            platform="Win32",
            webgl_vendor="Intel Inc.",
            renderer="Intel Iris OpenGL Engine",
            fix_hairline=True,
            )

    driver.get(url)

    time.sleep(random.uniform(1, 3))

    html_content = driver.page_source

    scroll_and_type(driver)

    driver.quit()
    return html_content

def fetch_url(url):
    """Fetches content from URL using requests with progress updates."""
    logger.info(colored("Fetching URL: ", FETCHING_URL_COLOR, 'on_' + FETCHING_URL_BG_COLOR if FETCHING_URL_BG_COLOR else None) + colored(url, FETCHING_URL_LINK_COLOR))
    response_html = fetch_url_headless(url)
    return response_html

def scroll_and_type(driver):
    """Performs random scrolling actions to mimic human behavior."""
    for _ in range(random.randint(1, 3)):
        scroll_amount = random.uniform(-0.5, 0.5)
        driver.execute_script("window.scrollBy(0, window.innerHeight * arguments[0]);", scroll_amount)
        time.sleep(random.uniform(0.5, 1.5))

def scroll_and_type(driver):
    """Performs random scrolling and typing actions to mimic human behavior."""
    for _ in range(random.randint(1, 3)):
        scroll_amount = random.uniform(-0.5, 0.5)
        driver.execute_script("window.scrollBy(0, window.innerHeight * arguments[0]);", scroll_amount)
        time.sleep(random.uniform(0.5, 1.5))

    try:
        search_box = WebDriverWait(driver, 10).until(
            EC.element_to_be_clickable((By.NAME, "q"))
        )
        random_text = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(5, 15)))
        search_box.send_keys(random_text)
        search_box.send_keys(Keys.ENTER)
        time.sleep(random.uniform(1, 3))
    except (NoSuchElementException, TimeoutException):
        pass

def parse_results(response, query):
    logger.info(colored("Parsing search results...", PARSING_RESULTS_COLOR))
    soup = BeautifulSoup(response, "lxml")
    search_results = soup.find_all("div", class_="yuRUbf")
    results = []

    lemmatized_exclude_words = [lemmatizer.lemmatize(word.lower()) for word in EXCLUDE_WORDS]

    for result in search_results:
        link_elem = result.find("a")
        if link_elem:
            url = link_elem.get("href")
            parsed_url = urlparse(url)
            title_elem = result.find("h3")
            title = title_elem.text.strip() if title_elem else ""
            full_text = title.lower() + " " + url.lower()
            lemmatized_text = [lemmatizer.lemmatize(word) for word in nltk.word_tokenize(full_text)]

            if parsed_url.netloc and "google" not in parsed_url.netloc:
                title_elem = result.find("h3")
                title = title_elem.text.strip() if title_elem else ""

                # Prepare the text for exclusion check
                check_text = title.lower() + " " + url.lower()

                # Use lemmatization for a more accurate exclusion check
                check_words = nltk.word_tokenize(check_text)
                lemmatized_words = [lemmatizer.lemmatize(word) for word in check_words]

                # Check for desired words
                contains_desired_word = any(lemmatizer.lemmatize(desired_word) in lemmatized_text for desired_word in DESIRED_WORDS)

                # Check against excluded words
                if not any(excluded_word in lemmatized_words for excluded_word in lemmatized_exclude_words):
                    price_text = result.parent.parent.parent.get_text()
                    price_matches = re.findall(r'\$\d+(?:,\d{3})*\.?\d*', price_text)

                    if price_matches:
                        price = price_matches[0].replace(',', '')
                        if price.endswith('.'):
                            price += '00'
                        elif '.' not in price:
                            price += '.00'
                        else:
                            dollars, cents = price.split('.')
                            if len(cents) == 1:
                                price += '0'

                        try:
                            price_float = float(price.replace('$', ''))
                        except ValueError:
                            continue  # Skip this result if the price cannot be converted to float

                        # Check if price is within the specified range
                        if MINIMUM_PRICE <= price_float <= MAXIMUM_PRICE:
                            results.append((title, url, price, contains_desired_word))
                    else:
                        price = "N/A"

    logger.info(colored(f"Found {len(results)} relevant results.", RESULTS_FOUND_COLOR))
    return results

def get_spelling_suggestion(response):
    """Extracts the spelling suggestion from Google's search results."""
    soup = BeautifulSoup(response, "lxml")
    suggestion_elem = soup.find("div", class_="gL9Hy")
    if suggestion_elem:
        return suggestion_elem.text
    return None

def search_google(query, desired_results=25):
    """Searches Google for the query until at least 25 results with prices are found or 300 results are reached."""
    logger.info(colored("Starting search for: ", SEARCH_STARTING_COLOR, 'on_' + SEARCH_STARTING_BG_COLOR if SEARCH_STARTING_BG_COLOR else None) +
                colored(query, SEARCH_QUERY_COLOR, 'on_' + SEARCH_QUERY_BG_COLOR if SEARCH_QUERY_BG_COLOR else None))
    results = []
    start = 0
    max_results = 300
    num_results_options = [50, 100, 150]  # List of numbers to randomly select from
    prev_num_results = None  # Variable to keep track of the previously used num_results

    while len(results) < desired_results and start < max_results:
        # Randomly select the number of results to fetch, ensuring it's different from the previous iteration
        num_results = random.choice([num for num in num_results_options if num != prev_num_results])
        prev_num_results = num_results  # Update the previous num_results

        encoded_query = quote_plus(query)
        url = f"https://www.google.com/search?q={encoded_query}&num={num_results}&start={start}"
        response = fetch_url(url)
        results.extend(parse_results(response, query))
        start += num_results

    if len(results) == 0:
        suggestion = get_spelling_suggestion(response)
        if suggestion:
            logger.info(colored(f"No results found. Did you mean: {suggestion}?", PARSING_RESULTS_COLOR))
            choice = input(colored("Enter 'y' to search for the suggested query or 'n' to continue: ", PARSING_RESULTS_COLOR))
            if choice.lower() == 'y':
                return search_google(suggestion, desired_results)
        else:
            logger.info(colored("No results found.", NO_RESULTS_COLOR))

    # Sort results based on prioritized words and price, excluding results with no price
    results.sort(key=lambda x: (not x[3], float(x[2].replace("$", "").replace(",", "")) if x[2] != "N/A" else float('inf')))

    # Filter out results with "N/A" prices
    results = [result for result in results if result[2] != "N/A"]

    return results[:desired_results]

def write_results_to_file(results, filepath):
    """Writes the search results to a specified file with progress updates."""
    logger.info(colored(f"Writing results to file: {filepath}", WRITING_RESULTS_COLOR))

    directory = os.path.dirname(filepath)
    if directory:
        os.makedirs(directory, exist_ok=True) # Create directory if it doesn't exist and is not empty

    with open(filepath, 'w') as file:
        for title, url, price, _ in results:
            file.write(f"Title: {title}\nURL: {url}\nPrice: {price}\n\n")

def display_menu(results, show_output_option):
    """Displays search results and prompts user for action with progress updates."""
    clear_screen()
    if not results:
        logger.info(colored("No results found.", NO_RESULTS_COLOR))
        sys.exit(0)

    print(colored(f"Search Results:", 'green', attrs=['bold']))
    print('-' * 80)  # Add a separator for visual clarity

    for i, (title, url, price, contains_desired_word) in enumerate(results, start=1):
        # Price display adjustment
        price_display = colored(price, RESULT_PRICE_COLOR) if price != "N/A" else colored("Price Not Available", RESULT_PRICE_COLOR)

        # Constructing the display strings
        result_number_display = colored(f"{i}.", RESULT_NUMBER_COLOR)
        title_display = f"{result_number_display} {title} - {price_display}"
        url_display = f"   {url}"

        # Printing the formatted strings
        print(colored(title_display, RESULT_TITLE_COLOR, 'on_' + RESULT_TITLE_BG_COLOR if RESULT_TITLE_BG_COLOR else None))
        print(colored(url_display, RESULT_URL_COLOR, 'on_' + RESULT_URL_BG_COLOR if RESULT_URL_BG_COLOR else None))
        print()  # Extra newline for better readability between entries

    print('-' * 80)  # End separator for visual clarity

    # Enhanced menu options display
    options = [
        "1. Enter the number(s) of the result(s) you wish to open (comma-separated or range)",
        "2. Enter 'o' to output the results to a file" if show_output_option else "2. Enter 'q' to quit",
        "3. Enter 'q' to quit" if show_output_option else None  # Only show this option if outputting is enabled
    ]

    print(colored("Options:", 'yellow', attrs=['bold']))
    for option in filter(None, options):  # Filter out any None values in case the last option is not needed
        print(option)

    choice = input(colored("\nEnter your choice: ", MENU_COLOR))
    return choice

def handle_selection(choice, results, show_output_option):
    """Processes the user's selection to open URLs or exit with progress updates."""
    if choice.lower() == 'q':
        logger.info(colored("Exiting...", EXITING_COLOR))
        sys.exit(0)
    elif choice.lower() == 'o' and show_output_option:
        filepath = input(colored("Enter the output file path: ", WRITING_RESULTS_COLOR))
        write_results_to_file(results, filepath)
        logger.info(colored(f"Results written to {filepath}", RESULTS_WRITTEN_COLOR))
        # Clear the screen and re-display the menu
        clear_screen()
        choice = display_menu(results, show_output_option)
        handle_selection(choice, results, show_output_option)
    else:
        indices = []
        for part in choice.split(','):
            if '-' in part:
                start, end = map(int, part.split('-'))
                indices.extend(range(start - 1, end))
            else:
                indices.append(int(part) - 1)

        for index in indices:
            if 0 <= index < len(results):
                try:
                    subprocess.Popen([BROWSER, results[index][1]])
                    logger.info(colored(f"Opening: {results[index][1]}", OPENING_URL_COLOR))
                    time.sleep(1)  # Add a 1-second delay between opening each URL
                except Exception as e:
                    logger.error(colored(f"Failed to open URL: {e}", FAILED_URL_COLOR))

def main():
    parser = argparse.ArgumentParser(description="Search Google and fetch results with prices.")
    parser.add_argument("query", type=str, help="Search query")
    parser.add_argument("-o", "--output", type=str, help="Output file path for search results", default="")
    parser.add_argument("-min", "--min-price", type=float, help="Minimum price for results (default: 0)", default=0)
    parser.add_argument("-max", "--max-price", type=float, help="Maximum price for results (default: infinity)", default=float('inf'))
    args = parser.parse_args()

    global MINIMUM_PRICE, MAXIMUM_PRICE
    MINIMUM_PRICE = args.min_price
    MAXIMUM_PRICE = args.max_price

    results = search_google(args.query)
    show_output_option = not bool(args.output)

    if args.output:
        write_results_to_file(results, args.output)
        logger.info(colored(f"Results written to {args.output}", RESULTS_WRITTEN_COLOR))

    while True:
        choice = display_menu(results, show_output_option)
        handle_selection(choice, results, show_output_option)

if __name__ == "__main__":
    main()
