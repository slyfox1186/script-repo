#!/usr/bin/env python3
"""
Disk Space Analyzer (DSA) - High-Performance Storage Scanner
=============================================================
A multi-threaded, parallel disk space analyzer optimized for NVMe SSDs
and multi-core processors. Designed for speed, flexibility, and insight.
"""

import os
import sys
import argparse
import concurrent.futures
import threading
import time
import json
import csv
import math
import re
import signal
from pathlib import Path
from collections import defaultdict
from datetime import datetime
from fnmatch import fnmatch
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple, Set
from enum import Enum

# ────────────────────────────────────────────────────────────────
# Configuration & Constants
# ────────────────────────────────────────────────────────────────

VERSION = "2.0.0"
DEFAULT_TOP_N = 20
MAX_WORKERS = min(os.cpu_count() or 4, 64)
CHUNK_SIZE = 256


class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    DIM = '\033[2m'
    UNDERLINE = '\033[4m'
    END = '\033[0m'


# ────────────────────────────────────────────────────────────────
# Data Structures
# ────────────────────────────────────────────────────────────────

class SortBy(Enum):
    SIZE = "size"
    COUNT = "count"
    MODIFIED = "modified"
    CREATED = "created"
    NAME = "name"
    EXTENSION = "ext"


class SizeUnit(Enum):
    AUTO = "auto"
    B = "B"
    KB = "KB"
    MB = "MB"
    GB = "GB"
    TB = "TB"
    PB = "PB"


@dataclass
class FileEntry:
    """Represents a single file with its metadata."""
    path: Path
    size: int
    modified: float
    created: float
    is_symlink: bool = False
    is_hardlink: bool = False
    link_target: Optional[Path] = None
    inode: Optional[int] = None

    @property
    def extension(self) -> str:
        return self.path.suffix.lower()

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def age_days(self) -> float:
        return (time.time() - self.modified) / 86400


@dataclass
class FolderEntry:
    """Represents a folder with aggregated statistics."""
    path: Path
    total_size: int = 0
    file_count: int = 0
    folder_count: int = 0
    max_file_size: int = 0
    min_file_size: Optional[int] = None
    avg_file_size: float = 0.0
    oldest_file: Optional[float] = None
    newest_file: Optional[float] = None
    extensions: Dict[str, int] = field(default_factory=lambda: defaultdict(int))
    depth: int = 0

    @property
    def name(self) -> str:
        return self.path.name or str(self.path)


# ────────────────────────────────────────────────────────────────
# Signal Handling
# ────────────────────────────────────────────────────────────────

_shutdown_requested = threading.Event()


def _signal_handler(signum, frame):
    if not _shutdown_requested.is_set():
        _shutdown_requested.set()
        print("\n\n[!] Shutdown requested. Finishing current batch...", file=sys.stderr)
    else:
        print("\n[!] Forcing immediate exit.", file=sys.stderr)
        sys.exit(1)


signal.signal(signal.SIGINT, _signal_handler)
signal.signal(signal.SIGTERM, _signal_handler)


# ────────────────────────────────────────────────────────────────
# Utility Functions
# ────────────────────────────────────────────────────────────────

def format_size(size_bytes: int, unit: SizeUnit = SizeUnit.AUTO, precision: int = 2) -> str:
    """Format byte size into human-readable string."""
    if size_bytes < 0:
        return "N/A"

    if unit != SizeUnit.AUTO:
        divisor = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3,
                   "TB": 1024**4, "PB": 1024**5}[unit.value]
        val = size_bytes / divisor
        return f"{val:.{precision}f} {unit.value}"

    if size_bytes == 0:
        return "0 B"

    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    idx = min(int(math.log2(size_bytes) / 10), len(units) - 1)
    val = size_bytes / (1024 ** idx)

    if idx == 0:
        return f"{int(val)} B"
    return f"{val:.{precision}f} {units[idx]}"


def format_timestamp(ts: float, fmt: str = "%Y-%m-%d %H:%M") -> str:
    """Format Unix timestamp."""
    try:
        return datetime.fromtimestamp(ts).strftime(fmt)
    except (OSError, ValueError):
        return "N/A"


def format_age(days: float) -> str:
    """Format age in human-friendly terms."""
    if days < 1:
        hours = int(days * 24)
        return f"{hours}h ago"
    elif days < 30:
        return f"{int(days)}d ago"
    elif days < 365:
        return f"{int(days / 30)}mo ago"
    else:
        return f"{days / 365:.1f}y ago"


def matches_patterns(name: str, patterns: List[str]) -> bool:
    """Check if name matches any of the glob patterns."""
    return any(fnmatch(name, pat) for pat in patterns)


def should_exclude(path: Path, exclude_patterns: List[str], exclude_paths: List[Path]) -> bool:
    """Check if path should be excluded."""
    try:
        for ex_path in exclude_paths:
            if path == ex_path or ex_path in path.parents:
                return True
    except (ValueError, OSError):
        pass
    return matches_patterns(path.name, exclude_patterns)


# ────────────────────────────────────────────────────────────────
# Core Scanning Engine
# ────────────────────────────────────────────────────────────────

