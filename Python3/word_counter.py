#!/usr/bin/env python3

"""Count occurrences of each word in a text file."""

import argparse
import sys
from collections import Counter
from pathlib import Path


def count_words(path: Path) -> Counter:
    text = path.read_text(encoding="utf-8", errors="replace")
    return Counter(text.lower().split())


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Count occurrences of each word in a text file."
    )
    parser.add_argument("file", type=Path, help="Path to the text file")
    parser.add_argument(
        "-n",
        "--top",
        type=int,
        default=0,
        help="Show only the top N most common words (default: all).",
    )
    args = parser.parse_args()

    if not args.file.is_file():
        print(f"Error: file does not exist: {args.file}", file=sys.stderr)
        return 1

    counts = count_words(args.file)
    items = counts.most_common(args.top) if args.top > 0 else counts.most_common()
    for word, count in items:
        print(f"{word}: {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
