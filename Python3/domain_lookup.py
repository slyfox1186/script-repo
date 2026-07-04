#!/usr/bin/env python3
"""Domain lookup tool: WHOIS, DNS, geolocation, SSL, and HTTP headers.

Features:
- Concurrent lookups across domains while preserving input order
- IP address resolution (IPv4 + IPv6) and reverse DNS
- IP geolocation via ipinfo.io over HTTPS
- SSL certificate validity over TLSv1.2+ only
- Key HTTP response headers (HTTPS preferred, HTTP fallback)
- Strict input validation, structured logging on stderr, exit codes

Usage:
    python3 domain_lookup.py example.com python.org -o report.txt
    python3 domain_lookup.py example.com -v -w 16
"""

from __future__ import annotations

import argparse
import concurrent.futures
import ipaddress
import logging
import re
import socket
import ssl
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Any, Final

import certifi
import requests
import whois
from whois.exceptions import WhoisDomainNotFoundError, WhoisError

if TYPE_CHECKING:
    from collections.abc import Sequence

HTTP_TIMEOUT_SEC: Final[float] = 10.0
SOCKET_TIMEOUT_SEC: Final[float] = 10.0
DEFAULT_WORKERS: Final[int] = 8
USER_AGENT: Final[str] = "domain-lookup/2.0 (+https://github.com/)"
SEPARATOR: Final[str] = "=" * 40
DATE_FORMAT: Final[str] = "%m-%d-%Y %H:%M:%S %Z"
SSL_CERT_DATE_FORMAT: Final[str] = "%b %d %H:%M:%S %Y %Z"
HTTP_HEADERS_OF_INTEREST: Final[tuple[str, ...]] = (
    "Server",
    "Content-Type",
    "Last-Modified",
)

# RFC 1035 / 1123 hostname syntax. Total 1..253 chars, label 1..63 chars,
# no leading or trailing hyphens, at least one dot.
_DOMAIN_RE: Final[re.Pattern[str]] = re.compile(
    r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)"
    r"(?:\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))+$"
)

_LOG: Final[logging.Logger] = logging.getLogger("domain_lookup")


def validate_domain(domain: str) -> str:
    """Validate a hostname against RFC 1035/1123 syntax (argparse type)."""
    if not _DOMAIN_RE.match(domain):
        msg = f"Invalid domain name: {domain!r}"
        raise argparse.ArgumentTypeError(msg)
    return domain


def positive_int(value: str) -> int:
    """Parse a strictly positive integer (argparse type)."""
    try:
        parsed = int(value)
    except ValueError as exc:
        msg = f"{value!r} is not a valid integer"
        raise argparse.ArgumentTypeError(msg) from exc
    if parsed < 1:
        msg = f"{value!r} must be >= 1"
        raise argparse.ArgumentTypeError(msg)
    return parsed


def _coerce_to_datetime(value: object) -> datetime | None:
    """Reduce a python-whois date field (datetime, list, None) to one datetime."""
    if isinstance(value, list):
        return next((v for v in value if isinstance(v, datetime)), None)
    return value if isinstance(value, datetime) else None


def _as_utc(value: datetime) -> datetime:
    """Return a timezone-aware datetime, assuming naive values are UTC."""
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def _format_whois_date(value: object) -> str:
    moment = _coerce_to_datetime(value)
    if moment is None:
        return "N/A"
    return _as_utc(moment).astimezone(timezone.utc).strftime(DATE_FORMAT)


def _get_reverse_dns(ip_address: str) -> str:
    try:
        return socket.gethostbyaddr(ip_address)[0]
    except socket.herror:
        return "No reverse DNS record found"
    except (socket.gaierror, OSError) as exc:
        return f"Reverse DNS error: {exc}"


