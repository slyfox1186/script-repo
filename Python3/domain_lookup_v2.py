#!/usr/bin/env python3

# Added the below functionality
#  - Batch processing for passing multiple domains at once to the script
#  - Added the ability to create an output file at the end of the command using '-o filename.ext'
#    - Example command: python3 domain_lookup_v2.py reddit.com google.com -o output.txt

import whois
import sys
from datetime import datetime

def format_dates(dates):
    if isinstance(dates, list):
        return ", ".join([date.strftime('%m-%d-%Y %H:%M:%S UTC') for date in dates])
    elif dates:
        return dates.strftime('%m-%d-%Y %H:%M:%S UTC')
    else:
        return "N/A"

def display_info(domain_info, domain_name, verbose=False):
    output = []

    output.append(f"\nDomain Searched: {domain_name}")
    output.append(f"Registrant Name: {domain_info.name}")
    output.append(f"Registrant Organization: {domain_info.org}")
    output.append(f"Registrar: {domain_info.registrar}")

    output.append(f"\nCreation Date: {format_dates(domain_info.creation_date)}")
    output.append(f"Expiration Date: {format_dates(domain_info.expiration_date)}")
    output.append(f"Updated Date: {format_dates(domain_info.updated_date)}")

    nameservers = sorted(set([ns.lower() for ns in domain_info.name_servers]))
    if nameservers:
        output.append("\nName Servers:")
        for ns in nameservers:
            output.append(f"- {ns}")

    if domain_info.dnssec:
        output.append(f"\nDNSSEC: {domain_info.dnssec}")

    if domain_info.emails:
        output.append("\nContact Emails:")
        if isinstance(domain_info.emails, list):
            output.extend([f"- {email}" for email in domain_info.emails])
        else:
            output.append(f"- {domain_info.emails}")

    if verbose:
        output.append("\n[Verbose Mode]")
        output.append(f"Domain Status: {domain_info.status}")
        output.append(f"Whois Server: {domain_info.whois_server}")

    return '\n'.join(output)

def is_domain_available(domain):
    try:
        whois_result = whois.whois(domain)
        return not whois_result.domain_name
    except:
        return True

def process_domains(domains, verbose=False, output_file=None):
    results = []
    for domain in domains:
        try:
            domain_info = whois.whois(domain)
            if not domain_info.status or "No match for domain" in str(domain_info.status):
                availability = is_domain_available(domain)
                result = f"Domain '{domain}' is {'available' if availability else 'not available'} for registration."
            else:
                result = display_info(domain_info, domain, verbose)
        except Exception as e:
            result = f"An error occurred while processing '{domain}': {e}"

        results.append(result)

    final_output = '\n'.join(results)
    print(final_output)

    if output_file:
        with open(output_file, 'w') as file:
            file.write(final_output)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: python3 {sys.argv[0]} <domain/subdomain> [-v] [-o output_file]")
        sys.exit(1)

    verbose = '-v' in sys.argv
    output_file_flag = '-o' in sys.argv
    output_file = sys.argv[sys.argv.index('-o') + 1] if output_file_flag and sys.argv.index('-o') + 1 < len(sys.argv) else None
    domain_list = [arg for arg in sys.argv[1:] if arg != '-v' and arg != '-o']

    process_domains(domain_list, verbose, output_file)
