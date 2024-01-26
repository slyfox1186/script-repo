#!/usr/bin/env python3

#  Improved script features with the below-added functionality
#   - Added separators for each domain to make for easier reading.
#   - Added Batch processing for passing multiple domains at once to the script
#   - Added the ability to create an output file at the end of the command using '-o filename.ext'
#   - Added IP address lookup for each domain
#  -  Added Reverse IP lookup to find the hostname associated with the IP address.
#  -  Added Geolocation information of the IP address.
#  -  Added SSL certificate information, including its validity period.
#  -  Usage: python3 domain_lookup.py reddit.com google.com -o output.txt

import whois
import sys
import socket
import requests
import ssl
from datetime import datetime

def format_dates(dates):
    if isinstance(dates, list):
        return dates[0].strftime('%m-%d-%Y %H:%M:%S UTC')
    elif dates:
        return dates.strftime('%m-%d-%Y %H:%M:%S UTC')
    else:
        return "N/A"

def get_reverse_ip(ip_address):
    try:
        return socket.gethostbyaddr(ip_address)[0]
    except socket.herror:
        return "No reverse DNS record found"
    except Exception as e:
        return f"Error retrieving hostname - {e}"

def get_geolocation(ip_address):
    try:
        response = requests.get(f"http://ip-api.com/json/{ip_address}")
        data = response.json()
        return f"Country: {data['country']}, City: {data['city']}, ISP: {data['isp']}"
    except Exception as e:
        return f"Error retrieving geolocation - {e}"

def get_ssl_info(domain_name):
    try:
        context = ssl.create_default_context()
        with socket.create_connection((domain_name, 443), timeout=10) as sock:
            with context.wrap_socket(sock, server_hostname=domain_name) as ssock:
                cert = ssock.getpeercert()
                valid_from = datetime.strptime(cert['notBefore'], '%b %d %H:%M:%S %Y %Z').strftime('%m-%d-%Y %H:%M:%S UTC')
                valid_until = datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z').strftime('%m-%d-%Y %H:%M:%S UTC')
                return f"SSL Valid:\n  - From:  {valid_from}\n  - Until: {valid_until}"
    except ssl.SSLError:
        return "SSL Error: No SSL certificate found"
    except socket.timeout:
        return "SSL Error: Connection timed out"
    except ConnectionRefusedError:
        return "SSL Error: Connection refused (No SSL service running on port 443)"
    except Exception as e:
        return f"SSL Error: {e}"

def get_http_headers(domain_name):
    try:
        response = requests.get(f"http://{domain_name}", timeout=10)
        headers = response.headers
        key_headers = ['Server', 'Content-Type', 'Last-Modified']
        return "\n".join([f"  - {header}: {headers.get(header, 'Not Available')}" for header in key_headers])
    except requests.ConnectionError:
        return "  - Could not establish a connection"
    except requests.Timeout:
        return "  - Connection timed out"
    except Exception as e:
        return f"  - Error: {e}"

def get_alexa_rank(domain_name):
    try:
        response = requests.get(f"http://data.alexa.com/data?cli=10&url={domain_name}")
        rank = response.text.split('<POPULARITY URL')[1].split('TEXT="')[1].split('"')[0]
        return f"Alexa Traffic Rank: {rank}"
    except Exception:
        return "Alexa Traffic Rank: N/A"

def calculate_domain_age(creation_date):
    if isinstance(creation_date, list):
        creation_date = creation_date[0]
    if creation_date:
        age = datetime.now() - creation_date
        return f"Domain Age: {age.days // 365} Years, {age.days % 365} Days"
    return "Domain Age: N/A"

def display_info(domain_info, domain_name, verbose=False):
    output = [f"\n{'=' * 40}\nDomain: {domain_name}\n{'=' * 40}"]

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
            output.append(f"  - {ns}")

    if domain_info.dnssec:
        output.append(f"\nDNSSEC: {domain_info.dnssec}")

    if domain_info.emails:
        output.append("\nContact Emails:")
        if isinstance(domain_info.emails, list):
            output.extend([f"  - {email}" for email in domain_info.emails])
        else:
            output.append(f"  - {domain_info.emails}")

    try:
        ip_address = socket.gethostbyname(domain_name)
        output.append(f"\nIP Address: {ip_address}")
        output.append(f"Reverse IP: {get_reverse_ip(ip_address)}")
    except Exception as e:
        output.append(f"\nIP Address: Error retrieving IP - {e}")

    output.append(f"\n{get_alexa_rank(domain_name)}")
    output.append(f"{calculate_domain_age(domain_info.creation_date)}")
    output.append(f"Geolocation: {get_geolocation(ip_address)}")

    output.append("\nHTTP Header Information:")
    output.append(get_http_headers(domain_name))

    ssl_info = get_ssl_info(domain_name)
    if "SSL Valid:" in ssl_info:
        output.append("\n" + ssl_info)
    else:
        output.append("\n" + ssl_info.split(":")[0])

    if verbose:
        output.append("\n[Verbose Mode]")
        output.append(f"  Domain Status: {domain_info.status}")
        output.append(f"  Whois Server: {domain_info.whois_server}")

    return "\n".join(output)

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

    final_output = "\n".join(results)
    print(final_output)

    if output_file:
        with open(output_file, "w") as file:
            file.write(final_output)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: python3 {sys.argv[0]} <domain/subdomain> [-v] [-o output_file]")
        sys.exit(1)

    verbose = "-v" in sys.argv
    output_file_flag = "-o" in sys.argv
    output_file = sys.argv[sys.argv.index("-o") + 1] if output_file_flag and sys.argv.index("-o") + 1 < len(sys.argv) else None
    domain_list = [arg for arg in sys.argv[1:] if arg != "-v" and arg != "-o"]

    process_domains(domain_list, verbose, output_file)
