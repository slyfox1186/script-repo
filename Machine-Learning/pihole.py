#!/usr/bin/env python3

import argparse
import gc
import logging
import numpy as np
import os
import pandas as pd
import psutil
import re
import sqlite3
import sys
import time
from difflib import SequenceMatcher
from sklearn.cluster import DBSCAN
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from tqdm import tqdm

# Setup logging
def setup_logging(log_file=None):
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)

    formatter = logging.Formatter('%(message)s')

    # Console handler
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    # File handler
    if log_file:
        fh = logging.FileHandler(log_file)
        fh.setLevel(logging.INFO)
        fh.setFormatter(formatter)
        logger.addHandler(fh)

def check_and_prompt_for_db_paths(ftl_default_path, gravity_default_path):
    """Check if the default Pi-hole database files exist, if not, prompt the user for paths."""
    if not os.path.exists(ftl_default_path):
        print_and_log(f"FTL database file not found at {ftl_default_path}")
        ftl_db_path = input("Please enter the path to the Pi-hole FTL database file: ")
    else:
        ftl_db_path = ftl_default_path

    if not os.path.exists(gravity_default_path):
        print_and_log(f"Gravity database file not found at {gravity_default_path}")
        gravity_db_path = input("Please enter the path to the Pi-hole gravity database file: ")
    else:
        gravity_db_path = gravity_default_path

    return ftl_db_path, gravity_db_path

def calculate_similarity(file1, file2):
    """Calculate the similarity percentage between two text files."""
    with open(file1, 'r') as f1, open(file2, 'r') as f2:
        file1_data = f1.read()
        file2_data = f2.read()
    
    similarity = SequenceMatcher(None, file1_data, file2_data).ratio()
    return similarity * 100

def compare_databases(original_path, new_path, threshold=95.0):
    """Compare two database files and check if they match by a certain percentage."""
    similarity = calculate_similarity(original_path, new_path)
    return similarity >= threshold, similarity

def print_and_log(message, group=False):
    if group:
        print("\n", end="")
    print(message)
    logging.info(message)
    if group:
        print("\n", end="")

# Function to load the Pi-hole database
def load_database(db_path, table, column):
    """Load the Pi-hole database and return a DataFrame with the domain list."""
    try:
        conn = sqlite3.connect(db_path)
        if table == "queries":
            query = f"SELECT domain FROM query_storage"
        else:
            query = f"SELECT {column} FROM {table}"
        df = pd.read_sql_query(query, conn)
        conn.close()
        return df
    except Exception as e:
        logging.error(f"Error loading database {db_path}, table {table}: {e}")
        return None

# Function to initialize the history database
def initialize_history_database(history_db_path):
    """Initialize the history database with necessary tables if they don't exist."""
    try:
        conn = sqlite3.connect(history_db_path)
        cursor = conn.cursor()
        cursor.execute("CREATE TABLE IF NOT EXISTS optimized_domains (domain TEXT PRIMARY KEY)")
        conn.commit()
        conn.close()
    except Exception as e:
        logging.error(f"Error initializing history database {history_db_path}: {e}")

# Function to load the history database
def load_history_database(history_db_path):
    """Load the history database and return a DataFrame with the optimized domain list."""
    try:
        conn = sqlite3.connect(history_db_path)
        query = "SELECT domain FROM optimized_domains"
        df = pd.read_sql_query(query, conn)
        conn.close()
        return df
    except Exception as e:
        logging.error(f"Error loading history database {history_db_path}: {e}")
        return None

# Function to clean domain data
def clean_domains(domains):
    valid_domains = []
    for domain in domains:
        if domain and isinstance(domain, str) and not any(char.isdigit() for char in domain.split('.')[-1]):
            valid_domains.append(domain)
    return valid_domains

def create_cosine_similarity_matrix(data):
    # Check and handle negative values in data
    data = check_negative_values(data)
    
    try:
        logging.info(f"Cosine similarity matrix shape: {data.shape}")
        similarity_matrix = cosine_similarity(data)
        return similarity_matrix
    except ValueError as e:
        logging.error(f"Error creating cosine similarity matrix: {e}")
        return None

def initialize_progress_database(progress_db_path):
    conn = sqlite3.connect(progress_db_path)
    cursor = conn.cursor()
    cursor.execute('''CREATE TABLE IF NOT EXISTS progress
                      (id INTEGER PRIMARY KEY, 
                       database TEXT, 
                       chunk_start INTEGER, 
                       chunk_end INTEGER, 
                       completed INTEGER)''')
    conn.commit()
    conn.close()

