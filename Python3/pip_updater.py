#!/usr/bin/env python3
"""Safely update pip-owned packages inside non-base conda environments.

The updater deliberately treats conda and pip as separate ownership domains.  It
activates the selected environment through Conda's shell hook, and will not modify
the base environment, conda-owned Python distributions, user-site packages,
editable/direct-URL installs, or any wheel that would overwrite a file owned by
another distribution.  Every real update is resolved and downloaded before
mutation and carries a persistent rollback journal.
"""

import argparse
import base64
import configparser
import contextlib
import csv
import curses
import fcntl
import hashlib
import json
import os
import re
import selectors
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit

CACHE_ROOT = (
    Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "pip-updater"
)
CACHE_FILE = str(CACHE_ROOT / "cache-v2.json")
CACHE_VERSION = 2
BACK_TO_ENV = "__BACK_TO_ENV__"
PROTECTED_BOOTSTRAP_PACKAGES = {"pip", "setuptools", "wheel"}
SAFE_PROJECT_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
SAFE_VERSION = re.compile(r"^[A-Za-z0-9_.!+-]+$")
PROCESS_START_ENVIRONMENT = os.environ.copy()
# A transaction workspace without a journal never mutated the environment, but a
# concurrent preparation for another prefix may legitimately still be filling one
# in.  Only workspaces older than this are treated as abandoned.
ORPHAN_TRANSACTION_MAX_AGE_SECONDS = 24 * 60 * 60


class UpdaterError(RuntimeError):
    """A user-actionable safety or execution failure."""


class UpdateInterrupted(BaseException):
    """A termination signal, raised so an active transaction can roll back.

    This derives from BaseException so that ordinary ``except Exception`` blocks
    cannot accidentally swallow a shutdown request, matching KeyboardInterrupt.
    """


def _raise_termination(signum, _frame):
    """Convert a termination signal into a rollback-triggering exception."""
    raise UpdateInterrupted(f"terminated by signal {signum}")


def install_termination_handlers():
    """Make SIGTERM/SIGHUP unwind through the transaction rollback path.

    Without this, an orderly `kill` leaves a half-applied transaction that is
    only repaired on the next run.  Raising instead lets the running process
    roll itself back immediately.
    """
    for name in ("SIGTERM", "SIGHUP"):
        number = getattr(signal, name, None)
        if number is None:
            continue
        with contextlib.suppress(OSError, ValueError):
            signal.signal(number, _raise_termination)


def run_command(args, *, capture_output=False, timeout=None, env=None):
    """Run a command with consistent missing-binary handling."""
    try:
        return subprocess.run(
            args,
            capture_output=capture_output,
            text=True,
            timeout=timeout,
            env=env,
            check=False,
        )
    except FileNotFoundError as exc:
        raise UpdaterError(
            f"Required command '{args[0]}' was not found in PATH."
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise UpdaterError(
            f"Command timed out after {timeout} seconds: {args[0]}"
        ) from exc


def stream_command(
    args,
    *,
    timeout=None,
    on_start=None,
    on_line=None,
    on_tick=None,
    tick=1.0,
    merge_stderr=True,
    input_data=None,
):
    """Run a command, reporting each output line and a periodic liveness tick.

    ``run_command`` cannot show progress because it only returns once the child
    has exited.  Downloads take minutes, so this variant reads the merged output
    incrementally and calls ``on_tick`` at least once per ``tick`` seconds even
    while the child is silent. ``merge_stderr=False`` preserves machine-readable
    stdout such as pip's JSON report while still retaining stderr for failures.
    Everything stays in the calling thread so a termination signal still unwinds
    straight through the transaction rollback.
    """
    try:
        process = subprocess.Popen(
            args,
            stdin=subprocess.PIPE if input_data is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT if merge_stderr else subprocess.PIPE,
            bufsize=0,
        )
    except FileNotFoundError as exc:
        raise UpdaterError(
            f"Required command '{args[0]}' was not found in PATH."
        ) from exc

    collected = {"stdout": [], "stderr": []}
    pending = {"stdout": b"", "stderr": b""}

    def emit(kind, chunk):
        text = chunk.decode("utf-8", "replace").rstrip("\r")
        collected[kind].append(text)
        if kind == "stdout" and on_line is not None:
            on_line(text)

    deadline = time.monotonic() + timeout if timeout else None
    selector = selectors.DefaultSelector()
    try:
        if on_start is not None:
            on_start(process.pid)
        if input_data is not None:
            payload = (
                input_data.encode("utf-8")
                if isinstance(input_data, str)
                else input_data
            )
            assert process.stdin is not None
            try:
                process.stdin.write(payload)
            except BrokenPipeError:
                pass
            finally:
                process.stdin.close()
        selector.register(process.stdout, selectors.EVENT_READ, "stdout")
        if not merge_stderr:
            selector.register(process.stderr, selectors.EVENT_READ, "stderr")
        while selector.get_map():
            if deadline is not None and time.monotonic() > deadline:
                raise UpdaterError(
                    f"Command timed out after {timeout} seconds: {args[0]}"
                )
            ready = selector.select(tick)
            for key, _ in ready:
                kind = key.data
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                pending[kind] += chunk
                *lines, pending[kind] = pending[kind].split(b"\n")
                for line in lines:
                    emit(kind, line)
            if on_tick is not None:
                on_tick()
        for kind, tail in pending.items():
            if tail:
                emit(kind, tail)
    finally:
        selector.close()
        if process.poll() is None:
            process.kill()
        for stream in (
            process.stdin if input_data is not None else None,
            process.stdout,
            process.stderr if not merge_stderr else None,
        ):
            if stream is not None:
                with contextlib.suppress(OSError):
                    stream.close()
        process.wait()
    return subprocess.CompletedProcess(
        args,
        process.returncode,
        "\n".join(collected["stdout"]),
        "\n".join(collected["stderr"]),
    )


def format_bytes(count):
    """Return a byte count in the largest unit that keeps it readable."""
    size = float(count)
    for unit in ("B", "KB", "MB"):
        if size < 1024:
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} GB"


def format_rate(bytes_per_second):
    """Return a byte rate using the same readable units as transfer totals."""
    return f"{format_bytes(max(0, bytes_per_second))}/s"


def format_elapsed(seconds):
    """Return a whole number of seconds as MM:SS."""
    whole = int(seconds)
    return f"{whole // 60:02d}:{whole % 60:02d}"