def _get_geolocation(session: requests.Session, ip_address: str) -> str:
    try:
        ipaddress.ip_address(ip_address)
    except ValueError:
        return "Geolocation: invalid IP address"

    try:
        response = session.get(
            f"https://ipinfo.io/{ip_address}/json", timeout=HTTP_TIMEOUT_SEC
        )
        response.raise_for_status()
        data = response.json()
    except requests.RequestException as exc:
        _LOG.warning("Geolocation lookup failed for %s: %s", ip_address, exc)
        return "Geolocation: lookup failed"
    except ValueError:
        return "Geolocation: invalid response payload"

    if not isinstance(data, dict):
        return "Geolocation: invalid response payload"
    country = data.get("country") or "Unknown"
    city = data.get("city") or "Unknown"
    org = data.get("org") or "Unknown"
    return f"Country: {country}, City: {city}, ISP/Org: {org}"


def _get_ssl_info(domain_name: str) -> str:
    context = ssl.create_default_context(cafile=certifi.where())
    context.minimum_version = ssl.TLSVersion.TLSv1_2

    try:
        with (
            socket.create_connection(
                (domain_name, 443), timeout=SOCKET_TIMEOUT_SEC
            ) as sock,
            context.wrap_socket(sock, server_hostname=domain_name) as ssock,
        ):
            cert = ssock.getpeercert() or {}
    except (ssl.SSLError, OSError) as exc:
        return f"SSL Information: Error - {exc}"

    not_before = cert.get("notBefore")
    not_after = cert.get("notAfter")
    if not (isinstance(not_before, str) and isinstance(not_after, str)):
        return "SSL Information: validity dates not available"

    try:
        valid_from = datetime.strptime(not_before, SSL_CERT_DATE_FORMAT).replace(
            tzinfo=timezone.utc
        )
        valid_until = datetime.strptime(not_after, SSL_CERT_DATE_FORMAT).replace(
            tzinfo=timezone.utc
        )
    except ValueError as exc:
        return f"SSL Information: Error parsing dates - {exc}"

    return (
        f"SSL Information: Valid from {valid_from.strftime(DATE_FORMAT)} "
        f"until {valid_until.strftime(DATE_FORMAT)}"
    )


def _get_http_headers(session: requests.Session, domain_name: str) -> str:
    for scheme in ("https", "http"):
        try:
            response = session.get(
                f"{scheme}://{domain_name}",
                timeout=HTTP_TIMEOUT_SEC,
                allow_redirects=True,
            )
        except requests.RequestException as exc:
            _LOG.debug("HTTP fetch failed for %s://%s: %s", scheme, domain_name, exc)
            continue
        return "\n".join(
            f"  - {key}: {response.headers.get(key, 'Not Available')}"
            for key in HTTP_HEADERS_OF_INTEREST
        )
    return "Could not fetch HTTP headers"


def _calculate_domain_age(creation_date: object) -> str:
    moment = _coerce_to_datetime(creation_date)
    if moment is None:
        return "Domain Age: N/A"
    delta = datetime.now(timezone.utc) - _as_utc(moment)
    years, days_remainder = divmod(delta.days, 365)
    return f"Domain Age: {years} Years, {days_remainder} Days"


def _coerce_to_list(value: object) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, (list, tuple, set)):
        return [str(v) for v in value if v]
    return [str(value)]


# `info` is python-whois's WhoisEntry, a dict subclass with __getattr__
# returning Any. The library declares whois.whois() as dict[str, Any], so
# typing this boundary as Any is the honest choice.
def _render_report(
    session: requests.Session,
    info: Any,  # noqa: ANN401
    domain_name: str,
    *,
    verbose: bool,
) -> str:
    """Build a human-readable report for a single resolved domain."""
    lines: list[str] = [
        f"\n{SEPARATOR}\n",
        f"Domain: {domain_name}",
        f"Registrant Name: {info.name}",
        f"Registrant Organization: {info.org}",
        f"Registrar: {info.registrar}",
        "",
        f"Creation Date: {_format_whois_date(info.creation_date)}",
        f"Expiration Date: {_format_whois_date(info.expiration_date)}",
        f"Updated Date: {_format_whois_date(info.updated_date)}",
    ]

    name_servers = sorted({ns.lower() for ns in _coerce_to_list(info.name_servers)})
    if name_servers:
        lines.append("")
        lines.append("Name Servers:")
        lines.extend(f"  - {ns}" for ns in name_servers)

    if info.dnssec:
        lines.append("")
        lines.append(f"DNSSEC: {info.dnssec}")

    emails = _coerce_to_list(info.emails)
    if emails:
        lines.append("")
        lines.append("Contact Emails:")
        lines.extend(f"  - {email}" for email in emails)

    ip_address: str | None = None
    try:
        ip_address = socket.gethostbyname(domain_name)
    except socket.gaierror as exc:
        lines.append("")
        lines.append(f"IP Address: Error retrieving IP - {exc}")
    else:
        lines.append("")
        lines.append(f"IP Address: {ip_address}")
        lines.append(f"Reverse IP: {_get_reverse_dns(ip_address)}")

    lines.append("")
    lines.append(_calculate_domain_age(info.creation_date))
    if ip_address is not None:
        lines.append(f"Geolocation: {_get_geolocation(session, ip_address)}")

    lines.append("")
    lines.append("HTTP Header Information:")
    lines.append(_get_http_headers(session, domain_name))

    lines.append("")
    lines.append(_get_ssl_info(domain_name))

    if verbose:
        lines.append("")
        lines.append("[Verbose Mode]")
        lines.append(f"  Domain Status: {info.status}")
        lines.append(f"  Whois Server: {info.whois_server}")

    return "\n".join(lines)


