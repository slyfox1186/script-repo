#!/usr/bin/env python3

# Added batch functionality so you can pass multiple domains at once.

import whois
import sys
from datetime import datetime

def format_date(date):
    if isinstance(date, list):
        return ", ".join([d.strftime('%m-%d-%Y %H:%M:%S UTC') for d in date])
    else:
        return date.strftime('%m-%d-%Y %H:%M:%S UTC')

def display_info(domain_info, domain_name, verbose=False):
    output = []

    # Use the input domain name directly
    output.append(f"\nDomain Searched: {domain_name}")

    # Other details remain the same
    output.append(f"Registrant Name: {domain_info.name}")
    output.append(f"Registrant Organization: {domain_info.org}")
    output.append(f"Registrar: {domain_info.registrar}")

    # Dates
    output.append(f"\nCreation Date(s): {format_date(domain_info.creation_date)}")
    output.append(f"Expiration Date(s): {format_date(domain_info.expiration_date)}")
    output.append(f"Updated Date(s): {format_date(domain_info.updated_date)}")

    # Nameservers
    nameservers = list(set([ns.lower() for ns in domain_info.name_servers]))
    nameservers.sort(key=lambda x: int(x[2:]) if x.startswith('ns') and x[2:].isdigit() else x)
    if nameservers:
        output.append("\nName Servers:")
        for ns in nameservers:
            output.append(f"- {ns}")

    # Additional Information
    if domain_info.dnssec:
        output.append(f"\nDNSSEC: {domain_info.dnssec}")

    if domain_info.emails:
        output.append("\nContact Emails:")
        if isinstance(domain_info.emails, list):
            output.append(", ".join(domain_info.emails))
        else:
            output.append(domain_info.emails)

    # Verbose Mode
    if verbose:
        output.append("\n[Verbose Mode]")
        output.append(f"Domain Status: {domain_info.status}")
        output.append(f"Whois Server: {domain_info.whois_server}")

    return '\n'.join(output)

def is_domain_available(domain):
    try:
        whois_result = whois.whois(domain)
        return False if whois_result.domain_name else True
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

# Handling command-line arguments
if len(sys.argv) < 2:
    print(f"Usage: python3 {sys.argv[0]} <domain/subdomain> [-v] [-o output_file]")
    sys.exit(1)

verbose = '-v' in sys.argv
output_file = None
domain_list = sys.argv[1:]  # Get all domains passed as arguments

# Main execution
process_domains(domain_list, verbose, output_file)
