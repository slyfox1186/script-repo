#!/usr/bin/env python3
"""Find and sort matching video files by size with resumable caching.

Design goals:
- Efficient scanning via `os.scandir()`
- Deterministic ordering for readable output and exact cache resume points
- Atomic `/tmp` cache checkpoints that survive normal interruption signals
- Clear CLI help and robust error handling
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import sys
import time
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_CEILING, ROUND_FLOOR
from pathlib import Path
from typing import Iterable, Sequence


DEFAULT_EXTENSIONS = (
    "mp4",
    "mkv",
    "avi",
    "mov",
    "wmv",
    "flv",
    "webm",
    "m4v",
    "mpg",
    "mpeg",
    "ts",
    "m2ts",
)
CHECKPOINT_ENTRY_INTERVAL = 250
CACHE_VERSION = 1
CACHE_DIR = Path("/tmp")
CACHE_PREFIX = "find_largest_videos_cache"
DECIMAL_BYTES_PER_MIB = Decimal("1048576")


class HelpFormatter(argparse.RawDescriptionHelpFormatter):
    """Readable help output with preserved examples."""


@dataclass(frozen=True, slots=True)
class VideoMatch:
    """A matched video file and its size."""

    path: Path
    size_bytes: int


@dataclass(slots=True)
class StopState:
    """Tracks whether the scan should stop and checkpoint immediately."""

    requested: bool = False
    reason: str = ""


def parse_extensions(value: str) -> tuple[str, ...]:
    """Parse a comma-separated extension list into normalized lowercase values."""
    extensions: list[str] = []
    seen: set[str] = set()

    for raw_part in value.split(","):
        cleaned = raw_part.strip().lower().lstrip(".")
        if not cleaned:
            continue
        if cleaned not in seen:
            seen.add(cleaned)
            extensions.append(cleaned)

    if not extensions:
        raise argparse.ArgumentTypeError(
            "extensions must contain at least one comma-separated value, "
            "for example: mp4,mkv,avi"
        )

    return tuple(extensions)


def format_extensions(extensions: Iterable[str]) -> str:
    """Format normalized extensions for display."""
    return ", ".join(f".{extension}" for extension in extensions)


def parse_size_mb(value: str) -> Decimal:
    """Parse a non-negative size value in decimal MB."""
    try:
        size_mb = Decimal(value)
    except InvalidOperation as exc:
        raise argparse.ArgumentTypeError(
            "size must be a non-negative number of MiB, for example: 1024"
        ) from exc

    if not size_mb.is_finite() or size_mb < 0:
        raise argparse.ArgumentTypeError(
            "size must be a non-negative number of MiB, for example: 1024"
        )

    return size_mb


def format_decimal(value: Decimal) -> str:
    """Format a Decimal without scientific notation or trailing zero noise."""
    rendered = format(value, "f")
    if "." in rendered:
        rendered = rendered.rstrip("0").rstrip(".")
    return rendered or "0"


def min_bytes_from_mb(size_mb: Decimal) -> int:
    """Convert an inclusive minimum MiB threshold into bytes."""
    return int((size_mb * DECIMAL_BYTES_PER_MIB).to_integral_value(rounding=ROUND_CEILING))


def max_bytes_from_mb(size_mb: Decimal) -> int:
    """Convert an inclusive maximum MiB threshold into bytes."""
    return int((size_mb * DECIMAL_BYTES_PER_MIB).to_integral_value(rounding=ROUND_FLOOR))


def format_size_filter(size_mb: Decimal | None, size_bytes: int | None) -> str:
    """Format a size filter for display."""
    if size_mb is None or size_bytes is None:
        return "none"
    return f"{format_decimal(size_mb)} MiB ({size_bytes:,} bytes)"


def human_size(num_bytes: int) -> str:
    """Convert a byte count to a compact human-readable string."""
    units = ("B", "KiB", "MiB", "GiB", "TiB", "PiB")
    size = float(num_bytes)

    for unit in units:
        if size < 1024.0 or unit == units[-1]:
            if unit == "B":
                return f"{int(size)} {unit}"
            return f"{size:.2f} {unit}"
        size /= 1024.0

    return f"{num_bytes} B"


def relative_display_path(root: Path, target: Path) -> str:
    """Return a clean display path relative to the scan root when possible."""
    try:
        return str(target.relative_to(root))
    except ValueError:
        return str(target)


def normalize_argv(argv: Sequence[str] | None) -> tuple[str, ...]:
    """Normalize argv and accept a typo-compatible alias without exposing it in help."""
    source = tuple(sys.argv[1:] if argv is None else argv)
    return tuple("--exclude-text" if arg == "--exclude-test" else arg for arg in source)


def make_scan_config(
    root_dir: Path,
    recurse: bool,
    extensions: tuple[str, ...],
    exclude_text: str,
    min_size_bytes: int | None,
    max_size_bytes: int | None,
) -> dict[str, object]:
    """Build the canonical config used to derive the cache key."""
    return {
        "root_dir": str(root_dir),
        "recurse": recurse,
        "extensions": list(extensions),
        "exclude_text": exclude_text,
        "min_size_bytes": min_size_bytes,
        "max_size_bytes": max_size_bytes,
    }


def cache_path_for_config(config: dict[str, object]) -> Path:
    """Return the deterministic cache path for this scan configuration."""
    payload = json.dumps(config, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]
    return CACHE_DIR / f"{CACHE_PREFIX}_{digest}.json"


def build_initial_state(config: dict[str, object]) -> dict[str, object]:
    """Create a new cache state."""
    now = time.time()
    return {
        "version": CACHE_VERSION,
        "status": "in_progress",
        "config": config,
        "pending_dirs": [config["root_dir"]],
        "current_dir": None,
        "directories_scanned": 0,
        "files_seen": 0,
        "matches": {},
        "warnings": [],
        "created_at": now,
        "updated_at": now,
    }


def write_cache_atomic(cache_path: Path, state: dict[str, object]) -> None:
    """Atomically write the cache so interruption never leaves a partial JSON file."""
    state["updated_at"] = time.time()
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = cache_path.with_suffix(cache_path.suffix + ".tmp")

    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")

    os.replace(temp_path, cache_path)


def load_cache(cache_path: Path) -> dict[str, object]:
    """Load and validate a cache file."""
    with cache_path.open("r", encoding="utf-8") as handle:
        state = json.load(handle)

    if state.get("version") != CACHE_VERSION:
        raise ValueError(
            f"unsupported cache version {state.get('version')!r}; expected {CACHE_VERSION}"
        )

    return state


def list_directory_entries(directory: Path, warnings: list[str]) -> list[dict[str, str]]:
    """Snapshot a directory into a deterministic list of file and directory entries."""
    entries: list[dict[str, str]] = []

    with os.scandir(directory) as scan_entries:
        for entry in scan_entries:
            try:
                if entry.is_dir(follow_symlinks=False):
                    kind = "dir"
                elif entry.is_file(follow_symlinks=False):
                    kind = "file"
                else:
                    continue
                entries.append({"name": entry.name, "kind": kind})
            except OSError as exc:
                warnings.append(f"{entry.path}: {exc.strerror or exc}")

    entries.sort(key=lambda item: item["name"].casefold())
    return entries


def checkpoint_state(
    state: dict[str, object],
    cache_path: Path,
    *,
    status: str | None = None,
    interrupted_by: str | None = None,
) -> None:
    """Persist the current scan state."""
    if status is not None:
        state["status"] = status

    if interrupted_by is None:
        state.pop("interrupted_by", None)
    else:
        state["interrupted_by"] = interrupted_by

    write_cache_atomic(cache_path, state)


def install_stop_handlers(stop_state: StopState) -> dict[int, object]:
    """Install signal handlers that request a checkpointed stop."""
    previous_handlers: dict[int, object] = {}
    wanted_signals = [signal.SIGINT, signal.SIGTERM]
    sighup = getattr(signal, "SIGHUP", None)
    if sighup is not None:
        wanted_signals.append(sighup)

    def handle_stop(signum: int, _frame: object) -> None:
        stop_state.requested = True
        stop_state.reason = signal.Signals(signum).name

    for signum in wanted_signals:
        previous_handlers[signum] = signal.getsignal(signum)
        signal.signal(signum, handle_stop)

    return previous_handlers


def restore_stop_handlers(previous_handlers: dict[int, object]) -> None:
    """Restore original signal handlers."""
    for signum, handler in previous_handlers.items():
        signal.signal(signum, handler)


def should_exclude(name: str, exclude_text: str) -> bool:
    """Return True when the filename contains the requested exclusion text."""
    return exclude_text != "" and exclude_text in name


def within_size_bounds(
    size_bytes: int,
    min_size_bytes: int | None,
    max_size_bytes: int | None,
) -> bool:
    """Return True when the file size fits the configured inclusive bounds."""
    if min_size_bytes is not None and size_bytes < min_size_bytes:
        return False
    if max_size_bytes is not None and size_bytes > max_size_bytes:
        return False
    return True


def record_match(state: dict[str, object], path: Path, size_bytes: int) -> None:
    """Record or update a matched file in the cache state."""
    matches = state["matches"]
    if not isinstance(matches, dict):
        raise TypeError("cache state 'matches' must be a dict")
    matches[str(path)] = size_bytes


def sorted_matches_from_state(state: dict[str, object]) -> list[VideoMatch]:
    """Build sorted match objects from cached state."""
    matches = state.get("matches", {})
    if not isinstance(matches, dict):
        raise TypeError("cache state 'matches' must be a dict")

    result = [
        VideoMatch(path=Path(path_string), size_bytes=int(size_bytes))
        for path_string, size_bytes in matches.items()
    ]
    result.sort(key=lambda match: (-match.size_bytes, str(match.path).lower()))
    return result


def run_scan(
    state: dict[str, object],
    cache_path: Path,
    stop_state: StopState,
) -> str:
    """Run or resume the scan until completion or interruption."""
    config = state["config"]
    if not isinstance(config, dict):
        raise TypeError("cache state 'config' must be a dict")

    recurse = bool(config["recurse"])
    extensions = frozenset(str(extension) for extension in config["extensions"])
    exclude_text = str(config["exclude_text"])
    min_size_bytes = config["min_size_bytes"]
    max_size_bytes = config["max_size_bytes"]
    if min_size_bytes is not None:
        min_size_bytes = int(min_size_bytes)
    if max_size_bytes is not None:
        max_size_bytes = int(max_size_bytes)

    pending_dirs = state["pending_dirs"]
    warnings = state["warnings"]
    if not isinstance(pending_dirs, list) or not isinstance(warnings, list):
        raise TypeError("cache state contains invalid collections")

    while state["current_dir"] is not None or pending_dirs:
        if stop_state.requested:
            checkpoint_state(
                state,
                cache_path,
                status="interrupted",
                interrupted_by=stop_state.reason or "INTERRUPTED",
            )
            return "interrupted"

        if state["current_dir"] is None:
            directory_string = pending_dirs.pop()
            current_dir_path = Path(directory_string)

            try:
                entries = list_directory_entries(current_dir_path, warnings)
            except OSError as exc:
                warnings.append(f"{current_dir_path}: {exc.strerror or exc}")
                state["directories_scanned"] = int(state["directories_scanned"]) + 1
                checkpoint_state(state, cache_path, status="in_progress")
                continue

            state["current_dir"] = {
                "path": str(current_dir_path),
                "entries": entries,
                "next_index": 0,
            }
            checkpoint_state(state, cache_path, status="in_progress")

        current_dir = state["current_dir"]
        if not isinstance(current_dir, dict):
            raise TypeError("cache state 'current_dir' must be a dict or null")

        directory_path = Path(str(current_dir["path"]))
        entries = current_dir["entries"]
        if not isinstance(entries, list):
            raise TypeError("cache state 'current_dir.entries' must be a list")

        since_checkpoint = 0
        while int(current_dir["next_index"]) < len(entries):
            if stop_state.requested:
                checkpoint_state(
                    state,
                    cache_path,
                    status="interrupted",
                    interrupted_by=stop_state.reason or "INTERRUPTED",
                )
                return "interrupted"

            entry = entries[int(current_dir["next_index"])]
            if not isinstance(entry, dict):
                raise TypeError("cache entry snapshot must be a dict")

            entry_name = str(entry["name"])
            entry_kind = str(entry["kind"])
            entry_path = directory_path / entry_name

            if entry_kind == "dir":
                if recurse:
                    pending_dirs.append(str(entry_path))
            elif entry_kind == "file":
                state["files_seen"] = int(state["files_seen"]) + 1
                suffix = entry_path.suffix.lower().lstrip(".")

                if suffix in extensions and not should_exclude(entry_name, exclude_text):
                    try:
                        size_bytes = entry_path.stat().st_size
                    except OSError as exc:
                        warnings.append(f"{entry_path}: {exc.strerror or exc}")
                    else:
                        if within_size_bounds(size_bytes, min_size_bytes, max_size_bytes):
                            record_match(state, entry_path, size_bytes)

            current_dir["next_index"] = int(current_dir["next_index"]) + 1
            since_checkpoint += 1

            if since_checkpoint >= CHECKPOINT_ENTRY_INTERVAL:
                checkpoint_state(state, cache_path, status="in_progress")
                since_checkpoint = 0

        state["current_dir"] = None
        state["directories_scanned"] = int(state["directories_scanned"]) + 1
        checkpoint_state(state, cache_path, status="in_progress")

    checkpoint_state(state, cache_path, status="complete", interrupted_by=None)
    return "complete"


def build_parser() -> argparse.ArgumentParser:
    """Construct the CLI parser."""
    default_extensions = ",".join(DEFAULT_EXTENSIONS)
    description = (
        "Scan a directory for video files and print matches sorted largest first.\n"
        "Symlinks are not followed."
    )
    epilog = f"""Examples:
  python find_largest_videos.py -d .
  python find_largest_videos.py -d ~/Videos -r
  python find_largest_videos.py -d /mnt/media -r -e mp4,mkv,avi
  python find_largest_videos.py -d . -r --exclude-text " (x265)"
  python find_largest_videos.py -d /mnt/media -r --min-size 1024 --max-size 2048
  python find_largest_videos.py -d /mnt/media -r -b