class ScanEngine:
    """High-performance parallel file system scanner."""

    def __init__(self, args):
        self.args = args
        self.stats = {
            'files_scanned': 0,
            'folders_scanned': 0,
            'errors': 0,
            'skipped': 0,
            'start_time': time.time(),
            'symlinks_followed': 0,
            'hardlinks_detected': 0,
        }
        self._lock = threading.Lock()
        self._seen_inodes: Set[Tuple[int, int]] = set()
        self._progress_interval = 0.5
        self._last_progress = 0

    def _update_stat(self, key: str, increment: int = 1):
        with self._lock:
            self.stats[key] += increment

    def _is_duplicate(self, st) -> bool:
        """Check if this is a hardlink we've already counted."""
        if not self.args.deduplicate_hardlinks:
            return False
        key = (st.st_dev, st.st_ino)
        with self._lock:
            if key in self._seen_inodes:
                return True
            self._seen_inodes.add(key)
            return False

    def _scan_file(self, path: Path, depth: int = 0) -> Optional[FileEntry]:
        """Scan a single file and return its metadata."""
        if _shutdown_requested.is_set():
            return None

        try:
            st = os.lstat(path)

            if os.path.islink(path):
                if not self.args.follow_symlinks:
                    self._update_stat('skipped')
                    return None
                try:
                    resolved = path.resolve(strict=False)
                    if resolved.exists():
                        st = os.stat(resolved)
                        self._update_stat('symlinks_followed')
                    else:
                        return None
                except (OSError, ValueError):
                    return None

            size = st.st_size
            if self.args.min_size is not None and size < self.args.min_size:
                return None
            if self.args.max_size is not None and size > self.args.max_size:
                return None

            mtime = st.st_mtime
            if self.args.min_age_days is not None:
                age = (time.time() - mtime) / 86400
                if age < self.args.min_age_days:
                    return None
            if self.args.max_age_days is not None:
                age = (time.time() - mtime) / 86400
                if age > self.args.max_age_days:
                    return None

            if self.args.extensions:
                ext = path.suffix.lower().lstrip('.')
                if ext not in self.args.extensions:
                    return None

            is_hardlink = st.st_nlink > 1
            if is_hardlink and self._is_duplicate(st):
                self._update_stat('hardlinks_detected')
                return None

            self._update_stat('files_scanned')

            return FileEntry(
                path=path,
                size=size,
                modified=mtime,
                created=getattr(st, 'st_birthtime', st.st_ctime),
                is_symlink=os.path.islink(path),
                is_hardlink=is_hardlink,
                link_target=Path(os.readlink(path)) if os.path.islink(path) else None,
                inode=st.st_ino
            )

        except (OSError, PermissionError) as e:
            if self.args.verbose:
                with self._lock:
                    print(f"  [Error] {path}: {e}", file=sys.stderr)
            self._update_stat('errors')
            return None

    def _scan_directory_recursive(self, root: Path, depth: int = 0) -> Tuple[List[FileEntry], List[FolderEntry]]:
        """Recursively scan a directory tree."""
        files = []
        folders = []

        if _shutdown_requested.is_set():
            return files, folders

        if self.args.max_depth is not None and depth > self.args.max_depth:
            return files, folders

        try:
            entries = list(os.scandir(root))
        except (OSError, PermissionError) as e:
            if self.args.verbose:
                print(f"  [Error] Cannot access {root}: {e}", file=sys.stderr)
            self._update_stat('errors')
            return files, folders

        dirs = []
        file_paths = []

        for entry in entries:
            if _shutdown_requested.is_set():
                break

            path = Path(entry.path)

            if should_exclude(path, self.args.exclude, self.args.exclude_path):
                self._update_stat('skipped')
                continue

            if entry.is_symlink() and not self.args.follow_symlinks:
                continue

            try:
                if entry.is_dir(follow_symlinks=self.args.follow_symlinks):
                    dirs.append(path)
                elif entry.is_file(follow_symlinks=self.args.follow_symlinks):
                    file_paths.append(path)
            except OSError:
                self._update_stat('errors')
                continue

        # Process files in parallel batches
        if file_paths and not self.args.no_parallel and len(file_paths) > 1:
            with concurrent.futures.ThreadPoolExecutor(max_workers=self.args.workers) as executor:
                futures = {executor.submit(self._scan_file, fp, depth): fp for fp in file_paths}
                for future in concurrent.futures.as_completed(futures):
                    result = future.result()
                    if result:
                        files.append(result)
        else:
            for fp in file_paths:
                result = self._scan_file(fp, depth)
                if result:
                    files.append(result)

        folder_entry = FolderEntry(path=root, depth=depth)

        # Process subdirectories — only parallelize at shallow depths to avoid thread explosion
        if self.args.recursive and dirs:
            should_parallelize = (
                not self.args.no_parallel
                and len(dirs) > 1
                and depth < 2  # Only parallelize top-level branches
            )

            if should_parallelize:
                with concurrent.futures.ThreadPoolExecutor(max_workers=min(self.args.workers, len(dirs))) as executor:
                    futures = {executor.submit(self._scan_directory_recursive, d, depth + 1): d for d in dirs}
                    for future in concurrent.futures.as_completed(futures):
                        sub_files, sub_folders = future.result()
                        files.extend(sub_files)
                        folders.extend(sub_folders)
            else:
                for d in dirs:
                    sub_files, sub_folders = self._scan_directory_recursive(d, depth + 1)
                    files.extend(sub_files)
                    folders.extend(sub_folders)

            folder_entry.folder_count = len(dirs)

        # Aggregate stats from ALL files under this folder (not just direct children)
        for f in files:
            try:
                if root in f.path.parents or f.path.parent == root:
                    folder_entry.total_size += f.size
                    folder_entry.file_count += 1
                    folder_entry.extensions[f.extension] += 1
                    if f.size > folder_entry.max_file_size:
                        folder_entry.max_file_size = f.size
                    if folder_entry.min_file_size is None or f.size < folder_entry.min_file_size:
                        folder_entry.min_file_size = f.size
                    if folder_entry.oldest_file is None or f.modified < folder_entry.oldest_file:
                        folder_entry.oldest_file = f.modified
                    if folder_entry.newest_file is None or f.modified > folder_entry.newest_file:
                        folder_entry.newest_file = f.modified
            except (ValueError, OSError):
                continue

        if folder_entry.file_count > 0:
            folder_entry.avg_file_size = folder_entry.total_size / folder_entry.file_count

        folders.append(folder_entry)
        self._update_stat('folders_scanned')

        if self.args.progress and time.time() - self._last_progress > self._progress_interval:
            self._print_progress()
            self._last_progress = time.time()

        return files, folders

    def _scan_directory_flat(self, root: Path) -> Tuple[List[FileEntry], List[FolderEntry]]:
        """Non-recursive flat scan of a single directory."""
        files = []
        folder_entry = FolderEntry(path=root)

        try:
            entries = list(os.scandir(root))
        except (OSError, PermissionError) as e:
            if self.args.verbose:
                print(f"  [Error] Cannot access {root}: {e}", file=sys.stderr)
            self._update_stat('errors')
            return files, [folder_entry]

        file_paths = []
        for entry in entries:
            path = Path(entry.path)

            if should_exclude(path, self.args.exclude, self.args.exclude_path):
                self._update_stat('skipped')
                continue

            try:
                if entry.is_file(follow_symlinks=self.args.follow_symlinks):
                    file_paths.append(path)
                elif entry.is_dir(follow_symlinks=self.args.follow_symlinks):
                    folder_entry.folder_count += 1
            except OSError:
                self._update_stat('errors')
                continue

        if file_paths and not self.args.no_parallel and len(file_paths) > 1:
            with concurrent.futures.ThreadPoolExecutor(max_workers=self.args.workers) as executor:
                futures = {executor.submit(self._scan_file, fp): fp for fp in file_paths}
                for future in concurrent.futures.as_completed(futures):
                    result = future.result()
                    if result:
                        files.append(result)
        else:
            for fp in file_paths:
                result = self._scan_file(fp)
                if result:
                    files.append(result)

        for f in files:
            folder_entry.total_size += f.size
            folder_entry.file_count += 1
            folder_entry.extensions[f.extension] += 1
            if f.size > folder_entry.max_file_size:
                folder_entry.max_file_size = f.size
            if folder_entry.min_file_size is None or f.size < folder_entry.min_file_size:
                folder_entry.min_file_size = f.size
            if folder_entry.oldest_file is None or f.modified < folder_entry.oldest_file:
                folder_entry.oldest_file = f.modified
            if folder_entry.newest_file is None or f.modified > folder_entry.newest_file:
                folder_entry.newest_file = f.modified

        if folder_entry.file_count > 0:
            folder_entry.avg_file_size = folder_entry.total_size / folder_entry.file_count

        self._update_stat('folders_scanned')
        return files, [folder_entry]

    def _print_progress(self):
        """Print scanning progress."""
        elapsed = time.time() - self.stats['start_time']
        rate = self.stats['files_scanned'] / elapsed if elapsed > 0 else 0
        print(f"\r  Scanned: {self.stats['files_scanned']:,} files, "
              f"{self.stats['folders_scanned']:,} folders | "
              f"{rate:,.0f} files/sec | "
              f"Errors: {self.stats['errors']}",
              end='', file=sys.stderr, flush=True)

    def scan(self, paths: List[Path]) -> Tuple[List[FileEntry], List[FolderEntry]]:
        """Main entry point for scanning."""
        all_files = []
        all_folders = []

        for path in paths:
            if not path.exists():
                print(f"[Warning] Path does not exist: {path}", file=sys.stderr)
                continue

            if path.is_file():
                result = self._scan_file(path)
                if result:
                    all_files.append(result)
            elif path.is_dir():
                if self.args.recursive:
                    files, folders = self._scan_directory_recursive(path)
                else:
                    files, folders = self._scan_directory_flat(path)
                all_files.extend(files)
                all_folders.extend(folders)

        if self.args.progress:
            print(file=sys.stderr)

        return all_files, all_folders


