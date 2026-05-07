#!/usr/bin/env python3

"""Walk a directory tree and report image files that ImageMagick can't decode."""

import argparse
import concurrent.futures
import multiprocessing
import os
import subprocess
import sys
from pathlib import Path

from tqdm import tqdm

DEFAULT_EXTENSIONS = (".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif", ".webp")


def check_image_validity(image_path: str) -> str | None:
    try:
        result = subprocess.run(
            ["identify", "-regard-warnings", image_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        raise SystemExit(
            "ImageMagick's 'identify' is not installed or not on PATH."
        )
    return image_path if result.returncode != 0 else None


def find_images(directory: Path, extensions: tuple[str, ...]) -> list[str]:
    matches: list[str] = []
    lowered = tuple(e.lower() for e in extensions)
    for root, _, files in os.walk(directory):
        for name in files:
            if name.lower().endswith(lowered):
                matches.append(os.path.join(root, name))
    return matches


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "directory",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="Directory to scan (default: this script's directory).",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent / "corrupted_images.txt",
        help="Output file path.",
    )
    parser.add_argument(
        "-e",
        "--extensions",
        nargs="+",
        default=list(DEFAULT_EXTENSIONS),
        help=f"Image extensions to scan (default: {', '.join(DEFAULT_EXTENSIONS)}).",
    )
    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=multiprocessing.cpu_count(),
        help="Worker threads (default: CPU count).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.directory.is_dir():
        print(f"Not a directory: {args.directory}", file=sys.stderr)
        return 1

    print(f"Scanning {args.directory} for image files...")
    images = find_images(args.directory, tuple(args.extensions))
    if not images:
        print("No image files found.")
        return 0
    print(f"Found {len(images)} candidate image(s); validating with 'identify'...")

    corrupted: list[str] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as executor:
        futures = [executor.submit(check_image_validity, p) for p in images]
        for future in tqdm(
            concurrent.futures.as_completed(futures),
            total=len(futures),
            desc="Validating",
            unit="img",
        ):
            result = future.result()
            if result:
                corrupted.append(result)

    corrupted.sort()
    args.output.write_text("\n".join(corrupted) + ("\n" if corrupted else ""), encoding="utf-8")
    print(f"Found {len(corrupted)} corrupted image(s); list written to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
