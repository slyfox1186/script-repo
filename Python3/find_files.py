#!/usr/bin/env python3
"""Find files by extension, name, regex, path substring, and size.

Examples:
    # Find all .py and .sh files larger than 1 MB, sorted by size
    find-files.py -d ~/projects -X py,sh --min-size 1M -s

    # Find images excluding any path containing 'thumbnails', null-separated for xargs -0
    find-files.py -d ~/Pictures -X jpg,jpeg,png,gif --exclude thumbnails --null | xargs -0 ls

    # JSON output, capped at 50 results
    find-files.py -d /var/log -N '*.log' --limit 50 --json

    # Regex match against the full path
    find-files.py -d ~/code -R 'tests?/.+\\.py$'

    # Interactive extension picker (legacy; runs only when no extension/name/regex flag is given)
    find-files.py -d ~/Downloads
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Iterator, Sequence

EXTENSION_CATEGORIES: dict[str, tuple[str, ...]] = {
    "archives":   (".zip", ".rar", ".tar", ".gz", ".bz2", ".xz", ".zst", ".7z"),
    "documents":  (".pdf", ".docx", ".doc", ".txt", ".md", ".odt", ".rtf",
                   ".xlsx", ".xls", ".pptx", ".ppt"),
    "images":     (".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".svg",
                   ".webp", ".heic", ".avif"),
    "audio":      (".mp3", ".wav", ".aac", ".flac", ".ogg", ".m4a", ".opus"),
    "code":       (".py", ".js", ".ts", ".java", ".c", ".cpp", ".h", ".hpp",
                   ".cs", ".php", ".rb", ".go", ".rs", ".kt", ".swift"),
    "shell":      (".sh", ".bash", ".zsh", ".fish", ".ps1", ".bat", ".cmd", ".vbs"),
    "video":      (".mp4", ".avi", ".mkv", ".flv", ".wmv", ".mov", ".webm", ".m4v"),
    "web":        (".html", ".htm", ".css", ".scss", ".sass", ".less", ".jsx", ".tsx", ".vue"),
}

# Suffix multipliers for human-friendly size strings ("1.5G", "500K").
SIZE_UNITS: dict[str, int] = {
    "B": 1,
    "K": 1024, "KB": 1024,
    "M": 1024**2, "MB": 1024**2,
    "G": 1024**3, "GB": 1024**3,
    "T": 1024**4, "TB": 1024**4,
}

LEGACY_DEFAULT_UNIT = SIZE_UNITS["M"]  # bare integer in --min/max-size means MB (backward compat)
BYTES_PER_MB = 1024 * 1024

LOG = logging.getLogger("find-files")


def parse_size(value: str) -> int:
    """Parse a size string like ``500``, ``500K``, ``1.5G`` into bytes.

    A bare integer (no suffix) is interpreted as megabytes for backward
    compatibility with the original script's ``--min-size``/``--max-size`` flags.
    """
    value = value.strip().upper()
    if not value:
        raise ValueError("size cannot be empty")

    match = re.fullmatch(r"(\d+(?:\.\d+)?)\s*([A-Z]+)?", value)
    if not match:
        raise ValueError(f"invalid size: {value!r}")
    number, unit = match.groups()
    multiplier = LEGACY_DEFAULT_UNIT if unit is None else SIZE_UNITS.get(unit)
    if multiplier is None:
        raise ValueError(f"unknown size unit {unit!r}; expected one of {sorted(SIZE_UNITS)}")
    return int(float(number) * multiplier)


def normalize_extensions(raw: str) -> tuple[str, ...]:
    """Turn ``"jpg,.PNG, gif"`` into ``(".jpg", ".png", ".gif")``."""
    extensions = []
    for token in raw.split(","):
        token = token.strip().lower()
        if not token:
            continue
        extensions.append(token if token.startswith(".") else f".{token}")
    if not extensions:
        raise ValueError("no extensions provided")
    return tuple(extensions)


def interactive_extension_picker() -> tuple[str, ...]:
    """Prompt the user to pick an extension category. Used only when no flag is given."""
    print("Select a category of files to search for:")
    items = list(EXTENSION_CATEGORIES.items())
    for i, (name, exts) in enumerate(items, start=1):
        print(f"  {i}. {name} ({', '.join(exts)})")
    custom_index = len(items) + 1
    print(f"  {custom_index}. custom (enter your own extensions)")

    while True:
        try:
            raw = input("Enter the number of your choice: ").strip()
        except EOFError:
            raise SystemExit("no selection provided") from None
        try:
            choice = int(raw)
        except ValueError:
            print("Invalid input. Please enter a number.")
            continue
        if 1 <= choice <= len(items):
            return items[choice - 1][1]
        if choice == custom_index:
            try:
                raw = input("Enter extensions separated by commas (e.g., jpg,png,gif): ")
            except EOFError:
                raise SystemExit("no extensions provided") from None
            try:
                return normalize_extensions(raw)
            except ValueError as exc:
                print(f"Error: {exc}")
                continue
        print("Invalid choice. Please try again.")


@dataclass(frozen=True)
class FileMatch:
    """A file that matched the search criteria."""
    path: Path
    size: int


@dataclass
class SearchOptions:
    """All the knobs ``find_files`` accepts. Created from parsed CLI args."""
    directory: Path
    extensions: tuple[str, ...] | None = None
    name_glob: str | None = None
    regex: re.Pattern[str] | None = None
    include: str | None = None
    exclude: str | None = None
    min_size: int | None = None
    max_size: int | None = None
    max_depth: int | None = None
    follow_symlinks: bool = False


def _walk(base: Path, *, max_depth: int | None, follow_symlinks: bool) -> Iterator[Path]:
    """Yield every file under ``base``. Iterative and bounded; never recurses Python's stack."""
    base_depth = len(base.parts)
    for root, dirs, files in os.walk(base, followlinks=follow_symlinks, onerror=_on_walk_error):
        root_path = Path(root)
        depth = len(root_path.parts) - base_depth
        if max_depth is not None and depth >= max_depth:
            dirs.clear()  # prune; don't descend further
        for filename in files:
            yield root_path / filename