Cache behavior:
  A scan-specific JSON cache is stored under /tmp and reused automatically.
  Partial cache state resumes on the next run after SIGINT, SIGTERM, or SIGHUP.
  Use -b/--bypass-cache to discard any existing cache and rescan.

Extension matching is case-insensitive, and both 'mp4' and '.mp4' are accepted.
Default extensions: {format_extensions(DEFAULT_EXTENSIONS)}
"""

    parser = argparse.ArgumentParser(
        prog="find_largest_videos.py",
        description=description,
        epilog=epilog,
        formatter_class=HelpFormatter,
    )
    parser.add_argument(
        "-d",
        "--dir",
        dest="directory",
        required=True,
        metavar="PATH",
        help="Directory to scan. Accepts relative or absolute paths.",
    )
    parser.add_argument(
        "-r",
        "--recurse",
        action="store_true",
        help="Recursively scan subdirectories. Default: top-level only.",
    )
    parser.add_argument(
        "-e",
        "--extensions",
        type=parse_extensions,
        default=DEFAULT_EXTENSIONS,
        metavar="LIST",
        help=f"Comma-separated video extensions to match. Default: {default_extensions}.",
    )
    parser.add_argument(
        "--exclude-text",
        default="",
        metavar="TEXT",
        help="Exclude matches whose filename contains this exact text.",
    )
    parser.add_argument(
        "--min-size",
        type=parse_size_mb,
        default=None,
        metavar="MIB",
        help="Only include files at or above this size in MiB.",
    )
    parser.add_argument(
        "--max-size",
        type=parse_size_mb,
        default=None,
        metavar="MIB",
        help="Only include files at or below this size in MiB.",
    )
    parser.add_argument(
        "-b",
        "--bypass-cache",
        action="store_true",
        dest="bypass_cache",
        help="Ignore and overwrite any existing cache for this scan configuration.",
    )
    return parser


def validate_directory(parser: argparse.ArgumentParser, raw_path: str) -> Path:
    """Validate and normalize the scan root."""
    path = Path(raw_path).expanduser()

    if not path.exists():
        parser.error(f"directory does not exist: {raw_path}")
    if not path.is_dir():
        parser.error(f"path is not a directory: {raw_path}")

    return path.resolve()


def resolve_size_filters(
    parser: argparse.ArgumentParser,
    min_size_mb: Decimal | None,
    max_size_mb: Decimal | None,
) -> tuple[int | None, int | None]:
    """Validate the size range and convert MB thresholds into bytes."""
    if min_size_mb is not None and max_size_mb is not None and min_size_mb > max_size_mb:
        parser.error("--min-size cannot be greater than --max-size")

    min_size_bytes = min_bytes_from_mb(min_size_mb) if min_size_mb is not None else None
    max_size_bytes = max_bytes_from_mb(max_size_mb) if max_size_mb is not None else None

    if (
        min_size_bytes is not None
        and max_size_bytes is not None
        and min_size_bytes > max_size_bytes
    ):
        parser.error("the requested size range does not include any whole-byte file sizes")

    return min_size_bytes, max_size_bytes


def prepare_state(
    config: dict[str, object],
    cache_path: Path,
    bypass_cache: bool,
) -> tuple[dict[str, object], str]:
    """Create, resume, or reuse a cache state."""
    if bypass_cache:
        cache_path.unlink(missing_ok=True)
        state = build_initial_state(config)
        checkpoint_state(state, cache_path, status="in_progress")
        return state, "fresh-bypass"

    if not cache_path.exists():
        state = build_initial_state(config)
        checkpoint_state(state, cache_path, status="in_progress")
        return state, "fresh"

    try:
        state = load_cache(cache_path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(
            f"Warning: ignoring unreadable cache at {cache_path}: {exc}",
            file=sys.stderr,
        )
        state = build_initial_state(config)
        checkpoint_state(state, cache_path, status="in_progress")
        return state, "fresh-rebuilt"

    if state.get("config") != config:
        print(
            f"Warning: cache mismatch at {cache_path}; rebuilding fresh cache.",
            file=sys.stderr,
        )
        state = build_initial_state(config)
        checkpoint_state(state, cache_path, status="in_progress")
        return state, "fresh-rebuilt"

    if state.get("status") == "complete":
        return state, "reused-complete"

    state["status"] = "in_progress"
    checkpoint_state(state, cache_path, status="in_progress")
    return state, "resumed"


def describe_cache_mode(cache_mode: str) -> str:
    """Human-readable cache mode label."""
    labels = {
        "fresh": "new cache created",
        "fresh-bypass": "existing cache bypassed and overwritten",
        "fresh-rebuilt": "cache rebuilt from scratch",
        "reused-complete": "complete cache reused",
        "resumed": "partial cache resumed",
    }
    return labels.get(cache_mode, cache_mode)


def print_results(
    root_dir: Path,
    recurse: bool,
    extensions: tuple[str, ...],
    exclude_text: str,
    min_size_mb: Decimal | None,
    max_size_mb: Decimal | None,
    min_size_bytes: int | None,
    max_size_bytes: int | None,
    matches: list[VideoMatch],
    warnings: list[str],
    directories_scanned: int,
    files_seen: int,
    cache_path: Path,
    cache_mode: str,
) -> None:
    """Print a readable summary and sorted results."""
    total_size = sum(match.size_bytes for match in matches)
    size_width = max((len(human_size(match.size_bytes)) for match in matches), default=4)

    print(f"Scan root   : {root_dir}")
    print(f"Mode        : {'recursive' if recurse else 'top-level only'}")
    print(f"Extensions  : {format_extensions(extensions)}")
    print(f"Excluded    : {exclude_text!r}" if exclude_text else "Excluded    : none")
    print(f"Min size    : {format_size_filter(min_size_mb, min_size_bytes)}")
    print(f"Max size    : {format_size_filter(max_size_mb, max_size_bytes)}")
    print(f"Cache file  : {cache_path}")
    print(f"Cache mode  : {describe_cache_mode(cache_mode)}")
    print(f"Directories : {directories_scanned}")
    print(f"Files seen  : {files_seen}")
    print(f"Matches     : {len(matches)}")
    print(f"Total size  : {human_size(total_size)}")

    if matches:
        print("\nLargest matches:")
        for match in matches:
            display_path = relative_display_path(root_dir, match.path)
            print(f"  {human_size(match.size_bytes):>{size_width}}  {display_path}")
    else:
        print("\nNo matching video files were found.")

    if warnings:
        print(f"\nWarnings ({len(warnings)}):", file=sys.stderr)
        for warning in warnings:
            print(f"  {warning}", file=sys.stderr)


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entry point."""
    normalized_argv = normalize_argv(argv)
    parser = build_parser()
    args = parser.parse_args(normalized_argv)
    root_dir = validate_directory(parser, args.directory)
    min_size_bytes, max_size_bytes = resolve_size_filters(
        parser,
        args.min_size,
        args.max_size,
    )
    config = make_scan_config(
        root_dir=root_dir,
        recurse=args.recurse,
        extensions=args.extensions,
        exclude_text=args.exclude_text,
        min_size_bytes=min_size_bytes,
        max_size_bytes=max_size_bytes,
    )
    cache_path = cache_path_for_config(config)
    state, cache_mode = prepare_state(config, cache_path, args.bypass_cache)

    if cache_mode != "reused-complete":
        stop_state = StopState()
        previous_handlers = install_stop_handlers(stop_state)
        try:
            final_status = run_scan(state, cache_path, stop_state)
        finally:
            restore_stop_handlers(previous_handlers)

        if final_status != "complete":
            print(
                f"Scan interrupted and checkpointed to {cache_path}. "
                "Run the same command again to resume.",
                file=sys.stderr,
            )
            return 130

    matches = sorted_matches_from_state(state)
    warnings = [str(item) for item in state.get("warnings", [])]
    print_results(
        root_dir=root_dir,
        recurse=args.recurse,
        extensions=args.extensions,
        exclude_text=args.exclude_text,
        min_size_mb=args.min_size,
        max_size_mb=args.max_size,
        min_size_bytes=min_size_bytes,
        max_size_bytes=max_size_bytes,
        matches=matches,
        warnings=warnings,
        directories_scanned=int(state.get("directories_scanned", 0)),
        files_seen=int(state.get("files_seen", 0)),
        cache_path=cache_path,
        cache_mode=cache_mode,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


# Signed-off-by: Codex (GPT-5.4)
