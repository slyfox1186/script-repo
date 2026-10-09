#!/usr/bin/env python3

"""Append a video record to video_data.json (creating it if missing)."""

import argparse
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("filename", help="Output filename for the video.")
    parser.add_argument("extension", help="Container/extension (e.g. mp4).")
    parser.add_argument("path", help="Local path the video should be saved to.")
    parser.add_argument("url", help="Source URL of the video.")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("video_data.json"),
        help="JSON file to append into (default: video_data.json).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    record = {
        "filename": args.filename,
        "path": args.path,
        "url": args.url,
        "extension": args.extension,
    }

    existing: list[dict] = []
    if args.output.exists():
        try:
            with args.output.open("r", encoding="utf-8") as fh:
                existing = json.load(fh)
            if not isinstance(existing, list):
                raise ValueError("expected a JSON array")
        except (json.JSONDecodeError, ValueError) as exc:
            print(
                f"Warning: '{args.output}' is not a valid JSON list ({exc}); starting fresh.",
                file=sys.stderr,
            )
            existing = []

    existing.append(record)
    with args.output.open("w", encoding="utf-8") as fh:
        json.dump(existing, fh, indent=2)
    print(f"Video details added to {args.output}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
