#!/usr/bin/env python3

import os
import sqlite3
import pandas as pd
from sklearn.cluster import KMeans
import click
from transformers import pipeline
import subprocess
import sys
import matplotlib.pyplot as plt
import logging
from tqdm import tqdm

# Configuration
DATABASE_PATH = "/etc/pihole/gravity.db"
RESULTS_DB_PATH = "/etc/pihole/results.db"
NLP_MODEL = "distilbert-base-uncased-finetuned-sst-2-english"
N_CLUSTERS = 3

# Initialize logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger()

# Initialize NLP pipeline
logger.info("Initializing NLP pipeline...")
try:
    nlp = pipeline("sentiment-analysis", model=NLP_MODEL)
    logger.info("NLP pipeline initialized successfully.")
except Exception as e:
    logger.error(f"Failed to initialize NLP pipeline: {e}")
    sys.exit(1)

def connect_db(db_path):
    """Connect to the Pi-hole database."""
    logger.info(f"Connecting to the database at {db_path}...")
    if not os.path.exists(db_path):
        logger.error(f"Database not found at {db_path}")
        sys.exit(1)
    try:
        conn = sqlite3.connect(db_path)
        logger.info("Database connected successfully.")
        return conn
    except sqlite3.Error as e:
        logger.error(f"Error connecting to database: {e}")
        sys.exit(1)

def connect_results_db():
    """Connect to the results database and create necessary tables if they don't exist."""
    logger.info(f"Connecting to the results database at {RESULTS_DB_PATH}...")
    try:
        conn = sqlite3.connect(RESULTS_DB_PATH)
        logger.info("Results database connected successfully.")
        
        # Create tables if they do not exist
        with conn:
            conn.execute('''CREATE TABLE IF NOT EXISTS clustered_domains (
                                domain TEXT,
                                length INTEGER,
                                cluster INTEGER
                            )''')
            conn.execute('''CREATE TABLE IF NOT EXISTS domain_sentiments (
                                domain TEXT,
                                label TEXT,
                                score REAL
                            )''')
        return conn
    except sqlite3.Error as e:
        logger.error(f"Error connecting to results database: {e}")
        sys.exit(1)

def fetch_data(conn, query):
    """Fetch data from the database."""
    logger.info(f"Fetching data with query: {query}")
    try:
        data = pd.read_sql_query(query, conn)
        logger.info(f"Fetched {len(data)} records.")
        return data
    except pd.io.sql.DatabaseError as e:
        logger.error(f"Error fetching data: {e}")
        sys.exit(1)

def save_results(conn, df, table_name):
    """Save results to the results database."""
    logger.info(f"Saving results to table '{table_name}' in the results database...")
    try:
        df.to_sql(table_name, conn, if_exists='replace', index=False)
        logger.info("Results saved successfully.")
    except pd.io.sql.DatabaseError as e:
        logger.error(f"Error saving results: {e}")

def load_results(conn, table_name):
    """Load results from the results database."""
    logger.info(f"Loading results from table '{table_name}' in the results database...")
    try:
        data = pd.read_sql_query(f"SELECT * FROM {table_name}", conn)
        logger.info("Results loaded successfully.")
        return data
    except pd.io.sql.DatabaseError as e:
        logger.error(f"Error loading results: {e}")
        return None

def cluster_domains(df, n_clusters=N_CLUSTERS):
    """Cluster domains using K-means."""
    logger.info("Clustering domains using K-means...")
    df['length'] = df['domain'].apply(len)
    try:
        model = KMeans(n_clusters=n_clusters, n_init=10)
        df['cluster'] = model.fit_predict(df[['length']])
        logger.info("Clustering completed.")
        return df
    except Exception as e:
        logger.error(f"Error during clustering: {e}")
        sys.exit(1)

def recover_database():
    """Recover the Pi-hole database."""
    logger.info("Attempting to recover the database...")
    try:
        subprocess.run(["pihole", "-g", "-r", "recover"], check=True)
        logger.info("Database recovery successful.")
    except subprocess.CalledProcessError as e:
        logger.error(f"Database recovery failed: {e}")
        sys.exit(1)

def recreate_database():
    """Recreate the Pi-hole database."""
    logger.info("Attempting to recreate the database...")
    try:
        subprocess.run(["pihole", "-g", "-r", "recreate"], check=True)
        logger.info("Database recreation successful.")
    except subprocess.CalledProcessError as e:
        logger.error(f"Database recreation failed: {e}")
        sys.exit(1)