# ────────────────────────────────────────────────────────────────
# Results Processing & Analysis
# ────────────────────────────────────────────────────────────────

class ResultsAnalyzer:
    """Analyzes and formats scan results."""

    def __init__(self, files: List[FileEntry], folders: List[FolderEntry], args):
        self.files = files
        self.folders = folders
        self.args = args
        self.total_size = sum(f.size for f in files)
        self.total_files = len(files)

    def get_top_files(self, n: int, sort_by: SortBy) -> List[FileEntry]:
        """Get top N files sorted by criteria."""
        reverse = not self.args.reverse

        if sort_by == SortBy.SIZE:
            key = lambda f: f.size
        elif sort_by == SortBy.MODIFIED:
            key = lambda f: f.modified
        elif sort_by == SortBy.CREATED:
            key = lambda f: f.created
        elif sort_by == SortBy.NAME:
            key = lambda f: f.name.lower()
        elif sort_by == SortBy.EXTENSION:
            key = lambda f: f.extension
        else:
            key = lambda f: f.size

        return sorted(self.files, key=key, reverse=reverse)[:n]

    def get_top_folders(self, n: int, sort_by: SortBy) -> List[FolderEntry]:
        """Get top N folders sorted by criteria."""
        reverse = not self.args.reverse

        if sort_by == SortBy.SIZE:
            key = lambda f: f.total_size
        elif sort_by == SortBy.COUNT:
            key = lambda f: f.file_count
        elif sort_by == SortBy.MODIFIED:
            key = lambda f: f.newest_file or 0
        elif sort_by == SortBy.NAME:
            key = lambda f: f.name.lower()
        else:
            key = lambda f: f.total_size

        return sorted(self.folders, key=key, reverse=reverse)[:n]

    def get_extension_summary(self) -> List[Tuple[str, int, int]]:
        """Get summary by file extension."""
        ext_stats = defaultdict(lambda: {'count': 0, 'size': 0})
        for f in self.files:
            ext = f.extension or '(no extension)'
            ext_stats[ext]['count'] += 1
            ext_stats[ext]['size'] += f.size

        return sorted(
            [(ext, stats['count'], stats['size']) for ext, stats in ext_stats.items()],
            key=lambda x: x[2],
            reverse=True
        )

    def get_size_distribution(self) -> Tuple[Dict[str, int], Dict[str, int]]:
        """Get file size distribution buckets (counts and total sizes)."""
        bucket_keys = [
            '< 1 KB', '1 KB - 1 MB', '1 MB - 10 MB', '10 MB - 100 MB',
            '100 MB - 1 GB', '1 GB - 10 GB', '> 10 GB',
        ]
        buckets = {k: 0 for k in bucket_keys}
        bucket_sizes = {k: 0 for k in bucket_keys}

        for f in self.files:
            s = f.size
            if s < 1024:
                key = '< 1 KB'
            elif s < 1024**2:
                key = '1 KB - 1 MB'
            elif s < 10 * 1024**2:
                key = '1 MB - 10 MB'
            elif s < 100 * 1024**2:
                key = '10 MB - 100 MB'
            elif s < 1024**3:
                key = '100 MB - 1 GB'
            elif s < 10 * 1024**3:
                key = '1 GB - 10 GB'
            else:
                key = '> 10 GB'
            buckets[key] += 1
            bucket_sizes[key] += s

        return buckets, bucket_sizes

    def get_age_distribution(self) -> Dict[str, int]:
        """Get file age distribution."""
        now = time.time()
        bucket_keys = [
            '< 1 day', '1-7 days', '1-4 weeks', '1-3 months',
            '3-12 months', '1-2 years', '> 2 years',
        ]
        buckets = {k: 0 for k in bucket_keys}

        for f in self.files:
            age_days = (now - f.modified) / 86400
            if age_days < 1:
                buckets['< 1 day'] += 1
            elif age_days < 7:
                buckets['1-7 days'] += 1
            elif age_days < 30:
                buckets['1-4 weeks'] += 1
            elif age_days < 90:
                buckets['1-3 months'] += 1
            elif age_days < 365:
                buckets['3-12 months'] += 1
            elif age_days < 730:
                buckets['1-2 years'] += 1
            else:
                buckets['> 2 years'] += 1

        return buckets