def _on_walk_error(exc: OSError) -> None:
    LOG.warning("cannot enter %s: %s", exc.filename, exc.strerror or exc)


def find_files(opts: SearchOptions) -> Iterator[FileMatch]:
    """Yield ``FileMatch`` for every file under ``opts.directory`` that satisfies all filters."""
    if not opts.directory.is_dir():
        raise NotADirectoryError(f"not a directory: {opts.directory}")

    for entry in _walk(opts.directory, max_depth=opts.max_depth, follow_symlinks=opts.follow_symlinks):
        if opts.extensions and entry.suffix.lower() not in opts.extensions:
            continue
        if opts.name_glob and not entry.match(opts.name_glob):
            continue
        path_str = str(entry)
        if opts.regex and not opts.regex.search(path_str):
            continue
        path_lower = path_str.lower()
        if opts.include and opts.include.lower() not in path_lower:
            continue
        if opts.exclude and opts.exclude.lower() in path_lower:
            continue
        try:
            size = entry.stat().st_size
        except OSError as exc:
            LOG.warning("cannot stat %s: %s", entry, exc.strerror or exc)
            continue
        if opts.min_size is not None and size < opts.min_size:
            continue
        if opts.max_size is not None and size > opts.max_size:
            continue
        LOG.debug("match: %s (%d bytes)", entry, size)
        yield FileMatch(path=entry, size=size)


def emit_results(
    matches: Sequence[FileMatch],
    *,
    out: object,  # io.TextIOBase or BufferedWriter when null mode
    json_mode: bool,
    null_mode: bool,
    print_sizes: bool,
) -> None:
    """Write matches to ``out`` in the requested format."""
    if json_mode:
        payload = [{"path": str(m.path), "size_bytes": m.size} for m in matches]
        out.write(json.dumps(payload, indent=2))
        out.write("\n")
        return

    if null_mode:
        # Null-terminated paths for xargs -0; sizes intentionally omitted (machine output).
        for match in matches:
            out.write(f"{match.path}\0")
        return

    for match in matches:
        if print_sizes:
            out.write(f"{match.path} - {match.size / BYTES_PER_MB:.2f} MB\n")
        else:
            out.write(f"{match.path}\n")