def visualize_clusters(df):
    """Visualize clusters using matplotlib."""
    logger.info("Visualizing clusters...")
    try:
        plt.figure(figsize=(10, 6))
        for cluster in df['cluster'].unique():
            clustered_data = df[df['cluster'] == cluster]
            plt.scatter(clustered_data['domain'], clustered_data['length'], label=f'Cluster {cluster}')
        plt.xlabel('Domain')
        plt.ylabel('Length')
        plt.title('Domain Clusters')
        plt.legend()
        plt.xticks(rotation=90)
        plt.tight_layout()
        plt.show()
        logger.info("Visualization completed.")
    except Exception as e:
        logger.error(f"Error during visualization: {e}")

def display_table(df, title):
    """Display a formatted table in the terminal."""
    logger.info(f"Displaying table: {title}")
    print(f"\n{title}")
    print(df.to_string(index=False))

def analyze_sentiments(domains):
    """Analyze sentiments with progress bar."""
    sentiments = []
    logger.info("Performing NLP sentiment analysis on domains...")
    for domain in tqdm(domains, desc="Analyzing domains"):
        sentiment = nlp(domain)
        sentiments.append(sentiment[0])
    return sentiments

def display_summary(sentiment_df):
    """Display a summary of sentiment analysis results."""
    positive_count = sentiment_df[sentiment_df['label'] == 'POSITIVE'].shape[0]
    negative_count = sentiment_df[sentiment_df['label'] == 'NEGATIVE'].shape[0]
    total_count = len(sentiment_df)

    print("\nSummary of Sentiment Analysis:")
    print(f"Total domains analyzed: {total_count}")
    print(f"Positive sentiments: {positive_count} ({positive_count/total_count:.2%})")
    print(f"Negative sentiments: {negative_count} ({negative_count/total_count:.2%})")

    top_positive = sentiment_df[sentiment_df['label'] == 'POSITIVE'].nlargest(5, 'score')
    top_negative = sentiment_df[sentiment_df['label'] == 'NEGATIVE'].nlargest(5, 'score')

    print("\nTop 5 Positive Domains:")
    print(top_positive[['domain', 'score']].to_string(index=False))

    print("\nTop 5 Negative Domains:")
    print(top_negative[['domain', 'score']].to_string(index=False))

@click.command()
@click.option('--query', default='SELECT * FROM domainlist', help='SQL query to fetch data.')
@click.option('--clusters', default=N_CLUSTERS, help='Number of clusters for K-means.')
@click.option('--recover', is_flag=True, help='Recover the damaged gravity database.')
@click.option('--recreate', is_flag=True, help='Recreate the gravity database from scratch.')
@click.option('--visualize', is_flag=True, help='Visualize domain clusters.')
def main(query, clusters, recover, recreate, visualize):
    """Main function to manage Pi-hole database."""
    if recover:
        recover_database()
        return

    if recreate:
        recreate_database()
        return

    conn = connect_db(DATABASE_PATH)
    results_conn = connect_results_db()
    
    # Fetch data
    data = fetch_data(conn, query)
    if data.empty:
        logger.warning("No data fetched.")
        print("No data fetched.")
        return

    # Check if clustering results already exist
    cached_clusters = load_results(results_conn, 'clustered_domains')
    if cached_clusters is not None and len(cached_clusters) == len(data):
        logger.info("Using cached clustering results.")
        clustered_data = cached_clusters
    else:
        # Cluster data
        clustered_data = cluster_domains(data, clusters)
        save_results(results_conn, clustered_data, 'clustered_domains')

    # Display clustered data
    display_table(clustered_data[['domain', 'cluster']], "Clustered Domains")
    
    # Check if sentiment analysis results already exist
    cached_sentiments = load_results(results_conn, 'domain_sentiments')
    if cached_sentiments is not None and len(cached_sentiments) == len(clustered_data):
        logger.info("Using cached sentiment analysis results.")
        sentiment_df = cached_sentiments
    else:
        # NLP analysis on domains
        try:
            sentiments = analyze_sentiments(clustered_data['domain'].tolist())
            sentiment_df = pd.DataFrame(sentiments)
            sentiment_df['domain'] = clustered_data['domain'].values
            save_results(results_conn, sentiment_df, 'domain_sentiments')
        except Exception as e:
            logger.error(f"Error during NLP sentiment analysis: {e}")
            return

    # Display sentiment analysis results
    display_table(sentiment_df[['domain', 'label', 'score']], "NLP Sentiment Analysis on Domains")

    # Display summary of sentiment analysis
    display_summary(sentiment_df)

    # Visualization
    if visualize:
        visualize_clusters(clustered_data)

if __name__ == "__main__":
    main()
