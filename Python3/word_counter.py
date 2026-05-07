#!/usr/bin/env python3

import sys
from collections import Counter

def count_words(file_path):
    try:
        with open(file_path, 'r') as file:
            text = file.read().lower()
            words = text.split()
            word_count = Counter(words)
        
        for word, count in word_count.items():
            print(f"{word}: {count}")
    except Exception as e:
        print(f"Error: {e}")

def main():
    if len(sys.argv) != 2:
        print_help()
        sys.exit(1)

    file_path = sys.argv[1]

    if not os.path.isfile(file_path):
        print("Error: File does not exist.")
        sys.exit(1)

    count_words(file_path)

def print_help():
    print("Usage: count_words.py <file_path>")
    print("Counts the occurrences of each word in the specified text file.")
    print("Arguments:")
    print("  <file_path> Path to the text file to count words in")

if __name__ == "__main__":
    main()