def build_parser() -> argparse.ArgumentParser:
    """Construct the CLI parser."""
    parser = argparse.ArgumentParser(
        prog="find-files.py",
        description="Find files by extension, name, regex, substring, and size.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Size units: bare numbers default to MB for backward compat; "
            "use B/K/M/G/T (e.g., 500K, 1.5G) to be explicit.\n"
            "If no extension/name/regex flag is given, an interactive picker runs."
        ),
    )
    parser.add_argument("-d", "--directory", required=True, type=Path,
                        help="directory to search (required)")
    parser.add_argument("-X", "--ext", type=normalize_extensions, default=None,
                        help="comma-separated extensions, e.g. py,sh,jpg")
    parser.add_argument("-N", "--name", dest="name_glob",
                        help="glob pattern matched against file path, e.g. '*.log'")
    parser.add_argument("-R", "--regex", type=re.compile,
                        help="regex matched against the full file path")
    parser.add_argument("-i", "--include",
                        help="case-insensitive substring that must appear in the path")
    parser.add_argument("-e", "--exclude",
                        help="case-insensitive substring that must NOT appear in the path")
    parser.add_argument("--min-size", type=parse_size, default=None,
                        help="minimum file size (bare number = MB; or use 100K/1G/etc.)")
    parser.add_argument("--max-size", type=parse_size, default=None,
                        help="maximum file size (bare number = MB; or use 100K/1G/etc.)")
    parser.add_argument("--max-depth", type=int, default=None,
                        help="cap recursion depth (0 = top level only)")
    parser.add_argument("--follow-symlinks", action="store_true",
                        help="follow symlinks during the walk (off by default to avoid loops)")
    parser.add_argument("-s", "--size", dest="sort_by_size", action="store_true",
                        help="sort results by size, largest first")
    parser.add_argument("--limit", type=int, default=None,
                        help="cap the number of results returned")
    parser.add_argument("--print-sizes", action="store_true",
                        help="print sizes alongside paths (MB, two decimals)")
    parser.add_argument("--json", dest="json_mode", action="store_true",
                        help="emit results as a JSON array")
    parser.add_argument("--null", dest="null_mode", action="store_true",
                        help="null-separate paths for piping into xargs -0")
    parser.add_argument("-o", "--output", type=Path,
                        help="write results to this file in addition to stdout")
    parser.add_argument("-v", "--verbose", action="count", default=0,
                        help="increase verbosity (-v info, -vv debug)")
    return parser


def configure_logging(verbosity: int) -> None:
    level = logging.WARNING
    if verbosity == 1:
        level = logging.INFO
    elif verbosity >= 2:
        level = logging.DEBUG
    logging.basicConfig(level=level, format="%(levelname)s %(name)s: %(message)s")


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    configure_logging(args.verbose)

    if args.json_mode and args.null_mode:
        parser.error("--json and --null are mutually exclusive")
    if args.min_size is not None and args.max_size is not None and args.min_size > args.max_size:
        parser.error("--min-size cannot exceed --max-size")
    if args.max_depth is not None and args.max_depth < 0:
        parser.error("--max-depth must be >= 0")

    extensions = args.ext
    if extensions is None and not args.name_glob and not args.regex:
        if sys.stdin.isatty():
            extensions = interactive_extension_picker()
        else:
            parser.error("provide --ext, --name, or --regex when stdin is not a TTY")

    opts = SearchOptions(
        directory=args.directory,
        extensions=extensions,
        name_glob=args.name_glob,
        regex=args.regex,
        include=args.include,
        exclude=args.exclude,
        min_size=args.min_size,
        max_size=args.max_size,
        max_depth=args.max_depth,
        follow_symlinks=args.follow_symlinks,
    )

    try:
        matches: list[FileMatch] = list(find_files(opts))
    except NotADirectoryError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        return 130

    if args.sort_by_size:
        matches.sort(key=lambda m: m.size, reverse=True)
    if args.limit is not None:
        matches = matches[: args.limit]

    emit_results(
        matches,
        out=sys.stdout,
        json_mode=args.json_mode,
        null_mode=args.null_mode,
        print_sizes=args.print_sizes,
    )

    if args.output:
        try:
            with args.output.open("w", encoding="utf-8") as fh:
                emit_results(
                    matches,
                    out=fh,
                    json_mode=args.json_mode,
                    null_mode=args.null_mode,
                    print_sizes=args.print_sizes,
                )
            LOG.info("wrote %d results to %s", len(matches), args.output)
        except OSError as exc:
            print(f"error: cannot write to {args.output}: {exc}", file=sys.stderr)
            return 1

    if not args.null_mode and not args.json_mode:
        sys.stdout.flush()  # ensure data appears before the status line under 2>&1
        print(f"\nTotal matches: {len(matches)}", file=sys.stderr)

    return 0 if matches else 1


if __name__ == "__main__":
    sys.exit(main())