# ────────────────────────────────────────────────────────────────
# Output Formatting
# ────────────────────────────────────────────────────────────────

class OutputFormatter:
    """Handles all output formatting."""

    def __init__(self, args):
        self.args = args
        self.use_color = args.color and sys.stdout.isatty()

    def _color(self, text: str, color: str) -> str:
        if not self.use_color:
            return text
        return f"{color}{text}{Colors.END}"

    def _bar(self, value: float, max_value: float, width: int = 20) -> str:
        """Generate ASCII bar chart."""
        if max_value == 0:
            return ' ' * width
        filled = int((value / max_value) * width)
        filled = min(filled, width)
        return '█' * filled + '░' * (width - filled)

    def print_header(self, text: str):
        """Print a section header."""
        print()
        print(self._color(f"{'─' * 60}", Colors.DIM))
        print(self._color(f"  {text}", Colors.BOLD + Colors.CYAN))
        print(self._color(f"{'─' * 60}", Colors.DIM))

    def print_files_table(self, files: List[FileEntry], title: str = "Top Files"):
        """Print files in a formatted table."""
        if not files:
            print("  No files found.")
            return

        self.print_header(title)

        max_size = max(f.size for f in files) if files else 0
        size_strs = [format_size(f.size, self.args.unit) for f in files]
        size_width = max(len(s) for s in size_strs) if size_strs else 10

        header = f"{'Size':>{size_width}} │ {'Age':>8} │ {'Name'}"
        print(self._color(header, Colors.BOLD))
        print(self._color("─" * (size_width + 12 + 50), Colors.DIM))

        for f, size_str in zip(files, size_strs):
            age_str = format_age(f.age_days)
            name = str(f.path)

            if len(name) > 60:
                name = "..." + name[-57:]

            if f.size > 1024**3:
                size_color = Colors.RED
            elif f.size > 100 * 1024**2:
                size_color = Colors.YELLOW
            else:
                size_color = Colors.GREEN

            # Pad before colorizing so width math stays correct
            padded_size = f"{size_str:>{size_width}}"
            colored_size = self._color(padded_size, size_color)

            line = f"{colored_size} │ {age_str:>8} │ {name}"
            if self.args.bars:
                bar = self._bar(f.size, max_size, 10)
                line += f"  {self._color(bar, Colors.BLUE)}"

            if f.is_symlink and f.link_target and self.args.show_links:
                line += f"\n{' ' * (size_width + 13)}→ {f.link_target}"

            print(line)

    def print_folders_table(self, folders: List[FolderEntry], title: str = "Top Folders"):
        """Print folders in a formatted table."""
        if not folders:
            print("  No folders found.")
            return

        self.print_header(title)

        max_size = max(f.total_size for f in folders) if folders else 0
        size_strs = [format_size(f.total_size, self.args.unit) for f in folders]
        size_width = max(len(s) for s in size_strs) if size_strs else 10

        header = f"{'Size':>{size_width}} │ {'Files':>6} │ {'Folders':>7} │ {'Name'}"
        print(self._color(header, Colors.BOLD))
        print(self._color("─" * (size_width + 20 + 50), Colors.DIM))

        for f, size_str in zip(folders, size_strs):
            name = str(f.path)
            if len(name) > 50:
                name = "..." + name[-47:]

            if f.total_size > 1024**3:
                size_color = Colors.RED
            elif f.total_size > 100 * 1024**2:
                size_color = Colors.YELLOW
            else:
                size_color = Colors.GREEN

            padded_size = f"{size_str:>{size_width}}"
            colored_size = self._color(padded_size, size_color)

            line = f"{colored_size} │ {f.file_count:>6,} │ {f.folder_count:>7,} │ {name}"
            if self.args.bars:
                bar = self._bar(f.total_size, max_size, 10)
                line += f"  {self._color(bar, Colors.BLUE)}"

            print(line)

    def print_summary(self, analyzer: ResultsAnalyzer, stats: Dict):
        """Print overall summary."""
        self.print_header("Scan Summary")

        elapsed = time.time() - stats['start_time']

        lines = [
            f"  Total Size:        {self._color(format_size(analyzer.total_size, self.args.unit), Colors.BOLD + Colors.CYAN)}",
            f"  Total Files:       {analyzer.total_files:,}",
            f"  Total Folders:     {len(analyzer.folders):,}",
            f"  Scan Time:         {elapsed:.2f}s",
        ]

        if elapsed > 0:
            lines.append(f"  Throughput:        {stats['files_scanned'] / elapsed:,.0f} files/sec")

        lines.extend([
            f"  Errors:            {stats['errors']:,}",
            f"  Skipped:           {stats['skipped']:,}",
        ])

        if stats['symlinks_followed'] > 0:
            lines.append(f"  Symlinks Followed: {stats['symlinks_followed']:,}")
        if stats['hardlinks_detected'] > 0:
            lines.append(f"  Hardlinks Deduped: {stats['hardlinks_detected']:,}")

        for line in lines:
            print(line)

    def print_extension_summary(self, analyzer: ResultsAnalyzer):
        """Print file extension breakdown."""
        if not self.args.show_extensions:
            return

        ext_summary = analyzer.get_extension_summary()
        if not ext_summary:
            return

        self.print_header("By Extension")

        max_size = max(s[2] for s in ext_summary) if ext_summary else 0
        size_strs = [format_size(s[2], self.args.unit) for s in ext_summary[:self.args.top]]
        size_width = max(len(s) for s in size_strs) if size_strs else 10

        header = f"{'Size':>{size_width}} │ {'Count':>7} │ {'Extension'}"
        print(self._color(header, Colors.BOLD))
        print(self._color("─" * (size_width + 12 + 30), Colors.DIM))

        for (ext, count, size), size_str in zip(ext_summary[:self.args.top], size_strs):
            bar = self._bar(size, max_size, 15)
            print(f"{size_str:>{size_width}} │ {count:>7,} │ {ext or '(none)':<10}  {self._color(bar, Colors.BLUE)}")

    def print_size_distribution(self, analyzer: ResultsAnalyzer):
        """Print size distribution histogram."""
        if not self.args.show_distribution:
            return

        buckets, bucket_sizes = analyzer.get_size_distribution()
        if not any(buckets.values()):
            return

        self.print_header("Size Distribution")

        max_count = max(buckets.values()) if buckets else 0

        for bucket, count in buckets.items():
            if count == 0:
                continue
            bar = self._bar(count, max_count, 30)
            pct = (count / analyzer.total_files * 100) if analyzer.total_files > 0 else 0
            size_str = format_size(bucket_sizes[bucket], self.args.unit)
            print(f"  {bucket:>15} │ {count:>6,} ({pct:>5.1f}%) │ {size_str:>10} │ {self._color(bar, Colors.BLUE)}")

    def print_age_distribution(self, analyzer: ResultsAnalyzer):
        """Print age distribution."""
        if not self.args.show_age_distribution:
            return

        buckets = analyzer.get_age_distribution()
        if not any(buckets.values()):
            return

        self.print_header("Age Distribution (by modification time)")

        max_count = max(buckets.values()) if buckets else 0

        for bucket, count in buckets.items():
            if count == 0:
                continue
            bar = self._bar(count, max_count, 30)
            pct = (count / analyzer.total_files * 100) if analyzer.total_files > 0 else 0
            print(f"  {bucket:>15} │ {count:>6,} ({pct:>5.1f}%) │ {self._color(bar, Colors.BLUE)}")

    def export_json(self, analyzer: ResultsAnalyzer, filepath: str):
        """Export results to JSON."""
        data = {
            'scan_info': {
                'timestamp': datetime.now().isoformat(),
                'paths': [str(p) for p in self.args.paths],
                'recursive': self.args.recursive,
                'workers': self.args.workers,
                'version': VERSION,
            },
            'summary': {
                'total_size': analyzer.total_size,
                'total_size_human': format_size(analyzer.total_size),
                'total_files': analyzer.total_files,
                'total_folders': len(analyzer.folders),
            },
            'top_files': [
                {
                    'path': str(f.path),
                    'size': f.size,
                    'size_human': format_size(f.size),
                    'modified': format_timestamp(f.modified),
                    'created': format_timestamp(f.created),
                    'extension': f.extension,
                    'is_symlink': f.is_symlink,
                    'is_hardlink': f.is_hardlink,
                }
                for f in analyzer.get_top_files(self.args.top, self.args.sort_files)
            ],
            'top_folders': [
                {
                    'path': str(f.path),
                    'total_size': f.total_size,
                    'total_size_human': format_size(f.total_size),
                    'file_count': f.file_count,
                    'folder_count': f.folder_count,
                    'avg_file_size': f.avg_file_size,
                    'extensions': dict(f.extensions),
                }
                for f in analyzer.get_top_folders(self.args.top, self.args.sort_folders)
            ],
            'extension_summary': [
                {'extension': ext, 'count': count, 'size': size, 'size_human': format_size(size)}
                for ext, count, size in analyzer.get_extension_summary()
            ],
        }

        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"\n[✓] Exported JSON to: {filepath}")

    def export_csv(self, analyzer: ResultsAnalyzer, filepath: str):
        """Export results to CSV."""
        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Type', 'Path', 'Size (bytes)', 'Size (human)', 'Files', 'Modified'])

            for file_entry in analyzer.files:
                writer.writerow([
                    'file',
                    str(file_entry.path),
                    file_entry.size,
                    format_size(file_entry.size),
                    1,
                    format_timestamp(file_entry.modified)
                ])

            for folder_entry in analyzer.folders:
                writer.writerow([
                    'folder',
                    str(folder_entry.path),
                    folder_entry.total_size,
                    format_size(folder_entry.total_size),
                    folder_entry.file_count,
                    format_timestamp(folder_entry.newest_file) if folder_entry.newest_file else ''
                ])

        print(f"[✓] Exported CSV to: {filepath}")


