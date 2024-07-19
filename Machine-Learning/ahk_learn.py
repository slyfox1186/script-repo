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
import logging
from typing import List, Tuple
import concurrent.futures

DATABASE_PATH = 'ahk_learned_data.db'
MODEL_PATH = 'ahk_model.pkl'
LOG_FILE = 'ahk_analyzer.log'

# Set up logging
logging.basicConfig(filename=LOG_FILE, level=logging.INFO, 
                    format='%(asctime)s - %(levelname)s - %(message)s')

def read_extracted_files(directory: str) -> List[str]:
    content = []
    html_files = glob.glob(os.path.join(directory, '**/*.htm'), recursive=True) + \
                 glob.glob(os.path.join(directory, '**/*.html'), recursive=True)
    if not html_files:
        logging.warning(f"No HTML or HTM files found in {directory}. Please ensure the CHM extraction is correct.")
        return content

    def process_file(file_path: str) -> str:
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                soup = BeautifulSoup(file, 'html.parser')
                return soup.get_text(separator=' ', strip=True)
        except Exception as e:
            logging.error(f"Error processing file {file_path}: {str(e)}")
            return ""

    with concurrent.futures.ThreadPoolExecutor() as executor:
        content = list(filter(None, executor.map(process_file, html_files)))

    return content

def store_in_database(content: List[str], db_path: str = DATABASE_PATH) -> None:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute('''CREATE TABLE IF NOT EXISTS BestPractices (
                        id INTEGER PRIMARY KEY,
                        content TEXT
                      )''')
    
    cursor.executemany('INSERT INTO BestPractices (content) VALUES (?)', [(c,) for c in content])
    
    conn.commit()
    conn.close()
    logging.info(f"Stored {len(content)} entries in the database")

def database_exists(db_path: str = DATABASE_PATH) -> bool:
    if not os.path.exists(db_path):
        return False
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('SELECT COUNT(*) FROM BestPractices')
    count = cursor.fetchone()[0]
    conn.close()
    return count > 0

def train_model(content: List[str], model_path: str = MODEL_PATH) -> None:
    vectorizer = TfidfVectorizer(max_features=1000)
    model = KMeans(n_clusters=5, n_init=10)
    pipeline = make_pipeline(vectorizer, model)
    
    pipeline.fit(content)
    joblib.dump(pipeline, model_path)
    logging.info(f"Model trained and saved to {model_path}")

def analyze_ahk_script(script_path: str, model_path: str = MODEL_PATH) -> List[str]:
    try:
        with open(script_path, 'r', encoding='utf-8') as file:
            script_content = file.read()
    except Exception as e:
        logging.error(f"Error reading script file {script_path}: {str(e)}")
        return [f"Error reading script file: {str(e)}"]
    
    issues = []
    lines = script_content.split('\n')
    
    for i, line in enumerate(lines):
        line = line.strip()
        if '::' in line and not line.startswith(';'):
            parts = line.split('::')
            if len(parts) != 2 or 'Up' in parts[0]:
                issues.append(f"Line {i+1}: Possibly malformed hotkey definition: {line}")
        elif line.startswith('if') and not line.endswith('{'):
            issues.append(f"Line {i+1}: 'if' statement should end with a curly brace in AHK v2: {line}")
        elif 'SetWorkingDir' not in script_content:
            issues.append("Consider adding 'SetWorkingDir A_ScriptDir' at the beginning of your script for better file handling")
            break

    # Use the trained model to suggest improvements (placeholder for now)
    # TODO: Implement model-based suggestions

    if not issues:
        logging.info(f"No issues found during analysis of {script_path}")
    else:
        logging.info(f"Detected {len(issues)} issues in {script_path}")

    return issues

def list_topics(db_path: str = DATABASE_PATH) -> List[Tuple[int, str]]:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute('SELECT id, content FROM BestPractices')
    topics = cursor.fetchall()
    
    conn.close()
    
    topic_list = []
    for id, content in topics:
        title = content.split('|')[0].strip() if '|' in content else f"Topic {id}"
        topic_list.append((id, title))
    
    return topic_list

def display_learned_content(db_path: str = DATABASE_PATH) -> None:
    topics = list_topics(db_path)
    
    if not topics:
        print("No topics found in the database.")
        return

    while True:
        print("\nAvailable topics:")
        for id, title in topics:
            print(f"{id}. {title}")
        
        choice = input("\nEnter the number of the topic you want to explore (or 'q' to quit): ")
        if choice.lower() == 'q':
            break
        
        try:
            topic_id = int(choice)
            selected_topic = next((t for t in topics if t[0] == topic_id), None)
            if not selected_topic:
                print("Invalid topic number. Please try again.")
                continue
        except ValueError:
            print("Invalid input. Please enter a number or 'q' to quit.")
            continue

        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute('SELECT content FROM BestPractices WHERE id = ?', (topic_id,))
        content = cursor.fetchone()[0]
        conn.close()

        title = content.split('|')[0].strip()
        description = content.split('|')[1].strip() if '|' in content else content

        print(f"\n{title}")
        print("=" * len(title))
        print(f"Description: {description}\n")

        # Extract key points
        key_points = re.findall(r'•\s*(.*?)(?:\n|$)', content)
        if key_points:
            print("Key Points:")
            for point in key_points:
                print(f"  • {point.strip()}")

        # Extract code examples
        code_examples = re.findall(r'```autohotkey(.*?)```', content, re.DOTALL)
        if code_examples:
            print("\nCode Examples:")
            for i, example in enumerate(code_examples, 1):
                print(f"\nExample {i}:")
                print(example.strip())

        print("\nPress Enter to return to the topic list...")
        input()

def main() -> None:
    extracted_directory = input("Please enter the directory where the CHM file has been manually extracted: ")

    if not database_exists():
        logging.info("Database not found or empty. Reading and processing extracted files...")
        content = read_extracted_files(extracted_directory)
        
        if not content:
            logging.error("No content extracted. Please check the CHM extraction process.")
            return
        
        store_in_database(content)
        train_model(content)
    else:
        logging.info("Database found. Skipping file extraction and model training.")
    
    while True:
        user_input = input("\nEnter the path to an AutoHotkey v2 script, type 'learned' to see what was learned, or 'quit' to exit: ")
        if user_input.lower() == 'quit':
            break
        elif user_input.lower() == 'learned':
            display_learned_content()
            continue

def main() -> None:
    extracted_directory = input("Please enter the directory where the CHM file has been manually extracted: ")

    if not database_exists():
        logging.info("Database not found or empty. Reading and processing extracted files...")
        content = read_extracted_files(extracted_directory)
        
        if not content:
            logging.error("No content extracted. Please check the CHM extraction process.")
            return
        
        store_in_database(content)
        train_model(content)
    else:
        logging.info("Database found. Skipping file extraction and model training.")
    
    while True:
        user_input = input("\nEnter the path to an AutoHotkey v2 script, type 'learned' to see what was learned, or 'quit' to exit: ")
        if user_input.lower() == 'quit':
            break
        elif user_input.lower() == 'learned':
            display_learned_content()
            continue
        
        script_path = user_input
        
        if not os.path.exists(script_path):
            logging.warning(f"File not found: {script_path}")
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
    logging.info("Program terminated normally")

if __name__ == "__main__":
    main()
