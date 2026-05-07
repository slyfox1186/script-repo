#!/usr/bin/env python3

"""Domain lookup tool: WHOIS, DNS, geolocation, SSL, and HTTP headers.

Features:
- Batch lookup for multiple domains in a single invocation
- Visual separators between domains for readability
- IP address resolution and reverse DNS lookup
- IP geolocation via ipinfo.io over HTTPS
- SSL certificate validity (TLSv1.2+ only)
- Key HTTP response headers (HTTPS preferred, HTTP fallback)
- Optional output to a file via -o

Usage: python3 domain_lookup.py reddit.com google.com -o output.txt
"""

import argparse
import re
import socket
import ssl
import sys
from datetime import datetime

import certifi
import requests
import whois

DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)"
    r"(?:\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))+$"
)
IPV4_RE = re.compile(r"^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$")
HTTP_TIMEOUT = 10
SOCKET_TIMEOUT = 10


def validate_domain(domain):
    """Validate a domain name before interpolating it into URLs or sockets."""
    if not DOMAIN_RE.match(domain):
        raise ValueError(f"Invalid domain name: {domain!r}")
    return domain


def validate_ipv4(ip):
    """Validate an IPv4 string before interpolating it into a URL."""
    if not IPV4_RE.match(ip):
        raise ValueError(f"Invalid IPv4 address: {ip!r}")
    return ip


def format_dates(dates):
    """Format a whois date (or list of dates) for output."""
    if isinstance(dates, list):
        dates = dates[0] if dates else None
    if dates:
        return dates.strftime("%m-%d-%Y %H:%M:%S UTC")
    return "N/A"


def get_reverse_ip(ip_address):
    """Return the reverse DNS hostname for an IP address."""
    try:
        return socket.gethostbyaddr(ip_address)[0]
    except socket.herror:
        return "No reverse DNS record found"
    except OSError as e:
        return f"Error retrieving hostname - {e}"


def get_geolocation(session, ip_address):
    """Look up geolocation for an IP address via ipinfo.io over HTTPS."""
    try:
        validate_ipv4(ip_address)
        response = session.get(
            f"https://ipinfo.io/{ip_address}/json", timeout=HTTP_TIMEOUT
        )
        response.raise_for_status()
        data = response.json()
        country = data.get("country") or "Unknown"
        city = data.get("city") or "Unknown"
        org = data.get("org") or "Unknown"
        return f"Country: {country}, City: {city}, ISP/Org: {org}"
    except (requests.RequestException, ValueError):
        return "Error retrieving geolocation"


def get_ssl_info(domain_name):
    """Return SSL certificate validity period over a TLSv1.2+ connection."""
    try:
        context = ssl.create_default_context(cafile=certifi.where())
        context.minimum_version = ssl.TLSVersion.TLSv1_2

        with socket.create_connection((domain_name, 443), timeout=SOCKET_TIMEOUT) as sock:
            with context.wrap_socket(sock, server_hostname=domain_name) as ssock:
                cert = ssock.getpeercert() or {}

        not_before = cert.get("notBefore")
        not_after = cert.get("notAfter")
        if not (not_before and not_after):
            return "SSL Information: Validity dates not available"

        valid_from = datetime.strptime(not_before, "%b %d %H:%M:%S %Y %Z").strftime(
            "%m-%d-%Y %H:%M:%S UTC"
        )
        valid_until = datetime.strptime(not_after, "%b %d %H:%M:%S %Y %Z").strftime(
            "%m-%d-%Y %H:%M:%S UTC"
        )
        return f"SSL Information: Valid from {valid_from} until {valid_until}"
    except (ssl.SSLError, socket.gaierror, OSError, ValueError) as e:
        return f"SSL Information: Error - {e}"


def get_http_headers(session, domain_name):
    """Fetch a few key response headers, preferring HTTPS."""
    for scheme in ("https", "http"):
        try:
            response = session.get(f"{scheme}://{domain_name}", timeout=HTTP_TIMEOUT)
            keys = ("Server", "Content-Type", "Last-Modified")
            return "\n".join(
                f"  - {k}: {response.headers.get(k, 'Not Available')}" for k in keys
            )
        except requests.RequestException:
            continue
    return "Could not fetch HTTP headers"


