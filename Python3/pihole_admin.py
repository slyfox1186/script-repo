#!/usr/bin/env python3

import argparse
import logging
import matplotlib.pyplot as plt
import os
import requests
import sqlite3
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta
from fuzzywuzzy import fuzz
from tabulate import tabulate
from typing import List, Dict, Any

class PiholeDBAdmin:
    def __init__(self, gravity_db_path: str = "/etc/pihole/gravity.db", query_db_path: str = "/etc/pihole/pihole-FTL.db"):
        self.gravity_db_path = gravity_db_path
        self.query_db_path = query_db_path
        self.logger = self._setup_logger()

    def _setup_logger(self) -> logging.Logger:
        logger = logging.getLogger("PiholeDBAdmin")
        logger.setLevel(logging.INFO)
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
        logger.addHandler(handler)
        return logger

    def _get_connection(self, db_path: str) -> sqlite3.Connection:
        return sqlite3.connect(db_path)

    def optimize_database(self) -> None:
        self.logger.info("Starting database optimization...")

        with self._get_connection() as conn:
            cursor = conn.cursor()

            cursor.execute("PRAGMA page_count")
            initial_pages = cursor.fetchone()[0]
            cursor.execute("PRAGMA page_size")
            page_size = cursor.fetchone()[0]
            initial_size = initial_pages * page_size / 1024 / 1024  # Size in MB

            cursor.execute("PRAGMA freelist_count")
            initial_fragmentation = cursor.fetchone()[0] * page_size / 1024 / 1024  # Fragmentation in MB

            start_time = time.time()
            conn.execute("VACUUM")
            vacuum_time = time.time() - start_time

            cursor.execute("PRAGMA page_count")
            post_vacuum_pages = cursor.fetchone()[0]
            post_vacuum_size = post_vacuum_pages * page_size / 1024 / 1024  # Size in MB

            cursor.execute("PRAGMA freelist_count")
            post_vacuum_fragmentation = cursor.fetchone()[0] * page_size / 1024 / 1024  # Fragmentation in MB

            start_time = time.time()
            conn.execute("ANALYZE")
            analyze_time = time.time() - start_time

            cursor.execute("SELECT COUNT(*) FROM sqlite_stat1")
            stats_count = cursor.fetchone()[0]

        summary = f"""
Database Optimization Summary:
==============================
Initial State:
  - Size: {initial_size:.2f} MB
  - Fragmentation: {initial_fragmentation:.2f} MB

VACUUM Operation:
  - Duration: {vacuum_time:.2f} seconds
  - Size after VACUUM: {post_vacuum_size:.2f} MB
  - Fragmentation after VACUUM: {post_vacuum_fragmentation:.2f} MB
  - Space saved: {initial_size - post_vacuum_size:.2f} MB

ANALYZE Operation:
  - Duration: {analyze_time:.2f} seconds
  - Table statistics gathered: {stats_count}

Final Results:
  - Total optimization time: {vacuum_time + analyze_time:.2f} seconds
  - Final database size: {post_vacuum_size:.2f} MB
  - Total space saved: {initial_size - post_vacuum_size:.2f} MB
  - Total fragmentation reduced: {initial_fragmentation - post_vacuum_fragmentation:.2f} MB

Changes Made:
  - Database size change: {post_vacuum_size - initial_size:+.2f} MB
  - Fragmentation change: {post_vacuum_fragmentation - initial_fragmentation:+.2f} MB
"""
        print(summary)
        self.logger.info("Database optimization completed.")

    def backup_database(self, backup_path: str) -> None:
        self.logger.info(f"Backing up database to {backup_path}")
        start_time = time.time()
        with self._get_connection() as conn:
            backup = sqlite3.connect(backup_path)
            conn.backup(backup)
            backup.close()
        backup_time = time.time() - start_time
        backup_size = os.path.getsize(backup_path) / 1024 / 1024  # Size in MB
        self.logger.info(f"Database backup completed in {backup_time:.2f} seconds")
        self.logger.info(f"Backup size: {backup_size:.2f} MB")

    def get_statistics(self) -> Dict[str, Any]:
        self.logger.info("Fetching database statistics...")
        stats = {}
        with self._get_connection(self.gravity_db_path) as conn:
            cursor = conn.cursor()

            def safe_execute(query, default=0):
                try:
                    cursor.execute(query)
                    return cursor.fetchone()[0]
                except sqlite3.OperationalError as e:
                    self.logger.warning(f"Query failed: {query}. Error: {str(e)}")
                    return default

            # Fetch total domains from gravity table
            stats['total_domains'] = safe_execute("SELECT COUNT(*) FROM gravity")

            # Fetch whitelisted and blacklisted domains from domainlist table
            stats['whitelisted_domains'] = safe_execute("SELECT COUNT(*) FROM domainlist WHERE type = 0 AND enabled = 1")
            stats['blacklisted_domains'] = safe_execute("SELECT COUNT(*) FROM domainlist WHERE type = 1 AND enabled = 1")

            # Fetch adlist information
            stats['total_adlists'] = safe_execute("SELECT COUNT(*) FROM adlist WHERE enabled = 1")
            stats['adlist_urls'] = safe_execute("SELECT COUNT(DISTINCT address) FROM adlist WHERE enabled = 1")

            # Fetch gravity information from info table
            cursor.execute("SELECT value FROM info WHERE property = 'gravity_count'")
            result = cursor.fetchone()
            stats['gravity_count'] = int(result[0]) if result else 0

            cursor.execute("SELECT value FROM info WHERE property = 'updated'")
            result = cursor.fetchone()
            if result:
                last_updated = datetime.fromtimestamp(int(result[0]))
                stats['last_gravity_update'] = last_updated.strftime("%m-%d-%Y %I:%M:%S %p")
            else:
                stats['last_gravity_update'] = "Unknown"

        self.logger.info("Statistics fetched successfully.")
        return stats

    def clean_old_data(self, days: int = 30) -> None:
        self.logger.info(f"Cleaning data older than {days} days...")
        with self._get_connection(self.query_db_path) as conn:
            cursor = conn.cursor()
            timestamp = int((datetime.now() - timedelta(days=days)).timestamp())

            cursor.execute("SELECT COUNT(*) FROM query_storage WHERE timestamp < ?", (timestamp,))
            queries_to_delete = cursor.fetchone()[0]

            cursor.execute("DELETE FROM query_storage WHERE timestamp < ?", (timestamp,))
            conn.commit()

        self.logger.info(f"Deleted {queries_to_delete} old queries.")
        self.logger.info("Old data cleaned successfully.")

    def add_domains_to_list(self, domains: List[str], list_type: int) -> None:
        list_name = "whitelist" if list_type == 0 else "blacklist"
        self.logger.info(f"Adding domains to {list_name}...")
        added_count = 0
        with self._get_connection() as conn:
            cursor = conn.cursor()
            for domain in domains:
                cursor.execute(
                    "INSERT OR IGNORE INTO domainlist (type, domain, enabled, date_added) VALUES (?, ?, 1, strftime('%s', 'now'))",
                    (list_type, domain)
                )
                if cursor.rowcount > 0:
                    added_count += 1
            conn.commit()
        self.logger.info(f"{added_count} domains added to {list_name} successfully.")

    def remove_domains_from_list(self, domains: List[str], list_type: int) -> None:
        list_name = "whitelist" if list_type == 0 else "blacklist"
        self.logger.info(f"Removing domains from {list_name}...")
        removed_count = 0
        with self._get_connection() as conn:
            cursor = conn.cursor()
            for domain in domains:
                cursor.execute(
                    "DELETE FROM domainlist WHERE type = ? AND domain = ?",
                    (list_type, domain)
                )
                removed_count += cursor.rowcount
            conn.commit()
        self.logger.info(f"{removed_count} domains removed from {list_name} successfully.")

    def update_gravity(self) -> None:
        self.logger.info("Updating gravity...")
        start_time = time.time()
        result = os.system("pihole -g")
        update_time = time.time() - start_time
        if result == 0:
            self.logger.info(f"Gravity updated successfully in {update_time:.2f} seconds.")
        else:
            self.logger.error(f"Gravity update failed after {update_time:.2f} seconds.")

    def analyze_top_domains(self, limit: int = 10) -> List[Dict[str, Any]]:
        self.logger.info(f"Analyzing top {limit} domains...")
        with self._get_connection(self.gravity_db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT domain, COUNT(*) as count
                FROM gravity
                GROUP BY domain
                ORDER BY count DESC
                LIMIT ?
            """, (limit,))
            results = [{"domain": row[0], "count": row[1]} for row in cursor.fetchall()]
        self.logger.info("Top domains analysis completed.")
        return results

    def run_custom_query(self, query: str) -> List[Dict[str, Any]]:
        self.logger.info("Running custom query...")
        with self._get_connection(self.gravity_db_path) as conn:
            cursor = conn.cursor()
            start_time = time.time()
            cursor.execute(query)
            query_time = time.time() - start_time
            columns = [description[0] for description in cursor.description]
            results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        self.logger.info(f"Custom query executed successfully in {query_time:.2f} seconds.")
        return results

    def generate_report(self) -> str:
        self.logger.info("Generating comprehensive report...")

        stats = self.get_statistics()
        top_blocked_domains = self.analyze_top_domains(10)
        top_allowed_domains = self.analyze_top_allowed_domains(10)

        report = []
        report.append("\nPi-hole Database Report")
        report.append("=======================\n")
        report.append("General Statistics:\n")
        report.append(f"Total domains in gravity: {stats['total_domains']:,}\n")
        report.append(f"Whitelisted domains: {stats['whitelisted_domains']:,}\n")
        report.append(f"Blacklisted domains: {stats['blacklisted_domains']:,}\n")
        report.append(f"Total enabled adlists: {stats['total_adlists']:,}\n")
        report.append(f"Unique adlist URLs: {stats['adlist_urls']:,}\n")
        report.append(f"Gravity count: {stats['gravity_count']:,}\n")
        report.append(f"Last gravity update: {stats['last_gravity_update']}\n\n")
        report.append("Top 10 Blocked Domains:\n")
        report.append(tabulate(top_blocked_domains, headers="keys", tablefmt="grid"))
        report.append("\n\nPlease see 'top_blocked_domains_chart.png' for a visual representation.\n")
        report.append("Top 10 Allowed Domains:\n")
        report.append(tabulate(top_allowed_domains, headers="keys", tablefmt="grid"))
        report.append("\n\nPlease see 'top_allowed_domains_chart.png' for a visual representation.\n")

        report_str = "\n".join(report)
        print(report_str)

        return report_str

    def analyze_top_allowed_domains(self, limit: int = 10) -> List[Dict[str, Any]]:
        self.logger.info(f"Analyzing top {limit} allowed domains...")
        with self._get_connection(self.query_db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT domain, COUNT(*) as count
                FROM query_storage
                WHERE status IN (2, 3)
                GROUP BY domain
                ORDER BY count DESC
                LIMIT ?
            """, (limit,))
            results = [{"domain": row[0], "count": row[1]} for row in cursor.fetchall()]
        self.logger.info("Top allowed domains analysis completed.")
        return results

    def check_for_updates(self) -> None:
        self.logger.info("Checking for Pi-hole updates...")
        try:
            result = os.popen("pihole -v").read()
            self.logger.info(f"Raw version output: {result}")
            current_version = result.split("Pi-hole version is ")[1].split("\n")[0].split()[0].strip()
            self.logger.info(f"Extracted current version: {current_version}")

            response = requests.get("https://api.github.com/repos/pi-hole/pi-hole/releases/latest")
            latest_version = response.json()["tag_name"].strip()
            self.logger.info(f"Extracted latest version: {latest_version}")

            if current_version != latest_version:
                self.logger.info(f"Update available: {latest_version} (current: {current_version})")
            else:
                self.logger.info("Pi-hole is up to date.")
        except Exception as e:
            self.logger.error(f"Error checking for updates: {str(e)}")

    def remove_duplicate_domains(self):
        self.logger.info("Searching for and removing duplicate domains...")
        with self._get_connection() as conn:
            cursor = conn.cursor()

            # Get domains from domainlist with their types
            cursor.execute("SELECT domain, type FROM domainlist")
            domainlist_domains = [(row[0], self.get_list_type(row[1])) for row in cursor.fetchall()]

            # Get addresses from adlist table
            cursor.execute("SELECT address FROM adlist")
            adlist_urls = [(row[0], 'adlist') for row in cursor.fetchall()]

            all_entries = domainlist_domains + adlist_urls

            # Find duplicates while keeping one instance
            seen_entries = {}
            duplicates = defaultdict(list)
            for entry, list_type in all_entries:
                if entry in seen_entries:
                    duplicates[list_type].append(entry)
                else:
                    seen_entries[entry] = list_type

            # Remove duplicates while keeping one instance
            for list_type, entries in duplicates.items():
                for entry in entries:
                    if list_type != 'adlist':
                        cursor.execute("DELETE FROM domainlist WHERE domain = ? AND type = ? AND id NOT IN (SELECT id FROM domainlist WHERE domain = ? AND type = ? LIMIT 1)", (entry, self.get_list_type_value(list_type), entry, self.get_list_type_value(list_type)))
                    else:
                        cursor.execute("DELETE FROM adlist WHERE address = ? AND id NOT IN (SELECT id FROM adlist WHERE address = ? LIMIT 1)", (entry, entry))

            conn.commit()

        total_duplicates = sum(len(entries) for entries in duplicates.values())
        self.logger.info(f"Removed {total_duplicates} duplicate entries.")
        return duplicates

    def find_similar_domains(self, similarity_threshold: int) -> Dict[str, List[str]]:
        self.logger.info(f"Searching for similar domains with a threshold of {similarity_threshold}%...")
        with self._get_connection(self.gravity_db_path) as conn:
            cursor = conn.cursor()

            # Get all domains from the domainlist table
            cursor.execute("SELECT domain, type FROM domainlist")
            domains = cursor.fetchall()

            similar_domains = defaultdict(list)
            seen_pairs = set()

            for i in range(len(domains)):
                for j in range(i + 1, len(domains)):
                    domain1, type1 = domains[i]
                    domain2, type2 = domains[j]

                    if (domain1, domain2) in seen_pairs or (domain2, domain1) in seen_pairs:
                        continue

                    similarity_ratio = fuzz.ratio(domain1, domain2)
                    if similarity_ratio >= similarity_threshold:
                        similar_domains[domain1].append((domain2, type2, similarity_ratio))
                        seen_pairs.add((domain1, domain2))
                        seen_pairs.add((domain2, domain1))

            self.logger.info(f"Found {len(similar_domains)} domains with similar matches.")
            return similar_domains

    def get_list_type(self, type_value):
        if type_value == 0:
            return "exact whitelist"
        elif type_value == 1:
            return "exact blacklist"
        elif type_value == 2:
            return "regex whitelist"
        elif type_value == 3:
            return "regex blacklist"
        else:
            return "unknown list type"

    def get_list_type_value(self, list_type):
        if list_type == "exact whitelist":
            return 0
        elif list_type == "exact blacklist":
            return 1
        elif list_type == "regex whitelist":
            return 2
        elif list_type == "regex blacklist":
            return 3
        else:
            return -1