class ResolverProgress:
    """Explain pip's observable work while it searches a dependency graph.

    pip does not expose an overall completion percentage. It does, however,
    announce packages, candidate metadata, and the packages for which it is
    backtracking. The selected-package bar below is deliberately scoped to the
    measurable metadata-loading stage; graph size and backtracking remain counts
    so the display never implies that resolver search is linear.
    """

    WIDTH = 16
    LOG_INTERVAL = 30
    REFRESH_INTERVAL = 0.2
    _PACKAGE_EVENT = re.compile(
        r"^(?:Collecting|Requirement already satisfied:)\s+"
        r"([A-Za-z0-9][A-Za-z0-9._-]*)"
    )
    _METADATA_EVENT = re.compile(
        r"^(?:Using cached|Downloading)\s+(\S+\.whl\.metadata)\b"
    )
    _BACKTRACK_EVENT = re.compile(
        r"pip is (?:still )?looking at multiple versions of "
        r"([A-Za-z0-9][A-Za-z0-9._-]*)"
    )

    def __init__(self, selected, stream=None):
        self.selected = {canonicalize_name(name) for name in selected}
        self.total = len(self.selected)
        self.stream = stream if stream is not None else sys.stdout
        self.interactive = bool(getattr(self.stream, "isatty", lambda: False)())
        self.started = time.monotonic()
        self.phase = "Loading metadata"
        self.loaded_selected = set()
        self.graph_packages = set()
        self.candidate_metadata = set()
        self.backtracking_packages = set()
        self.current = ""
        self.pid = None
        self.cpu_percent = None
        self.rss_bytes = None
        self._last_cpu_seconds = None
        self._last_cpu_measurement = None
        self._painted = []
        self._last_paint = None
        self._reported_interval = -1
        self._finished = False

    def watch(self, pid):
        """Remember the resolver process so silent CPU work stays visible."""
        self.pid = pid
        self.cpu_percent = None
        self.rss_bytes = None
        self._last_cpu_seconds = None
        self._last_cpu_measurement = None
        self._measure_process()

    def note(self, line):
        """Turn pip's human-readable resolver events into stable counters."""
        text = line.strip()
        package = self._PACKAGE_EVENT.match(text)
        if package:
            name = canonicalize_name(package.group(1))
            self.graph_packages.add(name)
            if name in self.selected:
                self.loaded_selected.add(name)
            self.current = name
            if len(self.loaded_selected) == self.total:
                self.phase = "Resolving dependencies"

        metadata = self._METADATA_EVENT.match(text)
        if metadata:
            self.candidate_metadata.add(metadata.group(1))

        backtrack = self._BACKTRACK_EVENT.search(text)
        if backtrack:
            name = canonicalize_name(backtrack.group(1))
            self.backtracking_packages.add(name)
            self.current = name
            self.phase = "Backtracking"

        if text.startswith(("Downloading ", "Using cached ")):
            if ".whl (" in text:
                self.phase = "Preparing candidate files"
        elif text.startswith("Would install "):
            self.phase = "Finalizing plan"

    def _measure_process(self):
        """Sample Linux resolver CPU and memory without making them mandatory."""
        if self.pid is None:
            return
        now = time.monotonic()
        try:
            stat_text = Path(f"/proc/{self.pid}/stat").read_text(encoding="utf-8")
            fields = stat_text[stat_text.rfind(")") + 2 :].split()
            ticks = int(fields[11]) + int(fields[12])
            cpu_seconds = ticks / os.sysconf("SC_CLK_TCK")
            if self._last_cpu_seconds is not None:
                elapsed = now - self._last_cpu_measurement
                if elapsed > 0:
                    self.cpu_percent = max(
                        0.0,
                        100 * (cpu_seconds - self._last_cpu_seconds) / elapsed,
                    )
            self._last_cpu_seconds = cpu_seconds
            self._last_cpu_measurement = now

            status = Path(f"/proc/{self.pid}/status").read_text(encoding="utf-8")
            rss = re.search(r"^VmRSS:\s+(\d+)\s+kB$", status, re.MULTILINE)
            if rss:
                self.rss_bytes = int(rss.group(1)) * 1024
        except (OSError, ValueError, IndexError):
            # The process may have exited between the two reads, and non-Linux
            # systems do not provide /proc. Resolver event reporting still works.
            return

    def _selected_bar(self):
        loaded = len(self.loaded_selected)
        filled = self.WIDTH if not self.total else self.WIDTH * loaded // self.total
        return "#" * filled + "-" * (self.WIDTH - filled)

    def _line(self, max_width):
        elapsed = format_elapsed(time.monotonic() - self.started)
        loaded = len(self.loaded_selected)
        selected = f"selected [{self._selected_bar()}] {loaded}/{self.total} loaded"
        graph = (
            f"graph {count_label(len(self.graph_packages), 'package')} / "
            f"{count_label(len(self.candidate_metadata), 'candidate')}"
        )
        compact_selected = f"selected {loaded}/{self.total}"
        compact_graph = (
            f"graph {len(self.graph_packages)}/{len(self.candidate_metadata)}"
        )
        current = self.current
        if len(current) > 30:
            current = current[:27] + "..."

        optional = []
        if current:
            optional.append(f"current {current}")
        if self.backtracking_packages:
            optional.append(
                f"backtracking "
                f"{count_label(len(self.backtracking_packages), 'package')}"
            )
        process = []
        if self.cpu_percent is not None:
            process.append(f"CPU {self.cpu_percent:.0f}%")
        if self.rss_bytes is not None:
            process.append(f"RAM {format_bytes(self.rss_bytes)}")
        if process:
            optional.append(" / ".join(process))

        parts = [f"  {self.phase}", selected, graph]
        for item in optional:
            candidate = " | ".join([*parts, item, elapsed])
            if len(candidate) <= max_width:
                parts.append(item)
        line = " | ".join([*parts, elapsed])
        if len(line) > max_width:
            line = " | ".join(
                [f"  {self.phase}", compact_selected, compact_graph, elapsed]
            )
        return line[:max_width]

    @staticmethod
    def _truncate_label(value, available):
        if available <= 0:
            return ""
        if len(value) <= available:
            return value
        if available <= 3:
            return value[:available]
        return value[: available - 3] + "..."

    def _resolver_activity(self):
        if self.phase == "Resolver finished":
            return "finished"
        if self.phase == "Resolver stopped":
            return "stopped"
        if self.phase == "Preparing candidate files":
            return "preparing candidate wheel files"
        if self.phase == "Finalizing plan":
            return "finalizing the exact plan"
        if self.phase == "Discovering compatible wheels":
            return "finding compatible binary targets"
        if self.backtracking_packages:
            return (
                "backtracking across "
                f"{count_label(len(self.backtracking_packages), 'package')}"
            )
        if self.phase == "Loading metadata":
            return "loading selected package metadata"
        return "searching compatible versions"

    def _terminal_lines(self, max_width):
        """Build a compact dashboard whose three rows fit the terminal."""
        loaded = len(self.loaded_selected)
        line1 = (
            f"  Selected metadata [{self._selected_bar()}] {loaded}/{self.total} loaded"
        )
        if len(line1) > max_width:
            line1 = f"  Selected [{self._selected_bar()}] {loaded}/{self.total}"

        graph_prefix = (
            f"  Dependency graph: {count_label(len(self.graph_packages), 'package')}, "
            f"{count_label(len(self.candidate_metadata), 'candidate')} | current: "
        )
        if len(graph_prefix) + 1 > max_width:
            graph_prefix = (
                f"  Graph {len(self.graph_packages)}/{len(self.candidate_metadata)}"
                " | current: "
            )
        current = self.current or "waiting for pip"
        line2 = graph_prefix + self._truncate_label(
            current, max_width - len(graph_prefix)
        )

        elapsed = format_elapsed(time.monotonic() - self.started)
        parts = [f"  Resolver: {self._resolver_activity()}"]
        if self.cpu_percent is not None:
            parts.append(f"CPU {self.cpu_percent:.0f}%")
        if self.rss_bytes is not None:
            parts.append(f"RAM {format_bytes(self.rss_bytes)}")
        while len(" | ".join([*parts, elapsed])) > max_width and len(parts) > 1:
            parts.pop()
        line3 = " | ".join([*parts, elapsed])
        if len(line3) > max_width:
            line3 = self._truncate_label(line3, max_width)

        return [line[:max_width] for line in (line1, line2, line3)]

    def _paint(self):
        width = max(40, shutil.get_terminal_size((180, 24)).columns - 1)
        lines = self._terminal_lines(width)
        if self._painted:
            self.stream.write("\r\x1b[2A")
        else:
            self.stream.write("\r")
        for index, line in enumerate(lines):
            if index:
                self.stream.write("\n")
            previous = self._painted[index] if self._painted else 0
            self.stream.write(line.ljust(previous))
        self.stream.flush()
        self._painted = [len(line) for line in lines]
        self._last_paint = time.monotonic()

    def tick(self):
        """Refresh real telemetry or emit a bounded log heartbeat."""
        if self._finished:
            return
        if self.interactive:
            now = time.monotonic()
            if (
                self._last_paint is not None
                and now - self._last_paint < self.REFRESH_INTERVAL
            ):
                return
            self._measure_process()
            self._paint()
            return
        elapsed = time.monotonic() - self.started
        interval = int(elapsed // self.LOG_INTERVAL)
        if interval == self._reported_interval:
            return
        self._measure_process()
        print(self._line(10_000), file=self.stream, flush=True)
        self._reported_interval = interval

    def finish(self, success):
        """Settle the telemetry without claiming success on failure."""
        if self._finished:
            return
        self._finished = True
        self.phase = "Resolver finished" if success else "Resolver stopped"
        if self.interactive:
            self._paint()
            self.stream.write("\n")
            self.stream.flush()
        else:
            print(self._line(10_000), file=self.stream, flush=True)


class DownloadProgress:
    """Live, plain-language progress for a batch of wheel downloads.

    Progress is measured from the filesystem -- finished wheels in the
    destination plus the partial wheel the child still has open -- rather than
    from pip's wording, which is not a stable interface.  Its output is parsed
    solely to name the file in flight, so a future pip that words it differently
    loses the label and nothing else.
    """

    def __init__(self, title, total, destination, stream=None):
        self.title = title
        self.total = total
        self.destination = Path(destination)
        self.stream = stream if stream is not None else sys.stdout
        self.interactive = bool(getattr(self.stream, "isatty", lambda: False)())
        self.started = time.monotonic()
        self.current = ""
        self.pid = None
        self.done = 0
        self.downloaded = 0
        self.source = ""
        self.speed = None
        self._peak = 0
        self._complete = set()
        self._observed_sizes = {}
        self._parallel_active = False
        self._settling_parallel = False
        self._network_started = None
        self._network_start_bytes = 0
        self._rate_bytes = 0
        self._rate_time = self.started
        self._painted = 0
        self._reported = 0
        self._reported_interval = -1

    def watch(self, pid):
        """Follow this child so the wheel it is still fetching can be counted."""
        self.pid = pid

    # pip says "Downloading x.whl (5 MB)" for a fetch and "Using cached x.whl
    # (5 MB)" when it serves the same wheel from its own HTTP cache.
    FETCH_PREFIXES = ("Downloading ", "Using cached ")

    def note(self, line):
        """Record the wheel pip has just started fetching, for display only."""
        text = line.strip()
        for prefix in self.FETCH_PREFIXES:
            if text.startswith(prefix):
                name = text[len(prefix) :].split(" (")[0]
                if not name.endswith(".metadata"):
                    self.current = name
                    self.source = "network" if prefix == "Downloading " else "cache"
                    if self.source == "network" and self._network_started is None:
                        self._network_started = time.monotonic()
                        self._network_start_bytes = self.downloaded
                    self.speed = None
                    self._rate_bytes = self.downloaded
                    self._rate_time = time.monotonic()
                return

    def network_downloads(self, count, concurrent_files, connections_per_file):
        """Describe the real queue and bounded HTTP concurrency."""
        active = min(count, concurrent_files)
        self.current = (
            f"network: {count} queued, up to {active} files x "
            f"{connections_per_file} connections"
        )
        self._parallel_active = True
        self.source = "network"
        self._network_started = time.monotonic()
        self._network_start_bytes = self.downloaded
        self.speed = None
        self._rate_bytes = self.downloaded
        self._rate_time = time.monotonic()

    def parallel_finished(self):
        """Settle final files only after the parallel child has exited."""
        self._parallel_active = False
        self._settling_parallel = True
        try:
            self.tick()
        finally:
            self._settling_parallel = False

    def parallel_failed(self):
        """Stop treating retry cleanup as an active parallel transfer."""
        self._parallel_active = False

    def cache_hit(self, filename):
        """Expose verified local-cache reuse without calling it network speed."""
        self.current = f"cache: {filename}"
        self.source = "cache"

    def _inflight_bytes(self):
        """Return how much of the wheel pip is still fetching has arrived.

        pip downloads each wheel to a temporary file and only copies it into
        ``--dest`` once it is complete, so a counter based on the destination
        alone reads zero for the whole of a multi-gigabyte fetch.  Reading the
        child's open files gives a live figure instead.  This is advisory and
        best-effort: where /proc is unavailable the counter simply advances once
        per finished wheel, exactly as it did before.
        """
        if self.pid is None:
            return 0
        try:
            handles = list(Path(f"/proc/{self.pid}/fd").iterdir())
        except OSError:
            return 0
        largest = 0
        for handle in handles:
            try:
                name = os.path.basename(os.readlink(str(handle)))
                if not name.endswith(".whl") or name in self._complete:
                    continue
                # pip fetches one wheel at a time, so the largest open wheel is
                # the one in flight; max() also avoids double counting during
                # the moment a finished file is being copied into place.
                largest = max(largest, handle.stat().st_size)
            except OSError:
                continue
        return largest

    def _measure(self):
        previous_done = self.done
        wheels = list(self.destination.glob("*.whl"))
        sizes = {}
        for wheel in wheels:
            with contextlib.suppress(OSError):
                sizes[wheel.name] = wheel.stat().st_size
        complete = []
        for wheel in wheels:
            size = sizes.get(wheel.name)
            if size is None or Path(str(wheel) + ".aria2").exists():
                continue
            # aria2 can remove its control file just before the last write is
            # visible. While it is active, require one unchanged sample before
            # calling a file complete. A successful child exit settles all.
            if self._parallel_active and self._observed_sizes.get(wheel.name) != size:
                continue
            complete.append(wheel)
        self.done = len(complete)
        self._complete = {wheel.name for wheel in complete}
        total = sum(sizes.values())
        self._observed_sizes = sizes
        # There is a moment between pip closing a finished download and copying
        # it into place where neither location holds it.  Reporting the running
        # peak keeps the counter from flicking back to zero, which reads as a
        # failure rather than as the last step of a successful fetch.
        self._peak = max(self._peak, total + self._inflight_bytes())
        self.downloaded = self._peak
        now = time.monotonic()
        elapsed = now - self._rate_time
        if (
            self.source == "network"
            and (self._settling_parallel or self.done > previous_done)
            and self._network_started is not None
        ):
            network_elapsed = now - self._network_started
            if network_elapsed > 0:
                self.speed = (
                    max(0, self.downloaded - self._network_start_bytes)
                    / network_elapsed
                )
        elif self.source == "network" and elapsed >= 0.1:
            self.speed = max(0, self.downloaded - self._rate_bytes) / elapsed
            self._rate_bytes = self.downloaded
            self._rate_time = now

    def _transfer_status(self):
        if self.source == "cache":
            return "cache"
        if self.source == "network":
            return format_rate(self.speed or 0)
        return ""

    def _report(self):
        status = self._transfer_status()
        suffix = f", {status}" if status else ""
        print(
            f"  {self.title}: {self.done} of {self.total} downloaded "
            f"({format_bytes(self.downloaded)}{suffix}).",
            file=self.stream,
            flush=True,
        )
        self._reported = self.done
        self._reported_interval = int((time.monotonic() - self.started) // 30)

    def tick(self):
        """Repaint the progress line, or report each completion when piped."""
        self._measure()
        if self.interactive:
            self._paint()
        elif self.done != self._reported:
            self._report()
        elif self.source == "network" and self.done < self.total:
            # A pipe cannot repaint one terminal row, but it must not go silent
            # for the duration of one multi-gigabyte wheel either. Emit one
            # bounded heartbeat every 30 seconds with the same live byte/rate
            # telemetry as the interactive display.
            interval = int((time.monotonic() - self.started) // 30)
            if interval != self._reported_interval:
                status = self._transfer_status()
                current = f" | {self.current}" if self.current else ""
                print(
                    f"  {self.title}: {self.done}/{self.total} complete | "
                    f"{format_bytes(self.downloaded)} | {status} | "
                    f"{format_elapsed(time.monotonic() - self.started)}{current}",
                    file=self.stream,
                    flush=True,
                )
                self._reported_interval = interval

    def _paint(self):
        filled = round(20 * self.done / self.total) if self.total else 20
        bar = "#" * filled + "-" * (20 - filled)
        line = (
            f"  {self.title} [{bar}] {self.done}/{self.total}  "
            f"{format_bytes(self.downloaded)}"
        )
        status = self._transfer_status()
        if status:
            line += f"  {status}"
        line += f"  {format_elapsed(time.monotonic() - self.started)}"
        if self.current:
            width = max(40, shutil.get_terminal_size((180, 24)).columns - 1)
            available = width - len(line) - 2
            if available > 3:
                line += "  " + ResolverProgress._truncate_label(self.current, available)
        # Pad to erase the tail of any longer line drawn a moment ago.
        self.stream.write("\r" + line.ljust(self._painted))
        self.stream.flush()
        self._painted = len(line)

    def finish(self):
        """Leave one settled summary line behind for the session transcript."""
        # The child has been reaped by now, so drop it before measuring rather
        # than risk reading the open files of whatever inherits its pid next.
        self.pid = None
        self._measure()
        if self.interactive:
            self.current = ""
            self._paint()
            self.stream.write("\n")
            self.stream.flush()
        elif self.done != self._reported:
            self._report()


class InstallProgress:
    """Live, plain-language progress for installing verified local wheels.

    pip prints nothing between starting to install collected packages and its
    final summary line, so a multi-gigabyte install looks hung at the exact
    moment the environment is being mutated.  Progress is therefore measured
    from the filesystem -- pip writes each package's versioned
    ``.dist-info/RECORD`` as the last step of installing that package -- never
    from pip's wording.  The wheel the child currently holds open supplies the
    in-flight label; as with downloads this is advisory, and where /proc is
    unavailable only the label is lost while the completed-package counter
    keeps working.
    """

    def __init__(self, title, expected, stream=None):
        self.title = title
        self.expected = expected
        self.total = len(expected)
        self.stream = stream if stream is not None else sys.stdout
        self.interactive = bool(getattr(self.stream, "isatty", lambda: False)())
        self.started = time.monotonic()
        self.current = ""
        self.pid = None
        self.done = 0
        self._labels = {item["wheel"]: item["label"] for item in expected}
        self._painted = 0
        self._reported = 0
        self._reported_interval = -1

    def watch(self, pid):
        """Follow this child so the wheel it is unpacking can be named."""
        self.pid = pid

    def _inflight_label(self):
        """Name the package whose wheel the child currently holds open."""
        if self.pid is None:
            return ""
        try:
            handles = list(Path(f"/proc/{self.pid}/fd").iterdir())
        except OSError:
            return ""
        for handle in handles:
            try:
                name = os.path.basename(os.readlink(str(handle)))
            except OSError:
                continue
            label = self._labels.get(name)
            if label:
                return label
        return ""

    def _measure(self):
        self.done = sum(
            1
            for item in self.expected
            if any(record.is_file() for record in item["records"])
        )
        label = self._inflight_label()
        if label:
            # Between packages no wheel is open for a moment; keep the last
            # label rather than flickering, exactly as downloads do.
            self.current = f"installing {label}"
        elif self.done >= self.total:
            self.current = ""

    def _report(self):
        print(
            f"  {self.title.rstrip()}: {self.done} of "
            f"{count_label(self.total, 'package')} in place.",
            file=self.stream,
            flush=True,
        )
        self._reported = self.done
        self._reported_interval = int((time.monotonic() - self.started) // 30)

    def tick(self):
        """Repaint the progress line, or report each completion when piped."""
        self._measure()
        if self.interactive:
            self._paint()
        elif self.done != self._reported:
            self._report()
        elif self.done < self.total:
            # A pipe cannot repaint one terminal row, but it must not go
            # silent for the whole of one large package either.  Emit one
            # bounded heartbeat every 30 seconds.
            interval = int((time.monotonic() - self.started) // 30)
            if interval != self._reported_interval:
                current = f" | {self.current}" if self.current else ""
                print(
                    f"  {self.title.rstrip()}: {self.done}/{self.total} complete | "
                    f"{format_elapsed(time.monotonic() - self.started)}{current}",
                    file=self.stream,
                    flush=True,
                )
                self._reported_interval = interval

    def _paint(self):
        filled = round(20 * self.done / self.total) if self.total else 0
        bar = "#" * filled + "-" * (20 - filled)
        line = (
            f"  {self.title} [{bar}] {self.done}/{self.total} in place  "
            f"{format_elapsed(time.monotonic() - self.started)}"
        )
        if self.current:
            width = max(40, shutil.get_terminal_size((180, 24)).columns - 1)
            available = width - len(line) - 2
            if available > 3:
                line += "  " + ResolverProgress._truncate_label(self.current, available)
        # Pad to erase the tail of any longer line drawn a moment ago.
        self.stream.write("\r" + line.ljust(self._painted))
        self.stream.flush()
        self._painted = len(line)

    def finish(self):
        """Leave one settled summary line behind for the session transcript."""
        # The child has been reaped by now, so drop it before measuring rather
        # than risk reading the open files of whatever inherits its pid next.
        self.pid = None
        self._measure()
        if self.interactive:
            self.current = ""
            self._paint()
            self.stream.write("\n")
            self.stream.flush()
        elif self.done != self._reported:
            self._report()


class PackageScanProgress:
    """Truthful liveness telemetry for pip's non-linear outdated scan.

    ``pip list --outdated`` emits one JSON document only after checking every
    installed distribution, so there is no honest completion percentage to
    parse. The moving bar is explicitly activity, while scope, stage, process
    CPU/RAM, elapsed time, and the final update count are measured facts.
    """

    WIDTH = 20
    REFRESH_INTERVAL = 0.2
    LOG_INTERVAL = 15

    def __init__(self, *, cached_count=None, render=True, stream=None):
        self.cached_count = cached_count
        self.render = render
        self.stream = stream if stream is not None else sys.stdout
        self.interactive = bool(getattr(self.stream, "isatty", lambda: False)())
        self.started = time.monotonic()
        self.phase = "Reading installed package metadata"
        self.scope = None
        self.found = None
        self.pid = None
        self.cpu_percent = None
        self.rss_bytes = None
        self.success = None
        self._last_cpu_seconds = None
        self._last_cpu_measurement = None
        self._last_paint = None
        self._painted = []
        self._reported_interval = -1
        self._lock = threading.Lock()

    def set_phase(self, phase):
        with self._lock:
            self.phase = phase

    def set_scope(self, count):
        with self._lock:
            self.scope = count

    def set_found(self, count):
        with self._lock:
            self.found = count

    def watch(self, pid):
        with self._lock:
            self.pid = pid
            self._last_cpu_seconds = None
            self._last_cpu_measurement = None
        self._measure_process()

    def _measure_process(self):
        with self._lock:
            pid = self.pid
            previous_cpu = self._last_cpu_seconds
            previous_time = self._last_cpu_measurement
        if pid is None:
            return
        now = time.monotonic()
        try:
            stat_text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
            fields = stat_text[stat_text.rfind(")") + 2 :].split()
            ticks = int(fields[11]) + int(fields[12])
            cpu_seconds = ticks / os.sysconf("SC_CLK_TCK")
            cpu_percent = None
            if previous_cpu is not None and previous_time is not None:
                elapsed = now - previous_time
                if elapsed > 0:
                    cpu_percent = max(0.0, 100 * (cpu_seconds - previous_cpu) / elapsed)
            status = Path(f"/proc/{pid}/status").read_text(encoding="utf-8")
            rss = re.search(r"^VmRSS:\s+(\d+)\s+kB$", status, re.MULTILINE)
            rss_bytes = int(rss.group(1)) * 1024 if rss else None
        except (OSError, ValueError, IndexError):
            return
        with self._lock:
            self._last_cpu_seconds = cpu_seconds
            self._last_cpu_measurement = now
            if cpu_percent is not None:
                self.cpu_percent = cpu_percent
            if rss_bytes is not None:
                self.rss_bytes = rss_bytes

    def snapshot(self):
        with self._lock:
            return {
                "phase": self.phase,
                "scope": self.scope,
                "found": self.found,
                "cpu_percent": self.cpu_percent,
                "rss_bytes": self.rss_bytes,
                "success": self.success,
            }

    def _activity_bar(self, elapsed, success):
        if success is True:
            return "#" * self.WIDTH
        if success is False:
            return "!" + "-" * (self.WIDTH - 1)
        span = self.WIDTH - 4
        step = int(elapsed * 5) % (2 * span)
        position = step if step <= span else 2 * span - step
        cells = ["-"] * self.WIDTH
        cells[position : position + 4] = ["#", "#", "#", ">"]
        return "".join(cells)

    def terminal_lines(self, max_width):
        snap = self.snapshot()
        elapsed_seconds = time.monotonic() - self.started
        elapsed = format_elapsed(elapsed_seconds)
        state = (
            "complete"
            if snap["success"] is True
            else "failed"
            if snap["success"] is False
            else "running"
        )
        line1 = (
            f"  Live package scan activity "
            f"[{self._activity_bar(elapsed_seconds, snap['success'])}] "
            f"{state} | {elapsed}"
        )
        line2 = f"  Stage: {snap['phase']}"
        facts = []
        if snap["scope"] is not None:
            facts.append(f"scope {count_label(snap['scope'], 'installed package')}")
        if self.cached_count is not None:
            facts.append(f"cached result {count_label(self.cached_count, 'update')}")
        if snap["found"] is not None:
            facts.append(f"found {count_label(snap['found'], 'update')}")
        if snap["cpu_percent"] is not None:
            facts.append(f"CPU {snap['cpu_percent']:.0f}%")
        if snap["rss_bytes"] is not None:
            facts.append(f"RAM {format_bytes(snap['rss_bytes'])}")
        line3 = "  " + (" | ".join(facts) or "Starting scan process...")
        return [
            ResolverProgress._truncate_label(line, max_width)
            for line in (line1, line2, line3)
        ]

    def compact_status(self, max_width):
        snap = self.snapshot()
        elapsed = time.monotonic() - self.started
        text = (
            f" Scan [{self._activity_bar(elapsed, snap['success'])}] "
            f"{snap['phase']} | {format_elapsed(elapsed)}"
        )
        return ResolverProgress._truncate_label(text, max_width)

    def paint(self, *, force=False):
        now = time.monotonic()
        if (
            not force
            and self._last_paint is not None
            and now - self._last_paint < self.REFRESH_INTERVAL
        ):
            return
        self._measure_process()
        if self.interactive:
            width = max(40, shutil.get_terminal_size((180, 24)).columns - 1)
            lines = self.terminal_lines(width)
            if self._painted:
                self.stream.write("\r\x1b[2A")
            else:
                self.stream.write("\r")
            for index, line in enumerate(lines):
                if index:
                    self.stream.write("\n")
                previous = self._painted[index] if self._painted else 0
                self.stream.write(line.ljust(previous))
            self.stream.flush()
            self._painted = [len(line) for line in lines]
            self._last_paint = now
            return
        interval = int((now - self.started) // self.LOG_INTERVAL)
        if force or interval != self._reported_interval:
            print(" | ".join(self.terminal_lines(10_000)), file=self.stream, flush=True)
            self._reported_interval = interval

    def tick(self):
        if self.render:
            self.paint()
        else:
            self._measure_process()

    def finish(self, success):
        with self._lock:
            self.pid = None
            self.success = success
            self.phase = (
                "Package index scan complete"
                if success
                else "Package index scan failed"
            )
        if self.render:
            self.paint(force=True)
            self.end_display()

    def end_display(self):
        if self.interactive and self._painted:
            self.stream.write("\n")
            self.stream.flush()


def parse_json_output(raw, context):
    """Parse JSON output with context-specific error messaging."""
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise UpdaterError(
            f"Unexpected JSON output while {context} ({len(raw)} bytes received)."
        ) from exc


def canonicalize_name(name):
    """Return the PEP 503 normalized form of a distribution name."""
    return re.sub(r"[-_.]+", "-", str(name)).lower()


def wheel_filename_from_url(url):
    """Return a safe wheel basename from a resolver-selected URL."""
    if not isinstance(url, str) or not url or "\n" in url or "\r" in url:
        raise UpdaterError("pip proposed an invalid wheel URL.")
    encoded = PurePosixPath(urlsplit(url).path).name
    filename = unquote(encoded)
    if (
        not filename.endswith(".whl")
        or "/" in filename
        or "\\" in filename
        or filename in {"", ".", ".."}
    ):
        raise UpdaterError(f"pip proposed a URL without a safe wheel filename: {url!r}")
    return filename


def secure_directory(path):
    """Create a private, non-symlinked, owner-only directory.

    Every updater-owned directory (cache root, locks, transactions) needs the
    same guarantees, so the checks live in one place instead of being repeated
    with slightly different strictness.
    """
    path = Path(path)
    if path.is_symlink():
        raise UpdaterError(f"Refusing symlinked updater directory {path}.")
    try:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        info = path.lstat()
        if not stat.S_ISDIR(info.st_mode):
            raise UpdaterError(f"Updater path is not a directory: {path}")
        if info.st_uid != os.getuid():
            raise UpdaterError(f"Updater directory is not privately owned: {path}")
        path.chmod(0o700)
    except OSError as exc:
        raise UpdaterError(f"Could not secure updater directory {path}: {exc}") from exc
    return path


def ensure_cache_root():
    """Create the private cache root and enforce owner-only permissions."""
    return secure_directory(CACHE_ROOT)


def _fsync_directory(path):
    """Flush a directory entry so an atomic replace survives power loss."""
    try:
        fd = os.open(str(path), os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        # Some filesystems reject directory fsync; the replace itself is atomic.
        pass
    finally:
        os.close(fd)


def conda_executable():
    """Return the exact conda executable used by the current shell."""
    configured = os.environ.get("CONDA_EXE")
    if configured and Path(configured).is_file():
        return configured
    discovered = shutil.which("conda")
    if discovered:
        return discovered
    raise UpdaterError("Conda was not found. Activate Conda or set CONDA_EXE.")


def environment_python(prefix):
    """Resolve the interpreter belonging to a conda prefix."""
    prefix_path = Path(prefix)
    candidates = (
        prefix_path / "bin" / "python",
        prefix_path / "python.exe",
        prefix_path / "Scripts" / "python.exe",
    )
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    raise UpdaterError(f"No runnable Python interpreter exists in {prefix}.")


def pip_command(prefix):
    """Build an isolated pip command that cannot see the user site directory."""
    return [environment_python(prefix), "-I", "-m", "pip"]


def command_failure(context, result, *, max_lines=None):
    """Create a concise exception from a failed subprocess result."""
    detail = (result.stderr or result.stdout or "").strip()
    if max_lines is not None:
        lines = detail.splitlines()
        if len(lines) > max_lines:
            omitted = len(lines) - max_lines
            detail = (
                f"[... {omitted} earlier pip output lines omitted ...]\n"
                + "\n".join(lines[-max_lines:])
            )
    suffix = f"\n{detail}" if detail else ""
    return UpdaterError(f"{context} failed with exit code {result.returncode}.{suffix}")


def load_cache():
    """Load the private cache, returning a normalized cache structure."""
    empty = {"version": CACHE_VERSION, "envs": {}, "holds": {}}
    try:
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return empty
    except (OSError, json.JSONDecodeError):
        return empty

    if not isinstance(data, dict) or data.get("version") != CACHE_VERSION:
        return empty
    envs = data.get("envs", {})
    if not isinstance(envs, dict):
        envs = {}
    holds = data.get("holds", {})
    if not isinstance(holds, dict):
        holds = {}
    return {"version": CACHE_VERSION, "envs": envs, "holds": holds}


def save_cache(cache):
    """Persist cache atomically in a private, symlink-safe directory."""
    tmp_path = None
    try:
        ensure_cache_root()
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=CACHE_ROOT,
            prefix="cache-",
            suffix=".tmp",
            delete=False,
        ) as f:
            tmp_path = Path(f.name)
            os.fchmod(f.fileno(), 0o600)
            json.dump(cache, f, separators=(",", ":"))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, CACHE_FILE)
        _fsync_directory(CACHE_ROOT)
    except OSError:
        # Cache persistence must never block updater behavior.
        pass
    finally:
        if tmp_path is not None:
            with contextlib.suppress(FileNotFoundError, OSError):
                tmp_path.unlink()


def get_cached_packages(env_name):
    """Return cached outdated packages for one env, or None if unavailable."""
    cache = load_cache()
    entry = cache["envs"].get(env_name)
    if not isinstance(entry, dict):
        return None
    packages = entry.get("packages")
    if not isinstance(packages, list):
        return None
    normalized = []
    for pkg in packages:
        if not isinstance(pkg, dict):
            continue
        name = pkg.get("name")
        if not name:
            continue
        normalized.append(
            {
                "name": str(name),
                "version": str(pkg.get("version", "?")),
                "latest_version": str(pkg.get("latest_version", "?")),
            }
        )
    normalized.sort(key=lambda p: p["name"].lower())
    return normalized


def set_cached_packages(env_name, packages):
    """Store latest package scan for one env."""
    cache = load_cache()
    cache["envs"][env_name] = {
        "timestamp": int(time.time()),
        "packages": packages,
    }
    save_cache(cache)


def remove_cached_packages(env_name, names):
    """Remove successfully-updated package names from one env cache entry."""
    cache = load_cache()
    entry = cache["envs"].get(env_name)
    if not isinstance(entry, dict):
        return
    packages = entry.get("packages")
    if not isinstance(packages, list):
        return

    selected = {canonicalize_name(name) for name in names}
    remaining = []
    for pkg in packages:
        if not isinstance(pkg, dict):
            continue
        pkg_name = canonicalize_name(pkg.get("name", ""))
        if pkg_name not in selected:
            remaining.append(pkg)

    entry["timestamp"] = int(time.time())
    entry["packages"] = remaining
    cache["envs"][env_name] = entry
    save_cache(cache)


def get_cached_holds(prefix):
    """Return the resolver's last held-back package records for one prefix.

    Each record ties a held package to the exact installed versions of the
    packages whose requirements capped it, so a hold self-invalidates the
    moment either side releases: the scan then offers the package again and
    the resolver retests it for real.
    """
    holds = load_cache()["holds"].get(str(prefix))
    return holds if isinstance(holds, dict) else {}


def set_cached_holds(prefix, holds):
    """Store the resolver's held-back package records for one prefix."""
    cache = load_cache()
    cache["holds"][str(prefix)] = holds
    save_cache(cache)


def _is_within(path, parent):
    """Return whether path resolves within parent without requiring existence."""
    if not path:
        # An empty path would resolve to the current directory, which can itself
        # sit inside the prefix and wrongly pass a containment check.
        return False
    try:
        Path(path).resolve(strict=False).relative_to(Path(parent).resolve(strict=False))
        return True
    except (OSError, ValueError):
        return False


def get_environment_inventory(prefix):
    """Read installed distribution metadata using the target interpreter."""
    helper = r"""
import json
from importlib import metadata

rows = []
for dist in metadata.distributions():
    name = dist.metadata.get("Name") or ""
    if not name:
        continue
    metadata_path = getattr(dist, "_path", None)
    rows.append({
        "name": name,
        "version": dist.version,
        "installer": (dist.read_text("INSTALLER") or "").strip().lower(),
        "requires": dist.requires or [],
        "direct_url": (dist.read_text("direct_url.json") or "").strip(),
        "metadata_path": str(metadata_path) if metadata_path is not None else "",
        "location": str(dist.locate_file("")),
    })
print(json.dumps(rows, separators=(",", ":")))
"""
    result = run_command(
        [environment_python(prefix), "-I", "-c", helper],
        capture_output=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise command_failure(f"Reading installed packages in {prefix}", result)
    rows = parse_json_output(result.stdout, f"reading installed packages in {prefix}")
    if not isinstance(rows, list):
        raise UpdaterError(f"Installed package inventory for {prefix} was not a list.")
    return rows


def index_inventory(rows):
    """Index inventory by normalized name and reject ambiguous metadata."""
    grouped = {}
    for row in rows:
        if not isinstance(row, dict) or not row.get("name"):
            continue
        grouped.setdefault(canonicalize_name(row["name"]), []).append(row)
    duplicates = {name: items for name, items in grouped.items() if len(items) != 1}
    if duplicates:
        raise UpdaterError(explain_duplicate_metadata(duplicates))
    return {name: items[0] for name, items in grouped.items()}


def record_evidence(metadata_path):
    """Compare one distribution's hashed RECORD entries with files on disk.

    Duplicate metadata cannot be resolved safely from version numbers or path
    overlap: either copy may be the stale one. Wheel RECORD hashes provide
    direct evidence instead. Entries outside site-packages are skipped because
    they are unnecessary here and must not turn a RECORD into an arbitrary read.
    """
    directory = Path(metadata_path)
    own_records = directory.name + "/"
    try:
        with open(
            directory / "RECORD", newline="", encoding="utf-8", errors="replace"
        ) as handle:
            rows = list(csv.reader(handle))
    except OSError:
        return None
    claims = set()
    matched = changed = missing = 0
    root = directory.parent.resolve(strict=False)
    for row in rows:
        if not row or not row[0] or row[0].startswith(own_records):
            continue
        recorded = PurePosixPath(row[0])
        if recorded.is_absolute() or ".." in recorded.parts:
            continue
        claims.add(row[0])
        if len(row) < 2 or not row[1] or not row[1].startswith("sha256="):
            continue
        target = root.joinpath(*recorded.parts)
        if not _is_within(target, root):
            continue
        try:
            if not target.is_file():
                missing += 1
                continue
            digest = hashlib.sha256()
            with open(target, "rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
        except OSError:
            missing += 1
            continue
        actual = base64.urlsafe_b64encode(digest.digest()).rstrip(b"=").decode()
        expected = row[1].split("=", 1)[1]
        if actual == expected:
            matched += 1
        else:
            changed += 1
    return {
        "claims": claims,
        "matched": matched,
        "changed": changed,
        "missing": missing,
    }


def explain_duplicate_metadata(duplicates):
    """Explain duplicate records and quarantine only demonstrably stale copies.

    An upgrade normally replaces a package's records; when that clean-up does
    not happen the old directory stays behind and the environment now claims two
    versions of one package at once.  The updater cannot tell which one an
    update is meant to replace, so it stops.

    Choosing which directory to move by version number or path overlap alone
    would be a guess. A copy is called current only when all of its verifiable
    RECORD hashes match the files on disk and every other copy has a mismatch.
    """
    lines = [
        "Two sets of records exist for the same package, so this environment",
        "cannot be updated safely -- there is no way to tell which copy an",
        "update is meant to replace.",
        "",
        "This is commonly left by an upgrade that did not finish cleaning up.",
        "The updater verifies RECORD hashes before identifying a stale copy.",
        "",
    ]
    removable = []
    for name, items in sorted(duplicates.items()):
        lines.append(f"  {name}:")
        evidence = {}
        for item in items:
            path = item.get("metadata_path") or ""
            found = record_evidence(path) if path else None
            if found is not None:
                evidence[path] = found
        current = [
            path
            for path, found in evidence.items()
            if found["matched"] > 0 and found["changed"] == 0 and found["missing"] == 0
        ]
        stale = [
            path
            for path, found in evidence.items()
            if found["changed"] > 0 or found["missing"] > 0
        ]
        decided = (
            len(evidence) == len(items)
            and len(current) == 1
            and len(stale) == len(items) - 1
        )
        if not decided:
            lines += [
                f"    {item['metadata_path']}"
                for item in sorted(
                    items, key=lambda row: row.get("metadata_path") or ""
                )
                if item.get("metadata_path")
            ]
            lines.append("    RECORD hashes do not identify one current copy, so")
            lines.append(
                "    moving either one could break the package. Check by hand."
            )
            continue
        current_path = current[0]
        lines.append(f"    {current_path}  (all RECORD hashes match)")
        current_claims = evidence[current_path]["claims"]
        for path in sorted(stale):
            found = evidence[path]
            problems = found["changed"] + found["missing"]
            problem_label = count_label(problems, "RECORD hash", "RECORD hashes")
            verb = "differs" if problems == 1 else "differ"
            lines.append(f"    {path}  (stale: {problem_label} {verb})")
            old_only = len(found["claims"] - current_claims)
            if old_only:
                lines.append(
                    f"      It also lists {count_label(old_only, 'file')} that the"
                )
                lines.append(
                    "      current records do not claim. Moving this metadata does"
                )
                lines.append("      not delete those files.")
            removable.append(path)
    if removable:
        lines += [
            "",
            "Move the stale record directories aside, then run this command again:",
            "",
        ]
        for path in removable:
            destination = path + ".pip-updater-stale"
            lines.append(
                "  " + shlex.join(["mv", "-T", "--no-clobber", "--", path, destination])
            )
        lines += [
            "",
            "This is recoverable: move a .pip-updater-stale directory back to",
            "its original name if you need to undo it.",
        ]
    return "\n".join(lines)


def _metadata_name(metadata_path):
    """Read a distribution Name field without importing the distribution."""
    try:
        with open(metadata_path, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.lower().startswith("name:"):
                    return line.split(":", 1)[1].strip()
                if not line.strip():
                    break
    except OSError:
        return None
    return None


def load_conda_ownership(prefix):
    """Return conda-owned distribution names, files, and record fingerprint.

    Distribution ownership comes from dist-info files in conda records rather
    than conda package names.  This correctly maps ``python-librt`` to the
    ``librt`` Python distribution and does not confuse the system ``tzdata``
    package with PyPI's unrelated same-named distribution.
    """
    prefix_path = Path(prefix).resolve(strict=False)
    meta_dir = prefix_path / "conda-meta"
    if not meta_dir.is_dir():
        raise UpdaterError(
            f"{prefix} is not a conda environment (conda-meta is missing)."
        )

    owned_paths = set()
    distribution_names = set()
    digest = hashlib.sha256()
    for record_path in sorted(meta_dir.glob("*.json")):
        try:
            raw = record_path.read_bytes()
            record = json.loads(raw)
        except (OSError, json.JSONDecodeError) as exc:
            raise UpdaterError(f"Invalid conda record {record_path}: {exc}") from exc
        digest.update(record_path.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(raw)
        for raw_path in record.get("files", []):
            if not isinstance(raw_path, str):
                continue
            posix_path = PurePosixPath(raw_path)
            if posix_path.is_absolute() or ".." in posix_path.parts:
                raise UpdaterError(
                    f"Unsafe path in conda record {record_path}: {raw_path}"
                )
            normalized_path = posix_path.as_posix()
            owned_paths.add(normalized_path)
            lower = normalized_path.lower()
            if lower.endswith((".dist-info/metadata", ".egg-info/pkg-info")):
                name = _metadata_name(prefix_path / Path(*posix_path.parts))
                if not name:
                    directory = posix_path.parent.name
                    stem = re.sub(
                        r"\.(dist|egg)-info$", "", directory, flags=re.IGNORECASE
                    )
                    name = re.split(r"-(?=\d)", stem, maxsplit=1)[0]
                if name:
                    distribution_names.add(canonicalize_name(name))
    return {
        "distributions": distribution_names,
        "paths": owned_paths,
        "records_digest": digest.hexdigest(),
    }


def filter_outdated_packages(packages, inventory, conda_ownership, prefix):
    """Split pip's outdated list into eligible and excluded distributions."""
    inventory_by_name = index_inventory(inventory)
    holds = get_cached_holds(prefix)
    eligible = []
    excluded = []
    for package in packages:
        if not isinstance(package, dict) or not package.get("name"):
            continue
        name = str(package["name"])
        normalized = canonicalize_name(name)
        installed = inventory_by_name.get(normalized)
        reason = None
        if normalized in PROTECTED_BOOTSTRAP_PACKAGES:
            reason = "bootstrap tooling is protected"
        elif normalized in conda_ownership["distributions"]:
            reason = "owned by conda"
        elif installed is None:
            reason = "installed metadata is missing"
        elif installed.get("installer") != "pip":
            reason = f"installer is {installed.get('installer') or 'unknown'}"
        elif not _is_within(installed.get("metadata_path", ""), prefix):
            reason = "outside the selected environment"
        elif installed.get("direct_url"):
            reason = "editable/direct-URL installs are not reproducible"
        elif not SAFE_PROJECT_NAME.fullmatch(name):
            reason = "invalid or unsafe project name"
        else:
            reason = _still_valid_hold(package, holds.get(normalized), inventory_by_name)

        if reason:
            excluded.append((name, reason))
            continue
        eligible.append(
            {
                "name": name,
                "version": str(package.get("version", "?")),
                "latest_version": str(package.get("latest_version", "?")),
            }
        )
    eligible.sort(key=lambda package: package["name"].lower())
    return eligible, excluded


def _still_valid_hold(package, hold, inventory_by_name):
    """Return an exclusion reason if a recorded resolver hold still applies.

    A hold is trusted only while nothing that produced it has moved: the held
    package's newest release is unchanged and every capping package is still
    installed at the recorded version.  Anything else returns None so the
    package is offered again and the resolver retests it for real.
    """
    if not isinstance(hold, dict):
        return None
    cappers = hold.get("cappers")
    if not isinstance(cappers, dict) or not cappers:
        return None
    if hold.get("latest") != str(package.get("latest_version", "?")):
        return None
    for capper_name, capper_version in cappers.items():
        row = inventory_by_name.get(canonicalize_name(str(capper_name))) or {}
        if str(row.get("version") or "") != str(capper_version):
            return None
    return "held back by " + ", ".join(sorted(cappers))


def scan_outdated_packages(prefix, *, report_exclusions=False, progress=None):
    """Scan reproducibly pip-owned packages with live, truthful telemetry."""
    progress = progress or PackageScanProgress()
    success = False
    eligible = []
    excluded = []
    try:
        progress.set_phase("Reading installed package metadata")
        progress.tick()
        inventory = get_environment_inventory(prefix)
        progress.set_scope(len(inventory))
        progress.set_phase("Querying configured package indexes")
        progress.tick()
        result = stream_command(
            pip_command(prefix)
            + [
                "list",
                "--outdated",
                "--format=json",
                "--disable-pip-version-check",
            ],
            timeout=300,
            merge_stderr=False,
            on_start=progress.watch,
            on_tick=progress.tick,
        )
        if result.returncode != 0:
            raise command_failure(f"Checking outdated packages in {prefix}", result)
        packages = parse_json_output(
            result.stdout, f"checking outdated packages in {prefix}"
        )
        if not isinstance(packages, list):
            raise UpdaterError(
                f"Outdated package response for {prefix} was not a list."
            )
        progress.set_phase("Checking package ownership and safety")
        progress.tick()
        ownership = load_conda_ownership(prefix)
        eligible, excluded = filter_outdated_packages(
            packages, inventory, ownership, prefix
        )
        progress.set_found(len(eligible))
        success = True
    finally:
        progress.finish(success)
    if report_exclusions and excluded:
        print_excluded_packages(excluded)
    return eligible


def print_excluded_packages(excluded):
    """Explain intentionally skipped packages without treating them as errors."""
    conda_managed = sorted(
        name for name, reason in excluded if reason == "owned by conda"
    )
    protected = sorted(
        name for name, reason in excluded if reason == "bootstrap tooling is protected"
    )
    held = sorted(
        name for name, reason in excluded if reason.startswith("held back by")
    )
    other = sorted(
        (
            (name, reason)
            for name, reason in excluded
            if reason not in {"owned by conda", "bootstrap tooling is protected"}
            and not reason.startswith("held back by")
        ),
        key=lambda item: item[0].lower(),
    )

    print(f"\nSkipped automatically ({len(excluded)}) — no action is needed:")
    if conda_managed:
        print(
            "  Conda-managed: "
            + ", ".join(conda_managed)
            + " (pip must not replace these)"
        )
    if protected:
        print(
            "  Core update tools: "
            + ", ".join(protected)
            + " (protected so the updater cannot break itself)"
        )
    if held:
        print(
            "  Version-capped: "
            + ", ".join(held)
            + " (an installed package pins each of these; they will be offered "
            "again once the capping package updates)"
        )
    for name, reason in other:
        print(f"  {name}: skipped for safety ({reason})")


def get_outdated_packages(env_key, prefix, *, refresh=False):
    """Get eligible outdated packages, using cache unless refresh=True."""
    if not refresh:
        cached = get_cached_packages(env_key)
        if cached is not None:
            return cached, True

    packages = scan_outdated_packages(prefix, report_exclusions=True)
    set_cached_packages(env_key, packages)
    return packages, False


def package_signature(packages):
    """Build a stable signature for comparing package lists."""
    return sorted(
        (
            str(pkg.get("name", "")).lower(),
            str(pkg.get("version", "")),
            str(pkg.get("latest_version", "")),
        )
        for pkg in packages
        if isinstance(pkg, dict)
    )


def refresh_packages_background(env_key, prefix, package_state, progress):
    """Background refresh: rescan env, update cache, and mark if list changed."""
    try:
        fresh_packages = scan_outdated_packages(prefix, progress=progress)
    except Exception as exc:  # noqa: BLE001 - thread boundary must always publish failure state.
        with package_state["lock"]:
            package_state["scan_in_progress"] = False
            package_state["scan_done"] = True
            package_state["scan_error"] = str(exc) or exc.__class__.__name__
        return

    set_cached_packages(env_key, fresh_packages)

    with package_state["lock"]:
        old_signature = package_signature(package_state["packages"])
        new_signature = package_signature(fresh_packages)
        package_state["packages"] = fresh_packages
        package_state["scan_in_progress"] = False
        package_state["scan_done"] = True
        package_state["scan_error"] = None
        package_state["cache_mismatch"] = old_signature != new_signature


def wait_for_background_scan(thread, progress, stream=None):
    """Join a live refresh without ever leaving the terminal on a static line."""
    if thread is None or not thread.is_alive():
        return False
    stream = stream if stream is not None else sys.stdout
    progress.stream = stream
    progress.interactive = bool(getattr(stream, "isatty", lambda: False)())
    print("\nFinishing the live package scan...", file=stream, flush=True)
    while thread.is_alive():
        progress.paint()
        thread.join(timeout=PackageScanProgress.REFRESH_INTERVAL)
    progress.paint(force=True)
    progress.end_display()
    return True


def interactive_select(stdscr, package_state, allow_back=False):
    """Curses package selector that can live-refresh when background scan completes."""
    curses.curs_set(0)
    hint_attr = 0
    try:
        curses.use_default_colors()
        curses.init_pair(2, curses.COLOR_CYAN, -1)
        hint_attr = curses.color_pair(2)
    except curses.error:
        # Some terminals don't support colors; keep rendering without color attributes.
        hint_attr = 0

    stdscr.timeout(150)
    selected = set()
    cursor = 0
    scroll = 0
    while True:
        with package_state["lock"]:
            packages = list(package_state["packages"])
            scan_in_progress = package_state["scan_in_progress"]
            scan_done = package_state["scan_done"]
            scan_error = package_state["scan_error"]
            cache_mismatch = package_state["cache_mismatch"]
            from_cache = package_state["started_from_cache"]
            scan_progress = package_state.get("scan_progress")

        package_names_lower = {pkg["name"].lower() for pkg in packages}
        selected &= package_names_lower

        package_count = len(packages)
        confirm_idx = package_count + 1
        total = package_count + 2  # update all + packages + confirm
        cursor = min(cursor, total - 1)

        stdscr.clear()
        h, w = stdscr.getmaxyx()
        safe_w = max(1, w - 1)

        if scan_error:
            status = f" Live refresh failed: {scan_error}"
        elif scan_in_progress and scan_progress is not None:
            status = scan_progress.compact_status(safe_w)
        elif from_cache and scan_done and cache_mismatch:
            status = " Live scan updated this list (cache was stale)."
        elif from_cache and scan_done:
            status = " Live scan confirmed cached results."
        else:
            status = " "

        stdscr.addnstr(
            0,
            0,
            f" {package_count} package(s) eligible for update",
            safe_w,
            curses.A_BOLD,
        )
        help_line = " [SPACE] Toggle  [a] All  [n] None  [ENTER] Confirm"
        if allow_back:
            help_line += "  [b] Back"
        help_line += "  [q] Quit"
        stdscr.addnstr(1, 0, help_line, safe_w, hint_attr)
        stdscr.addnstr(2, 0, status.ljust(safe_w), safe_w, hint_attr)
        stdscr.addnstr(3, 0, "-" * safe_w, safe_w)

        list_top = 4
        # Reserve 2 rows at bottom: blank + confirm button
        visible = max(h - list_top - 2, 1)

        if cursor < scroll:
            scroll = cursor
        elif cursor >= scroll + visible:
            scroll = cursor - visible + 1

        all_selected = package_count > 0 and all(
            pkg["name"].lower() in selected for pkg in packages
        )

        for vi in range(visible):
            idx = scroll + vi
            if idx >= total:
                break
            row = list_top + vi

            if idx == 0:
                mark = "[x]" if all_selected else "[ ]"
                line = f"  {mark}  ** UPDATE ALL **"
            elif 1 <= idx <= package_count:
                pkg = packages[idx - 1]
                key = pkg["name"].lower()
                mark = "[x]" if key in selected else "[ ]"
                line = f"  {mark}  {pkg['name']:<40} {pkg['version']:>12} -> {pkg['latest_version']}"
            else:
                selected_count = sum(
                    1 for pkg in packages if pkg["name"].lower() in selected
                )
                line = f"  >>> CONFIRM ({selected_count} selected) <<<"

            attr = curses.A_REVERSE if idx == cursor else 0
            stdscr.addnstr(row, 0, line.ljust(safe_w), safe_w, attr)

        stdscr.refresh()
        key = stdscr.getch()
        if key == -1:
            continue

        if key == ord("q") or key == 27:
            return []
        elif allow_back and key == ord("b"):
            return BACK_TO_ENV
        elif key == curses.KEY_UP or key == ord("k"):
            cursor = max(0, cursor - 1)
        elif key == curses.KEY_DOWN or key == ord("j"):
            cursor = min(total - 1, cursor + 1)
        elif key == curses.KEY_HOME:
            cursor = 0
        elif key == curses.KEY_END:
            cursor = total - 1
        elif key == curses.KEY_PPAGE:
            cursor = max(0, cursor - visible)
        elif key == curses.KEY_NPAGE:
            cursor = min(total - 1, cursor + visible)
        elif key == ord(" "):
            if cursor == 0:
                if all_selected:
                    selected.clear()
                else:
                    selected = {pkg["name"].lower() for pkg in packages}
            elif 1 <= cursor <= package_count:
                pkg_key = packages[cursor - 1]["name"].lower()
                if pkg_key in selected:
                    selected.remove(pkg_key)
                else:
                    selected.add(pkg_key)
        elif key == ord("a"):
            selected = {pkg["name"].lower() for pkg in packages}
        elif key == ord("n"):
            selected.clear()
        elif key in (10, 13, curses.KEY_ENTER):
            if cursor == confirm_idx:
                return [
                    pkg["name"] for pkg in packages if pkg["name"].lower() in selected
                ]
            elif cursor == 0:
                if all_selected:
                    selected.clear()
                else:
                    selected = {pkg["name"].lower() for pkg in packages}
            elif 1 <= cursor <= package_count:
                pkg_key = packages[cursor - 1]["name"].lower()
                if pkg_key in selected:
                    selected.remove(pkg_key)
                else:
                    selected.add(pkg_key)


def interactive_select_env(stdscr, env_names):
    """Curses-based selector for conda environment names."""
    curses.curs_set(0)
    hint_attr = 0
    try:
        curses.use_default_colors()
        curses.init_pair(2, curses.COLOR_CYAN, -1)
        hint_attr = curses.color_pair(2)
    except curses.error:
        hint_attr = 0

    cursor = 0
    scroll = 0

    while True:
        stdscr.clear()
        h, w = stdscr.getmaxyx()
        safe_w = max(1, w - 1)

        stdscr.addnstr(0, 0, " Select a conda environment", safe_w, curses.A_BOLD)
        stdscr.addnstr(
            1, 0, " [UP/DOWN] Move  [ENTER] Select  [q] Quit", safe_w, hint_attr
        )
        stdscr.addnstr(2, 0, "-" * safe_w, safe_w)

        list_top = 3
        visible = max(h - list_top, 1)

        total = len(env_names)
        if cursor < scroll:
            scroll = cursor
        elif cursor >= scroll + visible:
            scroll = cursor - visible + 1

        for vi in range(visible):
            idx = scroll + vi
            if idx >= total:
                break
            row = list_top + vi
            line = f"  {env_names[idx]}"
            attr = curses.A_REVERSE if idx == cursor else 0
            stdscr.addnstr(row, 0, line.ljust(safe_w), safe_w, attr)

        stdscr.refresh()
        key = stdscr.getch()

        if key in (ord("q"), 27):
            return None
        if key in (curses.KEY_UP, ord("k")):
            cursor = max(0, cursor - 1)
        elif key in (curses.KEY_DOWN, ord("j")):
            cursor = min(total - 1, cursor + 1)
        elif key in (curses.KEY_HOME,):
            cursor = 0
        elif key in (curses.KEY_END,):
            cursor = total - 1
        elif key in (curses.KEY_PPAGE,):
            cursor = max(0, cursor - visible)
        elif key in (curses.KEY_NPAGE,):
            cursor = min(total - 1, cursor + visible)
        elif key in (10, 13, curses.KEY_ENTER):
            return env_names[cursor]


def get_known_environments():
    """Return display-name-to-prefix mapping and Conda's root prefix."""
    conda = conda_executable()
    info_result = run_command(
        [conda, "info", "--json"], capture_output=True, timeout=60
    )
    if info_result.returncode != 0:
        raise command_failure("Reading conda information", info_result)
    info = parse_json_output(info_result.stdout, "reading conda information")
    raw_root_prefix = info.get("root_prefix") or info.get("default_prefix")
    if not raw_root_prefix:
        raise UpdaterError("Conda did not report a root prefix.")
    root_prefix = str(Path(raw_root_prefix).resolve())

    list_result = run_command(
        [conda, "env", "list", "--json"], capture_output=True, timeout=60
    )
    if list_result.returncode != 0:
        raise command_failure("Listing conda environments", list_result)
    env_paths = parse_json_output(list_result.stdout, "listing conda environments").get(
        "envs", []
    )

    resolved = []
    for raw_path in env_paths:
        if not raw_path:
            continue
        prefix = str(Path(raw_path).resolve())
        if prefix not in resolved:
            resolved.append(prefix)
    if root_prefix not in resolved:
        resolved.append(root_prefix)

    basename_counts = {}
    for prefix in resolved:
        if prefix == root_prefix:
            continue
        name = Path(prefix).name
        basename_counts[name] = basename_counts.get(name, 0) + 1

    # "base" is reserved for Conda's root prefix, and a basename shared by
    # several registered environments is ambiguous.  In both cases the short
    # name is withheld so selection can only happen through the exact prefix;
    # the previous behaviour silently gave the short name to whichever
    # environment Conda happened to list first.
    labels = {"base": root_prefix}
    for prefix in resolved:
        if prefix == root_prefix:
            continue
        name = Path(prefix).name
        if name == "base" or basename_counts[name] > 1:
            labels[prefix] = prefix
        else:
            labels[name] = prefix
    return labels, root_prefix


def activate_environment(prefix, root_prefix):
    """Activate a target through Conda's hook and adopt its environment.

    Activation normally changes the calling shell, which a child Python process
    cannot do. A clean Bash child instead sources Conda's own hook, activates the
    exact prefix, and returns the resulting environment. Adopting that environment
    gives this updater and all of its children normal Conda activation semantics
    without changing the user's parent shell.
    """
    prefix = str(Path(prefix).resolve())
    root = Path(root_prefix).resolve()
    conda_hook = root / "etc" / "profile.d" / "conda.sh"
    if not conda_hook.is_file() or not _is_within(conda_hook, root):
        raise UpdaterError(f"Conda activation hook was not found at {conda_hook}.")

    startup_path = PROCESS_START_ENVIRONMENT.get("PATH", os.defpath)
    bash = shutil.which("bash", path=startup_path)
    if not bash:
        raise UpdaterError(
            "Bash is required to activate the selected Conda environment."
        )

    target_python = environment_python(prefix)
    environment_helper = (
        "import json,os; "
        "print(json.dumps(dict(os.environ),ensure_ascii=True,separators=(',',':')))"
    )
    activation_script = 'source "$1" && conda activate "$2" && exec "$3" -I -c "$4"'
    result = run_command(
        [
            bash,
            "-c",
            activation_script,
            "pip-updater-activation",
            str(conda_hook),
            prefix,
            target_python,
            environment_helper,
        ],
        capture_output=True,
        timeout=60,
        env=PROCESS_START_ENVIRONMENT,
    )
    if result.returncode != 0:
        raise command_failure(f"Activating Conda environment {prefix}", result)

    activated = parse_json_output(
        result.stdout, f"activating Conda environment {prefix}"
    )
    if not isinstance(activated, dict) or not all(
        isinstance(key, str) and isinstance(value, str)
        for key, value in activated.items()
    ):
        raise UpdaterError(
            f"Conda activation for {prefix} returned an invalid environment."
        )

    activated_prefix = activated.get("CONDA_PREFIX")
    if not activated_prefix or str(Path(activated_prefix).resolve()) != prefix:
        raise UpdaterError(
            f"Conda activated {activated_prefix or '<nothing>'} instead of {prefix}."
        )
    activated_python = shutil.which("python", path=activated.get("PATH", ""))
    if (
        not activated_python
        or Path(activated_python).resolve() != Path(target_python).resolve()
    ):
        raise UpdaterError(
            f"Conda activation for {prefix} did not select its Python interpreter."
        )

    os.environ.clear()
    os.environ.update(activated)
    print(
        f"[OK] Activated Conda environment '{Path(prefix).name}'.",
        flush=True,
    )


def resolve_environment(requested, environments):
    """Resolve an environment name or exact prefix without basename ambiguity."""
    if requested in environments:
        return requested, environments[requested]
    if requested:
        resolved = str(Path(requested).expanduser().resolve())
        matches = [
            (name, prefix)
            for name, prefix in environments.items()
            if prefix == resolved
        ]
        if len(matches) == 1:
            return matches[0]
    available = ", ".join(sorted(environments))
    raise UpdaterError(
        f"Conda environment '{requested}' was not found. Available: {available}"
    )


def doctor_snapshot(prefix):
    """Return a normalized Conda health report for mutation-sensitive checks."""
    result = run_command(
        [
            conda_executable(),
            "doctor",
            "-p",
            str(prefix),
            "altered-files",
            "missing-files",
            "consistency",
        ],
        capture_output=True,
        timeout=300,
    )
    if result.returncode != 0:
        raise command_failure(f"Running conda doctor for {prefix}", result)
    lines = []
    for line in result.stdout.splitlines():
        if line.startswith("Environment Health Report for:"):
            lines.append("Environment Health Report")
        else:
            lines.append(line.rstrip())
    return "\n".join(lines).strip()


PIP_CONFLICT_PATTERN = re.compile(
    r"^(?P<holder>\S+) (?P<holder_version>\S+) has requirement (?P<requirement>\S+), "
    # The version is non-greedy so the sentence-ending period is not absorbed.
    r"but you have (?P<installed>\S+) (?P<installed_version>\S+?)\.?$"
)


def pip_check_report(prefix):
    """Return the set of currently broken pip requirements.

    This reports instead of raising.  A pre-existing version conflict between
    two pip packages is exactly the problem this updater exists to repair, so
    refusing to start on one would make the tool useless precisely when it is
    needed.  Callers compare against a recorded baseline so the updater can
    still guarantee it never makes dependency health worse.
    """
    result = run_command(
        pip_command(prefix) + ["check", "--disable-pip-version-check"],
        capture_output=True,
        timeout=300,
    )
    if result.returncode == 0:
        return set()
    conflicts = {
        line.strip()
        for line in (result.stdout or "").splitlines()
        if line.strip() and not line.strip().lower().startswith("no broken")
    }
    if not conflicts:
        # A non-zero exit with nothing parseable is a real tool failure.
        raise command_failure(f"Checking installed packages in {prefix}", result)
    return conflicts


def describe_pip_conflict(line):
    """Rewrite one raw `pip check` line into plain language."""
    match = PIP_CONFLICT_PATTERN.match(line.strip())
    if not match:
        return line.strip()
    return (
        f"{match['holder']} {match['holder_version']} needs "
        f"{match['requirement']}, but {match['installed']} "
        f"{match['installed_version']} is installed"
    )


def print_existing_conflicts(conflicts):
    """Explain pre-existing dependency conflicts without blocking the run."""
    print(
        f"\n[!] {count_label(len(conflicts), 'package conflict')} already existed "
        "here before the updater started:"
    )
    for line in sorted(conflicts):
        print(f"      {describe_pip_conflict(line)}")
    print("\n    This is not something the updater did, and it is not fatal.")
    print("    Updating these packages is often what repairs it.")
    print("    If an update introduces any *new* conflict, it is undone automatically.")


def print_conda_inconsistencies(issues):
    """Report Conda's dependency complaints without stopping the run."""
    if not issues:
        return
    total = sum(len(found) for found in issues.values())
    print(
        f"\n[!] Conda reports "
        f"{count_label(total, 'dependency mismatch', 'dependency mismatches')} "
        "in this environment:"
    )
    for package in sorted(issues):
        for sentence in issues[package]:
            print(
                textwrap.fill(
                    sentence,
                    width=74,
                    initial_indent="      ",
                    subsequent_indent="        ",
                    break_on_hyphens=False,
                    break_long_words=False,
                )
            )
    print("\n    Nothing is damaged: every Conda file is present and unaltered.")
    print("    This is about Conda's records, not your packages, and it is not")
    print("    fatal. Any change that makes it worse is undone automatically.")


def damaged_conda_packages(lines):
    """Extract conda package names from a doctor report's problem lines."""
    names = []
    for raw_line in lines:
        line = raw_line.strip()
        head, separator, count = line.rpartition(":")
        if not separator or not count.strip().isdigit():
            continue
        # "wheel-0.47.0-py313h06a4308_0: 6" -> "wheel"
        parts = head.strip().rsplit("-", 2)
        name = parts[0] if len(parts) == 3 else head.strip()
        if name and name not in names:
            names.append(name)
    return names


# Every check `conda doctor` runs prints one headline containing its own
# subject word, so the word identifies which check spoke.
DOCTOR_CHECK_KEYWORDS = (
    ("altered", "altered-files"),
    ("missing", "missing-files"),
    ("consistent", "consistency"),
)


def doctor_sections(snapshot):
    """Split a `conda doctor` report into one entry per check it ran.

    Which check failed decides everything that follows, and the checks are not
    interchangeable: altered or missing files mean Conda's own files are
    already damaged and only Conda can put them back, while an inconsistency is
    a statement about dependency metadata with no damaged file anywhere.
    Treating any cross in the report as file damage reports the second as the
    first, which is simply untrue and sends the reader after the wrong repair.
    """
    sections = []
    for raw_line in snapshot.splitlines():
        line = raw_line.strip()
        if line.startswith(("✅", "❌")):
            kind = next(
                (k for word, k in DOCTOR_CHECK_KEYWORDS if word in line.lower()), None
            )
            sections.append(
                {"failed": line.startswith("❌"), "kind": kind, "detail": []}
            )
        elif sections and line:
            sections[-1]["detail"].append(line)
    return sections


def parse_consistency_detail(text):
    """Read the verbose consistency report into per-package complaints.

    The report is a small two-level listing: a package name, then the
    requirements it is missing or that are met by the wrong version.  Anything
    outside that shape is skipped rather than guessed at, so an unfamiliar
    report yields nothing and the caller falls back to Conda's own words.
    """
    issues = {}
    package = None
    bucket = None
    expected = None
    for raw_line in text.splitlines():
        body = raw_line.strip()
        if not body or body.startswith(("✅", "❌", "Environment Health")):
            continue
        indent = len(raw_line) - len(raw_line.lstrip())
        if indent == 0:
            package = body[:-1] if body.endswith(":") else None
            bucket = None
            if package:
                issues.setdefault(package, [])
        elif package is None:
            continue
        elif body.endswith(":") and not body.startswith("- "):
            bucket = body[:-1]
        elif body.startswith("- ") and bucket == "missing":
            issues[package].append({"kind": "missing", "spec": body[2:]})
        elif body.startswith("- expected:"):
            expected = body.split(":", 1)[1].strip()
        elif body.startswith("installed:") and expected:
            issues[package].append(
                {
                    "kind": "inconsistent",
                    "spec": expected,
                    "installed": body.split(":", 1)[1].strip(),
                }
            )
            expected = None
    return {name: found for name, found in issues.items() if found}


def describe_consistency_issue(package, issue, installed):
    """Turn one Conda dependency complaint into a sentence."""
    if issue["kind"] == "inconsistent":
        return f"{package} needs {issue['spec']}, but {issue['installed']} is installed"
    name = canonicalize_name(re.split(r"[\s\[<>=!~;(]", issue["spec"], maxsplit=1)[0])
    version = installed.get(name)
    if version:
        # Conda only sees what Conda installed, so a requirement satisfied by
        # pip reads to it as absent.  Saying so is the difference between a
        # description of a normal environment and a false alarm.
        return (
            f"{package} needs {issue['spec']}, which Conda did not install "
            f"({name} {version} is here, installed by pip itself)"
        )
    return f"{package} needs {issue['spec']}, which is not installed at all"


def conda_consistency_issues(prefix):
    """Name the packages behind a bare "the environment is not consistent".

    The summary report states only that it is inconsistent, which names nobody
    and leaves nothing to act on.  The verbose form lists every package and
    what it wants, and costs well under a second because it reads metadata and
    hashes no files.
    """
    result = run_command(
        [conda_executable(), "doctor", "-p", str(prefix), "consistency", "--verbose"],
        capture_output=True,
        timeout=300,
    )
    if result.returncode != 0:
        raise command_failure(f"Reading dependency details for {prefix}", result)
    issues = parse_consistency_detail(result.stdout)
    if not issues:
        return {}
    installed = {}
    with contextlib.suppress(UpdaterError, OSError):
        installed = {
            canonicalize_name(row["name"]): row["version"]
            for row in get_environment_inventory(prefix)
            if row.get("name")
        }
    return {
        package: [
            describe_consistency_issue(package, issue, installed) for issue in found
        ]
        for package, found in issues.items()
    }


def explain_conda_file_damage(prefix, sections, snapshot):
    """Explain that Conda's own files are damaged, naming the packages."""
    damaged = []
    for section in sections:
        for name in damaged_conda_packages(section["detail"]):
            if name not in damaged:
                damaged.append(name)
    lines = [
        (
            "Conda reports altered or missing files in "
            f"{', '.join(damaged) or 'one or more packages'}."
        ),
        "",
        "Conda installed these packages, so Conda must restore them. The",
        "updater stops here on purpose: if it ran now, any later problem could",
        "not be told apart from the damage that was already present.",
        "",
    ]
    if damaged:
        command = shlex.join(
            ["conda", "install", "-p", str(prefix), "--force-reinstall", *damaged]
        )
        lines += [
            "Affected Conda packages:",
            "",
            f"  {', '.join(damaged)}",
            "",
            "Repair them with Conda, then run this command again:",
            "",
            f"  {command}",
        ]
    else:
        # Never print a placeholder in place of a name: an instruction the
        # reader cannot run is worse than admitting the report was silent.
        lines += [
            "Conda's report did not name them. This command lists them:",
            "",
            f"  conda doctor -p {prefix} altered-files missing-files --verbose",
            "",
            "Reinstall each package it names with Conda, then run this again.",
        ]
    return "\n".join(lines) + "\n\nConda's full report:\n" + snapshot


def explain_unknown_doctor_report(snapshot):
    """Fail closed without inventing a diagnosis for unfamiliar Conda output."""
    return (
        "Conda returned a health report this updater could not interpret safely.\n\n"
        "No package names or repair commands are shown because the report does\n"
        "not provide enough verified information to identify the problem. Update\n"
        "Conda or inspect the full report below, then run this command again.\n\n"
        "Conda's full report:\n" + snapshot
    )


def preflight_health(prefix):
    """Snapshot dependency health and return the baseline mutation fingerprint."""
    snapshot = doctor_snapshot(prefix)
    sections = doctor_sections(snapshot)
    expected_checks = {"altered-files", "missing-files", "consistency"}
    reported_checks = {section["kind"] for section in sections}
    if reported_checks != expected_checks:
        raise UpdaterError(explain_unknown_doctor_report(snapshot))
    blocking = [
        section
        for section in sections
        if section["failed"] and section["kind"] in {"altered-files", "missing-files"}
    ]
    if blocking:
        raise UpdaterError(explain_conda_file_damage(prefix, blocking, snapshot))
    ownership = load_conda_ownership(prefix)
    inconsistent = any(
        section["failed"] and section["kind"] == "consistency" for section in sections
    )
    return {
        "doctor": snapshot,
        "conda_records_digest": ownership["records_digest"],
        # Recorded, not enforced, for the same reason as pip conflicts below: a
        # Conda inconsistency is a dependency statement, not file damage, and
        # refusing to start on one would strand environments that are working
        # perfectly well.  The guarantee is kept elsewhere -- postflight
        # compares this whole report and rolls back on any difference -- so the
        # updater still cannot make consistency worse.
        "conda_issues": conda_consistency_issues(prefix) if inconsistent else {},
        # Recorded, not enforced: postflight only fails on conflicts that are
        # new relative to this set.
        "pip_broken": sorted(pip_check_report(prefix)),
    }


def plan_signature(plan):
    """Return a stable signature for a resolved pip plan."""
    return sorted(
        (
            canonicalize_name(item["name"]),
            item.get("current_version"),
            item["version"],
            item["sha256"],
            bool(item["requested"]),
        )
        for item in plan
    )


def retained_environment_pins(inventory, targets):
    """Pin every distribution the plan retains at its exact installed version.

    pip's resolver only honors the requirements of distributions inside the
    requirement set it is given.  A package that is already at its newest
    version is never selected for an update, so without these pins its version
    caps are invisible while the plan is chosen, and the first check that can
    fail is `pip check` -- after the whole update has been installed.  Pinned
    to the exact installed version, a retained package resolves to the already
    installed distribution (nothing is downloaded, nothing changes) while its
    requirements constrain the joint resolution.  This also means the plan can
    never move a package the user did not select: where that is impossible,
    pip explains the conflict before anything is downloaded.
    """
    pins = []
    for normalized in sorted(set(inventory) - set(targets)):
        row = inventory[normalized]
        name = str(row.get("name") or "")
        version = str(row.get("version") or "")
        # A row that cannot be written as a `name==version` spec is left
        # unpinned; its requirements are still enforced by the post-install
        # `pip check` regression gate.
        if SAFE_PROJECT_NAME.fullmatch(name) and SAFE_VERSION.fullmatch(version):
            pins.append(f"{name}=={version}")
    return pins


def holdback_reasons(held, inventory, plan):
    """Name the requirements that reject each held-back package's newest release.

    The hold itself is already a fact established by the resolver; this only
    explains it.  When the `packaging` library is unavailable the holds are
    reported without naming the cap rather than re-implementing PEP 440.
    """
    try:
        from packaging.requirements import InvalidRequirement, Requirement
        from packaging.version import InvalidVersion, Version
    except ImportError:
        return {}

    planned = {canonicalize_name(item["name"]): item for item in plan}
    sources = []
    for normalized, row in inventory.items():
        chosen = planned.get(normalized, row)
        sources.append(
            (chosen.get("name"), chosen.get("version"), chosen.get("requires") or [])
        )
    for normalized, item in planned.items():
        if normalized not in inventory:
            sources.append((item["name"], item["version"], item.get("requires") or []))

    reasons = {}
    for normalized, (_, latest) in held.items():
        try:
            latest_version = Version(latest)
        except InvalidVersion:
            continue
        for capper_name, capper_version, requires in sources:
            for raw in requires:
                try:
                    requirement = Requirement(str(raw))
                except InvalidRequirement:
                    continue
                if canonicalize_name(requirement.name) != normalized:
                    continue
                if requirement.marker is not None:
                    # Extra-gated requirements do not constrain a base install,
                    # and markers here evaluate against the updater's own
                    # interpreter; skip anything not clearly applicable.
                    try:
                        if not requirement.marker.evaluate({"extra": ""}):
                            continue
                    except Exception:
                        continue
                if requirement.specifier and latest_version not in requirement.specifier:
                    reasons.setdefault(normalized, []).append(
                        {
                            "capper": str(capper_name),
                            "capper_version": str(capper_version),
                            "text": (
                                f"{capper_name} {capper_version} requires "
                                f"{requirement.name}{requirement.specifier}"
                            ),
                        }
                    )
    return reasons


def print_held_back(held, inventory, reasons):
    """Explain selected updates the resolver kept at their installed versions.

    A hold is not an error: the newest release of a selected package is
    rejected by a requirement of a package that is staying as it is, so the
    resolver keeps the installed version instead of breaking the environment.
    The cap is named so the user knows which package must release an update
    before the hold can lift.
    """
    print(
        f"[INFO] {count_label(len(held), 'selected package')} held back to stay "
        "compatible with packages not being updated:"
    )
    for normalized, (name, latest) in sorted(held.items()):
        installed = str((inventory.get(normalized) or {}).get("version") or "")
        line = (
            f"  {name} stays at {installed or 'its current version'}"
            f" instead of {latest}"
        )
        causes = [cause["text"] for cause in reasons.get(normalized, ())][:3]
        if causes:
            line += " (" + "; ".join(causes) + ")"
        print(line, flush=True)


def resolve_update_plan(prefix, names):
    """Resolve an update without mutation and enforce package ownership."""
    if not names:
        raise UpdaterError("No package names were selected.")
    for name in names:
        if not SAFE_PROJECT_NAME.fullmatch(name):
            raise UpdaterError(f"Unsafe project name in selection: {name!r}")

    inventory_rows = get_environment_inventory(prefix)
    inventory = index_inventory(inventory_rows)
    ownership = load_conda_ownership(prefix)
    for name in names:
        normalized = canonicalize_name(name)
        installed = inventory.get(normalized)
        if normalized in PROTECTED_BOOTSTRAP_PACKAGES:
            raise UpdaterError(
                f"Refusing to update protected bootstrap package {name}."
            )
        if normalized in ownership["distributions"]:
            raise UpdaterError(f"Refusing to update Conda-owned package {name}.")
        if not installed or installed.get("installer") != "pip":
            raise UpdaterError(f"{name} is not an unambiguous pip-owned distribution.")
        if not _is_within(installed.get("metadata_path", ""), prefix):
            raise UpdaterError(f"{name} is outside the selected environment.")
        if installed.get("direct_url"):
            raise UpdaterError(
                f"{name} is an editable/direct-URL install and cannot be reproduced."
            )

    progress = ResolverProgress(names)
    progress.phase = "Discovering compatible wheels"
    progress.tick()
    resolved = False
    with tempfile.TemporaryDirectory(prefix="pip-updater-resolver-") as raw_tmp:
        candidate_path = Path(raw_tmp) / "candidates.json"
        report_path = Path(raw_tmp) / "report.json"
        try:
            candidate_result = stream_command(
                pip_command(prefix)
                + [
                    "install",
                    "--dry-run",
                    "--report",
                    str(candidate_path),
                    "--upgrade",
                    "--no-deps",
                    "--only-binary=:all:",
                    "--disable-pip-version-check",
                ]
                + list(names),
                timeout=300,
                on_start=progress.watch,
                on_line=progress.note,
                on_tick=progress.tick,
            )
            if candidate_result.returncode != 0:
                raise command_failure(
                    f"Finding compatible wheels for {prefix}",
                    candidate_result,
                    max_lines=60,
                )
            try:
                raw_candidates = candidate_path.read_text(encoding="utf-8")
            except OSError as exc:
                raise UpdaterError(
                    "pip completed without writing its candidate report."
                ) from exc
            candidate_report = parse_json_output(
                raw_candidates, f"finding compatible wheels for {prefix}"
            )
            candidate_items = candidate_report.get("install", [])
            if not isinstance(candidate_items, list):
                raise UpdaterError(
                    "pip's candidate report did not contain an install list."
                )

            selected_names = {canonicalize_name(name) for name in names}
            targets = {}
            candidate_rows = []
            for item in candidate_items:
                metadata = item.get("metadata") or {}
                name = str(metadata.get("name") or "")
                version = str(metadata.get("version") or "")
                normalized = canonicalize_name(name)
                if (
                    normalized not in selected_names
                    or normalized in targets
                    or not SAFE_PROJECT_NAME.fullmatch(name)
                    or not version
                ):
                    raise UpdaterError(
                        "pip returned an invalid or unexpected compatible-wheel candidate."
                    )
                targets[normalized] = (name, version)
                candidate_rows.append({"requires": metadata.get("requires_dist") or []})

            depended = (
                depended_upon_packages(inventory_rows)
                | depended_upon_packages(candidate_rows)
            ) & set(targets)
            resolver_specs = [
                name if normalized in depended else f"{name}=={version}"
                for normalized, (name, version) in targets.items()
            ]
            if not resolver_specs:
                report = {"install": []}
                resolved = True
            else:
                resolver_specs.extend(retained_environment_pins(inventory, targets))
                progress.phase = "Resolving dependencies"
                result = stream_command(
                    pip_command(prefix)
                    + [
                        "install",
                        "--dry-run",
                        "--report",
                        str(report_path),
                        "--upgrade",
                        "--upgrade-strategy",
                        "only-if-needed",
                        "--only-binary=:all:",
                        "--disable-pip-version-check",
                    ]
                    + resolver_specs,
                    timeout=600,
                    on_start=progress.watch,
                    on_line=progress.note,
                    on_tick=progress.tick,
                )
                if result.returncode != 0:
                    raise command_failure(
                        f"Resolving updates for {prefix}", result, max_lines=60
                    )
                try:
                    raw_report = report_path.read_text(encoding="utf-8")
                except OSError as exc:
                    raise UpdaterError(
                        "pip completed without writing its resolver report."
                    ) from exc
                report = parse_json_output(
                    raw_report, f"resolving updates for {prefix}"
                )
                resolved = True
        finally:
            progress.finish(resolved)
    raw_plan = report.get("install", [])
    if not isinstance(raw_plan, list):
        raise UpdaterError("pip's install report did not contain an install list.")

    plan = []
    seen = set()
    for raw_item in raw_plan:
        metadata = raw_item.get("metadata") or {}
        name = str(metadata.get("name") or "")
        version = str(metadata.get("version") or "")
        normalized = canonicalize_name(name)
        if not name or not version or not SAFE_PROJECT_NAME.fullmatch(name):
            raise UpdaterError(
                "pip proposed an item with invalid name/version metadata."
            )
        if normalized in seen:
            raise UpdaterError(f"pip proposed {name} more than once.")
        seen.add(normalized)
        if normalized in PROTECTED_BOOTSTRAP_PACKAGES:
            raise UpdaterError(f"The update would modify protected package {name}.")
        if normalized in ownership["distributions"]:
            raise UpdaterError(
                f"The update would overwrite Conda-owned dependency {name} {version}."
            )

        installed = inventory.get(normalized)
        if installed:
            if installed.get("installer") != "pip" or not _is_within(
                installed.get("metadata_path", ""), prefix
            ):
                raise UpdaterError(f"The update would replace non-pip package {name}.")
            if installed.get("direct_url"):
                raise UpdaterError(
                    f"The update would replace direct-URL package {name}."
                )

        download = raw_item.get("download_info") or {}
        archive = download.get("archive_info") or {}
        hashes = archive.get("hashes") or {}
        sha256 = hashes.get("sha256")
        url = download.get("url")
        if (
            raw_item.get("is_direct")
            or download.get("vcs_info")
            or download.get("dir_info")
        ):
            raise UpdaterError(
                f"The update plan contains non-reproducible source {name}."
            )
        if raw_item.get("is_yanked"):
            raise UpdaterError(
                f"The update plan contains yanked release {name} {version}."
            )
        if not isinstance(sha256, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", sha256):
            raise UpdaterError(
                f"The update artifact for {name} lacks a SHA-256 digest."
            )
        filename = wheel_filename_from_url(url)

        plan.append(
            {
                "name": name,
                "current_version": installed.get("version") if installed else None,
                "version": version,
                "sha256": sha256.lower(),
                # Kept only in memory. Transaction journals store versions and
                # hashes, never private-index URLs that may contain credentials.
                "url": url,
                "filename": filename,
                "requested": bool(raw_item.get("requested")),
                "requires": list(metadata.get("requires_dist") or []),
            }
        )

    held = {
        normalized: candidate
        for normalized, candidate in targets.items()
        if normalized not in seen
    }
    reasons = holdback_reasons(held, inventory, plan) if held else {}
    cached_holds = get_cached_holds(prefix)
    records = {}
    for normalized, (name, latest) in held.items():
        cappers = {
            cause["capper"]: cause["capper_version"]
            for cause in reasons.get(normalized, ())
        }
        if cappers:
            records[normalized] = {
                "name": name,
                "installed": str(
                    (inventory.get(normalized) or {}).get("version") or ""
                ),
                "latest": latest,
                "cappers": cappers,
            }
    # A hold is announced when it is news; a hold identical to the recorded one
    # was already explained (and the scan normally filters it out earlier).
    # Holds whose cap pip saw but this explanation cannot name are never
    # recorded, so they stay visible and are retested on every run.
    fresh = {
        normalized: candidate
        for normalized, candidate in held.items()
        if normalized not in records
        or cached_holds.get(normalized) != records[normalized]
    }
    if fresh:
        print_held_back(fresh, inventory, reasons)
    merged = {
        normalized: record
        for normalized, record in cached_holds.items()
        if normalized not in targets and isinstance(record, dict)
    }
    merged.update(records)
    if merged != cached_holds:
        set_cached_holds(prefix, merged)
    return plan


def environment_layout(prefix):
    """Return target installation scheme paths for wheel collision checks."""
    helper = (
        "import json,sysconfig; "
        "print(json.dumps({k:sysconfig.get_paths()[k] for k in "
        "('purelib','platlib','scripts','data','include')}))"
    )
    result = run_command(
        [environment_python(prefix), "-I", "-c", helper],
        capture_output=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise command_failure(f"Reading Python installation paths in {prefix}", result)
    layout = parse_json_output(result.stdout, f"reading installation paths in {prefix}")
    for key, value in layout.items():
        if not _is_within(value, prefix) and key != "include":
            raise UpdaterError(
                f"Python's {key} path escapes the selected prefix: {value}"
            )
    return layout


def _safe_relative_target(prefix, base, relative):
    """Map an archive-relative path to a safe prefix-relative target."""
    relative_path = PurePosixPath(relative)
    if relative_path.is_absolute() or ".." in relative_path.parts:
        raise UpdaterError(f"Wheel contains unsafe path: {relative}")
    target = Path(base, *relative_path.parts).resolve(strict=False)
    try:
        return target.relative_to(Path(prefix).resolve(strict=False)).as_posix()
    except ValueError as exc:
        raise UpdaterError(
            f"Wheel target escapes the selected environment: {relative}"
        ) from exc


def generated_script_names(entry_points_text):
    """Return the script names pip generates from wheel entry point metadata.

    pip writes one launcher per ``console_scripts``/``gui_scripts`` entry into
    the environment's scripts directory and adds it to the installed RECORD.
    These files exist in no wheel archive, so ownership analysis that reads
    only the archive would believe an update deletes every generated script
    and never puts one back.
    """
    parser = configparser.RawConfigParser(strict=False, delimiters=("=",))
    parser.optionxform = str
    try:
        parser.read_string(entry_points_text)
    except configparser.Error:
        return []
    scripts = []
    for section in ("console_scripts", "gui_scripts"):
        if parser.has_section(section):
            scripts.extend(
                name.strip() for name in parser.options(section) if name.strip()
            )
    return scripts


def inspect_wheel(wheel_path, prefix, layout):
    """Read wheel identity, hash, and exact installation targets."""
    digest = hashlib.sha256()
    with open(wheel_path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)

    try:
        archive = zipfile.ZipFile(wheel_path)
    except (OSError, zipfile.BadZipFile) as exc:
        raise UpdaterError(f"Invalid wheel {wheel_path}: {exc}") from exc
    with archive:
        names = archive.namelist()
        # Anchor to the archive root: a wheel may legitimately ship a vendored
        # ``foo/bar.dist-info/METADATA`` as package data, which must not be
        # mistaken for the wheel's own identity.
        metadata_names = [
            name
            for name in names
            if name.lower().endswith(".dist-info/metadata") and name.count("/") == 1
        ]
        if len(metadata_names) != 1:
            raise UpdaterError(f"Wheel {wheel_path.name} has ambiguous METADATA.")
        metadata_text = archive.read(metadata_names[0]).decode(
            "utf-8", errors="replace"
        )
        project_name = None
        version = None
        for line in metadata_text.splitlines():
            if line.startswith("Name:"):
                project_name = line.split(":", 1)[1].strip()
            elif line.startswith("Version:"):
                version = line.split(":", 1)[1].strip()
            elif not line:
                break
        if not project_name or not version:
            raise UpdaterError(f"Wheel {wheel_path.name} lacks Name/Version metadata.")

        dist_info = PurePosixPath(metadata_names[0]).parent.as_posix()
        wheel_metadata = f"{dist_info}/WHEEL"
        if wheel_metadata not in names:
            raise UpdaterError(f"Wheel {wheel_path.name} lacks WHEEL metadata.")
        wheel_text = archive.read(wheel_metadata).decode("utf-8", errors="replace")
        pure = any(
            line.lower() == "root-is-purelib: true" for line in wheel_text.splitlines()
        )
        root_base = layout["purelib" if pure else "platlib"]
        targets = set()
        target_sources = {}
        for info in archive.infolist():
            if info.is_dir():
                continue
            file_type = (info.external_attr >> 16) & 0o170000
            if file_type == stat.S_IFLNK:
                raise UpdaterError(f"Wheel {wheel_path.name} contains a symbolic link.")
            member = PurePosixPath(info.filename)
            if member.is_absolute() or ".." in member.parts:
                raise UpdaterError(
                    f"Wheel {wheel_path.name} contains unsafe path {info.filename}."
                )
            parts = member.parts
            if parts and parts[0].lower().endswith(".data"):
                if len(parts) < 3:
                    raise UpdaterError(
                        f"Wheel {wheel_path.name} has malformed .data path."
                    )
                category = parts[1].lower()
                rest = PurePosixPath(*parts[2:]).as_posix()
                base_by_category = {
                    "purelib": layout["purelib"],
                    "platlib": layout["platlib"],
                    "scripts": layout["scripts"],
                    "data": layout["data"],
                    "headers": layout["include"],
                }
                if category not in base_by_category:
                    raise UpdaterError(
                        f"Wheel {wheel_path.name} uses unsupported .data category {category}."
                    )
                target = _safe_relative_target(prefix, base_by_category[category], rest)
            else:
                target = _safe_relative_target(prefix, root_base, member.as_posix())
            if target in target_sources:
                raise UpdaterError(
                    f"Wheel {wheel_path.name} maps multiple members to {target}."
                )
            target_sources[target] = info.filename
            targets.add(target)
        entry_points_name = f"{dist_info}/entry_points.txt"
        if entry_points_name in names:
            entry_points_text = archive.read(entry_points_name).decode(
                "utf-8", errors="replace"
            )
            for script in generated_script_names(entry_points_text):
                target = _safe_relative_target(prefix, layout["scripts"], script)
                # setdefault, not the duplicate check above: a generated script
                # may legitimately coincide with a packaged script of the same
                # name, and pip still writes exactly one file.
                target_sources.setdefault(target, entry_points_name)
                targets.add(target)
    return {
        "name": project_name,
        "version": version,
        "sha256": digest.hexdigest(),
        "path": str(wheel_path),
        "targets": targets,
    }


def inspect_wheelhouse(directory, prefix):
    """Index all downloaded wheels and reject unexpected artifacts."""
    layout = environment_layout(prefix)
    wheels = {}
    files = list(Path(directory).iterdir())
    unexpected = [path.name for path in files if not path.name.endswith(".whl")]
    if unexpected:
        raise UpdaterError(
            "Only binary wheels are allowed; found: " + ", ".join(unexpected)
        )
    for path in files:
        wheel = inspect_wheel(path, prefix, layout)
        normalized = canonicalize_name(wheel["name"])
        if normalized in wheels:
            raise UpdaterError(
                f"Wheelhouse contains multiple artifacts for {wheel['name']}."
            )
        wheels[normalized] = wheel
    return wheels


def installed_file_owners(prefix, inventory):
    """Map installed RECORD paths to owning Python distributions.

    Returns the first claimant of each path, the distributions that have a
    readable RECORD, and every path claimed by more than one distribution.
    Shared claims are reported rather than raised: legacy namespace packages
    legitimately overlap (every ``nvidia-*`` wheel ships ``nvidia/__init__.py``),
    so a pre-existing overlap must not make an unrelated package un-updatable.
    Whether an overlap is fatal is decided per transaction by the caller.
    """
    prefix_path = Path(prefix).resolve(strict=False)
    owners = {}
    shared_claims = {}
    distributions_with_records = set()
    for name, item in inventory.items():
        metadata_path = Path(item.get("metadata_path") or "")
        record_path = metadata_path / "RECORD"
        if not record_path.is_file() or not _is_within(record_path, prefix_path):
            continue
        distributions_with_records.add(name)
        try:
            with open(
                record_path, newline="", encoding="utf-8", errors="replace"
            ) as handle:
                rows = list(csv.reader(handle))
        except OSError as exc:
            raise UpdaterError(f"Could not read {record_path}: {exc}") from exc
        for row in rows:
            if not row or not row[0]:
                continue
            target = (metadata_path.parent / Path(row[0])).resolve(strict=False)
            try:
                relative = target.relative_to(prefix_path).as_posix()
            except ValueError as exc:
                raise UpdaterError(
                    f"Installed RECORD path escapes {prefix}: {row[0]}"
                ) from exc
            previous = owners.get(relative)
            if previous and previous != name:
                shared_claims.setdefault(relative, {previous}).add(name)
                continue
            owners[relative] = name
    return owners, distributions_with_records, shared_claims


def depended_upon_packages(rows):
    """Return every distribution named as a requirement by an installed one."""
    needed = set()
    for row in rows:
        for requirement in row.get("requires") or []:
            name = re.split(r"[\s\[<>=!~;(]", str(requirement), maxsplit=1)[0]
            if name:
                needed.add(canonicalize_name(name))
    return needed


def shared_file_report(prefix, plan):
    """Count files a planned package shares with a package staying as it is.

    The overlap is a property of the installed environment, not of the update,
    so it is surfaced while the user can still decline rather than raised as an
    error once the downloads have already run.  Requirement metadata is not
    used to recommend removals: absence from that metadata does not prove an
    application or user does not import a package directly.
    """
    planned = {canonicalize_name(item["name"]) for item in plan}
    rows = get_environment_inventory(prefix)
    inventory = index_inventory(rows)
    _, _, shared_claims = installed_file_owners(prefix, inventory)
    groups = {}
    for claimants in shared_claims.values():
        if not claimants & planned or claimants <= planned:
            continue
        key = frozenset(claimants)
        groups[key] = groups.get(key, 0) + 1
    return {"groups": groups}


def print_shared_file_warning(report):
    """Explain pre-existing file overlap in terms a non-expert can act on."""
    groups = report["groups"]
    if not groups:
        return
    total = sum(groups.values())
    print(f"\nSHARED FILES ({count_label(total, 'file')})")
    print("  These files are installed by two packages at once. Only one copy can")
    print("  exist on disk, so the package installed most recently is the one you")
    print("  currently have. That is already true today; updating does not cause it.")
    print()
    for claimants, count in sorted(
        groups.items(), key=lambda entry: (-entry[1], sorted(entry[0]))
    ):
        print(f"    {count_label(count, 'file')}: {' and '.join(sorted(claimants))}")
    print()
    print("  This warning does not prove either package is unused. The updater will")
    print("  inspect the exact new wheels before fetching rollback copies. Updating")
    print("  one side is allowed only when its new wheel puts every shared file back;")
    print("  otherwise the transaction stops before any package is changed.")
    print()
    print("  Do not uninstall either package solely because it appears in this list.")


def pip_cache_root(prefix):
    """Return pip's configured cache directory, or None when unavailable."""
    result = run_command(
        pip_command(prefix) + ["cache", "dir"],
        capture_output=True,
        timeout=30,
    )
    if result.returncode != 0:
        return None
    path = Path(result.stdout.strip())
    return path if path.is_dir() else None


def resolve_exact_download_artifacts(prefix, specs):
    """Ask pip for compatible URLs and hashes for exact rollback versions."""
    if not specs:
        return []
    expected = {}
    for spec in specs:
        name, separator, version = spec.partition("==")
        if separator != "==" or not SAFE_PROJECT_NAME.fullmatch(name) or not version:
            raise UpdaterError(f"Invalid exact rollback requirement: {spec!r}")
        normalized = canonicalize_name(name)
        if normalized in expected:
            raise UpdaterError(f"Duplicate rollback requirement: {name}")
        expected[normalized] = (name, version)

    with tempfile.TemporaryDirectory(prefix="pip-updater-rollback-resolver-") as tmp:
        report_path = Path(tmp) / "report.json"
        result = stream_command(
            pip_command(prefix)
            + [
                "install",
                "--dry-run",
                "--ignore-installed",
                "--no-deps",
                "--report",
                str(report_path),
                "--only-binary=:all:",
                "--disable-pip-version-check",
            ]
            + list(specs),
            timeout=300,
        )
        if result.returncode != 0:
            raise command_failure(
                "Locating exact rollback wheels", result, max_lines=60
            )
        try:
            report = parse_json_output(
                report_path.read_text(encoding="utf-8"),
                "locating exact rollback wheels",
            )
        except OSError as exc:
            raise UpdaterError(
                "pip completed without writing its rollback-wheel report."
            ) from exc

    raw_items = report.get("install", [])
    if not isinstance(raw_items, list):
        raise UpdaterError("pip's rollback-wheel report had no install list.")
    found = {}
    for raw_item in raw_items:
        metadata = raw_item.get("metadata") or {}
        name = str(metadata.get("name") or "")
        version = str(metadata.get("version") or "")
        normalized = canonicalize_name(name)
        if normalized not in expected or normalized in found:
            raise UpdaterError(
                "pip returned an invalid or unexpected rollback-wheel candidate."
            )
        expected_name, expected_version = expected[normalized]
        if version != expected_version:
            raise UpdaterError(
                f"pip selected {name} {version}, not rollback version "
                f"{expected_version}."
            )
        download = raw_item.get("download_info") or {}
        archive = download.get("archive_info") or {}
        sha256 = (archive.get("hashes") or {}).get("sha256")
        url = download.get("url")
        if (
            raw_item.get("is_direct")
            or raw_item.get("is_yanked")
            or download.get("vcs_info")
            or download.get("dir_info")
            or not isinstance(sha256, str)
            or not re.fullmatch(r"[0-9a-fA-F]{64}", sha256)
        ):
            raise UpdaterError(
                f"pip did not select a reproducible rollback wheel for {name}."
            )
        found[normalized] = {
            "name": expected_name,
            "version": version,
            "sha256": sha256.lower(),
            "url": url,
            "filename": wheel_filename_from_url(url),
        }
    if set(found) != set(expected):
        missing = ", ".join(
            expected[name][0] for name in expected.keys() - found.keys()
        )
        raise UpdaterError(f"pip did not locate rollback wheels for: {missing}")
    return [found[canonicalize_name(spec.split("==", 1)[0])] for spec in specs]


def cached_http_body(cache_root, url):
    """Locate pip's separate cached response body for an exact URL."""
    if cache_root is None:
        return None
    digest = hashlib.sha224(url.encode("utf-8")).hexdigest()
    relative = Path(*digest[:5]) / (digest + ".body")
    for cache_name in ("http-v2", "http"):
        candidate = cache_root / cache_name / relative
        if candidate.is_file():
            return candidate
    return None


def copy_verified_cache_body(body, target, expected_sha256):
    """Copy a pip HTTP-cache body only when it matches the resolver hash."""
    if body is None:
        return False
    temporary = target.parent / f".{target.name}.pip-updater-cache"
    digest = hashlib.sha256()
    try:
        with open(body, "rb") as source, open(temporary, "xb") as output:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        if digest.hexdigest() != expected_sha256:
            temporary.unlink()
            return False
        os.replace(temporary, target)
        return True
    except OSError:
        with contextlib.suppress(FileNotFoundError, OSError):
            temporary.unlink()
        return False


ARIA2_MAX_CONCURRENT_FILES = 4
ARIA2_CONNECTIONS_PER_FILE = 8


def download_with_aria2(artifacts, destination, progress):
    """Fetch cache misses with bounded file and HTTP-range parallelism."""
    aria2 = shutil.which("aria2c")
    if not aria2 or not artifacts:
        return False
    lines = []
    for item in artifacts:
        if urlsplit(item["url"]).scheme not in {"http", "https"}:
            return False
        lines += [
            item["url"],
            f"  out={item['filename']}",
            f"  checksum=sha-256={item['sha256']}",
        ]
    progress.network_downloads(
        len(artifacts),
        ARIA2_MAX_CONCURRENT_FILES,
        ARIA2_CONNECTIONS_PER_FILE,
    )
    result = stream_command(
        [
            aria2,
            "--input-file=-",
            f"--dir={destination}",
            f"--max-concurrent-downloads={ARIA2_MAX_CONCURRENT_FILES}",
            f"--split={ARIA2_CONNECTIONS_PER_FILE}",
            f"--max-connection-per-server={ARIA2_CONNECTIONS_PER_FILE}",
            "--min-split-size=1M",
            "--file-allocation=none",
            "--auto-file-renaming=false",
            "--allow-overwrite=false",
            "--check-integrity=true",
            "--max-tries=5",
            "--retry-wait=1",
            "--timeout=30",
            "--connect-timeout=15",
            "--console-log-level=warn",
            "--summary-interval=0",
            "--show-console-readout=false",
            "--download-result=hide",
        ],
        input_data="\n".join(lines) + "\n",
        timeout=1800,
        on_tick=progress.tick,
    )
    if result.returncode != 0:
        # Some private indexes reject ranged requests even though pip's normal
        # one-connection client works. Remove only this transaction's known
        # partial targets, then let the caller use the universal pip fallback.
        progress.parallel_failed()
        for item in artifacts:
            target = Path(destination) / item["filename"]
            for partial in (target, Path(str(target) + ".aria2")):
                with contextlib.suppress(FileNotFoundError, OSError):
                    partial.unlink()
        print(
            "  [INFO] Parallel transfer was unavailable; retrying these files "
            "with pip.",
            file=progress.stream,
            flush=True,
        )
        return False
    progress.parallel_finished()
    return True


def _download_with_pip(prefix, specs, destination, progress):
    """Use pip's compatible serial downloader as the universal fallback."""
    result = stream_command(
        pip_command(prefix)
        + [
            "download",
            "--only-binary=:all:",
            "--no-deps",
            "--no-input",
            "--disable-pip-version-check",
            "--dest",
            str(destination),
        ]
        + specs,
        timeout=1800,
        on_start=progress.watch,
        on_line=progress.note,
        on_tick=progress.tick,
    )
    if result.returncode != 0:
        raise command_failure("Downloading transaction wheels", result)


def download_exact_wheels(prefix, specs, destination, title=None, artifacts=None):
    """Download exact binary wheels before any environment mutation.

    These are the slowest steps in the whole run -- multi-gigabyte CUDA wheels
    are routine -- so the output is streamed and a progress line is kept alive.
    Without it the updater looks hung for minutes at the riskiest-looking moment.
    """
    if not specs:
        return
    progress = DownloadProgress(title or "Downloading", len(specs), destination)
    progress.tick()
    try:
        remaining_specs = list(specs)
        if artifacts and len(artifacts) == len(specs):
            by_name = {canonicalize_name(item["name"]): item for item in artifacts}
            filenames = [item.get("filename") for item in artifacts]
            if len(by_name) != len(artifacts) or len(set(filenames)) != len(filenames):
                raise UpdaterError(
                    "The resolved download set contains duplicate names or filenames."
                )
            ordered = []
            for spec in specs:
                item = by_name.get(canonicalize_name(spec.split("==", 1)[0]))
                if item is None:
                    break
                ordered.append(item)
            else:
                cache_root = pip_cache_root(prefix)
                cache_misses = []
                for item in ordered:
                    target = Path(destination) / item["filename"]
                    body = cached_http_body(cache_root, item["url"])
                    if copy_verified_cache_body(body, target, item["sha256"]):
                        progress.cache_hit(item["filename"])
                        progress.tick()
                    else:
                        cache_misses.append(item)
                missing_names = {
                    canonicalize_name(item["name"]) for item in cache_misses
                }
                remaining_specs = [
                    spec
                    for spec in specs
                    if canonicalize_name(spec.split("==", 1)[0]) in missing_names
                ]
                if not cache_misses or download_with_aria2(
                    cache_misses, destination, progress
                ):
                    remaining_specs = []
        if remaining_specs:
            _download_with_pip(prefix, remaining_specs, destination, progress)
    finally:
        progress.finish()


def explain_owner_collisions(prefix, collisions, plan=()):
    """Turn raw file-ownership collisions into something the user can act on.

    Reaching this point means an installed package that is staying put owns
    files the new wheel wants to write.  Rolling the update back could not
    restore them, because the older version of the updated package never
    shipped them, so the only safe outcome is to stop and let the user retire
    one of the two packages.
    """
    pip = shlex.join(pip_command(prefix))
    blockers = sorted({owner for _, owner in collisions})
    items = {canonicalize_name(item["name"]): item for item in plan}
    reverse_requirements = {}
    for item in plan:
        parent = canonicalize_name(item["name"])
        for requirement in item.get("requires") or []:
            requirement_text = str(requirement)
            _requirement, separator, marker = requirement_text.partition(";")
            # Wheel metadata lists requirements for every optional extra, but
            # pip's report does not identify which parent (if any) activated an
            # extra. An optional entry alone is therefore not evidence that the
            # selected package caused this dependency, and using it here would
            # implicate unrelated updates (for example diffusers -> phonemizer).
            if separator and re.search(r"\bextra\b", marker, re.IGNORECASE):
                continue
            dependency = re.split(r"[\s\[<>=!~;(]", requirement_text, maxsplit=1)[0]
            if dependency:
                reverse_requirements.setdefault(
                    canonicalize_name(dependency), set()
                ).add(parent)

    def selected_causes(name):
        causes = set()
        pending = [canonicalize_name(name)]
        seen = set(pending)
        while pending:
            dependency = pending.pop()
            for parent in reverse_requirements.get(dependency, ()):
                item = items.get(parent, {})
                if item.get("requested"):
                    causes.add(item.get("name", parent))
                elif parent not in seen:
                    seen.add(parent)
                    pending.append(parent)
        return causes

    lines = [
        "A new wheel and an installed package target the same files, so this",
        "update cannot run.",
        "",
    ]
    for (updating, owner), targets in sorted(collisions.items()):
        lines.append(
            f"  Updating {updating} would replace "
            f"{count_label(len(targets), 'file')} belonging to {owner},"
        )
        lines.append(f"  such as {min(targets)}.")
    introduced = sorted(
        {
            updating
            for updating, _ in collisions
            if "current_version" in items.get(canonicalize_name(updating), {})
            and items[canonicalize_name(updating)].get("current_version") is None
        }
    )
    skip_updates = set()
    for name in introduced:
        skip_updates.update(selected_causes(name))

    lines += [
        "",
        "The updater stopped before installation because uninstalling or rolling",
        "back either side could delete files still claimed by the other package.",
        "This collision is not proof that either installed package is unused, so",
        "the updater will not guess which one to remove.",
    ]
    if introduced:
        lines += [
            "",
            "The conflicting package is a new dependency in this plan:",
            "",
        ]
        lines += [f"  {name}" for name in introduced]
    if skip_updates:
        lines += [
            "",
            "Safest way to update everything else: run the selector again and",
            "leave these updates unchecked:",
            "",
        ]
        lines += [f"  {name}" for name in sorted(skip_updates)]
    lines += [
        "",
        "To investigate the installed owners without changing anything:",
        "",
    ]
    lines += [f"  {pip} show {name}" for name in blockers]
    lines += [
        "",
        "Do not uninstall one merely because it appears here. If both are needed,",
        "keep the conflicting update out of this environment or use a separate",
        "environment until the wheel owners no longer overlap.",
    ]
    return "\n".join(lines)


def validate_new_wheels(
    prefix, plan, new_wheels, inventory, ownership, *, require_complete=True
):
    """Require exact report artifacts and reject every file ownership collision.

    A partial check is used only for newly introduced dependencies before the
    large main download. Ownership decisions still use the complete plan, so a
    package already scheduled for replacement is not mistaken for a fixed
    external owner. The complete assembled wheelhouse is always checked again.
    """
    planned_names = {canonicalize_name(item["name"]) for item in plan}
    downloaded_names = set(new_wheels)
    invalid = downloaded_names - planned_names
    if invalid or (require_complete and downloaded_names != planned_names):
        missing = planned_names - set(new_wheels)
        extra = downloaded_names - planned_names
        raise UpdaterError(
            f"Downloaded wheel set differs from plan (missing={sorted(missing)}, extra={sorted(extra)})."
        )
    for item in plan:
        normalized = canonicalize_name(item["name"])
        if normalized not in new_wheels:
            continue
        wheel = new_wheels[normalized]
        if wheel["version"] != item["version"] or wheel["sha256"] != item["sha256"]:
            raise UpdaterError(
                f"Downloaded artifact for {item['name']} does not match the resolved report."
            )

    file_owners, with_records, shared_claims = installed_file_owners(prefix, inventory)
    for name in downloaded_names:
        if name in inventory and name not in with_records:
            raise UpdaterError(
                f"Cannot safely replace {name}: installed RECORD is missing."
            )
    for target, installed_owner in file_owners.items():
        claimants = shared_claims.get(target, {installed_owner})
        implicated = sorted(claimants & downloaded_names)
        if implicated and target in ownership["paths"]:
            raise UpdaterError(
                f"Installed pip RECORD for {implicated[0]} claims Conda-owned file {target}."
            )

    proposed_owners = {}
    collisions = {}
    prefix_path = Path(prefix).resolve(strict=False)
    for normalized, wheel in new_wheels.items():
        for target in wheel["targets"]:
            if target in ownership["paths"]:
                raise UpdaterError(
                    f"Wheel {wheel['name']} would overwrite Conda-owned file {target}."
                )
            installed_owner = file_owners.get(target)
            claimants = shared_claims.get(target) or (
                {installed_owner} if installed_owner else set()
            )
            # The wheel's own predecessor being a claimant makes this an
            # in-place replacement, not a takeover -- generated console
            # scripts especially are claimed by every distribution that
            # declares them, in whichever order RECORDs were read.
            if (
                claimants
                and normalized not in claimants
                and not claimants & planned_names
            ):
                # Gathered rather than raised one at a time: a single filename
                # says nothing, but the whole set names the two packages that
                # cannot both stay installed.
                for owner in sorted(claimants):
                    collisions.setdefault((wheel["name"], owner), []).append(target)
                continue
            previous = proposed_owners.get(target)
            if previous and previous != normalized and target not in shared_claims:
                raise UpdaterError(
                    f"Planned wheels {previous} and {normalized} both install {target}."
                )
            proposed_owners[target] = normalized
            target_path = prefix_path / Path(*PurePosixPath(target).parts)
            if (
                target_path.exists()
                and installed_owner not in planned_names
                and target not in shared_claims
            ):
                raise UpdaterError(
                    f"Wheel {wheel['name']} would overwrite unowned existing file {target}."
                )

    if collisions:
        raise UpdaterError(explain_owner_collisions(prefix, collisions, plan))

    # A path claimed by several installed distributions is already decided by
    # whichever wheel was written last; this transaction did not create that
    # ambiguity and refusing to run would strand the environment forever (the
    # NVIDIA cu12/cu13 wheels share one `nvidia/` namespace by design).  The one
    # outcome that is genuinely worse than the status quo is a shared file that
    # disappears: --force-reinstall removes every path the planned package's own
    # RECORD lists, so if no planned wheel ships it back, the other claimants
    # silently lose a file that nothing will restore.
    for target, claimants in sorted(shared_claims.items()):
        if target in proposed_owners or not claimants & downloaded_names:
            continue
        stranded = sorted(claimants - planned_names)
        if not stranded:
            continue
        updating = ", ".join(sorted(claimants & planned_names))
        raise UpdaterError(
            f"Updating {updating} would delete {target}, which "
            f"{', '.join(stranded)} also needs and no updated package puts back.\n"
            f"Update {', '.join(sorted(claimants))} together, or none of them."
        )


def _write_json_atomic(path, payload):
    """Atomically write a private transaction manifest."""
    path = Path(path)
    tmp = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix="manifest-",
            delete=False,
        ) as handle:
            tmp = Path(handle.name)
            os.fchmod(handle.fileno(), 0o600)
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
        # A transaction status change must survive power loss, otherwise
        # recovery cannot tell whether the environment was mutated.
        _fsync_directory(path.parent)
    finally:
        if tmp is not None:
            with contextlib.suppress(FileNotFoundError):
                tmp.unlink()


def transaction_root():
    """Return the private persistent transaction directory."""
    ensure_cache_root()
    return secure_directory(CACHE_ROOT / "transactions")


def _safe_remove_transaction(path):
    """Remove only a validated updater-owned transaction directory."""
    root = transaction_root().resolve()
    candidate = Path(path).resolve()
    if candidate.parent != root or not candidate.name.startswith("txn-"):
        raise UpdaterError(f"Refusing to remove unsafe transaction path {candidate}.")
    shutil.rmtree(candidate)


def lock_root():
    """Return the private directory holding per-environment lock files."""
    ensure_cache_root()
    return secure_directory(CACHE_ROOT / "locks")


def prune_stale_locks():
    """Delete lock files whose environment no longer exists.

    Lock names are digests, so each file records its prefix.  A lock is removed
    only when it can be taken exclusively, which proves no other updater holds
    it, and the recorded prefix is gone.
    """
    removed = 0
    for lock_path in lock_root().glob("*.lock"):
        try:
            with open(lock_path, "r+", encoding="utf-8") as handle:
                recorded = handle.read().strip()
                if not recorded or Path(recorded).is_dir():
                    continue
                try:
                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    continue
                lock_path.unlink()
                removed += 1
        except OSError:
            continue
    return removed


@contextlib.contextmanager
def environment_lock(prefix):
    """Prevent concurrent updater transactions for the same prefix."""
    resolved = str(Path(prefix).resolve())
    digest = hashlib.sha256(resolved.encode("utf-8")).hexdigest()
    lock_path = lock_root() / f"{digest}.lock"
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(lock_path, flags, 0o600)
    except OSError as exc:
        raise UpdaterError(
            f"Could not securely open environment lock {lock_path}: {exc}"
        ) from exc
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise UpdaterError(
                f"Another updater transaction is active for {prefix}."
            ) from exc
        # Record the prefix so an abandoned lock can later be identified.
        with contextlib.suppress(OSError):
            os.ftruncate(fd, 0)
            os.write(fd, resolved.encode("utf-8"))
        yield
    finally:
        with contextlib.suppress(OSError):
            fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _verify_expected_versions(prefix, expected):
    """Verify exact installed versions and pip ownership after a transaction."""
    inventory = index_inventory(get_environment_inventory(prefix))
    for normalized, version in expected.items():
        item = inventory.get(normalized)
        if not item or item.get("version") != version or item.get("installer") != "pip":
            actual = item.get("version") if item else "missing"
            raise UpdaterError(
                f"Postflight version mismatch for {normalized}: {actual} != {version}."
            )


def rollback_transaction(transaction_dir, manifest):
    """Restore exact pre-transaction wheels and verify the restored environment."""
    prefix = manifest["prefix"]
    manifest["status"] = "rolling_back"
    _write_json_atomic(Path(transaction_dir) / "manifest.json", manifest)
    new_only = manifest.get("new_only", [])
    if new_only:
        print("[INFO] Removing the newly introduced packages...", flush=True)
        result = run_command(
            pip_command(prefix) + ["uninstall", "-y", "--quiet"] + new_only,
            capture_output=True,
            timeout=1800,
        )
        if result.returncode != 0:
            raise command_failure(
                "Removing newly introduced packages during rollback", result
            )
    old_versions = manifest.get("old_versions", {})
    if old_versions:
        print("[INFO] Restoring the previous package versions...", flush=True)
        specs = [f"{name}=={version}" for name, version in sorted(old_versions.items())]
        result = _install_local_wheels(
            prefix, Path(transaction_dir) / "old", specs, "Restoring        "
        )
        if result.returncode != 0:
            raise command_failure("Restoring previous wheels", result)
    print("[INFO] Verifying the restored environment...", flush=True)
    _verify_expected_versions(
        prefix,
        {canonicalize_name(name): version for name, version in old_versions.items()},
    )
    regressions = pip_check_report(prefix) - set(
        manifest["baseline"].get("pip_broken", [])
    )
    if regressions:
        raise UpdaterError(
            "Rollback left dependency conflicts that were not there before:\n  "
            + "\n  ".join(describe_pip_conflict(line) for line in sorted(regressions))
        )
    ownership = load_conda_ownership(prefix)
    if ownership["records_digest"] != manifest["baseline"]["conda_records_digest"]:
        raise UpdaterError("Conda records changed and rollback could not restore them.")
    if doctor_snapshot(prefix) != manifest["baseline"]["doctor"]:
        raise UpdaterError(
            "Conda health differs after rollback; manual recovery is required."
        )
    manifest["status"] = "rolled_back"
    _write_json_atomic(Path(transaction_dir) / "manifest.json", manifest)


def recover_incomplete_transactions(prefix):
    """Recover transactions interrupted after mutation began."""
    root = transaction_root()
    resolved_prefix = str(Path(prefix).resolve())
    now = time.time()
    for transaction_dir in sorted(root.glob("txn-*")):
        manifest_path = transaction_dir / "manifest.json"
        if not manifest_path.is_file():
            # Written by a version that journalled only on success, or lost
            # between mkdtemp and the first write.  Neither case mutated the
            # environment, but a concurrent preparation for a different prefix
            # may still be filling one in, so only sweep clearly abandoned ones.
            try:
                age = now - transaction_dir.stat().st_mtime
            except OSError:
                continue
            if age > ORPHAN_TRANSACTION_MAX_AGE_SECONDS:
                print(
                    f"[INFO] Removing abandoned download workspace "
                    f"{transaction_dir.name} ({int(age // 3600)}h old, no journal)."
                )
                with contextlib.suppress(UpdaterError, OSError):
                    _safe_remove_transaction(transaction_dir)
            continue
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if not isinstance(manifest, dict):
                raise TypeError("journal is not a JSON object")
            journal_prefix = str(Path(manifest["prefix"]).resolve())
        except (OSError, ValueError, KeyError, TypeError) as exc:
            raise UpdaterError(
                f"Transaction journal {manifest_path} could not be read ({exc}).\n"
                "It may describe a partially applied update, so it is not removed "
                "automatically.\n"
                f"Inspect {transaction_dir}, confirm the environment is correct, "
                "then delete that directory to continue."
            ) from exc
        if journal_prefix != resolved_prefix:
            continue
        status = manifest.get("status")
        if status in {"preparing", "prepared"}:
            # No mutation happened yet; the downloaded wheels can be discarded.
            _safe_remove_transaction(transaction_dir)
        elif status in {"applying", "rolling_back", "rollback_failed"}:
            print(f"Recovering interrupted transaction {transaction_dir.name}...")
            try:
                rollback_transaction(transaction_dir, manifest)
            except Exception as exc:
                manifest["status"] = "rollback_failed"
                _write_json_atomic(manifest_path, manifest)
                raise UpdaterError(
                    f"Automatic recovery failed; preserved journal at {transaction_dir}: {exc}"
                ) from exc
            _safe_remove_transaction(transaction_dir)
        elif status in {"complete", "rolled_back"}:
            _safe_remove_transaction(transaction_dir)


def prepare_transaction(prefix, plan, baseline):
    """Download new and rollback wheels, then validate all target paths."""
    transaction_dir = None
    try:
        transaction_dir = Path(tempfile.mkdtemp(prefix="txn-", dir=transaction_root()))
        transaction_dir.chmod(0o700)
        # Claim the workspace before doing anything slow.  Preparation makes
        # several subprocess calls and two network downloads; a signal arriving
        # in any of them must leave behind either nothing at all or a journal
        # that identifies the prefix -- never an anonymous directory of wheels.
        _write_json_atomic(
            transaction_dir / "manifest.json",
            {
                "version": 1,
                "prefix": str(Path(prefix).resolve()),
                "created_at": int(time.time()),
                "status": "preparing",
            },
        )
        new_dir = transaction_dir / "new"
        preflight_dir = transaction_dir / "new-dependency-preflight"
        old_dir = transaction_dir / "old"
        new_dir.mkdir(mode=0o700)
        preflight_dir.mkdir(mode=0o700)
        old_dir.mkdir(mode=0o700)
        inventory = index_inventory(get_environment_inventory(prefix))
        ownership = load_conda_ownership(prefix)
        old_versions = {}
        new_only = []
        for item in plan:
            normalized = canonicalize_name(item["name"])
            installed = inventory.get(normalized)
            if installed:
                old_versions[item["name"]] = installed["version"]
            else:
                new_only.append(item["name"])

        introduced = [
            item
            for item in plan
            if "current_version" in item and item["current_version"] is None
        ]
        remaining = [item for item in plan if item not in introduced]
        introduced_specs = [f"{item['name']}=={item['version']}" for item in introduced]
        remaining_specs = [f"{item['name']}=={item['version']}" for item in remaining]
        old_specs = [f"{name}=={version}" for name, version in old_versions.items()]
        if introduced:
            print(
                "[INFO] Checking newly introduced dependencies before the large "
                "download...",
                flush=True,
            )
            download_exact_wheels(
                prefix,
                introduced_specs,
                preflight_dir,
                "New dependencies ",
                artifacts=introduced,
            )
            introduced_wheels = inspect_wheelhouse(preflight_dir, prefix)
            validate_new_wheels(
                prefix,
                plan,
                introduced_wheels,
                inventory,
                ownership,
                require_complete=False,
            )

        download_exact_wheels(
            prefix,
            remaining_specs,
            new_dir,
            "New packages     ",
            artifacts=remaining,
        )
        for wheel in preflight_dir.glob("*.whl"):
            os.replace(wheel, new_dir / wheel.name)
        new_wheels = inspect_wheelhouse(new_dir, prefix)
        # Nothing has touched the environment yet, so reject an unsafe new
        # wheel as soon as its exact paths are known.  In particular, do not
        # make the user fetch a second multi-gigabyte rollback batch for a
        # transaction that can never be applied.
        validate_new_wheels(prefix, plan, new_wheels, inventory, ownership)

        if old_specs:
            print("[INFO] Locating exact rollback wheels...", flush=True)
        old_artifacts = resolve_exact_download_artifacts(prefix, old_specs)
        download_exact_wheels(
            prefix,
            old_specs,
            old_dir,
            "Rollback copies  ",
            artifacts=old_artifacts,
        )
        old_wheels = inspect_wheelhouse(old_dir, prefix) if old_specs else {}
        if set(old_wheels) != {canonicalize_name(name) for name in old_versions}:
            raise UpdaterError("Rollback wheel set is incomplete.")
        for name, version in old_versions.items():
            if old_wheels[canonicalize_name(name)]["version"] != version:
                raise UpdaterError(f"Rollback wheel version mismatch for {name}.")
        manifest = {
            "version": 1,
            "prefix": str(Path(prefix).resolve()),
            "created_at": int(time.time()),
            "status": "prepared",
            "baseline": baseline,
            "old_versions": old_versions,
            "new_only": new_only,
            "new_versions": {item["name"]: item["version"] for item in plan},
            "plan_signature": plan_signature(plan),
        }
        _write_json_atomic(transaction_dir / "manifest.json", manifest)
        return transaction_dir, manifest
    except BaseException:
        # Preparation never mutates the environment, so any failure -- including
        # KeyboardInterrupt and SIGTERM -- can discard the workspace entirely.
        if transaction_dir is not None:
            with contextlib.suppress(UpdaterError, OSError):
                _safe_remove_transaction(transaction_dir)
        raise


def installed_record_targets(prefix, wheel_dir):
    """Map each wheel in a wheelhouse to the RECORD its installation writes.

    The binary-distribution format requires a wheel's ``.dist-info`` directory
    to be named after the distribution and version fields of its filename, and
    pip writes that directory's RECORD as the very last step of installing a
    package.  A RECORD's appearance is therefore a truthful per-package
    completion signal that needs nothing from pip's output.  Both library
    roots are candidates because either may be the wheel's install base.
    """
    layout = environment_layout(prefix)
    roots = sorted({layout["purelib"], layout["platlib"]})
    targets = []
    for wheel in sorted(Path(wheel_dir).glob("*.whl")):
        fields = wheel.name.split("-")
        if len(fields) < 2:
            continue
        targets.append(
            {
                "wheel": wheel.name,
                "label": f"{fields[0]} {fields[1]}",
                "records": [
                    Path(root, f"{fields[0]}-{fields[1]}.dist-info", "RECORD")
                    for root in roots
                ],
            }
        )
    return targets


def _install_local_wheels(prefix, wheel_dir, specs, title):
    """Install prevalidated wheels from one wheelhouse with live progress."""
    try:
        expected = installed_record_targets(prefix, wheel_dir)
    except (UpdaterError, OSError):
        # Progress is advisory: a failed layout probe must not stop the
        # transaction, so the bar only loses its per-package counter, and any
        # real environment problem will surface from pip itself just below.
        expected = []
    progress = InstallProgress(title, expected)
    progress.tick()
    try:
        result = stream_command(
            pip_command(prefix)
            + [
                "install",
                "--no-index",
                "--find-links",
                str(wheel_dir),
                "--no-deps",
                "--force-reinstall",
                "--quiet",
                "--disable-pip-version-check",
            ]
            + specs,
            timeout=1800,
            on_start=progress.watch,
            on_tick=progress.tick,
        )
    finally:
        progress.finish()
    return result


def apply_transaction(transaction_dir, manifest):
    """Install only prevalidated local wheels and roll back on any failure."""
    prefix = manifest["prefix"]
    manifest["status"] = "applying"
    _write_json_atomic(Path(transaction_dir) / "manifest.json", manifest)
    specs = [f"{name}=={version}" for name, version in manifest["new_versions"].items()]
    try:
        result = _install_local_wheels(
            prefix, Path(transaction_dir) / "new", specs, "Installing       "
        )
        if result.returncode != 0:
            raise command_failure("Applying prevalidated wheels", result)
        print("[INFO] Verifying the updated environment...", flush=True)
        _verify_expected_versions(
            prefix,
            {
                canonicalize_name(name): version
                for name, version in manifest["new_versions"].items()
            },
        )
        # Only *new* conflicts are a failure.  A conflict that already existed
        # before the update is not caused by it, and may even be resolved by it.
        regressions = pip_check_report(prefix) - set(
            manifest["baseline"].get("pip_broken", [])
        )
        if regressions:
            raise UpdaterError(
                "the update would have created new dependency conflicts:\n  "
                + "\n  ".join(
                    describe_pip_conflict(line) for line in sorted(regressions)
                )
            )
        ownership = load_conda_ownership(prefix)
        if ownership["records_digest"] != manifest["baseline"]["conda_records_digest"]:
            raise UpdaterError(
                "Conda package records changed during the pip transaction."
            )
        if doctor_snapshot(prefix) != manifest["baseline"]["doctor"]:
            raise UpdaterError(
                "Conda-managed files or health changed during the pip transaction."
            )
    except BaseException as exc:
        # BaseException, not Exception: KeyboardInterrupt and the SIGTERM/SIGHUP
        # exception must also unwind through rollback, because the environment
        # has already been mutated by this point.
        try:
            rollback_transaction(transaction_dir, manifest)
        except BaseException as rollback_exc:
            manifest["status"] = "rollback_failed"
            _write_json_atomic(Path(transaction_dir) / "manifest.json", manifest)
            raise UpdaterError(
                f"Update failed ({exc}); automatic rollback also failed ({rollback_exc}). "
                f"Recovery data is preserved at {transaction_dir}."
            ) from rollback_exc
        _safe_remove_transaction(transaction_dir)
        if not isinstance(exc, Exception):
            raise
        raise UpdaterError(
            f"Update failed and was rolled back successfully: {exc}"
        ) from exc

    manifest["status"] = "complete"
    _write_json_atomic(Path(transaction_dir) / "manifest.json", manifest)
    _safe_remove_transaction(transaction_dir)


def update_packages(prefix, env_label, names, expected_plan):
    """Run an ownership-safe, journaled pip transaction."""
    print(
        f"\nPreparing the safe update for {count_label(len(names), 'selected package')}...",
        flush=True,
    )
    print(
        "[INFO] Downloading both the new packages and rollback copies first.",
        flush=True,
    )
    with environment_lock(prefix):
        recover_incomplete_transactions(prefix)
        baseline = preflight_health(prefix)
        current_plan = resolve_update_plan(prefix, names)
        if plan_signature(current_plan) != plan_signature(expected_plan):
            raise UpdaterError(
                "The resolved update plan changed after confirmation; no packages were modified."
            )
        transaction_dir, manifest = prepare_transaction(prefix, current_plan, baseline)
        print(
            "[OK] Downloads, checksums, and file-ownership checks passed.",
            flush=True,
        )
        print(
            f"[INFO] Installing the verified packages into '{env_label}'...",
            flush=True,
        )
        apply_transaction(transaction_dir, manifest)


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Interactive/non-interactive pip package updater for conda environments."
    )
    parser.add_argument("env_name", nargs="?", help="Conda environment name")
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--all",
        action="store_true",
        help="Update all outdated packages without opening the interactive selector",
    )
    group.add_argument(
        "--packages",
        metavar="PKG1,PKG2",
        help="Comma-separated package names to update (non-interactive)",
    )
    parser.add_argument(
        "-y",
        "--yes",
        action="store_true",
        help="Skip the final confirmation prompt in non-interactive modes",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Ignore cache and force a fresh package scan",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview updates and recommended next steps without changing packages",
    )
    parser.add_argument(
        "--details",
        action="store_true",
        help="Show technical paths and full package artifact checksums",
    )
    return parser.parse_args()


def parse_package_list(raw):
    """Return a normalized list of package names from comma-separated input."""
    names = [p.strip() for p in raw.split(",")]
    names = [p for p in names if p]
    if not names:
        raise UpdaterError("--packages requires at least one package name.")
    invalid = [name for name in names if not SAFE_PROJECT_NAME.fullmatch(name)]
    if invalid:
        raise UpdaterError("Invalid package name(s): " + ", ".join(invalid))
    return names


def select_non_interactive(packages, *, select_all=False, requested_csv=None):
    """Choose packages without curses UI based on CLI flags."""
    outdated_map = {canonicalize_name(pkg["name"]): pkg["name"] for pkg in packages}
    if select_all:
        return [pkg["name"] for pkg in packages]

    requested = parse_package_list(requested_csv)
    selected = []
    missing = []
    seen = set()

    for name in requested:
        key = canonicalize_name(name)
        if key not in outdated_map:
            missing.append(name)
            continue
        actual = outdated_map[key]
        if canonicalize_name(actual) not in seen:
            selected.append(actual)
            seen.add(canonicalize_name(actual))

    if missing:
        available = ", ".join(pkg["name"] for pkg in packages) or "<none>"
        raise UpdaterError(
            "These packages are not eligible and outdated in this environment: "
            + ", ".join(missing)
            + f". Eligible outdated packages: {available}"
        )

    return selected


def reconcile_selected(selected, packages):
    """Drop selections that are no longer outdated in latest package list."""
    latest_map = {canonicalize_name(pkg["name"]): pkg["name"] for pkg in packages}
    kept = []
    dropped = []
    seen = set()
    for name in selected:
        key = canonicalize_name(name)
        actual = latest_map.get(key)
        if not actual:
            dropped.append(name)
            continue
        if canonicalize_name(actual) not in seen:
            kept.append(actual)
            seen.add(canonicalize_name(actual))
    return kept, dropped


def version_major(version):
    """Return a simple leading numeric major version for display warnings."""
    if version is None:
        return None
    match = re.match(r"^\s*(\d+)(?:\D|$)", str(version))
    return int(match.group(1)) if match else None


def is_major_version_change(item):
    """Identify likely semantic-major jumps without flagging calendar years."""
    current = version_major(item.get("current_version"))
    proposed = version_major(item.get("version"))
    if current is None or proposed is None:
        return False
    if current >= 100 or proposed >= 100:
        return False
    return current != proposed


def count_label(count, singular, plural=None):
    """Return a readable count with the correct singular or plural noun."""
    noun = singular if count == 1 else (plural or singular + "s")
    return f"{count} {noun}"


def format_plan_change(item):
    """Format one package change in user-facing current-to-new form."""
    current = item.get("current_version") or "not installed"
    return f"  {item['name']}: {current} -> {item['version']}"


def print_plan_group(title, items):
    """Print one logically grouped set of package changes."""
    if not items:
        return
    print(f"\n{title} ({len(items)}):")
    for item in sorted(items, key=lambda value: value["name"].lower()):
        print(format_plan_change(item))


def print_resolved_plan(plan, *, show_details=False):
    """Explain direct, dependency, and major-version changes in plain language."""
    selected = [item for item in plan if item["requested"]]
    dependencies = [item for item in plan if not item["requested"]]
    major_changes = [item for item in selected if is_major_version_change(item)]
    routine_changes = [item for item in selected if item not in major_changes]

    print("\nPACKAGE CHANGES")
    print(
        f"  {count_label(len(selected), 'package')} you selected; "
        f"{count_label(len(dependencies), 'required dependency change')}."
    )
    print_plan_group(
        "Review carefully — major-version updates can change behavior",
        major_changes,
    )
    print_plan_group("Other selected updates", routine_changes)
    print_plan_group("Extra dependencies required automatically", dependencies)

    if show_details:
        print("\nTechnical artifact checksums:")
        for item in sorted(plan, key=lambda value: value["name"].lower()):
            print(f"  {item['name']}=={item['version']}: sha256:{item['sha256']}")


def display_script_command():
    """Return a usable script path for copy-and-paste follow-up commands."""
    script = Path(sys.argv[0])
    if not script.is_absolute() and script.parent == Path("."):
        return script.name
    return str(script)


def build_apply_command(env_name, args, selected):
    """Build the non-dry-run command matching the user's selection mode."""
    command = ["python3", display_script_command(), env_name]
    if args.all:
        command.append("--all")
    elif args.packages:
        command.extend(["--packages", args.packages])
    else:
        command.extend(["--packages", ",".join(selected)])
    command.append("--refresh")
    if args.details:
        command.append("--details")
    return shlex.join(command)


def build_single_package_command(env_name, package_name, *, show_details=False):
    """Build a copy-and-paste command for one higher-risk package update."""
    command = [
        "python3",
        display_script_command(),
        env_name,
        "--packages",
        package_name,
        "--refresh",
    ]
    if show_details:
        command.append("--details")
    return shlex.join(command)


def conflicting_package_names(conflicts):
    """Return the package names mentioned by raw `pip check` lines."""
    names = set()
    for line in conflicts:
        match = PIP_CONFLICT_PATTERN.match(line.strip())
        if match:
            names.add(canonicalize_name(match["holder"]))
            names.add(canonicalize_name(match["installed"]))
    return names


def print_dry_run_result(env_name, args, selected, plan, existing_conflicts=()):
    """End a preview with an interpretation and a concrete next action."""
    existing_conflicts = set(existing_conflicts)
    major_changes = [item for item in plan if is_major_version_change(item)]
    print("\n" + "=" * 68)
    print("PREVIEW COMPLETE — NO CHANGES WERE MADE")
    print("=" * 68)
    if existing_conflicts:
        print("[OK] Conda-managed packages are healthy and will stay untouched.")
        planned = {canonicalize_name(item["name"]) for item in plan}
        covered = sorted(conflicting_package_names(existing_conflicts) & planned)
        if covered:
            print(
                f"[!] The conflict noted above involves {', '.join(covered)}, "
                "which this plan updates — that may repair it."
            )
        else:
            print(
                "[!] This plan does not touch the packages involved in the conflict "
                "above, so it will still be there afterward."
            )
    else:
        print("[OK] The environment health and package-ownership checks passed.")
    print("[OK] pip found a compatible installation plan.")
    print("[OK] Conda-managed packages and core update tools will stay untouched.")
    print(
        "[INFO] Package files are downloaded and inspected only during a real update."
    )
    if major_changes:
        names = ", ".join(
            item["name"]
            for item in sorted(major_changes, key=lambda value: value["name"].lower())
        )
        verb = "needs" if len(major_changes) == 1 else "need"
        print(
            f"[REVIEW] {count_label(len(major_changes), 'major-version change')} "
            f"{verb} extra care: {names}."
        )

    print("\nWhat to do next:")
    if major_changes:
        print(
            "  Safest approach: update and test the major-version packages "
            "one at a time:"
        )
        for item in sorted(major_changes, key=lambda value: value["name"].lower()):
            print(
                "\n    "
                + build_single_package_command(
                    env_name, item["name"], show_details=args.details
                )
            )
        print("\n  After each update, start the application or run its tests.")
        print("  Then run your preview command again to see what remains.")
        print("\n  Faster but higher risk: apply every update at once:")
        print(f"\n    {build_apply_command(env_name, args, selected)}")
    else:
        print("  To apply this selection, run:")
        print(f"\n    {build_apply_command(env_name, args, selected)}")
        print("\n  Afterward, start the application or run its tests.")
    print("\nThe updater will recheck everything and ask before installing.")
    print(
        "\nNote: these checks protect package integrity; they cannot predict every "
        "application-level behavior change."
    )


def print_no_updates_result(env_name):
    """Explain a clean scan as a successful no-op."""
    print("\n" + "=" * 68)
    print("NOTHING TO UPDATE")
    print("=" * 68)
    print(f"[OK] All eligible pip packages in '{env_name}' are already current.")
    print("[INFO] Automatically skipped Conda-managed/core packages need no action.")


def print_update_success(env_name, plan, before_conflicts=(), after_conflicts=()):
    """Report a successful transaction and its recommended follow-up."""
    before = set(before_conflicts)
    after = set(after_conflicts)
    selected_count = sum(bool(item["requested"]) for item in plan)
    dependency_count = len(plan) - selected_count
    print("\n" + "=" * 68)
    print("UPDATE COMPLETED SUCCESSFULLY")
    print("=" * 68)
    print(
        f"[OK] Updated {count_label(selected_count, 'selected package')} and "
        f"{count_label(dependency_count, 'required dependency package')} "
        f"in '{env_name}'."
    )
    if after:
        if before - after:
            print(
                f"[OK] Repaired {count_label(len(before - after), 'conflict')} "
                "that existed before this update."
            )
        print(f"[!] {count_label(len(after), 'conflict')} still needs attention:")
        for line in sorted(after):
            print(f"      {describe_pip_conflict(line)}")
        print("    This update did not cause it and did not make it worse.")
    else:
        print("[OK] pip reports no broken requirements.")
        if before:
            print(
                f"[OK] The {count_label(len(before), 'conflict')} that existed "
                "before this update is now resolved."
            )
    print("[OK] Conda-managed files and environment health are unchanged.")
    print("\nNext: start the application or run its tests to confirm normal behavior.")


def main():
    args = parse_args()
    install_termination_handlers()
    with contextlib.suppress(UpdaterError):
        prune_stale_locks()

    environments, root_prefix = get_known_environments()
    selectable = sorted(
        name for name, prefix in environments.items() if prefix != root_prefix
    )
    if not selectable:
        raise UpdaterError(
            "No named Conda environments were found. Base is intentionally never an update target."
        )

    fixed_environment = None
    if args.env_name:
        fixed_environment = resolve_environment(args.env_name, environments)
        if fixed_environment[1] == root_prefix:
            raise UpdaterError(
                "Refusing to update Conda's base environment. Base contains Conda's own control "
                "plane; create or select a named environment instead."
            )

    while True:
        if fixed_environment:
            env_name, prefix = fixed_environment
        else:
            if not sys.stdin.isatty() or not sys.stdout.isatty():
                raise UpdaterError(
                    "env_name is required in non-interactive mode. Available named environments: "
                    + ", ".join(selectable)
                )
            try:
                env_name = curses.wrapper(interactive_select_env, selectable)
            except curses.error as exc:
                raise UpdaterError(
                    f"Failed to initialize environment selector ({exc}). "
                    "Run the script directly in a local terminal session."
                ) from exc
            if not env_name:
                print("No environment selected. Exiting.")
                return
            prefix = environments[env_name]

        print("\n" + "=" * 68)
        print("PIP PACKAGE UPDATE PREVIEW" if args.dry_run else "PIP PACKAGE UPDATE")
        print("=" * 68)
        print(f"Environment: {env_name}")
        if args.dry_run:
            print("Mode: preview only — this command will not change any packages")
        print("\n[1/3] Activating and checking the environment...")
        activate_environment(prefix, root_prefix)

        with environment_lock(prefix):
            recover_incomplete_transactions(prefix)
            baseline = preflight_health(prefix)
        existing_conflicts = set(baseline["pip_broken"])
        conda_issues = baseline.get("conda_issues") or {}
        if existing_conflicts or conda_issues:
            print("[OK] Conda's own files are all present and unaltered.")
        else:
            print("[OK] Environment health checks passed.")
        print_conda_inconsistencies(conda_issues)
        if existing_conflicts:
            print_existing_conflicts(existing_conflicts)

        env_key = str(Path(prefix).resolve())

        print("\n[2/3] Looking for pip packages that can be safely updated...")
        packages, from_cache = get_outdated_packages(
            env_key, prefix, refresh=args.refresh
        )
        # Tracks whether `packages` came from a scan performed moments ago in
        # this run, with no user interaction since.
        packages_are_live = not from_cache
        if from_cache:
            print("[OK] Loaded the previous package scan; it will be rechecked live.")
        else:
            print("[OK] Fresh package scan completed.")
        if args.details:
            print(f"[DETAIL] Scan cache: {CACHE_FILE}")

        if not packages:
            if from_cache and not args.refresh:
                print("Cached result is empty; verifying with a live scan...")
                packages = scan_outdated_packages(prefix, report_exclusions=True)
                set_cached_packages(env_key, packages)
                packages_are_live = True
                if packages:
                    print(
                        f"[OK] Live scan found {count_label(len(packages), 'package')} "
                        "that can be updated."
                    )
                else:
                    print_no_updates_result(env_name)
                    if fixed_environment:
                        return
                    continue
            else:
                print_no_updates_result(env_name)
                if fixed_environment:
                    return
                continue
        else:
            print(
                f"[OK] Found {count_label(len(packages), 'package')} "
                "that can be updated."
            )

        if args.all or args.packages:
            # For non-interactive modes, prefer correctness over stale cache.
            if from_cache and not args.refresh:
                print("[INFO] Confirming the cached list with a live scan...")
                packages = scan_outdated_packages(prefix, report_exclusions=True)
                set_cached_packages(env_key, packages)
                packages_are_live = True
                if not packages:
                    print_no_updates_result(env_name)
                    return

            selected = select_non_interactive(
                packages,
                select_all=args.all,
                requested_csv=args.packages,
            )
        else:
            if not sys.stdin.isatty() or not sys.stdout.isatty():
                print("Error: interactive selection requires a TTY terminal.")
                print("Use --all or --packages for non-interactive usage.")
                sys.exit(1)

            package_state = {
                "lock": threading.Lock(),
                "packages": packages,
                "scan_in_progress": False,
                "scan_done": True,
                "scan_error": None,
                "cache_mismatch": False,
                "started_from_cache": from_cache,
                "scan_progress": None,
            }
            refresh_thread = None
            refresh_progress = None
            if from_cache and not args.refresh:
                package_state["scan_in_progress"] = True
                package_state["scan_done"] = False
                refresh_progress = PackageScanProgress(
                    cached_count=len(packages), render=False
                )
                package_state["scan_progress"] = refresh_progress
                refresh_thread = threading.Thread(
                    target=refresh_packages_background,
                    args=(env_key, prefix, package_state, refresh_progress),
                    daemon=True,
                )
                refresh_thread.start()

            # The user is about to spend an unbounded amount of time in the
            # selector, so whatever list they see must be revalidated afterward.
            packages_are_live = False
            print(f"Opening the selector with {len(packages)} available update(s)...")
            try:
                selected = curses.wrapper(
                    interactive_select, package_state, not bool(fixed_environment)
                )
            except curses.error as exc:
                raise UpdaterError(
                    f"Failed to initialize terminal UI ({exc}). Run this in a local terminal."
                ) from exc

            if selected == BACK_TO_ENV:
                wait_for_background_scan(refresh_thread, refresh_progress)
                continue

            waited_for_refresh = wait_for_background_scan(
                refresh_thread, refresh_progress
            )

            if refresh_thread:
                with package_state["lock"]:
                    packages = list(package_state["packages"])
                    had_mismatch = package_state["cache_mismatch"]
                if had_mismatch:
                    selected, dropped = reconcile_selected(selected, packages)
                    if dropped:
                        print("\nRemoved stale selections no longer outdated:")
                        print("  " + ", ".join(dropped))
                if waited_for_refresh:
                    with package_state["lock"]:
                        packages_are_live = package_state["scan_error"] is None

        if not selected:
            print("\nNo packages selected. Exiting.")
            return

        print("\n[3/3] Building and checking the exact update plan...")
        if packages_are_live:
            # This list came from a scan seconds ago in the same non-interactive
            # run, so rescanning only repeats a network round trip (measured at
            # ~2.6s, about a quarter of total runtime).  The authoritative
            # time-of-use checks are unchanged: resolve_update_plan queries pip
            # live below, and update_packages re-resolves under the environment
            # lock and refuses to proceed if the plan signature moved.
            live_packages = packages
        else:
            live_packages = scan_outdated_packages(prefix, report_exclusions=False)
            set_cached_packages(env_key, live_packages)
        selected, dropped = reconcile_selected(selected, live_packages)
        if dropped:
            print("[INFO] No longer need an update: " + ", ".join(dropped))
        if not selected:
            print_no_updates_result(env_name)
            return

        plan = resolve_update_plan(prefix, selected)
        if not plan:
            print_no_updates_result(env_name)
            return
        print("[OK] pip found a compatible update plan.")
        print_resolved_plan(plan, show_details=args.details)
        try:
            print_shared_file_warning(shared_file_report(prefix, plan))
        except (UpdaterError, OSError) as exc:
            # Advisory only; validate_new_wheels enforces the real guarantee
            # before anything is installed, so this must never end the run.
            print(f"[INFO] Could not check for shared files ({exc}).")

        if args.dry_run:
            print_dry_run_result(env_name, args, selected, plan, existing_conflicts)
            return

        if not args.yes:
            if not sys.stdin.isatty():
                print("Error: confirmation prompt requires a TTY. Re-run with --yes.")
                raise UpdaterError("Confirmation requires a TTY; re-run with --yes.")
            answer = input(f"\nApply these changes to '{env_name}'? [y/N] ")
            if answer.strip().lower() != "y":
                print("Cancelled. No packages were changed.")
                if fixed_environment:
                    return
                continue

        update_packages(prefix, env_name, selected, plan)
        remove_cached_packages(env_key, selected)
        print_update_success(
            env_name, plan, existing_conflicts, pip_check_report(prefix)
        )
        return


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        sys.exit(130)
    except UpdateInterrupted as exc:
        print(f"\nStopped: {exc}.", file=sys.stderr)
        sys.exit(143)
    except UpdaterError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
