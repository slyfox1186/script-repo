#!/usr/bin/env python3

import whois
import sys
from datetime import datetime

# Check if a domain or subdomain is provided as an argument
if len(sys.argv) != 2:
    print("Usage: ./domain_lookup.py <domain/subdomain>")
    sys.exit(1)

# Extract the domain from the argument
domain = sys.argv[1]

try:
    # Perform a whois lookup
    domain_info = whois.whois(domain)

    # Check if the domain exists or is registered
    if not domain_info.status or "No match for domain" in str(domain_info.status):
        print(f"Domain '{domain}' is not found or is not registered.")
    else:
        # Extract and display various information about the domain
        print(f"\nDomain Information for '{domain}':")

        # Registrant Information
        registrant_name = domain_info.name
        registrant_organization = domain_info.org
        registrar = domain_info.registrar
        print(f"Registrant Name: {registrant_name}")
        print(f"Registrant Organization: {registrant_organization}")
        print(f"Registrar: {registrar}")

        # Dates
        creation_date = domain_info.creation_date
        expiration_date = domain_info.expiration_date
        updated_date = domain_info.updated_date

        if isinstance(creation_date, list):
            creation_date = ", ".join([d.strftime('%m-%d-%Y %H:%M:%S UTC') for d in creation_date])
        else:
            creation_date = creation_date.strftime('%m-%d-%Y %H:%M:%S UTC')

        if isinstance(expiration_date, list):
            expiration_date = ", ".join([d.strftime('%m-%d-%Y %H:%M:%S UTC') for d in expiration_date])
        else:
            expiration_date = expiration_date.strftime('%m-%d-%Y %H:%M:%S UTC')

        if isinstance(updated_date, list):
            updated_date = ", ".join([d.strftime('%m-%d-%Y %H:%M:%S UTC') for d in updated_date])
        else:
            updated_date = updated_date.strftime('%m-%d-%Y %H:%M:%S UTC')

        print(f"\nCreation Date(s): {creation_date}")
        print(f"Expiration Date(s): {expiration_date}")
        print(f"Updated Date(s): {updated_date}")

        # Additional Information
        nameservers = list(set([ns.lower() for ns in domain_info.name_servers]))  # Remove duplicates and lowercase

        # Sort the nameservers numerically
        nameservers.sort(key=lambda x: int(x[2:]) if x.startswith('ns') and x[2:].isdigit() else x)

        if nameservers:
            print("\nName Servers:")
            for ns in nameservers:

                print(f"- {ns}")

        dnssec = domain_info.dnssec
        emails = domain_info.emails

        if dnssec:
            print(f"\nDNSSEC: {dnssec}")

        if emails:
            print("\nContact Emails:")
            for email in emails:
                print(f"- {email}")
except Exception as e:
    print(f"An error occurred: {e}")