def main():
    parser = argparse.ArgumentParser(description="Pi-hole Database Administrator")
    parser.add_argument("--optimize", "-o", action="store_true", help="Optimize the database")
    parser.add_argument("--backup", "-b", metavar="PATH", help="Backup the database to the specified path")
    parser.add_argument("--stats", "-s", action="store_true", help="Get database statistics")
    parser.add_argument("--clean", "-c", type=int, metavar="DAYS", help="Clean data older than specified days")
    parser.add_argument("--add-whitelist", "-aw", nargs="+", metavar="DOMAIN", help="Add domains to whitelist")
    parser.add_argument("--add-blacklist", "-ab", nargs="+", metavar="DOMAIN", help="Add domains to blacklist")
    parser.add_argument("--remove-whitelist", "-rw", nargs="+", metavar="DOMAIN", help="Remove domains from whitelist")
    parser.add_argument("--remove-blacklist", "-rb", nargs="+", metavar="DOMAIN", help="Remove domains from blacklist")
    parser.add_argument("--update-gravity", "-ug", action="store_true", help="Update gravity")
    parser.add_argument("--top-domains", "-td", type=int, metavar="LIMIT", help="Analyze top domains")
    parser.add_argument("--custom-query", "-q", metavar="QUERY", help="Run a custom SQL query")
    parser.add_argument("--report", "-r", metavar="FILE", help="Generate a comprehensive report")
    parser.add_argument("--check-updates", "-u", action="store_true", help="Check for Pi-hole updates")
    parser.add_argument("--remove-duplicates", "-rd", action="store_true", help="Remove duplicate domains across all lists")
    parser.add_argument("--find-similar", "-fs", type=int, metavar="THRESHOLD", help="Find similar domains based on the specified similarity threshold (e.g., 90 for 90% similarity)")

    args = parser.parse_args()

    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)

    admin = PiholeDBAdmin()

    if args.optimize:
        admin.optimize_database()

    if args.backup:
        admin.backup_database(args.backup)

    if args.stats:
        stats = admin.get_statistics()
        print("\nPi-hole Database Statistics:")
        print("============================")
        print(f"Total domains in gravity: {stats['total_domains']:,}")
        print(f"Whitelisted domains: {stats['whitelisted_domains']:,}")
        print(f"Blacklisted domains: {stats['blacklisted_domains']:,}")
        print(f"Total enabled adlists: {stats['total_adlists']:,}")
        print(f"Unique adlist URLs: {stats['adlist_urls']:,}")
        print(f"Gravity count: {stats['gravity_count']:,}")
        print(f"Last gravity update: {stats['last_gravity_update']}")

    if args.clean:
        admin.clean_old_data(args.clean)

    if args.add_whitelist:
        admin.add_domains_to_list(args.add_whitelist, 0)

    if args.add_blacklist:
        admin.add_domains_to_list(args.add_blacklist, 1)

    if args.remove_whitelist:
        admin.remove_domains_from_list(args.remove_whitelist, 0)

    if args.remove_blacklist:
        admin.remove_domains_from_list(args.remove_blacklist, 1)

    if args.update_gravity:
        admin.update_gravity()

    if args.top_domains:
        top_domains = admin.analyze_top_domains(args.top_domains)
        print("\nTop Blocked Domains:")
        print("====================")
        print(tabulate(top_domains, headers="keys", tablefmt="grid"))

    if args.custom_query:
        results = admin.run_custom_query(args.custom_query)
        print("\nCustom Query Results:")
        print("=====================")
        print(tabulate(results, headers="keys", tablefmt="grid"))

    if args.report:
        report_content = admin.generate_report()
        save_report = input("\nDo you want to save this report to a file? (y/n): ").lower().strip()
        if save_report == 'y':
            report_path = input("Enter the relative or full path to the output log file: ").strip()
            with open(report_path, 'w') as f:
                f.write(report_content)
            print(f"Report saved to: {report_path}")
        else:
            print("Report not saved.")

    if args.check_updates:
        admin.check_for_updates()

    if args.remove_duplicates:
        duplicates = admin.remove_duplicate_domains()
        print("\nRemoved Duplicate Domains:")
        print("==========================")
        for list_type, domains in duplicates.items():
            print(f"\n{list_type.capitalize()}:")
            for domain in domains:
                print(f"  {domain}")

        create_log = input("\nDo you want to create an output log file? (y/n): ").lower().strip()
        if create_log == 'y':
            script_dir = os.path.dirname(os.path.realpath(__file__))
            log_file_path = os.path.join(script_dir, 'pihole-duplicates.txt')
            with open(log_file_path, 'w') as log_file:
                log_file.write("Removed Duplicate Domains:\n")
                log_file.write("==========================\n")
                for list_type, domains in duplicates.items():
                    log_file.write(f"\n{list_type.capitalize()}:\n")
                    for domain in domains:
                        log_file.write(f"  {domain}\n")
            print(f"Log file created at: {log_file_path}")

    if args.find_similar:
        similar_domains = admin.find_similar_domains(args.find_similar)
        print("\nSimilar Domains:")
        print("================")
        for domain, matches in similar_domains.items():
            print(f"\nDomain: {domain}")
            print("Similar Matches:")
            for match in matches:
                print(f"  - {match[0]} (Type: {admin.get_list_type(match[1])}, Similarity: {match[2]}%)")

        create_log = input("\nDo you want to create an output log file with the results of the scan? (y/n): ").lower().strip()
        if create_log == 'y':
            script_dir = os.path.dirname(os.path.realpath(__file__))
            log_file_path = os.path.join(script_dir, f'similar-domains-{args.find_similar}.txt')
            with open(log_file_path, 'w') as log_file:
                log_file.write("Similar Domains:\n")
                log_file.write("================\n")
                for domain, matches in similar_domains.items():
                    log_file.write(f"\nDomain: {domain}\n")
                    log_file.write("Similar Matches:\n")
                    for match in matches:
                        log_file.write(f"  - {match[0]} (Type: {admin.get_list_type(match[1])}, Similarity: {match[2]}%)\n")
            print(f"Log file created at: {log_file_path}")

if __name__ == "__main__":
    main()