def calculate_domain_age(creation_date):
    """Calculate the age of a domain from its creation date."""
    if isinstance(creation_date, list):
        creation_date = creation_date[0] if creation_date else None
    if not creation_date:
        return "Domain Age: N/A"
    age = datetime.now() - creation_date
    return f"Domain Age: {age.days // 365} Years, {age.days % 365} Days"


def display_info(session, domain_info, domain_name, verbose=False):
    """Compile detailed domain information for display."""
    output = [f"\n{'=' * 40}\n\nDomain: {domain_name}"]

    output.append(f"Registrant Name: {domain_info.name}")
    output.append(f"Registrant Organization: {domain_info.org}")
    output.append(f"Registrar: {domain_info.registrar}")

    output.append(f"\nCreation Date: {format_dates(domain_info.creation_date)}")
    output.append(f"Expiration Date: {format_dates(domain_info.expiration_date)}")
    output.append(f"Updated Date: {format_dates(domain_info.updated_date)}")

    if domain_info.name_servers:
        nameservers = sorted({ns.lower() for ns in domain_info.name_servers})
        output.append("\nName Servers:")
        output.extend(f"  - {ns}" for ns in nameservers)

    if domain_info.dnssec:
        output.append(f"\nDNSSEC: {domain_info.dnssec}")

    if domain_info.emails:
        emails = (
            domain_info.emails
            if isinstance(domain_info.emails, list)
            else [domain_info.emails]
        )
        output.append("\nContact Emails:")
        output.extend(f"  - {email}" for email in emails)

    ip_address = None
    try:
        ip_address = socket.gethostbyname(domain_name)
        output.append(f"\nIP Address: {ip_address}")
        output.append(f"Reverse IP: {get_reverse_ip(ip_address)}")
    except socket.gaierror as e:
        output.append(f"\nIP Address: Error retrieving IP - {e}")

    output.append(f"\n{calculate_domain_age(domain_info.creation_date)}")
    if ip_address:
        output.append(f"Geolocation: {get_geolocation(session, ip_address)}")

    output.append("\nHTTP Header Information:")
    output.append(get_http_headers(session, domain_name))

    output.append(f"\n{get_ssl_info(domain_name)}")

    if verbose:
        output.append("\n[Verbose Mode]")
        output.append(f"  Domain Status: {domain_info.status}")
        output.append(f"  Whois Server: {domain_info.whois_server}")

    return "\n".join(output)


def is_domain_available(domain):
    """Check whether a domain appears to be available for registration."""
    try:
        whois_result = whois.whois(domain)
        return not whois_result.domain_name
    except Exception:
        return True


def process_domains(domains, verbose=False, output_file=None):
    """Process a list of domains and compile information."""
    results = []
    with requests.Session() as session:
        for domain in domains:
            try:
                domain_info = whois.whois(domain)
                if not domain_info.status or "No match for domain" in str(
                    domain_info.status
                ):
                    available = is_domain_available(domain)
                    state = "available" if available else "not available"
                    result = f"Domain '{domain}' is {state} for registration."
                else:
                    result = display_info(session, domain_info, domain, verbose)
            except Exception as e:
                result = f"An error occurred while processing '{domain}': {e}"
            results.append(result)

    final_output = "\n".join(results)
    print(final_output)

    if output_file:
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(final_output)


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Look up WHOIS, DNS, SSL, and HTTP info for one or more domains.",
    )
    parser.add_argument("domains", nargs="+", help="Domain names to look up")
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Show extra status fields"
    )
    parser.add_argument("-o", "--output", help="Write the report to this file")
    return parser.parse_args(argv)


if __name__ == "__main__":
    args = parse_args(sys.argv[1:])
    domain_list = [validate_domain(d) for d in args.domains]
    process_domains(domain_list, verbose=args.verbose, output_file=args.output)
