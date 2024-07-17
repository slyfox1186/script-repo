#!/usr/bin/env python3

import os
import re
import glob
import sqlite3
from bs4 import BeautifulSoup
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.cluster import KMeans
from sklearn.pipeline import make_pipeline
import joblib

DATABASE_PATH = 'ahk_learned_data.db'
MODEL_PATH = 'ahk_model.pkl'

# Read and process the extracted HTML files
def read_extracted_files(directory):
    content = []
    html_files = glob.glob(os.path.join(directory, '**/*.htm'), recursive=True) + \
                 glob.glob(os.path.join(directory, '**/*.html'), recursive=True)
    if not html_files:
        print(f"No HTML or HTM files found in {directory}. Please ensure the CHM extraction is correct.")
        return content

    for file_path in html_files:
        with open(file_path, 'r', encoding='utf-8') as file:
            soup = BeautifulSoup(file, 'html.parser')
            text = soup.get_text(separator=' ', strip=True)
            if text:  # Ensure the text is not empty
                content.append(text)
    return content

# Store results in a database
def store_in_database(content, db_path=DATABASE_PATH):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute('''CREATE TABLE IF NOT EXISTS BestPractices (
                        id INTEGER PRIMARY KEY,
                        content TEXT
                      )''')
    
    cursor.executemany('INSERT INTO BestPractices (content) VALUES (?)', [(c,) for c in content])
    
    conn.commit()
    conn.close()

# Check if the database already exists and has content
def database_exists(db_path=DATABASE_PATH):
    if not os.path.exists(db_path):
        return False
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('SELECT COUNT(*) FROM BestPractices')
    count = cursor.fetchone()[0]
    conn.close()
    return count > 0

# Train the machine learning model
def train_model(content, model_path=MODEL_PATH):
    vectorizer = TfidfVectorizer()
    model = KMeans(n_clusters=5)  # Adjust the number of clusters as needed
    pipeline = make_pipeline(vectorizer, model)
    
    pipeline.fit(content)
    joblib.dump(pipeline, model_path)
    print("Model trained and saved to", model_path)

# Analyze AHK Script
def analyze_ahk_script(script_path, model_path=MODEL_PATH):
    with open(script_path, 'r', encoding='utf-8') as file:
        script_content = file.read()
    
    issues = []
    lines = script_content.split('\n')
    
    for i, line in enumerate(lines):
        if '::' in line and not line.strip().startswith(';'):
            parts = line.split('::')
            if len(parts) != 2 or 'Up' in parts[0]:
                issues.append(f"Line {i+1}: Possibly malformed hotkey definition: {line.strip()}")
        elif line.strip().startswith('if') and not line.strip().endswith('{'):
            issues.append(f"Line {i+1}: 'if' statement should end with a curly brace in AHK v2: {line.strip()}")

    if not issues:
        print("No issues found during analysis.")
    else:
        print(f"Detected issues: {len(issues)}")
        for issue in issues:
            print(issue)

    return issues

# Function to display learned content from the database
def display_learned_content(db_path=DATABASE_PATH):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute('SELECT content FROM BestPractices')
    best_practices = cursor.fetchall()
    
    conn.close()
    
    if not best_practices:
        print("No best practices found in the database.")
    else:
        print(f"Learned best practices from scanned CHM/HTML files:")
        for i, practice in enumerate(best_practices, 1):
            print(f"{i}. {practice[0]}")

# Main Function
def main():
    extracted_directory = input("Please enter the directory where the CHM file has been manually extracted: ")

    if not database_exists():
        print("Database not found or empty. Reading and processing extracted files...")
        content = read_extracted_files(extracted_directory)
        
        if not content:
            print("No content extracted. Please check the CHM extraction process.")
            return
        
        # Store results in a database
        store_in_database(content)
        
        # Train the machine learning model
        train_model(content)
    else:
        print("Database found. Skipping file extraction and model training.")
    
    while True:
        user_input = input("\nEnter the path to an AutoHotkey v2 script, type 'learned' to see what was learned, or 'quit' to exit: ")
        if user_input.lower() == 'quit':
            break
        elif user_input.lower() == 'learned':
            display_learned_content()
            continue
        
        script_path = user_input
        
        if not os.path.exists(script_path):
            print("File not found. Please enter a valid file path.")
            continue
        
        issues = analyze_ahk_script(script_path)
        
        if not issues:
            print("\nNo issues or specific best practices found in the script.")
        else:
            print("\nIssues detected:")
            for issue in issues:
                print(issue)
        
        analyze_another = input("\nWould you like to analyze another script? (yes/no): ").strip().lower()
        if analyze_another != 'yes':
            break

    print("\nThank you for using the AutoHotkey v2 Script Analyzer. Goodbye!")

if __name__ == "__main__":
    main()