def save_chunk_progress(progress_db_path, database, chunk_start, chunk_end, completed):
    conn = sqlite3.connect(progress_db_path)
    cursor = conn.cursor()
    cursor.execute('''INSERT OR REPLACE INTO progress 
                      (database, chunk_start, chunk_end, completed) 
                      VALUES (?, ?, ?, ?)''', 
                   (database, chunk_start, chunk_end, completed))
    conn.commit()
    conn.close()

def get_last_completed_chunk(progress_db_path, database):
    conn = sqlite3.connect(progress_db_path)
    cursor = conn.cursor()
    cursor.execute('''SELECT MAX(chunk_end) FROM progress 
                      WHERE database = ? AND completed = 1''', (database,))
    result = cursor.fetchone()[0]
    conn.close()
    return result if result is not None else 0

def create_tfidf_matrix(valid_domains, chunk_size):
    """Create TF-IDF matrix with a progress bar and memory management."""
    vectorizer = TfidfVectorizer(analyzer='char', ngram_range=(2, 3), max_features=10000)
    tfidf_list = []

    for i in tqdm(range(0, len(valid_domains), chunk_size), desc="Creating TF-IDF matrix"):
        chunk = valid_domains[i:i+chunk_size]
        tfidf_chunk = vectorizer.fit_transform(chunk)
        tfidf_list.append(tfidf_chunk)
        del tfidf_chunk  # Free memory
        gc.collect()  # Collect garbage
    
    tfidf_matrix = np.vstack(tfidf_list)
    del tfidf_list  # Free memory
    gc.collect()  # Collect garbage
    return tfidf_matrix

def create_regex_patterns(domains, eps=0.5, min_samples=2, chunk_size=1000, progress_db_path=None, database_name=None):
    try:
        start_time = time.time()
        print_and_log("Starting create_regex_patterns function", group=True)
        
        cleaned_domains = clean_domains(domains)
        valid_domains = [domain for domain in cleaned_domains if isinstance(domain, str) and domain.strip()]
        
        print_and_log(f"Valid domains count: {len(valid_domains)}", group=True)
        
        if not valid_domains:
            logging.error("No valid domains to process.")
            return []

        print_and_log("Creating TF-IDF matrix...", group=True)
        tfidf_matrix = create_tfidf_matrix(valid_domains, chunk_size)
        print_and_log(f"TF-IDF matrix shape: {tfidf_matrix.shape}", group=True)
        
        print_and_log("Computing cosine similarity in chunks...", group=True)
        clusters = {}
        cluster_id = 0
        
        for i in tqdm(range(0, tfidf_matrix.shape[0], chunk_size), desc="Processing chunks"):
            chunk = tfidf_matrix[i:i+chunk_size]
            
            sim_chunk = cosine_similarity(chunk, chunk)
            sim_chunk = np.clip(sim_chunk, 0, 1)  # Clip values to [0, 1] range
            dist_chunk = 1 - sim_chunk
            
            chunk_clustering = DBSCAN(eps=eps, min_samples=min_samples, metric='precomputed', n_jobs=-1).fit(dist_chunk)
            
            for idx, label in enumerate(chunk_clustering.labels_):
                if label == -1 or label not in clusters:
                    clusters[cluster_id] = [valid_domains[i + idx]]
                    cluster_id += 1
                else:
                    clusters[label].append(valid_domains[i + idx])

            if progress_db_path:
                save_chunk_progress(progress_db_path, database_name, i, i+chunk_size, 1)

            del chunk, sim_chunk, dist_chunk, chunk_clustering  # Free memory
            gc.collect()  # Collect garbage

        print_and_log(f"Created {len(clusters)} clusters", group=True)

        print_and_log("Creating regex patterns...", group=True)
        regex_patterns = []
        for cluster in tqdm(clusters.values(), desc="Creating regex patterns"):
            if len(cluster) > 1:
                regex_pattern = '|'.join([re.escape(domain) for domain in cluster])
                regex_patterns.append(f"({regex_pattern})")
            else:
                regex_patterns.append(cluster[0])

        end_time = time.time()
        print_and_log(f"Created {len(regex_patterns)} regex patterns", group=True)
        print_and_log(f"Total time for create_regex_patterns: {end_time - start_time:.2f} seconds", group=True)
        return regex_patterns
    except Exception as e:
        logging.error(f"Error creating regex patterns: {e}")
        return []

def save_gravity_database(df, db_path):
    """Save the optimized domain list back to the Pi-hole gravity database."""
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        cursor.execute('''CREATE TABLE IF NOT EXISTS domainlist
                          (id INTEGER PRIMARY KEY, type INTEGER,
                           domain TEXT, enabled BOOLEAN,
                           date_added INTEGER, date_modified INTEGER,
                           comment TEXT)''')
        cursor.execute("DELETE FROM domainlist")
        records = [(None, 1, domain, 1, int(time.time()), int(time.time()), '') for domain in df['domain']]
        cursor.executemany("INSERT INTO domainlist (id, type, domain, enabled, date_added, date_modified, comment) VALUES (?, ?, ?, ?, ?, ?, ?)", records)
        
        conn.commit()
        conn.close()
        logging.info(f"Successfully saved {len(df)} domains to {db_path}, table domainlist")
    except Exception as e:
        logging.error(f"Error saving database {db_path}, table domainlist: {e}")

