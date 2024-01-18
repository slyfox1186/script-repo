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
        print(f"Domain Information for '{domain}':")

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

        print(f"Creation Date(s): {creation_date}")
        print(f"Expiration Date(s): {expiration_date}")
        print(f"Updated Date(s): {updated_date}")

        # Additional Information
        nameservers = domain_info.name_servers
        domain_status = domain_info.status
        dnssec = domain_info.dnssec
        emails = domain_info.emails

        if nameservers:
            print("Name Servers:")
            for ns in nameservers:
                print(f"- {ns}")

        if domain_status:
            print("Domain Status:")
            for status in domain_status:
                print(f"- {status}")

        if dnssec:
            print(f"DNSSEC: {dnssec}")

        if emails:
            print("Contact Emails:")
            for email in emails:
                print(f"- {email}")
except Exception as e:
    print(f"An error occurred: {e}")
