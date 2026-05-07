#!/usr/bin/env bash

# GitHub:
# Purpose: Crawl webpages and output to results.txt
# Updated: 06.22.24

# Function to prompt the user for input
prompt() {
    local prompt_text=$1
    local variable_name=$2
    local default_value=$3
    local user_input

    if [ -n "$default_value" ]; then
        read -p "$prompt_text ($default_value): " user_input
        eval "$variable_name=\"${user_input:-$default_value}\""
    else
        read -p "$prompt_text: " user_input
        eval "$variable_name=\"$user_input\""
    fi
}

# Prompt user for inputs
prompt "Enter the Scrapy project name (letters, numbers, and underscores only)" project_name
prompt "Enter the initial URL to start scraping (e.g., http://example.com)" start_url
prompt "Enter the output file name (e.g., results.json)" output_file "results.json"

# Create info_spider.py
cat > info_spider.py << EOL
import scrapy
from scrapy.crawler import CrawlerProcess
from scrapy.utils.project import get_project_settings
import random
import time

class InfoSpider(scrapy.Spider):
    name = 'info_spider'
    start_urls = ['$start_url']
    
    user_agents = [
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Firefox/89.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.1 Safari/605.1.15'
    ]

    custom_settings = {
        'ROBOTSTXT_OBEY': False,
        'DOWNLOAD_DELAY': 5,
        'CONCURRENT_REQUESTS': 1,
        'RETRY_TIMES': 3,
        'RETRY_HTTP_CODES': [401, 403, 429, 500, 502, 503, 504],
    }

    def start_requests(self):
        for url in self.start_urls:
            yield scrapy.Request(url,
                                 callback=self.parse,
                                 headers={
                                     'User-Agent': random.choice(self.user_agents),
                                     'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
                                     'Accept-Language': 'en-US,en;q=0.5',
                                     'Referer': 'https://www.google.com/',
                                 },
                                 dont_filter=True
                                )

    def parse(self, response):
        if response.status == 401:
            self.logger.error(f"Received 401 Unauthorized for {response.url}")
            return
        page_title = response.xpath('//title/text()').get()
        headings = response.xpath('//h1/text() | //h2/text() | //h3/text()').getall()
        links = response.xpath('//a/@href').getall()
        yield {
            'url': response.url,
            'title': page_title,
            'headings': headings,
            'links': links
        }
        for link in links:
            if link.startswith('http'):
                time.sleep(random.uniform(1, 3))
                yield response.follow(link,
                                      self.parse,
                                      headers={'User-Agent': random.choice(self.user_agents)},
                                      dont_filter=True
                                     )

if __name__ == "__main__":
    process = CrawlerProcess(settings={
        'FEEDS': {
            '$output_file': {
                'format': 'json',
                'encoding': 'utf8',
                'store_empty': False,
                'indent': 4,
            },
        },
    })
    process.crawl(InfoSpider)
    process.start()
EOL

echo "info_spider.py has been created with the specified content."
echo "Project name: $project_name"
echo "Start URL: $start_url"
echo "Output file: $output_file"