# ────────────────────────────────────────────────────────────────
# Argument Parser
# ────────────────────────────────────────────────────────────────

def parse_size(size_str: str) -> int:
    """Parse size string like '10MB', '1.5GB' to bytes."""
    size_str = size_str.strip().upper()
    multipliers = {
        'B': 1, 'KB': 1024, 'MB': 1024**2, 'GB': 1024**3,
        'TB': 1024**4, 'PB': 1024**5,
        'K': 1024, 'M': 1024**2, 'G': 1024**3, 'T': 1024**4, 'P': 1024**5,
    }

    match = re.match(r'^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB|PB|K|M|G|T|P)?$', size_str)
    if not match:
        raise argparse.ArgumentTypeError(f"Invalid size format: {size_str}")

    value = float(match.group(1))
    unit = match.group(2) or 'B'
    return int(value * multipliers[unit])


def _sort_by_arg(s: str) -> SortBy:
    try:
        return SortBy(s.lower())
    except ValueError:
        valid = ", ".join(e.value for e in SortBy)
        raise argparse.ArgumentTypeError(f"Invalid sort key '{s}'. Valid: {valid}")


def _size_unit_arg(s: str) -> SizeUnit:
    try:
        return SizeUnit(s if s == "auto" else s.upper())
    except ValueError:
        valid = ", ".join(e.value for e in SizeUnit)
        raise argparse.ArgumentTypeError(f"Invalid unit '{s}'. Valid: {valid}")


