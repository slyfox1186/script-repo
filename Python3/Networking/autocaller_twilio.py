#!/usr/bin/env python3

"""Place repeated Twilio voice calls reading a fixed message via TwiML.

Credentials and phone numbers are read from environment variables so they
never live in source control.

Required env vars:
    TWILIO_ACCOUNT_SID
    TWILIO_AUTH_TOKEN
    TWILIO_FROM_NUMBER
    TWILIO_TO_NUMBER
"""

import argparse
import os
import sys
import time

from twilio.rest import Client

DEFAULT_MESSAGE = (
    "This is an important message from your automated system. "
    "Please listen carefully as we provide important information. "
    "Thank you for your attention."
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-n",
        "--max-calls",
        type=int,
        default=0,
        help="Stop after this many calls (default: 0 = unlimited).",
    )
    parser.add_argument(
        "-i",
        "--interval",
        type=float,
        default=1.0,
        help="Seconds to sleep between calls (default: 1.0).",
    )
    parser.add_argument(
        "-m",
        "--message",
        default=DEFAULT_MESSAGE,
        help="The text to read during the call.",
    )
    return parser.parse_args()


def get_required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def main() -> int:
    args = parse_args()
    if args.interval < 0:
        print("Interval must be non-negative.", file=sys.stderr)
        return 1

    account_sid = get_required_env("TWILIO_ACCOUNT_SID")
    auth_token = get_required_env("TWILIO_AUTH_TOKEN")
    from_number = get_required_env("TWILIO_FROM_NUMBER")
    to_number = get_required_env("TWILIO_TO_NUMBER")

    client = Client(account_sid, auth_token)
    twiml = f"<Response><Say>{args.message}</Say></Response>"

    placed = 0
    try:
        while True:
            call = client.calls.create(twiml=twiml, to=to_number, from_=from_number)
            placed += 1
            print(f"Call {placed} placed -> {to_number}, SID={call.sid}")
            if args.max_calls and placed >= args.max_calls:
                print(f"Reached --max-calls={args.max_calls}; stopping.")
                break
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\nStopping the autodialer.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