def save_ftl_database(df, db_path):
    """Save the optimized domain list back to the Pi-hole FTL database."""
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        cursor.execute('''CREATE TABLE IF NOT EXISTS query_storage
                          (id INTEGER PRIMARY KEY, timestamp INTEGER,
                           type INTEGER, status INTEGER, domain TEXT,
                           client INTEGER, forward INTEGER,
                           additional_info INTEGER, reply_type INTEGER,
                           reply_time REAL, dnssec INTEGER)''')
        cursor.execute("DELETE FROM query_storage")
        records = [(None, int(time.time()), 1, 2, domain, 0, 0, 0, 0, 0.0, 0) for domain in df['domain']]
        cursor.executemany("INSERT INTO query_storage (id, timestamp, type, status, domain, client, forward, additional_info, reply_type, reply_time, dnssec) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", records)
        
        conn.commit()
        conn.close()
        logging.info(f"Successfully saved {len(df)} domains to {db_path}, table query_storage")
    except Exception as e:
        logging.error(f"Error saving database {db_path}, table query_storage: {e}")

def save_history_database(df, history_db_path):
    """Save the optimized domains to the history database."""
    try:
        conn = sqlite3.connect(history_db_path)
        cursor = conn.cursor()
        
        # Batch insertion
        records = [(domain,) for domain in df['domain']]
        cursor.executemany("INSERT OR IGNORE INTO optimized_domains (domain) VALUES (?)", records)
        
        conn.commit()
        conn.close()
    except Exception as e:
        logging.error(f"Error saving to history database {history_db_path}: {e}")

def display_help():
    """Display the help menu with available options."""
    help_text = """
    Pi-hole Database Optimizer

    This script optimizes the Pi-hole databases by merging similar domains into regex patterns,
    removing duplicates, and improving hit rates.

    Usage:
        optimize_pihole_db.py [options]

    Options:
        -h, --help          Show this help message and exit
        -d, --database      Path to the Pi-hole FTL database file (default: pihole-FTL.db)
        -g, --gravity       Path to the Pi-hole gravity database file (default: gravity.db)
        -e, --eps           Epsilon parameter for DBSCAN (default: 0.5)
        -m, --min_samples   Minimum samples parameter for DBSCAN (default: 2)
        -y, --history       Path to the history database file (default: history.db)
        -l, --log           Path to the log file (optional)
        -o, --output        Output directory for optimized databases (default: current directory)
        -c, --chunk_size    Chunk size to use for processing (default: 1000)
        -p, --progress      Path to the progress database file (default: progress.db)

    Example:
        ./optimize_pihole_db.py -d /path/to/pihole-FTL.db -g /path/to/gravity.db -e 0.5 -m 2 -y /path/to/history.db -l /path/to/logfile.log -o /path/to/output -c 1000
    """
    print(help_text)

def kill_prior_running_processes(script_name):
    """Kill any prior instances of this script that are still running."""
    current_pid = os.getpid()
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if proc.info['cmdline'] and len(proc.info['cmdline']) > 1 and script_name in proc.info['cmdline'][1]:
                if proc.info['pid'] != current_pid:
                    logging.info(f"Killing prior process {proc.info['pid']}")
                    proc.kill()
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess) as e:
            logging.warning(f"Failed to kill process {proc.info['pid']}: {e}")
            continue