def _build_session() -> requests.Session:
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})
    return session


def _process_one(domain: str, *, verbose: bool) -> str:
    """Generate the report (or an error line) for a single domain."""
    try:
        info = whois.whois(domain)
    except WhoisDomainNotFoundError:
        return f"Domain '{domain}' is not registered (WHOIS reports no match)."
    except WhoisError as exc:
        return f"WHOIS lookup failed for '{domain}': {exc}"
    except OSError as exc:
        # Covers TimeoutError, ConnectionError, socket.gaierror, etc.
        return f"Network error during WHOIS for '{domain}': {exc}"

    if not getattr(info, "domain_name", None):
        return f"Domain '{domain}' has no WHOIS record (likely unregistered)."

    with _build_session() as session:
        return _render_report(session, info, domain, verbose=verbose)


def process_domains(
    domains: Sequence[str],
    *,
    verbose: bool = False,
    output_file: Path | None = None,
    workers: int = DEFAULT_WORKERS,
) -> str:
    """Process domains concurrently and return the combined report."""
    if not domains:
        return ""

    pool_size = max(1, min(workers, len(domains)))
    results: list[str] = [""] * len(domains)
    with concurrent.futures.ThreadPoolExecutor(max_workers=pool_size) as pool:
        future_to_index = {
            pool.submit(_process_one, domain, verbose=verbose): idx
            for idx, domain in enumerate(domains)
        }
        for future in concurrent.futures.as_completed(future_to_index):
            idx = future_to_index[future]
            try:
                results[idx] = future.result()
            except Exception as exc:  # noqa: BLE001 -- boundary: keep batch alive
                _LOG.exception("Unhandled error processing %r", domains[idx])
                results[idx] = (
                    f"Unexpected error processing '{domains[idx]}': {exc}"
                )

    report = "\n".join(results)
    sys.stdout.write(report)
    if not report.endswith("\n"):
        sys.stdout.write("\n")
    sys.stdout.flush()

    if output_file is not None:
        output_file.write_text(report, encoding="utf-8")
        _LOG.info("Report written to %s", output_file)
    return report


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Look up WHOIS, DNS, SSL, and HTTP info for one or more domains."
        ),
    )
    parser.add_argument(
        "domains",
        nargs="+",
        type=validate_domain,
        help="Domain names to look up",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Show extra status fields and enable debug logging",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Write the report to this file in addition to stdout",
    )
    parser.add_argument(
        "-w",
        "--workers",
        type=positive_int,
        default=DEFAULT_WORKERS,
        help=(
            "Max concurrent domain lookups "
            f"(default: {DEFAULT_WORKERS}, must be >= 1)"
        ),
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)

    # Keep third-party loggers (urllib3, requests, etc.) at WARNING; only
    # raise the level on our own logger when --verbose is requested.
    logging.basicConfig(
        level=logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    if args.verbose:
        _LOG.setLevel(logging.DEBUG)

    process_domains(
        args.domains,
        verbose=args.verbose,
        output_file=args.output,
        workers=args.workers,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
