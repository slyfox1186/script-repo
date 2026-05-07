#!/usr/bin/env python3

"""Prefix every regular file in a directory with a chosen string."""

import argparse
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Directory containing files to rename.")
    parser.add_argument("prefix", help="Prefix to prepend (a single underscore is added between prefix and original name).")
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="Show what would happen without renaming anything.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.directory.is_dir():
        print(f"Error: not a directory: {args.directory}", file=sys.stderr)
        return 1

    prefix = args.prefix
    files = sorted(p for p in args.directory.iterdir() if p.is_file())
    if not files:
        print("No regular files to rename.")
        return 0

    renamed = 0
    for src in files:
        if src.name.startswith(f"{prefix}_"):
            continue  # Already renamed; idempotent re-run.
        dst = src.with_name(f"{prefix}_{src.name}")
        if dst.exists():
            print(f"Skipping '{src.name}': '{dst.name}' already exists.", file=sys.stderr)
            continue
        if args.dry_run:
            print(f"DRY-RUN: {src.name} -> {dst.name}")
        else:
            src.rename(dst)
            renamed += 1
    if not args.dry_run:
        print(f"Renamed {renamed} file(s) in {args.directory}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