# Main function
def main():
    parser = argparse.ArgumentParser(description="Pi-hole Database Optimizer", add_help=False)
    parser.add_argument('-d', '--database', type=str, default='/etc/pihole/pihole-FTL.db', help='Path to the Pi-hole FTL database file')
    parser.add_argument('-g', '--gravity', type=str, default='/etc/pihole/gravity.db', help='Path to the Pi-hole gravity database file')
    parser.add_argument('-e', '--eps', type=float, default=0.5, help='Epsilon parameter for DBSCAN')
    parser.add_argument('-m', '--min_samples', type=int, default=2, help='Minimum samples parameter for DBSCAN')
    parser.add_argument('-y', '--history', type=str, default='history.db', help='Path to the history database file')
    parser.add_argument('-l', '--log', type=str, help='Path to the log file (optional)')
    parser.add_argument('-o', '--output', type=str, default='.', help='Output directory for optimized databases')
    parser.add_argument('-c', '--chunk_size', type=int, default=1000, help='Chunk size for processing')
    parser.add_argument('-p', '--progress', type=str, default='progress.db', help='Path to the progress database file')
    parser.add_argument('-h', '--help', action='store_true', help='Show help message and exit')

    args = parser.parse_args()

    if args.help:
        display_help()
        return

    setup_logging(args.log)

    ftl_db_path, gravity_db_path = check_and_prompt_for_db_paths(args.database, args.gravity)
    eps = args.eps
    min_samples = args.min_samples
    history_db_path = args.history
    output_dir = args.output
    chunk_size = args.chunk_size
    progress_db_path = args.progress

    os.makedirs(output_dir, exist_ok=True)

    if not os.access(output_dir, os.W_OK):
        logging.error(f"No write permission for output directory: {output_dir}")
        return

    for db_path in [ftl_db_path, gravity_db_path]:
        if not os.path.exists(db_path):
            logging.error(f"Input database does not exist: {db_path}")
            return
        if not os.access(db_path, os.R_OK):
            logging.error(f"No read permission for input database: {db_path}")
            return

    ftl_output_path = os.path.join(output_dir, os.path.basename(ftl_db_path))
    gravity_output_path = os.path.join(output_dir, os.path.basename(gravity_db_path))

    for db_path in [ftl_output_path, gravity_output_path]:
        if os.path.exists(db_path):
            os.remove(db_path)
            logging.info(f"Removed existing output database: {db_path}")

    initialize_progress_database(progress_db_path)

    print_and_log("Initializing history database...", group=True)
    initialize_history_database(history_db_path)

    print_and_log("Loading history database...", group=True)
    history_df = load_history_database(history_db_path)

    print_and_log("Loading Pi-hole databases...", group=True)
    df_ftl = load_database(ftl_db_path, "query_storage", "domain")
    if df_ftl is None or df_ftl.empty:
        logging.error("Failed to load FTL database or database is empty. Exiting.")
        return

    df_gravity = load_database(gravity_db_path, "domainlist", "domain")
    if df_gravity is None or df_gravity.empty:
        logging.error("Failed to load gravity database or database is empty. Exiting.")
        return

    print_and_log(f"Loaded {len(df_ftl)} domains from FTL database and {len(df_gravity)} domains from gravity database.", group=True)

    print_and_log("Optimizing databases...", group=True)
    try:
        optimized_ftl_df = optimize_database(df_ftl, history_df, eps, min_samples, chunk_size, progress_db_path, "ftl")
        optimized_gravity_df = optimize_database(df_gravity, history_df, eps, min_samples, chunk_size, progress_db_path, "gravity")
    except Exception as e:
        logging.error(f"Error during optimization: {e}")
        return

    if optimized_ftl_df.empty or optimized_gravity_df.empty:
        logging.error("Optimization failed for one or more databases. Exiting.")
        return

    print_and_log(f"Optimization complete. FTL database: {len(df_ftl)} -> {len(optimized_ftl_df)} domains. Gravity database: {len(df_gravity)} -> {len(optimized_gravity_df)} domains.", group=True)

    print_and_log("Saving optimized databases...", group=True)
    try:
        save_ftl_database(optimized_ftl_df, ftl_output_path)
        save_gravity_database(optimized_gravity_df, gravity_output_path)
        save_history_database(optimized_ftl_df, history_db_path)
        save_history_database(optimized_gravity_df, history_db_path)
    except Exception as e:
        logging.error(f"Error saving optimized databases: {e}")
        return

    print_and_log("Database optimization complete.", group=True)
    print_and_log(f"Optimized FTL database saved to: {ftl_output_path}", group=True)
    print_and_log(f"Optimized gravity database saved to: {gravity_output_path}", group=True)
    print_and_log(f"History database updated: {history_db_path}", group=True)

    print_and_log("Comparing original and optimized databases...", group=True)

    ftl_comparison_pass, ftl_similarity = compare_databases(ftl_db_path, ftl_output_path)
    gravity_comparison_pass, gravity_similarity = compare_databases(gravity_db_path, gravity_output_path)

    if ftl_comparison_pass:
        print_and_log(f"FTL database comparison passed with {ftl_similarity:.2f}% similarity.", group=True)
    else:
        print_and_log(f"FTL database comparison failed with {ftl_similarity:.2f}% similarity.", group=True)

    if gravity_comparison_pass:
        print_and_log(f"Gravity database comparison passed with {gravity_similarity:.2f}% similarity.", group=True)
    else:
        print_and_log(f"Gravity database comparison failed with {gravity_similarity:.2f}% similarity.", group=True)

if __name__ == "__main__":
    script_name = os.path.basename(__file__)
    kill_prior_running_processes(script_name)
    time.sleep(2)  # Ensure previous instances are properly killed
    main()