def parse_args():
    """Parse and return command line arguments."""
    parser = argparse.ArgumentParser(
        prog="dsa",
        description="Disk Space Analyzer (DSA) - High-performance storage scanner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s /home/user                       Scan home directory recursively
  %(prog)s -n 50 /var/log                   Show top 50 largest files
  %(prog)s --no-recursive /downloads        Scan only top-level of downloads
  %(prog)s -t folders --sort-folders count /data  Sort folders by file count
  %(prog)s --min-size 1GB /                 Only files >= 1GB
  %(prog)s --exclude '*.tmp' --exclude '*.log' /tmp
  %(prog)s --json output.json /projects     Export to JSON
  %(prog)s --workers 32 --no-bars /         Use 32 threads, no bars
  %(prog)s --follow-symlinks /mnt           Follow symbolic links
  %(prog)s --max-age 30 /backups            Files modified within 30 days
  %(prog)s --dedup-hardlinks /photos        Count hardlinked files once
  %(prog)s --show-distribution --show-age-distribution ~/Downloads
""",
    )

    parser.add_argument(
        'paths', nargs='*', default=['.'],
        help='One or more paths to scan (default: current directory)',
    )

    # Scanning options
    scan_group = parser.add_argument_group('Scanning Options')
    scan_group.add_argument(
        '-nr', '--no-recursive', dest='recursive', action='store_false',
        help='Only scan top-level directory (default: recursive)',
    )
    scan_group.add_argument(
        '--max-depth', type=int, default=None, metavar='N',
        help='Maximum recursion depth',
    )
    scan_group.add_argument(
        '-L', '--follow-symlinks', action='store_true',
        help='Follow symbolic links',
    )
    scan_group.add_argument(
        '--dedup-hardlinks', dest='deduplicate_hardlinks', action='store_true',
        help='Count hardlinked files only once',
    )
    scan_group.add_argument(
        '-w', '--workers', type=int, default=MAX_WORKERS, metavar='N',
        help=f'Worker threads (default: {MAX_WORKERS})',
    )
    scan_group.add_argument(
        '--no-parallel', action='store_true',
        help='Disable parallel scanning (single-threaded)',
    )

    # Filter options
    filter_group = parser.add_argument_group('Filter Options')
    filter_group.add_argument(
        '--min-size', type=parse_size, default=None, metavar='SIZE',
        help='Minimum file size (e.g., 1MB, 500KB, 1.5GB)',
    )
    filter_group.add_argument(
        '--max-size', type=parse_size, default=None, metavar='SIZE',
        help='Maximum file size',
    )
    filter_group.add_argument(
        '--min-age', dest='min_age_days', type=float, default=None, metavar='DAYS',
        help='Only files older than N days',
    )
    filter_group.add_argument(
        '--max-age', dest='max_age_days', type=float, default=None, metavar='DAYS',
        help='Only files modified within last N days',
    )
    filter_group.add_argument(
        '-e', '--extensions', nargs='+', default=None, metavar='EXT',
        help='Filter by extensions (e.g., -e jpg png mp4)',
    )
    filter_group.add_argument(
        '-x', '--exclude', action='append', default=[], metavar='PATTERN',
        help='Glob pattern to exclude (repeatable, e.g., -x "*.tmp")',
    )
    filter_group.add_argument(
        '-X', '--exclude-path', action='append', default=[], metavar='PATH',
        help='Exact path to exclude (repeatable)',
    )

    # Display options
    display_group = parser.add_argument_group('Display Options')
    display_group.add_argument(
        '-n', '--top', type=int, default=DEFAULT_TOP_N, metavar='N',
        help=f'Show top N entries (default: {DEFAULT_TOP_N})',
    )
    display_group.add_argument(
        '-t', '--target', choices=['files', 'folders', 'both'], default='both',
        help='What to display (default: both)',
    )
    display_group.add_argument(
        '--sort-files', type=_sort_by_arg, default=SortBy.SIZE, metavar='KEY',
        help='Sort files by: size, modified, created, name, ext (default: size)',
    )
    display_group.add_argument(
        '--sort-folders', type=_sort_by_arg, default=SortBy.SIZE, metavar='KEY',
        help='Sort folders by: size, count, modified, name (default: size)',
    )
    display_group.add_argument(
        '--reverse', action='store_true',
        help='Reverse sort order (smallest first)',
    )
    display_group.add_argument(
        '-u', '--unit', type=_size_unit_arg, default=SizeUnit.AUTO, metavar='UNIT',
        help='Size unit: auto, B, KB, MB, GB, TB, PB (default: auto)',
    )
    display_group.add_argument(
        '--bars', action='store_true', default=True,
        help='Show ASCII bar charts (default)',
    )
    display_group.add_argument(
        '--no-bars', dest='bars', action='store_false',
        help='Disable bar charts',
    )
    display_group.add_argument(
        '--color', action='store_true', default=True,
        help='Enable colored output (default)',
    )
    display_group.add_argument(
        '--no-color', dest='color', action='store_false',
        help='Disable colored output',
    )
    display_group.add_argument(
        '--show-extensions', action='store_true',
        help='Show breakdown by file extension',
    )
    display_group.add_argument(
        '--show-distribution', action='store_true',
        help='Show file size distribution histogram',
    )
    display_group.add_argument(
        '--show-age-distribution', action='store_true',
        help='Show file age distribution histogram',
    )
    display_group.add_argument(
        '--show-links', action='store_true',
        help='Show symlink targets in file listings',
    )
    display_group.add_argument(
        '--show-all', action='store_true',
        help='Enable all summary sections (extensions, distributions)',
    )

    # Output options
    output_group = parser.add_argument_group('Output Options')
    output_group.add_argument(
        '--json', dest='json_output', metavar='FILE',
        help='Export results to JSON file',
    )
    output_group.add_argument(
        '--csv', dest='csv_output', metavar='FILE',
        help='Export results to CSV file',
    )
    output_group.add_argument(
        '-q', '--quiet', action='store_true',
        help='Suppress console output (use with --json/--csv)',
    )
    output_group.add_argument(
        '--progress', action='store_true', default=True,
        help='Show scan progress (default)',
    )
    output_group.add_argument(
        '--no-progress', dest='progress', action='store_false',
        help='Disable progress display',
    )
    output_group.add_argument(
        '-v', '--verbose', action='store_true',
        help='Verbose error messages',
    )
    output_group.add_argument(
        '--version', action='version', version=f'%(prog)s {VERSION}',
    )

    args = parser.parse_args()

    # Normalize paths
    args.paths = [Path(p).expanduser().resolve() for p in args.paths]
    args.exclude_path = [Path(p).expanduser().resolve() for p in args.exclude_path]

    # Normalize extensions (lowercase, no leading dot)
    if args.extensions:
        args.extensions = [e.lower().lstrip('.') for e in args.extensions]

    # --show-all expands to all sections
    if args.show_all:
        args.show_extensions = True
        args.show_distribution = True
        args.show_age_distribution = True

    # Validate worker count
    if args.workers < 1:
        parser.error("--workers must be >= 1")

    # Quiet implies no progress
    if args.quiet:
        args.progress = False

    return args


# ────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────

def _print_banner(args, formatter: OutputFormatter):
    """Print startup banner."""
    title = f"  Disk Space Analyzer v{VERSION}"
    bar = "═" * (len(title) + 4)

    print()
    print(formatter._color(f"  ╔{bar}╗", Colors.CYAN))
    print(formatter._color(f"  ║{title.ljust(len(bar))}  ║", Colors.CYAN + Colors.BOLD))
    print(formatter._color(f"  ╚{bar}╝", Colors.CYAN))
    print()
    print(f"  Scanning:  {', '.join(str(p) for p in args.paths)}")
    print(f"  Workers:   {args.workers}{' (parallel disabled)' if args.no_parallel else ''}")
    if args.recursive:
        depth_str = f" (max depth: {args.max_depth})" if args.max_depth is not None else ""
        print(f"  Mode:      Recursive{depth_str}")
    else:
        print(f"  Mode:      Top-level only")

    filters = []
    if args.min_size is not None:
        filters.append(f"size >= {format_size(args.min_size)}")
    if args.max_size is not None:
        filters.append(f"size <= {format_size(args.max_size)}")
    if args.min_age_days is not None:
        filters.append(f"age >= {args.min_age_days}d")
    if args.max_age_days is not None:
        filters.append(f"age <= {args.max_age_days}d")
    if args.extensions:
        filters.append(f"ext: {','.join(args.extensions)}")
    if args.exclude:
        filters.append(f"exclude: {len(args.exclude)} pattern(s)")
    if filters:
        print(f"  Filters:   {' | '.join(filters)}")
    print()


def main() -> int:
    args = parse_args()
    formatter = OutputFormatter(args)

    if not args.quiet:
        _print_banner(args, formatter)

    # Validate paths exist
    valid_paths = [p for p in args.paths if p.exists()]
    if not valid_paths:
        print(f"[!] No valid paths to scan.", file=sys.stderr)
        return 1

    # Run scan
    engine = ScanEngine(args)
    files, folders = engine.scan(args.paths)

    if not files and not folders:
        print("\n[!] No files matched the criteria.", file=sys.stderr)
        return 1

    # Analyze
    analyzer = ResultsAnalyzer(files, folders, args)

    if not args.quiet:
        if args.target in ('files', 'both'):
            top_files = analyzer.get_top_files(args.top, args.sort_files)
            formatter.print_files_table(
                top_files,
                f"Top {len(top_files)} Files (by {args.sort_files.value})",
            )

        if args.target in ('folders', 'both'):
            top_folders = analyzer.get_top_folders(args.top, args.sort_folders)
            formatter.print_folders_table(
                top_folders,
                f"Top {len(top_folders)} Folders (by {args.sort_folders.value})",
            )

        formatter.print_extension_summary(analyzer)
        formatter.print_size_distribution(analyzer)
        formatter.print_age_distribution(analyzer)
        formatter.print_summary(analyzer, engine.stats)
        print()

    # Exports
    if args.json_output:
        formatter.export_json(analyzer, args.json_output)
    if args.csv_output:
        formatter.export_csv(analyzer, args.csv_output)

    return 0 if not _shutdown_requested.is_set() else 130


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n[!] Interrupted by user.", file=sys.stderr)
        sys.exit(130)
    except BrokenPipeError:
        # Allow piping to head/less without ugly traceback
        sys.exit(0)
    except Exception as e:
        print(f"\n[!] Fatal error: {e}", file=sys.stderr)
        if '-v' in sys.argv or '--verbose' in sys.argv:
            import traceback
            traceback.print_exc()
        sys.exit(1)(base)
