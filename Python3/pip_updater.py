#!/usr/bin/env python3
"""Safely update pip- and uv-installed packages inside non-base conda environments.

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
import dataclasses
import fcntl
import functools
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
import termios
import textwrap
import threading
import time
import tty
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit

CACHE_ROOT = (
    Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "pip-updater"
)
CACHE_FILE = str(CACHE_ROOT / "cache-v2.json")
CACHE_VERSION = 2
BACK_TO_ENV = "__BACK_TO_ENV__"
STALE_METADATA_SUFFIX = ".pip-updater-stale"
PROTECTED_BOOTSTRAP_PACKAGES = {"pip", "setuptools", "wheel"}
# Installers whose installs pip can replace exactly: both write standard
# wheel metadata with a RECORD (an install missing one is still refused).  A
# uv install becomes pip-installed once the updater replaces it.
UPDATABLE_INSTALLERS = frozenset({"pip", "uv"})
SAFE_PROJECT_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
SAFE_VERSION = re.compile(r"^[A-Za-z0-9_.!+-]+$")
PROCESS_START_ENVIRONMENT = os.environ.copy()
# A transaction workspace without a journal never mutated the environment, but a
# concurrent preparation for another prefix may legitimately still be filling one
# in.  Only workspaces older than this are treated as abandoned.
ORPHAN_TRANSACTION_MAX_AGE_SECONDS = 24 * 60 * 60


class UpdaterError(RuntimeError):
    """A user-actionable safety or execution failure."""


class UnsolvableError(UpdaterError):
    """pip's resolver proved that no set of versions meets the requirements."""


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


@dataclasses.dataclass
class StreamHooks:
    """Callbacks stream_command makes while a child runs; any may be None."""

    on_start: object = None  # called once with the child's pid
    on_line: object = None  # called with each decoded stdout line
    on_tick: object = None  # called at least once every `interval` seconds
    interval: float = 1.0


class _OutputLines:
    """Split a child's raw output chunks into decoded lines, per stream."""

    def __init__(self, on_line):
        self.collected = {"stdout": [], "stderr": []}
        self._pending = {"stdout": b"", "stderr": b""}
        self._on_line = on_line

    def feed(self, kind, chunk):
        """Add a chunk read from ``kind`` ("stdout" or "stderr")."""
        self._pending[kind] += chunk
        *lines, self._pending[kind] = self._pending[kind].split(b"\n")
        for line in lines:
            self._emit(kind, line)

    def flush(self):
        """Deliver any final line that had no trailing newline."""
        for kind, tail in self._pending.items():
            if tail:
                self._emit(kind, tail)

    def _emit(self, kind, chunk):
        text = chunk.decode("utf-8", "replace").rstrip("\r")
        self.collected[kind].append(text)
        if kind == "stdout" and self._on_line is not None:
            self._on_line(text)


def _spawn(args, *, merge_stderr, with_stdin):
    try:
        # Not a `with` block: stream_command's `finally` must kill the child
        # before closing its pipes and reaping it, even on a termination signal.
        return subprocess.Popen(  # pylint: disable=consider-using-with
            args,
            stdin=subprocess.PIPE if with_stdin else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT if merge_stderr else subprocess.PIPE,
            bufsize=0,
        )
    except FileNotFoundError as exc:
        raise UpdaterError(
            f"Required command '{args[0]}' was not found in PATH."
        ) from exc


def _write_stdin(process, input_data):
    payload = input_data.encode("utf-8") if isinstance(input_data, str) else input_data
    assert process.stdin is not None
    try:
        process.stdin.write(payload)
    except BrokenPipeError:
        pass
    finally:
        process.stdin.close()


def _reap(process):
    if process.poll() is None:
        process.kill()
    for stream in (process.stdin, process.stdout, process.stderr):
        if stream is not None:
            with contextlib.suppress(OSError):
                stream.close()
    process.wait()


def stream_command(
    args, *, timeout=None, hooks=None, merge_stderr=True, input_data=None
):
    """Run a command, reporting each output line and a periodic liveness tick.

    ``run_command`` cannot show progress because it only returns once the child
    has exited.  Downloads take minutes, so this variant reads the merged output
    incrementally and calls ``hooks.on_tick`` at least once per
    ``hooks.interval`` seconds even while the child is silent.
    ``merge_stderr=False`` preserves machine-readable stdout such as pip's JSON
    report while still retaining stderr for failures.  Everything stays in the
    calling thread so a termination signal still unwinds straight through the
    transaction rollback.
    """
    hooks = hooks or StreamHooks()
    process = _spawn(args, merge_stderr=merge_stderr, with_stdin=input_data is not None)
    output = _OutputLines(hooks.on_line)
    deadline = time.monotonic() + timeout if timeout else None
    selector = selectors.DefaultSelector()
    try:
        if hooks.on_start is not None:
            hooks.on_start(process.pid)
        if input_data is not None:
            _write_stdin(process, input_data)
        selector.register(process.stdout, selectors.EVENT_READ, "stdout")
        if not merge_stderr:
            selector.register(process.stderr, selectors.EVENT_READ, "stderr")
        while selector.get_map():
            if deadline is not None and time.monotonic() > deadline:
                raise UpdaterError(
                    f"Command timed out after {timeout} seconds: {args[0]}"
                )
            for key, _ in selector.select(hooks.interval):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if chunk:
                    output.feed(key.data, chunk)
                else:
                    selector.unregister(key.fileobj)
            if hooks.on_tick is not None:
                hooks.on_tick()
        output.flush()
    finally:
        selector.close()
        _reap(process)
    return subprocess.CompletedProcess(
        args,
        process.returncode,
        "\n".join(output.collected["stdout"]),
        "\n".join(output.collected["stderr"]),
    )


# ANSI SGR codes for each style role.
STYLE_CODES = {
    "ok": "1;32",
    "info": "1;36",
    "warn": "1;33",
    "error": "1;31",
    "repair": "1;35",
    "preview": "1;34",
    "detail": "2",
    "heading": "1;36",
    "step": "1;34",
    "strong": "1",
    "muted": "2",
    "new": "1;32",
    "note": "33",
    "command": "36",
    "env": "1;35",
    "failed": "1;31",
}


class Palette:
    """ANSI styling for a color terminal; plain text whenever color is off.

    Color is decided once per run for stdout (``configure``), so piped or
    logged output never carries escape sequences.  NO_COLOR disables it and
    FORCE_COLOR enables it for a non-terminal stream (no-color.org and the
    FORCE_COLOR convention).
    """

    def __init__(self):
        self.enabled = False

    def configure(self, stream):
        """Enable color only for a terminal that has not opted out of it."""
        if os.environ.get("NO_COLOR"):
            self.enabled = False
        elif os.environ.get("FORCE_COLOR"):
            self.enabled = True
        else:
            is_terminal = bool(getattr(stream, "isatty", lambda: False)())
            self.enabled = is_terminal and os.environ.get("TERM") != "dumb"

    def __call__(self, text, role):
        """Return ``text`` in ``role``'s style, or unchanged when color is off."""
        if not self.enabled or not text:
            return text
        return f"\x1b[{STYLE_CODES[role]}m{text}\x1b[0m"


paint = Palette()

# Each status tag's style; the tag text itself is identical with color off.
STATUS_ROLES = {
    "OK": "ok",
    "INFO": "info",
    "!": "warn",
    "REVIEW": "warn",
    "REPAIR": "repair",
    "PREVIEW": "preview",
    "DETAIL": "detail",
}


def announce(tag, *parts, **print_options):
    """Print a message led by its colored ``[TAG]``."""
    print(paint(f"[{tag}]", STATUS_ROLES[tag]), *parts, **print_options)


def print_banner(title, role="heading"):
    """Print a full-width result banner; ``role`` sets its color."""
    rule = ("━" if paint.enabled else "=") * 68
    print("\n" + paint(rule, role))
    print(paint(title, role))
    print(paint(rule, role))


def print_section(title):
    """Print a section heading after a blank line."""
    print("\n" + paint(title, "heading"))


def print_labeled(label, text):
    """Print ``label text`` indented, wrapped to the terminal width.

    Wrapping runs on the plain text, so the label's styling cannot distort the
    measured line lengths.
    """
    width = max(40, min(100, shutil.get_terminal_size((100, 24)).columns - 1))
    lines = textwrap.wrap(
        f"{label} {text}",
        width=width,
        initial_indent="  ",
        subsequent_indent="    ",
        break_on_hyphens=False,
        break_long_words=False,
    )
    lines[0] = lines[0].replace(label, paint(label, "strong"), 1)
    print("\n".join(lines))


def print_step(position, text):
    """Print a numbered stage of the run, such as ``[2/3]``."""
    print("\n" + paint(f"[{position}]", "step"), paint(text, "strong"))


_PROGRESS_BAR = re.compile(r"\[([#>!-]{8,})\]")
_PROGRESS_LABEL = re.compile(r"^(\s*)([A-Z][A-Za-z ]*?)(?=:|\s\[)")
_PROGRESS_ELAPSED = re.compile(r"(\d{2}:\d{2})(\s*)$")
_BAR_CELLS = {
    "#": ("█", "ok"),
    ">": ("█", "ok"),
    "-": ("░", "muted"),
    "!": ("✗", "failed"),
}


def _paint_bar(match):
    cells = "".join(
        paint(glyph, role)
        for glyph, role in (_BAR_CELLS[cell] for cell in match.group(1))
    )
    return f"[{cells}]"


def colorize_progress(line):
    """Style one plain progress row without changing its visible width.

    Rows are built and fitted to the terminal as plain text; styling is added
    last, and every glyph swapped in occupies exactly one column.
    """
    if not paint.enabled:
        return line
    line = _PROGRESS_BAR.sub(_paint_bar, line)
    line = _PROGRESS_LABEL.sub(
        lambda m: m.group(1) + paint(m.group(2), "heading"), line
    )
    line = _PROGRESS_ELAPSED.sub(
        lambda m: paint(m.group(1), "muted") + m.group(2), line
    )
    return line.replace(" | ", paint(" | ", "muted"))


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


def truncate_label(value, available):
    """Fit value into available columns, marking a cut with an ellipsis."""
    if available <= 0:
        return ""
    if len(value) <= available:
        return value
    if available <= 3:
        return value[:available]
    return value[: available - 3] + "..."


def process_figures(cpu_percent, rss_bytes):
    """Format measured process CPU and memory, skipping unmeasured values."""
    facts = []
    if cpu_percent is not None:
        facts.append(f"CPU {cpu_percent:.0f}%")
    if rss_bytes is not None:
        facts.append(f"RAM {format_bytes(rss_bytes)}")
    return facts


class ProcessSampler:
    """Thread-safe CPU and RSS sampling of one child process from /proc.

    /proc exists only on Linux, and a process can exit between reads; either
    way a sample is skipped and the last measured figures stay on display.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self.pid = None
        self.cpu_percent = None
        self.rss_bytes = None
        self._last_cpu = None

    def watch(self, pid):
        """Follow a new process, forgetting the previous one's figures."""
        with self._lock:
            self.pid = pid
            self.cpu_percent = None
            self.rss_bytes = None
            self._last_cpu = None
        self.sample()

    def stop(self):
        """Stop sampling; a reaped pid can be reused by an unrelated process."""
        with self._lock:
            self.pid = None

    def sample(self):
        """Update CPU percent since the previous sample, and resident memory."""
        with self._lock:
            pid = self.pid
            previous = self._last_cpu
        if pid is None:
            return
        now = time.monotonic()
        try:
            stat_text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
            fields = stat_text[stat_text.rfind(")") + 2 :].split()
            ticks = int(fields[11]) + int(fields[12])
            cpu_seconds = ticks / os.sysconf("SC_CLK_TCK")
            status = Path(f"/proc/{pid}/status").read_text(encoding="utf-8")
        except (OSError, ValueError, IndexError):
            return
        rss = re.search(r"^VmRSS:\s+(\d+)\s+kB$", status, re.MULTILINE)
        with self._lock:
            if previous is not None and now > previous[1]:
                self.cpu_percent = max(
                    0.0, 100 * (cpu_seconds - previous[0]) / (now - previous[1])
                )
            if rss:
                self.rss_bytes = int(rss.group(1)) * 1024
            self._last_cpu = (cpu_seconds, now)

    def readings(self):
        """Return ``(cpu_percent, rss_bytes)``; None where not yet measured."""
        with self._lock:
            return self.cpu_percent, self.rss_bytes

    def figures(self):
        """Return the measured facts ("CPU n%", "RAM n MB") available so far."""
        return process_figures(*self.readings())


class LiveDisplay:
    """Rows repainted in place on a terminal; plain appended lines otherwise."""

    def __init__(self, stream=None):
        self.stream = stream if stream is not None else sys.stdout
        self.interactive = bool(getattr(self.stream, "isatty", lambda: False)())
        self._painted = []

    @staticmethod
    def width():
        """Return the usable terminal width, never narrower than 40 columns."""
        return max(40, shutil.get_terminal_size((180, 24)).columns - 1)

    def draw(self, lines):
        """Overwrite the rows drawn last time, padding away longer old text."""
        rows_up = len(self._painted) - 1
        self.stream.write(f"\r\x1b[{rows_up}A" if rows_up > 0 else "\r")
        for index, line in enumerate(lines):
            if index:
                self.stream.write("\n")
            previous = self._painted[index] if index < len(self._painted) else 0
            self.stream.write(colorize_progress(line.ljust(previous)))
        self.stream.flush()
        self._painted = [len(line) for line in lines]

    def log(self, text):
        """Append one line, above any drawn rows; the caller repaints them."""
        if self._painted:
            rows_up = len(self._painted) - 1
            self.stream.write(f"\r\x1b[{rows_up}A\x1b[J" if rows_up > 0 else "\r\x1b[J")
            self._painted = []
        print(text, file=self.stream, flush=True)

    def end(self):
        """Move below drawn rows so later output starts on a clean line."""
        if self._painted:
            self.stream.write("\n")
            self.stream.flush()


class Pacer:
    """Elapsed time plus the throttles that bound repaints and log lines."""

    def __init__(self, log_interval, refresh_interval=0.2):
        self.started = time.monotonic()
        self.log_interval = log_interval
        self.refresh_interval = refresh_interval
        self.logged_count = 0
        self._last_paint = None
        self._logged_interval = -1

    def elapsed(self):
        """Seconds since the tracked work started."""
        return time.monotonic() - self.started

    def paint_due(self, *, force=False):
        """Allow at most one repaint per refresh interval, unless forced."""
        now = time.monotonic()
        if (
            not force
            and self._last_paint is not None
            and now - self._last_paint < self.refresh_interval
        ):
            return False
        self._last_paint = now
        return True

    def log_due(self, *, force=False):
        """Allow one log line per log interval, unless forced."""
        interval = int(self.elapsed() // self.log_interval)
        if not force and interval == self._logged_interval:
            return False
        self._logged_interval = interval
        return True


@dataclasses.dataclass
class ResolverGraph:
    """Counters distilled from pip's resolver log lines."""

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

    selected: set
    loaded: set = dataclasses.field(default_factory=set)
    packages: set = dataclasses.field(default_factory=set)
    candidates: set = dataclasses.field(default_factory=set)
    backtracking: set = dataclasses.field(default_factory=set)
    current: str = ""
    last_line_at: float = dataclasses.field(default_factory=time.monotonic)

    def observe(self, text):
        """Count one stripped pip log line; return the phase it implies."""
        self.last_line_at = time.monotonic()
        phase = None
        package = self._PACKAGE_EVENT.match(text)
        if package:
            name = canonicalize_name(package.group(1))
            self.packages.add(name)
            if name in self.selected:
                self.loaded.add(name)
            self.current = name
            if len(self.loaded) == len(self.selected):
                phase = "Resolving dependencies"

        metadata = self._METADATA_EVENT.match(text)
        if metadata:
            self.candidates.add(metadata.group(1))

        backtrack = self._BACKTRACK_EVENT.search(text)
        if backtrack:
            name = canonicalize_name(backtrack.group(1))
            self.backtracking.add(name)
            self.current = name
            phase = "Backtracking"

        if text.startswith(("Downloading ", "Using cached ")):
            if ".whl (" in text:
                phase = "Preparing candidate files"
        elif text.startswith("Would install "):
            phase = "Finalizing plan"
        return phase


# Resolver phases whose activity text does not depend on the graph counters.
RESOLVER_PHASE_ACTIVITY = {
    "Resolver finished": "finished",
    "Resolver stopped": "stopped",
    "Preparing candidate files": "preparing candidate wheel files",
    "Finalizing plan": "finalizing the exact plan",
    "Discovering compatible wheels": "finding compatible binary targets",
}


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
    SILENCE_SHOWN = 10

    def __init__(self, selected, stream=None):
        self.graph = ResolverGraph({canonicalize_name(name) for name in selected})
        self.phase = "Loading metadata"
        self.sampler = ProcessSampler()
        self.display = LiveDisplay(stream)
        self.pacer = Pacer(self.LOG_INTERVAL, self.REFRESH_INTERVAL)
        self._finished = False
        self._step = ("", time.monotonic())

    @property
    def step(self):
        """Label of the solve now running, or "" before the first one."""
        return self._step[0]

    def begin_step(self, label):
        """Name the solve now running; the dashboard shows it until it ends."""
        self._step = (label, time.monotonic())
        self.phase = "Resolving dependencies"
        self.graph.backtracking.clear()
        self.graph.last_line_at = self._step[1]

    def end_step(self, result):
        """Log how the current solve ended, above the dashboard."""
        seconds = format_elapsed(time.monotonic() - self._step[1])
        self.display.log(f"  {self.step}: {result} ({seconds})")
        if self.display.interactive:
            self._paint()

    @property
    def total(self):
        """Number of selected packages whose metadata the bar tracks."""
        return len(self.graph.selected)

    def watch(self, pid):
        """Remember the resolver process so silent CPU work stays visible."""
        self.sampler.watch(pid)

    def note(self, line):
        """Turn pip's human-readable resolver events into stable counters."""
        phase = self.graph.observe(line.strip())
        if phase:
            self.phase = phase

    def _selected_bar(self):
        loaded = len(self.graph.loaded)
        filled = self.WIDTH if not self.total else self.WIDTH * loaded // self.total
        return "#" * filled + "-" * (self.WIDTH - filled)

    def _line(self, max_width):
        graph = self.graph
        elapsed = format_elapsed(self.pacer.elapsed())
        loaded = len(graph.loaded)
        selected = f"selected [{self._selected_bar()}] {loaded}/{self.total} loaded"
        counts = (
            f"graph {count_label(len(graph.packages), 'package')} / "
            f"{count_label(len(graph.candidates), 'candidate')}"
        )
        current = graph.current
        if len(current) > 30:
            current = current[:27] + "..."

        optional = []
        if current:
            optional.append(f"current {current}")
        if graph.backtracking:
            optional.append(
                f"backtracking {count_label(len(graph.backtracking), 'package')}"
            )
        process = self.sampler.figures()
        if process:
            optional.append(" / ".join(process))

        parts = [f"  {self.phase}", selected, counts]
        for item in optional:
            candidate = " | ".join([*parts, item, elapsed])
            if len(candidate) <= max_width:
                parts.append(item)
        line = " | ".join([*parts, elapsed])
        if len(line) > max_width:
            compact = [
                f"  {self.phase}",
                f"selected {loaded}/{self.total}",
                f"graph {len(graph.packages)}/{len(graph.candidates)}",
                elapsed,
            ]
            line = " | ".join(compact)
        return line[:max_width]

    def _resolver_activity(self):
        activity = RESOLVER_PHASE_ACTIVITY.get(self.phase)
        if activity:
            return activity
        if self.graph.backtracking:
            return (
                "backtracking across "
                f"{count_label(len(self.graph.backtracking), 'package')}"
            )
        if self.phase == "Loading metadata":
            return "loading selected package metadata"
        return "searching compatible versions"

    def _terminal_lines(self, max_width):
        """Build a compact dashboard whose three rows fit the terminal."""
        graph = self.graph
        loaded = len(graph.loaded)
        line1 = (
            f"  Selected metadata [{self._selected_bar()}] {loaded}/{self.total} loaded"
        )
        if len(line1) > max_width:
            line1 = f"  Selected [{self._selected_bar()}] {loaded}/{self.total}"

        graph_prefix = (
            f"  Dependency graph: {count_label(len(graph.packages), 'package')}, "
            f"{count_label(len(graph.candidates), 'candidate')} | current: "
        )
        if len(graph_prefix) + 1 > max_width:
            graph_prefix = (
                f"  Graph {len(graph.packages)}/{len(graph.candidates)} | current: "
            )
        current = graph.current or "waiting for pip"
        line2 = graph_prefix + truncate_label(current, max_width - len(graph_prefix))

        activity = self._resolver_activity()
        if self.step:
            activity = f"{self.step} · {activity}"
        head = f"  Resolver: {activity}"
        tail = [*self.sampler.figures(), format_elapsed(self.pacer.elapsed())]
        silent = time.monotonic() - self.graph.last_line_at
        if silent >= self.SILENCE_SHOWN:
            # pip prints nothing while it backtracks through candidates it
            # already loaded; the silence is the only sign of that search.
            tail.insert(0, f"no pip output for {format_elapsed(silent)}")
        while len(" | ".join([head, *tail])) > max_width and len(tail) > 2:
            tail.pop(-2)
        room = max_width - len(" | ".join(["", *tail]))
        line3 = " | ".join([truncate_label(head, room), *tail])

        return [line[:max_width] for line in (line1, line2, line3)]

    def _paint(self):
        self.display.draw(self._terminal_lines(self.display.width()))

    def tick(self):
        """Refresh real telemetry or emit a bounded log heartbeat."""
        if self._finished:
            return
        if self.display.interactive:
            if self.pacer.paint_due():
                self.sampler.sample()
                self._paint()
            return
        # Sample every tick so the closing line reports the resolver's last
        # real CPU/RAM, not the figure from the moment it was spawned.
        self.sampler.sample()
        if self.pacer.log_due():
            self.display.log(self._line(10_000))

    def finish(self, success):
        """Settle the telemetry without claiming success on failure."""
        if self._finished:
            return
        self._finished = True
        self.phase = "Resolver finished" if success else "Resolver stopped"
        if self.display.interactive:
            self._paint()
            self.display.end()
        else:
            self.display.log(self._line(10_000))


class CountedProgress:
    """One-line progress for work measured as N of a known total of items.

    Subclasses measure ``done`` and ``current`` from the filesystem.  On a
    terminal the line is repainted; on a pipe each completion is logged, plus
    a bounded heartbeat so a single multi-gigabyte item never goes silent.
    """

    HEARTBEAT_SECONDS = 30

    def __init__(self, title, total, stream=None):
        self.title = title
        self.total = total
        self.current = ""
        self.pid = None
        self.done = 0
        self.display = LiveDisplay(stream)
        self.pacer = Pacer(self.HEARTBEAT_SECONDS)

    def watch(self, pid):
        """Follow this child so the item it is working on can be observed."""
        self.pid = pid

    def _measure(self):
        """Refresh ``done`` and ``current`` from observable state."""
        raise NotImplementedError

    def _meter_line(self):
        """Return the repainted line, before the in-flight label."""
        raise NotImplementedError

    def _summary(self):
        """Return the logged sentence for the current completed count."""
        raise NotImplementedError

    def _heartbeat_facts(self):
        """Return fields for a piped heartbeat, or None when none applies."""
        return []

    def _report(self):
        self.display.log(f"  {self.title.rstrip()}: {self._summary()}")
        self.pacer.logged_count = self.done
        self.pacer.log_due(force=True)

    def _heartbeat(self):
        facts = self._heartbeat_facts()
        if facts is None or not self.pacer.log_due():
            return
        current = f" | {self.current}" if self.current else ""
        fields = [f"{self.done}/{self.total} complete", *facts]
        fields.append(format_elapsed(self.pacer.elapsed()) + current)
        self.display.log(f"  {self.title.rstrip()}: " + " | ".join(fields))

    def _paint(self):
        line = self._meter_line()
        if self.current:
            available = self.display.width() - len(line) - 2
            if available > 3:
                line += "  " + truncate_label(self.current, available)
        self.display.draw([line])

    def tick(self):
        """Repaint the progress line, or report each completion when piped."""
        self._measure()
        if self.display.interactive:
            self._paint()
        elif self.done != self.pacer.logged_count:
            self._report()
        elif self.done < self.total:
            self._heartbeat()

    def finish(self):
        """Leave one settled summary line behind for the session transcript."""
        # The child has been reaped by now, so drop it before measuring rather
        # than risk reading the open files of whatever inherits its pid next.
        self.pid = None
        self._measure()
        if self.display.interactive:
            self.current = ""
            self._paint()
            self.display.end()
        elif self.done != self.pacer.logged_count:
            self._report()


class TransferRate:
    """Download speed, measured only while bytes really come off the network."""

    def __init__(self):
        self.source = ""
        self.speed = None
        self._network_start = None
        self._window = (0, time.monotonic())

    def begin(self, source, downloaded, *, restart_network=False):
        """Start timing a new fetch from ``source`` ("network" or "cache")."""
        self.source = source
        if source == "network" and (restart_network or self._network_start is None):
            self._network_start = (downloaded, time.monotonic())
        self.speed = None
        self._window = (downloaded, time.monotonic())

    def update(self, downloaded, *, settled):
        """Recompute speed; ``settled`` means a whole file just finished."""
        if self.source != "network":
            return
        now = time.monotonic()
        if settled and self._network_start is not None:
            start_bytes, start_time = self._network_start
            if now - start_time > 0:
                self.speed = max(0, downloaded - start_bytes) / (now - start_time)
        elif now - self._window[1] >= 0.1:
            window_bytes, window_time = self._window
            self.speed = max(0, downloaded - window_bytes) / (now - window_time)
            self._window = (downloaded, now)

    def status(self):
        """Return "cache", a network rate, or "" before any fetch starts."""
        if self.source == "cache":
            return "cache"
        if self.source == "network":
            return format_rate(self.speed or 0)
        return ""


class WheelFolder:
    """Which wheels in a download destination are completely written."""

    def __init__(self, destination):
        self.destination = Path(destination)
        self.complete = set()
        self._observed_sizes = {}

    def measure(self, *, require_stable):
        """Refresh ``complete`` and return the bytes of every wheel present.

        ``require_stable`` is for while aria2 runs: it can remove its control
        file just before the last write is visible, so a file must also keep
        one size across two samples.  A successful child exit settles all.
        """
        sizes = {}
        for wheel in self.destination.glob("*.whl"):
            with contextlib.suppress(OSError):
                sizes[wheel.name] = wheel.stat().st_size
        complete = set()
        for name, size in sizes.items():
            if Path(str(self.destination / name) + ".aria2").exists():
                continue
            if require_stable and self._observed_sizes.get(name) != size:
                continue
            complete.add(name)
        self.complete = complete
        self._observed_sizes = sizes
        return sum(sizes.values())

    def is_complete(self, name):
        """Whether the wheel file ``name`` was complete at the last measure."""
        return name in self.complete


class DownloadProgress(CountedProgress):
    """Live, plain-language progress for a batch of wheel downloads.

    Progress is measured from the filesystem -- finished wheels in the
    destination plus the partial wheel the child still has open -- rather than
    from pip's wording, which is not a stable interface.  Its output is parsed
    solely to name the file in flight, so a future pip that words it differently
    loses the label and nothing else.
    """

    # pip says "Downloading x.whl (5 MB)" for a fetch and "Using cached x.whl
    # (5 MB)" when it serves the same wheel from its own HTTP cache.
    FETCH_PREFIXES = ("Downloading ", "Using cached ")

    def __init__(self, title, total, destination, stream=None):
        super().__init__(title, total, stream)
        self.folder = WheelFolder(destination)
        self.downloaded = 0
        self.rate = TransferRate()
        # "idle", "active" while aria2 runs, "settling" once it has exited.
        self._parallel = "idle"

    def note(self, line):
        """Record the wheel pip has just started fetching, for display only."""
        text = line.strip()
        for prefix in self.FETCH_PREFIXES:
            if text.startswith(prefix):
                name = text[len(prefix) :].split(" (")[0]
                if not name.endswith(".metadata"):
                    self.current = name
                    source = "network" if prefix == "Downloading " else "cache"
                    self.rate.begin(source, self.downloaded)
                return

    def network_downloads(self, count, concurrent_files, connections_per_file):
        """Describe the real queue and bounded HTTP concurrency."""
        active = min(count, concurrent_files)
        self.current = (
            f"network: {count} queued, up to {active} files x "
            f"{connections_per_file} connections"
        )
        self._parallel = "active"
        self.rate.begin("network", self.downloaded, restart_network=True)

    def parallel_finished(self):
        """Settle final files only after the parallel child has exited."""
        self._parallel = "settling"
        try:
            self.tick()
        finally:
            self._parallel = "idle"

    def parallel_failed(self):
        """Stop treating retry cleanup as an active parallel transfer."""
        self._parallel = "idle"

    def cache_hit(self, filename):
        """Expose verified local-cache reuse without calling it network speed."""
        self.current = f"cache: {filename}"
        self.rate.source = "cache"

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
                if not name.endswith(".whl") or self.folder.is_complete(name):
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
        present = self.folder.measure(require_stable=self._parallel == "active")
        self.done = len(self.folder.complete)
        # There is a moment between pip closing a finished download and copying
        # it into place where neither location holds it.  Reporting the running
        # peak keeps the counter from flicking back to zero, which reads as a
        # failure rather than as the last step of a successful fetch.
        self.downloaded = max(self.downloaded, present + self._inflight_bytes())
        settled = self._parallel == "settling" or self.done > previous_done
        self.rate.update(self.downloaded, settled=settled)

    def _summary(self):
        status = self.rate.status()
        suffix = f", {status}" if status else ""
        return (
            f"{self.done} of {self.total} downloaded "
            f"({format_bytes(self.downloaded)}{suffix})."
        )

    def _heartbeat_facts(self):
        if self.rate.source != "network":
            return None
        return [format_bytes(self.downloaded), self.rate.status()]

    def _meter_line(self):
        filled = round(20 * self.done / self.total) if self.total else 20
        meter = "#" * filled + "-" * (20 - filled)
        line = (
            f"  {self.title} [{meter}] {self.done}/{self.total}  "
            f"{format_bytes(self.downloaded)}"
        )
        status = self.rate.status()
        if status:
            line += f"  {status}"
        return line + f"  {format_elapsed(self.pacer.elapsed())}"


class InstallProgress(CountedProgress):
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
        super().__init__(title, len(expected), stream)
        self.expected = expected
        self._labels = {item["wheel"]: item["label"] for item in expected}

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

    def _summary(self):
        return f"{self.done} of {count_label(self.total, 'package')} in place."

    def _meter_line(self):
        filled = round(20 * self.done / self.total) if self.total else 0
        meter = "#" * filled + "-" * (20 - filled)
        return (
            f"  {self.title} [{meter}] {self.done}/{self.total} in place  "
            f"{format_elapsed(self.pacer.elapsed())}"
        )


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
        self.display = LiveDisplay(stream)
        self.pacer = Pacer(self.LOG_INTERVAL, self.REFRESH_INTERVAL)
        self.sampler = ProcessSampler()
        self._lock = threading.Lock()
        self._state = {
            "phase": "Reading installed package metadata",
            "scope": None,
            "found": None,
            "success": None,
        }

    def _set(self, **changes):
        with self._lock:
            self._state.update(changes)

    def set_phase(self, phase):
        """Record the scan stage shown to the user."""
        self._set(phase=phase)

    def set_scope(self, count):
        """Record how many installed distributions the scan covers."""
        self._set(scope=count)

    def set_found(self, count):
        """Record how many eligible updates the scan found."""
        self._set(found=count)

    def watch(self, pid):
        """Attach the running scan process for CPU and RAM sampling."""
        self.sampler.watch(pid)

    def redirect(self, stream):
        """Draw on ``stream`` from now on (a background scan gets a screen)."""
        self.display = LiveDisplay(stream)

    def snapshot(self):
        """Return a consistent copy of the measured scan state."""
        with self._lock:
            state = dict(self._state)
        state["cpu_percent"], state["rss_bytes"] = self.sampler.readings()
        return state

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
        """Return the three dashboard rows, each cut to max_width."""
        snap = self.snapshot()
        elapsed_seconds = self.pacer.elapsed()
        state = {True: "complete", False: "failed"}.get(snap["success"], "running")
        line1 = (
            f"  Live package scan activity "
            f"[{self._activity_bar(elapsed_seconds, snap['success'])}] "
            f"{state} | {format_elapsed(elapsed_seconds)}"
        )
        line2 = f"  Stage: {snap['phase']}"
        facts = []
        if snap["scope"] is not None:
            facts.append(f"scope {count_label(snap['scope'], 'installed package')}")
        if self.cached_count is not None:
            facts.append(f"cached result {count_label(self.cached_count, 'update')}")
        if snap["found"] is not None:
            facts.append(f"found {count_label(snap['found'], 'update')}")
        facts.extend(process_figures(snap["cpu_percent"], snap["rss_bytes"]))
        line3 = "  " + (" | ".join(facts) or "Starting scan process...")
        return [truncate_label(line, max_width) for line in (line1, line2, line3)]

    def compact_status(self, max_width):
        """Return a one-line scan summary for the selector header."""
        snap = self.snapshot()
        elapsed = self.pacer.elapsed()
        text = (
            f" Scan [{self._activity_bar(elapsed, snap['success'])}] "
            f"{snap['phase']} | {format_elapsed(elapsed)}"
        )
        return truncate_label(text, max_width)

    def paint(self, *, force=False):
        """Redraw in place on a terminal; otherwise log at LOG_INTERVAL."""
        if self.display.interactive:
            if self.pacer.paint_due(force=force):
                self.sampler.sample()
                self.display.draw(self.terminal_lines(self.display.width()))
            return
        self.sampler.sample()
        if self.pacer.log_due(force=force):
            fields = [line.strip() for line in self.terminal_lines(10_000)]
            self.display.log("  " + " | ".join(fields))

    def tick(self):
        """Repaint when rendering (paint throttles); otherwise just sample."""
        if self.render:
            self.paint()
        else:
            self.sampler.sample()

    def finish(self, success):
        """Mark the scan finished and draw its final state."""
        self.sampler.stop()
        self._set(
            success=success,
            phase=(
                "Package index scan complete"
                if success
                else "Package index scan failed"
            ),
        )
        if self.render:
            self.paint(force=True)
            self.end_display()

    def end_display(self):
        """Move below an in-place dashboard so later output starts clean."""
        self.display.end()


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
    # Shells without `conda init` (cron, systemd, env -i) have neither of the
    # above, but the shebang runs Conda's own base interpreter.
    bundled = Path(sys.prefix) / "bin" / "conda"
    if bundled.is_file() and os.access(bundled, os.X_OK):
        return str(bundled)
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


def _local_build(version):
    """Return the normalized local label of a version: `cu130` of `2.10+cu130`."""
    return re.sub(r"[-_]", ".", str(version).partition("+")[2].lower())


def build_change(installed, newest):
    """Say why ``newest`` would swap the installed build for another, or None.

    A local label names a build from a specific index (PyTorch's +cu130
    wheels).  A newest release with a different label is not an update of
    that build: installing it replaces, say, CUDA 13.0 torch with PyPI's.
    """
    if _local_build(installed) == _local_build(newest):
        return None
    return f"{newest} is a different build than the installed {installed}"


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


def _group_inventory(rows):
    grouped = {}
    for row in rows:
        if not isinstance(row, dict) or not row.get("name"):
            continue
        grouped.setdefault(canonicalize_name(row["name"]), []).append(row)
    return grouped


def index_inventory(rows, prefix):
    """Index inventory by normalized name and reject ambiguous metadata."""
    grouped = _group_inventory(rows)
    duplicates = {name: items for name, items in grouped.items() if len(items) != 1}
    if duplicates:
        raise UpdaterError(explain_duplicate_metadata(duplicates, prefix))
    return {name: items[0] for name, items in grouped.items()}


def repair_stale_duplicate_metadata(prefix, *, dry_run):
    """Move aside duplicate package records that file hashes prove stale.

    Moving is recoverable (rename the directory back) and never deletes a
    file.  Copies the evidence cannot tell apart are left for
    explain_duplicate_metadata to report, because guessing could break the
    package.
    """
    ledgers = InstallLedgers(prefix)
    grouped = _group_inventory(get_environment_inventory(prefix))
    for name, items in sorted(grouped.items()):
        if len(items) < 2:
            continue
        evidence, current = _duplicate_verdict(items, ledgers)
        if current is None:
            continue
        for path in sorted(evidence.keys() - {current}):
            destination = path + STALE_METADATA_SUFFIX
            if dry_run:
                announce("PREVIEW", f"Would move the stale {name} record {path} aside.")
                continue
            if not _is_within(path, prefix):
                raise UpdaterError(f"Refusing to move {path}: it is outside {prefix}.")
            if os.path.lexists(destination):
                raise UpdaterError(
                    f"Cannot move the stale {name} record aside: {destination} "
                    "already exists."
                )
            os.rename(path, destination)
            announce(
                "OK",
                f"Moved the stale {name} record aside: {destination} "
                "(rename it back to undo).",
            )


def file_sha256(path):
    """Return the SHA-256 hash object of a file, read in bounded chunks."""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest


def _hash_field(digest):
    """Return a SHA-256 digest in RECORD's ``sha256=`` form."""
    return "sha256=" + base64.urlsafe_b64encode(digest).rstrip(b"=").decode()


def _file_hash_field(path):
    """Return a file's hash in RECORD's ``sha256=`` form, or None if unreadable."""
    try:
        return _hash_field(file_sha256(path).digest())
    except OSError:
        return None


def _record_hashes(metadata_path, prefix_path):
    """Map the prefix-relative paths one RECORD hashes to their hash fields.

    Returns None without a readable RECORD.  Paths resolving outside the prefix
    are left out, so a RECORD cannot direct a read elsewhere.
    """
    try:
        with open(
            metadata_path / "RECORD", newline="", encoding="utf-8", errors="replace"
        ) as handle:
            rows = list(csv.reader(handle))
    except OSError:
        return None
    hashes = {}
    for row in rows:
        if len(row) < 2 or not row[0] or not row[1].startswith("sha256="):
            continue
        target = (metadata_path.parent / Path(row[0])).resolve(strict=False)
        if _is_within(target, prefix_path):
            hashes[target.relative_to(prefix_path).as_posix()] = row[1]
    return hashes


def _is_noarch_python(record):
    noarch = record.get("noarch")
    if isinstance(noarch, dict):
        noarch = noarch.get("type")
    return noarch == "python" or record.get("package_type") == "noarch_python"


def _noarch_python_target(path, site_packages):
    """Map a noarch: python package path to where Conda installed it.

    Mirrors Conda's own link step: ``site-packages/`` goes to the environment's
    site-packages and ``python-scripts/`` to ``bin/``.
    """
    head, _, rest = path.partition("/")
    if head == "site-packages" and rest and site_packages:
        return f"{site_packages}/{rest}"
    if head == "python-scripts" and rest:
        return f"bin/{rest}"
    return path


def _conda_record_hashes(record, site_packages):
    """Map the prefix-relative files one Conda record hashes to hash fields.

    Conda hashes each file as packaged and, when it rewrites the file while
    installing (``file_mode``), again as installed in ``sha256_in_prefix``.
    Only the installed hash describes the file on disk, so a rewritten file
    without one is left out, as are links and files compiled at install time,
    which carry no hash.  A noarch: python record names its files by their
    paths inside the package, so each is mapped to where it was installed and
    kept only if the record's ``files`` list confirms that location.
    """
    installed_files = {
        path for path in record.get("files", []) if isinstance(path, str)
    }
    noarch_python = _is_noarch_python(record)
    paths_data = record.get("paths_data")
    entries = paths_data.get("paths") if isinstance(paths_data, dict) else None
    hashes = {}
    for entry in entries if isinstance(entries, list) else ():
        if not isinstance(entry, dict) or entry.get("path_type") == "softlink":
            continue
        relative = entry.get("_path")
        installed = entry.get("sha256_in_prefix")
        if installed is None and not entry.get("file_mode"):
            installed = entry.get("sha256")
        if not isinstance(relative, str) or not isinstance(installed, str):
            continue
        if noarch_python:
            relative = _noarch_python_target(relative, site_packages)
        posix_path = PurePosixPath(relative)
        if (
            relative not in installed_files
            or posix_path.is_absolute()
            or ".." in posix_path.parts
        ):
            continue
        with contextlib.suppress(ValueError):
            hashes[relative] = _hash_field(bytes.fromhex(installed))
    return hashes


def conda_metadata_hashes(prefix_path):
    """Map each Python metadata directory Conda installed to its record's hashes.

    Keys are prefix-relative directories such as
    ``lib/python3.13/site-packages/setuptools-80.10.2-py3.13.egg-info``.  An
    unreadable record is skipped, so it vouches for nothing.
    """
    ledgers = {}
    for record_path in sorted((prefix_path / "conda-meta").glob("*.json")):
        try:
            record = json.loads(record_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(record, dict):
            continue
        directories = {
            PurePosixPath(raw_path).parent
            for raw_path in record.get("files", [])
            if isinstance(raw_path, str)
            and is_distribution_metadata(PurePosixPath(raw_path))
        }
        if not directories:
            continue
        # One site-packages is required to place noarch files; with none
        # placed, the record simply offers no evidence.
        site_dirs = {directory.parent.as_posix() for directory in directories}
        site_packages = site_dirs.pop() if len(site_dirs) == 1 else None
        hashes = _conda_record_hashes(record, site_packages)
        ledgers.update(
            dict.fromkeys((directory.as_posix() for directory in directories), hashes)
        )
    return ledgers


def _verify_hashed_file(root, relative, hash_field):
    """Check one hashed file: "matched", "changed", "missing" or None.

    None means the path resolves outside ``root`` and is not read at all.
    """
    target = root.joinpath(*PurePosixPath(relative).parts)
    if not _is_within(target, root):
        return None
    try:
        actual = _file_hash_field(target) if target.is_file() else None
    except OSError:
        actual = None
    if actual is None:
        return "missing"
    return "matched" if actual == hash_field else "changed"


class InstallLedgers:
    """Each installed copy's own ledger of its files and their SHA-256 hashes.

    pip keeps that ledger in the copy's RECORD and Conda in its conda-meta
    record.  A Conda egg-info copy has no RECORD at all, so judging copies by
    RECORD alone cannot tell it from a pip copy of the same package; that is
    what cloning or renaming an environment in which pip had replaced a Conda
    package leaves behind.  Conda's records are read only when first needed.
    """

    def __init__(self, prefix):
        self.prefix_path = Path(prefix).resolve(strict=False)
        self._conda = None

    def hashes(self, row):
        """Return (ledger name, {prefix-relative path: hash field}) for a copy.

        Conda's record judges a copy Conda installed.  pip's RECORD judges pip's
        copies, including one pip reinstalled into a Conda directory of the same
        name, because pip then rewrote its RECORD and INSTALLER.  (None, {})
        means the copy has no ledger to check.
        """
        metadata_path = Path(row.get("metadata_path") or "")
        if not row.get("metadata_path") or not _is_within(
            metadata_path, self.prefix_path
        ):
            return None, {}
        if row.get("installer") != "pip":
            if self._conda is None:
                self._conda = conda_metadata_hashes(self.prefix_path)
            relative = metadata_path.resolve(strict=False).relative_to(self.prefix_path)
            conda_hashes = self._conda.get(relative.as_posix())
            if conda_hashes is not None:
                return "Conda record", conda_hashes
        record_hashes = _record_hashes(metadata_path, self.prefix_path)
        return ("RECORD", record_hashes) if record_hashes is not None else (None, {})

    def evidence(self, row):
        """Compare one copy's ledger with the files on disk; None without one.

        The copy's own metadata directory is skipped: a RECORD cannot hash
        itself, and INSTALLER changes when another tool reinstalls in place.
        """
        source, hashes = self.hashes(row)
        if source is None:
            return None
        own = (
            Path(row["metadata_path"])
            .resolve(strict=False)
            .relative_to(self.prefix_path)
            .as_posix()
            + "/"
        )
        claims = {relative for relative in hashes if not relative.startswith(own)}
        counts = {"matched": 0, "changed": 0, "missing": 0}
        for relative in claims:
            outcome = _verify_hashed_file(self.prefix_path, relative, hashes[relative])
            if outcome:
                counts[outcome] += 1
        return {"source": source, "claims": claims, **counts}


def _duplicate_verdict(items, ledgers):
    """Return (evidence, current) for one package's metadata copies.

    ``evidence`` maps each copy with a ledger to its InstallLedgers.evidence.
    ``current`` is the one copy whose every hash matches the files on disk
    while every other copy has a mismatch, or None when the hashes do not
    single one out.  Version numbers and path overlap are never used: either
    copy may be the stale one.
    """
    evidence = {}
    for item in items:
        found = ledgers.evidence(item)
        if found is not None:
            evidence[item["metadata_path"]] = found
    current = [
        path
        for path, found in evidence.items()
        if found["matched"] and not found["changed"] and not found["missing"]
    ]
    stale = [
        path for path, found in evidence.items() if found["changed"] or found["missing"]
    ]
    decided = (
        len(evidence) == len(items)
        and len(current) == 1
        and len(stale) == len(items) - 1
    )
    return evidence, (current[0] if decided else None)


def _evidence_summary(found):
    """Summarize one copy's hash check for a copy that could not be judged."""
    if found is None:
        return "no RECORD or Conda record to check it against"
    counts = [
        f"{found[key]} {word}"
        for key, word in (
            ("matched", "matches" if found["matched"] == 1 else "match"),
            ("changed", "differs" if found["changed"] == 1 else "differ"),
            ("missing", "missing"),
        )
        if found[key]
    ]
    return f"{found['source']}: {', '.join(counts) or 'no file hashes to check'}"


def _stale_copy_lines(path, found, current_claims):
    """Describe one stale metadata copy and any files only it claims."""
    problems = found["changed"] + found["missing"]
    source = found["source"]
    problem_label = count_label(problems, f"{source} hash", f"{source} hashes")
    verb = "differs" if problems == 1 else "differ"
    lines = [f"    {path}  (stale: {problem_label} {verb})"]
    old_only = len(found["claims"] - current_claims)
    if old_only:
        lines += [
            f"      It also lists {count_label(old_only, 'file')} that the",
            "      current records do not claim. Moving this metadata does",
            "      not delete those files.",
        ]
    return lines


def explain_duplicate_metadata(duplicates, prefix):
    """Explain duplicate records and quarantine only demonstrably stale copies.

    An upgrade normally replaces a package's records; when that clean-up does
    not happen the old directory stays behind and the environment now claims two
    versions of one package at once.  The updater cannot tell which one an
    update is meant to replace, so it stops.
    """
    ledgers = InstallLedgers(prefix)
    lines = [
        "Two sets of records exist for the same package, so this environment",
        "cannot be updated safely -- there is no way to tell which copy an",
        "update is meant to replace.",
        "",
        "This is commonly left by an upgrade that did not finish cleaning up,",
        "or by cloning or renaming an environment in which pip had replaced a",
        "Conda package. Each copy is checked against its installer's own file",
        "hashes (pip's RECORD or Conda's record) before one is called stale.",
        "",
    ]
    removable = []
    for name, items in sorted(duplicates.items()):
        lines.append(f"  {name}:")
        evidence, current = _duplicate_verdict(items, ledgers)
        if current is None:
            lines += [
                f"    {item['metadata_path']}  "
                f"({_evidence_summary(evidence.get(item['metadata_path']))})"
                for item in sorted(
                    items, key=lambda row: row.get("metadata_path") or ""
                )
                if item.get("metadata_path")
            ]
            lines.append("    The hashes do not single out one current copy, so")
            lines.append(
                "    moving either one could break the package. Check by hand."
            )
            continue
        found = evidence[current]
        lines.append(f"    {current}  (all {found['source']} hashes match)")
        for path in sorted(evidence.keys() - {current}):
            lines += _stale_copy_lines(path, evidence[path], found["claims"])
            removable.append(path)
    if removable:
        lines += [
            "",
            "A real (not --dry-run) run moves each stale record directory aside",
            "automatically before updating; it is recoverable by renaming back:",
            "",
        ]
        lines += [f"  {path}{STALE_METADATA_SUFFIX}" for path in removable]
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


def _metadata_directory_name(posix_path):
    """Return the distribution name encoded in a .dist-info/.egg-info path."""
    stem = re.sub(
        r"\.(dist|egg)-info$", "", posix_path.parent.name, flags=re.IGNORECASE
    )
    return re.split(r"-(?=\d)", stem, maxsplit=1)[0]


def is_distribution_metadata(posix_path):
    """Whether a record path is the metadata of a distribution pip can see.

    Only metadata directly in site-packages names a distribution; a copy such
    as setuptools/_vendor/tomli-*.dist-info is part of the vendoring package.
    """
    return (
        posix_path.as_posix()
        .lower()
        .endswith((".dist-info/metadata", ".egg-info/pkg-info"))
        and posix_path.parent.parent.name.lower() == "site-packages"
    )


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
            owned_paths.add(posix_path.as_posix())
            if is_distribution_metadata(posix_path):
                name = _metadata_name(
                    prefix_path / Path(*posix_path.parts)
                ) or _metadata_directory_name(posix_path)
                if name:
                    distribution_names.add(canonicalize_name(name))
    return {
        "distributions": distribution_names,
        "paths": owned_paths,
        "records_digest": digest.hexdigest(),
    }


def filter_outdated_packages(packages, inventory, conda_ownership, prefix):
    """Split pip's outdated list into eligible and excluded distributions."""
    inventory_by_name = index_inventory(inventory, prefix)
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
        elif installed.get("installer") not in UPDATABLE_INSTALLERS:
            reason = f"installer is {installed.get('installer') or 'unknown'}"
        elif not _is_within(installed.get("metadata_path", ""), prefix):
            reason = "outside the selected environment"
        elif installed.get("direct_url"):
            reason = "editable/direct-URL installs are not reproducible"
        elif not SAFE_PROJECT_NAME.fullmatch(name):
            reason = "invalid or unsafe project name"
        elif swap := build_change(
            installed.get("version") or "", package.get("latest_version") or ""
        ):
            reason = swap
        else:
            reason = _still_valid_hold(
                package, holds.get(normalized), inventory_by_name
            )

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


def _installed_version(inventory_by_name, name):
    """Return the installed version of ``name`` as text, "" when absent."""
    row = inventory_by_name.get(canonicalize_name(str(name))) or {}
    return str(row.get("version") or "")


def _still_valid_hold(package, hold, inventory_by_name):
    """Return an exclusion reason if a recorded resolver hold still applies.

    A hold is trusted only while nothing that produced it has moved: the held
    package's newest release and installed version are unchanged, and every
    capping package is still installed at the recorded version (or, for a cap
    that could not be named, the whole environment is exactly as planned).
    Anything else returns None so the package is offered again and the
    resolver retests it for real.
    """
    if (
        not isinstance(hold, dict)
        or hold.get("latest") != str(package.get("latest_version", "?"))
        or hold.get("installed") != str(package.get("version", "?"))
    ):
        return None
    cappers = hold.get("cappers")
    if isinstance(cappers, dict) and cappers:
        unchanged = all(
            _installed_version(inventory_by_name, name) == str(version)
            for name, version in cappers.items()
        )
        return "held back by " + ", ".join(sorted(cappers)) if unchanged else None
    fingerprint = hold.get("environment")
    current = {
        name: str(row.get("version") or "") for name, row in inventory_by_name.items()
    }
    if fingerprint and fingerprint == inventory_fingerprint(current):
        return "held back by installed package requirements"
    return None


def scan_outdated_packages(prefix, *, report_exclusions=False, progress=None):
    """Scan reproducibly updatable packages with live, truthful telemetry."""
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
                # Must match the resolver and downloader, which install
                # verified wheels only; otherwise a source-only release is
                # listed as outdated on every run and never installs.
                "--only-binary=:all:",
            ],
            timeout=300,
            merge_stderr=False,
            hooks=StreamHooks(on_start=progress.watch, on_tick=progress.tick),
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

    print_section(f"Skipped automatically ({len(excluded)}) — no action is needed:")
    if conda_managed:
        print_labeled(
            "Conda-managed:",
            ", ".join(conda_managed) + " (pip must not replace these)",
        )
    if protected:
        print_labeled(
            "Core update tools:",
            ", ".join(protected) + " (protected so the updater cannot break itself)",
        )
    if held:
        print_labeled(
            "Version-capped:",
            ", ".join(held) + " (an installed package pins each of these; they "
            "will be offered again once the capping package updates)",
        )
    for name, reason in other:
        print_labeled(f"{name}:", f"skipped for safety ({reason})")


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
    # A thread boundary must publish every failure, or the selector would wait
    # on a scan that never reports back.
    except Exception as exc:  # noqa: BLE001  # pylint: disable=broad-exception-caught
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
    progress.redirect(stream)
    print("\nFinishing the live package scan...", file=stream, flush=True)
    while thread.is_alive():
        progress.paint()
        thread.join(timeout=PackageScanProgress.REFRESH_INTERVAL)
    progress.paint(force=True)
    progress.end_display()
    return True


def _init_curses_colors():
    """Hide the cursor; return the hint and success color attributes.

    Both are 0 when the terminal has no colors.
    """
    curses.curs_set(0)
    try:
        curses.use_default_colors()
        curses.init_pair(2, curses.COLOR_CYAN, -1)
        curses.init_pair(3, curses.COLOR_GREEN, -1)
        return curses.color_pair(2), curses.color_pair(3) | curses.A_BOLD
    except curses.error:
        # Some terminals don't support colors; keep rendering without color attributes.
        return 0, 0


def _check_mark(window):
    """Return a check mark the window's encoding can draw."""
    try:
        "✓".encode(window.encoding)
    except (UnicodeEncodeError, LookupError):
        return "[ok]"
    return "✓"


class ListCursor:
    """Cursor row and scroll offset of a vertically scrolling curses list."""

    def __init__(self):
        self.cursor = 0
        self.scroll = 0

    def follow(self, visible):
        """Scroll just far enough that the cursor row is on screen."""
        if self.cursor < self.scroll:
            self.scroll = self.cursor
        elif self.cursor >= self.scroll + visible:
            self.scroll = self.cursor - visible + 1

    def navigate(self, key, total, visible):
        """Apply a movement key; return False for any other key."""
        if key in (curses.KEY_UP, ord("k")):
            self.cursor = max(0, self.cursor - 1)
        elif key in (curses.KEY_DOWN, ord("j")):
            self.cursor = min(total - 1, self.cursor + 1)
        elif key == curses.KEY_HOME:
            self.cursor = 0
        elif key == curses.KEY_END:
            self.cursor = total - 1
        elif key == curses.KEY_PPAGE:
            self.cursor = max(0, self.cursor - visible)
        elif key == curses.KEY_NPAGE:
            self.cursor = min(total - 1, self.cursor + visible)
        else:
            return False
        return True


def _read_selector_state(package_state):
    with package_state["lock"]:
        state = {
            key: package_state[key]
            for key in (
                "scan_in_progress",
                "scan_done",
                "scan_error",
                "cache_mismatch",
                "started_from_cache",
            )
        }
        state["packages"] = list(package_state["packages"])
        state["scan_progress"] = package_state.get("scan_progress")
    return state


def _scan_status(state, width):
    """Return the selector's one-line report on the live background scan."""
    from_cache_done = state["started_from_cache"] and state["scan_done"]
    if state["scan_error"]:
        return f" Live refresh failed: {state['scan_error']}"
    if state["scan_in_progress"] and state["scan_progress"] is not None:
        return state["scan_progress"].compact_status(width)
    if from_cache_done and state["cache_mismatch"]:
        return " Live scan updated this list (cache was stale)."
    if from_cache_done:
        return " Live scan confirmed cached results."
    return " "


def _all_selected(packages, selected):
    return bool(packages) and all(pkg["name"].lower() in selected for pkg in packages)


def _package_row(idx, packages, selected):
    """Text of list row ``idx``: update-all, a package, or the confirm button."""
    if idx == 0:
        mark = "[x]" if _all_selected(packages, selected) else "[ ]"
        return f"  {mark}  ** UPDATE ALL **"
    if idx <= len(packages):
        pkg = packages[idx - 1]
        mark = "[x]" if pkg["name"].lower() in selected else "[ ]"
        return (
            f"  {mark}  {pkg['name']:<40} {pkg['version']:>12} "
            f"-> {pkg['latest_version']}"
        )
    selected_count = sum(1 for pkg in packages if pkg["name"].lower() in selected)
    return f"  >>> CONFIRM ({selected_count} selected) <<<"


def _toggled(cursor, packages, selected):
    """Return the selection after toggling the row under the cursor."""
    if cursor == 0:
        if _all_selected(packages, selected):
            return set()
        return {pkg["name"].lower() for pkg in packages}
    if 1 <= cursor <= len(packages):
        return selected ^ {packages[cursor - 1]["name"].lower()}
    return selected


class _PackageSelector:
    """Curses package checklist whose list a background scan may replace."""

    LIST_TOP = 4

    def __init__(self, stdscr, package_state, allow_back):
        self.stdscr = stdscr
        self.package_state = package_state
        self.allow_back = allow_back
        self.hint_attr = _init_curses_colors()[0]
        self.selected = set()
        self.nav = ListCursor()

    def run(self):
        """Return chosen names, [] to quit, or BACK_TO_ENV."""
        self.stdscr.timeout(150)
        while True:
            packages, visible = self.draw()
            key = self.stdscr.getch()
            if key == -1:
                continue
            result = self.handle_key(key, packages, visible)
            if result is not None:
                return result

    def draw(self):
        """Paint one frame; return the listed packages and visible row count."""
        state = _read_selector_state(self.package_state)
        packages = state["packages"]
        self.selected &= {pkg["name"].lower() for pkg in packages}
        total = len(packages) + 2  # update all + packages + confirm
        self.nav.cursor = min(self.nav.cursor, total - 1)

        self.stdscr.clear()
        height, width = self.stdscr.getmaxyx()
        safe_w = max(1, width - 1)
        self._draw_header(len(packages), _scan_status(state, safe_w), safe_w)

        # Reserve 2 rows at bottom: blank + confirm button
        visible = max(height - self.LIST_TOP - 2, 1)
        self.nav.follow(visible)
        for offset in range(min(visible, total - self.nav.scroll)):
            idx = self.nav.scroll + offset
            line = _package_row(idx, packages, self.selected)
            attr = curses.A_REVERSE if idx == self.nav.cursor else 0
            self.stdscr.addnstr(
                self.LIST_TOP + offset, 0, line.ljust(safe_w), safe_w, attr
            )
        self.stdscr.refresh()
        return packages, visible

    def _draw_header(self, package_count, status, safe_w):
        self.stdscr.addnstr(
            0,
            0,
            f" {package_count} package(s) eligible for update",
            safe_w,
            curses.A_BOLD,
        )
        help_line = " [SPACE] Toggle  [a] All  [n] None  [ENTER] Confirm"
        if self.allow_back:
            help_line += "  [b] Back"
        help_line += "  [q] Quit"
        self.stdscr.addnstr(1, 0, help_line, safe_w, self.hint_attr)
        self.stdscr.addnstr(2, 0, status.ljust(safe_w), safe_w, self.hint_attr)
        self.stdscr.addnstr(3, 0, "-" * safe_w, safe_w)

    def handle_key(self, key, packages, visible):
        """Apply one key; return the selector's result, or None to continue."""
        if key in (ord("q"), 27):
            return []
        if self.allow_back and key == ord("b"):
            return BACK_TO_ENV
        if self.nav.navigate(key, len(packages) + 2, visible):
            return None
        enter = key in (10, 13, curses.KEY_ENTER)
        if enter and self.nav.cursor == len(packages) + 1:
            return [
                pkg["name"] for pkg in packages if pkg["name"].lower() in self.selected
            ]
        if enter or key == ord(" "):
            self.selected = _toggled(self.nav.cursor, packages, self.selected)
        elif key == ord("a"):
            self.selected = {pkg["name"].lower() for pkg in packages}
        elif key == ord("n"):
            self.selected = set()
        return None


def interactive_select(stdscr, package_state, allow_back=False):
    """Curses package selector that can live-refresh when background scan completes."""
    return _PackageSelector(stdscr, package_state, allow_back).run()


class _EnvironmentSelector:
    """Curses list of conda environments to pick one from."""

    LIST_TOP = 3

    def __init__(self, stdscr, env_names, finished):
        self.stdscr = stdscr
        self.env_names = env_names
        self.finished = finished
        self.hint_attr, self.ok_attr = _init_curses_colors()
        self.mark = _check_mark(stdscr)
        self.nav = ListCursor()

    def run(self):
        """Return the chosen environment name, or None to quit."""
        while True:
            visible = self.draw()
            key = self.stdscr.getch()
            if key in (ord("q"), 27):
                return None
            if key in (10, 13, curses.KEY_ENTER):
                return self.env_names[self.nav.cursor]
            self.nav.navigate(key, len(self.env_names), visible)

    def draw(self):
        """Paint one frame; return the visible row count."""
        self.stdscr.clear()
        height, width = self.stdscr.getmaxyx()
        safe_w = max(1, width - 1)
        self.stdscr.addnstr(0, 0, " Select a conda environment", safe_w, curses.A_BOLD)
        self.stdscr.addnstr(
            1, 0, " [UP/DOWN] Move  [ENTER] Select  [q] Quit", safe_w, self.hint_attr
        )
        self.stdscr.addnstr(2, 0, "-" * safe_w, safe_w)

        visible = max(height - self.LIST_TOP, 1)
        self.nav.follow(visible)
        shown = self.env_names[self.nav.scroll : self.nav.scroll + visible]
        for offset, name in enumerate(shown):
            attr = (
                curses.A_REVERSE if self.nav.scroll + offset == self.nav.cursor else 0
            )
            line = f"  {name}"
            if name in self.finished:
                line += f" {self.mark}"
                attr |= self.ok_attr
            self.stdscr.addnstr(
                self.LIST_TOP + offset, 0, line.ljust(safe_w), safe_w, attr
            )
        self.stdscr.refresh()
        return visible


def interactive_select_env(stdscr, env_names, finished=frozenset()):
    """Curses-based selector for conda environment names.

    Environments in ``finished`` were updated successfully or found to have
    nothing to update earlier in this run, and are shown in green with a
    check mark.
    """
    return _EnvironmentSelector(stdscr, env_names, finished).run()


def _conda_json(conda, args, action):
    """Run a read-only ``conda ... --json`` command and parse its output.

    ``action`` names the step in errors, e.g. "Reading conda information".
    """
    result = run_command([conda, *args], capture_output=True, timeout=60)
    if result.returncode != 0:
        raise command_failure(action, result)
    return parse_json_output(result.stdout, action[:1].lower() + action[1:])


def environment_labels(env_paths, root_prefix):
    """Map each selectable name to an environment prefix.

    "base" is reserved for Conda's root prefix, and a basename shared by
    several registered environments is ambiguous.  In both cases the short
    name is withheld so selection can only happen through the exact prefix;
    giving it to whichever environment Conda happened to list first would
    silently pick one of them.
    """
    resolved = []
    for raw_path in env_paths:
        if not raw_path:
            continue
        prefix = str(Path(raw_path).resolve())
        if prefix not in resolved:
            resolved.append(prefix)
    others = [prefix for prefix in resolved if prefix != root_prefix]
    basename_counts = {}
    for prefix in others:
        name = Path(prefix).name
        basename_counts[name] = basename_counts.get(name, 0) + 1

    labels = {"base": root_prefix}
    for prefix in others:
        name = Path(prefix).name
        if name == "base" or basename_counts[name] > 1:
            labels[prefix] = prefix
        else:
            labels[name] = prefix
    return labels


def get_known_environments():
    """Return display-name-to-prefix mapping and Conda's root prefix."""
    conda = conda_executable()
    info = _conda_json(conda, ["info", "--json"], "Reading conda information")
    raw_root_prefix = info.get("root_prefix") or info.get("default_prefix")
    if not raw_root_prefix:
        raise UpdaterError("Conda did not report a root prefix.")
    root_prefix = str(Path(raw_root_prefix).resolve())
    env_paths = _conda_json(
        conda, ["env", "list", "--json"], "Listing conda environments"
    ).get("envs", [])
    return environment_labels(env_paths, root_prefix), root_prefix


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
    announce(
        "OK",
        f"Activated Conda environment '{Path(prefix).name}'.",
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
    print()
    announce(
        "!",
        f"{count_label(len(conflicts), 'package conflict')} already existed "
        "here before the updater started:",
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
    print()
    announce(
        "!",
        "Conda reports "
        f"{count_label(total, 'dependency mismatch', 'dependency mismatches')} "
        "in this environment:",
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


def pip_replaced_conda_packages(prefix, conda_names):
    """Find named Conda packages that pip has since installed over.

    Conda's record lists the package's own .dist-info directory, which pip
    removes when it replaces the package, so the Python distribution name comes
    from that recorded path rather than from metadata that may now be pip's.
    Returns {conda package: [{"distribution", "conda_version", "pip_version"}]}.
    """
    wanted = set(conda_names)
    distributions = {}
    meta_dir = Path(prefix) / "conda-meta"
    for record_path in sorted(meta_dir.glob("*.json")):
        try:
            record = json.loads(record_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(record, dict) or record.get("name") not in wanted:
            continue
        for raw_path in record.get("files", []):
            if not isinstance(raw_path, str):
                continue
            posix_path = PurePosixPath(raw_path)
            if not is_distribution_metadata(posix_path):
                continue
            name = _metadata_directory_name(posix_path)
            if name:
                distributions[canonicalize_name(name)] = (
                    record["name"],
                    str(record.get("version") or ""),
                )
    if not distributions:
        return {}
    try:
        rows = get_environment_inventory(prefix)
    except UpdaterError:
        return {}
    replaced = {}
    for row in rows:
        if not isinstance(row, dict) or row.get("installer") != "pip":
            continue
        owner = distributions.get(canonicalize_name(row.get("name") or ""))
        if owner:
            replaced.setdefault(owner[0], []).append(
                {
                    "distribution": str(row["name"]),
                    "conda_version": owner[1],
                    "pip_version": str(row.get("version") or ""),
                }
            )
    return replaced


def explain_conda_file_damage(sections, snapshot):
    """Explain Conda file damage found where it cannot be repaired right now."""
    damaged = []
    for section in sections:
        for name in damaged_conda_packages(section["detail"]):
            if name not in damaged:
                damaged.append(name)
    return (
        "Conda reports altered or missing files in "
        f"{', '.join(damaged) or 'one or more packages'}.\n\n"
        "This appeared after the updater's health check, so nothing was\n"
        "changed. Run the updater again: it repairs this automatically before\n"
        "updating.\n\nConda's full report:\n" + snapshot
    )


CONDA_DIST_PATTERN = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.+!]*(?:-[A-Za-z0-9_.+!]+){2}")


def damaged_conda_dists(lines):
    """Extract Conda record names ("name-version-build") from doctor output.

    Handles both the summary form ("setuptools-83.0.0-py313_0: 61") and the
    --verbose form, where the record name ends in a colon and the damaged
    paths follow on indented lines.
    """
    dists = []
    for raw_line in lines:
        head, separator, count = raw_line.strip().rpartition(":")
        head = head.strip()
        if not separator or (count.strip() and not count.strip().isdigit()):
            continue
        if CONDA_DIST_PATTERN.fullmatch(head) and head not in dists:
            dists.append(head)
    return dists


def _conda_record(prefix, dist):
    path = Path(prefix) / "conda-meta" / f"{dist}.json"
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise UpdaterError(
            f"Conda reports damage in {dist}, but its record {path} is unreadable."
        ) from exc
    fields = [
        record.get(key) if isinstance(record, dict) else None
        for key in ("name", "version", "build")
    ]
    if not all(isinstance(value, str) and value for value in fields):
        raise UpdaterError(f"Conda's record {path} lacks a name, version or build.")
    name, version, build = fields
    return {"dist": dist, "name": name, "version": version, "build": build}


def damaged_conda_records(prefix, sections):
    """Return the Conda records of every package the doctor report names.

    A report that names nothing is completed from `conda doctor --verbose`.
    """
    dists = damaged_conda_dists(
        line for section in sections for line in section["detail"]
    )
    if not dists:
        result = run_command(
            [
                conda_executable(),
                "doctor",
                "-p",
                str(prefix),
                "altered-files",
                "missing-files",
                "--verbose",
            ],
            capture_output=True,
            timeout=300,
        )
        if result.returncode != 0:
            raise command_failure(
                f"Running conda doctor --verbose for {prefix}", result
            )
        dists = damaged_conda_dists(result.stdout.splitlines())
    return [_conda_record(prefix, dist) for dist in dists]


def _refuse_breaking_restore(prefix, replaced):
    """Stop if an installed package needs pip's version over Conda's."""
    held = {
        canonicalize_name(entry["distribution"]): (
            entry["distribution"],
            entry["conda_version"],
        )
        for entries in replaced.values()
        for entry in entries
    }
    inventory = index_inventory(get_environment_inventory(prefix), prefix)
    reasons = holdback_reasons(held, inventory, [], marker_environment(prefix))
    if not reasons:
        return
    lines = [
        "Conda's files are damaged because pip installed its own copy over",
        "Conda's, and restoring Conda's version would break other packages:",
        "",
    ]
    for normalized, causes in sorted(reasons.items()):
        name, conda_version = held[normalized]
        lines.append(
            f"  Conda's {name} {conda_version}: "
            + "; ".join(dict.fromkeys(cause["text"] for cause in causes))
        )
    lines += [
        "",
        "The updater will not trade one breakage for another, so nothing was",
        "changed. Update or remove the packages named above so they accept",
        "Conda's version, then run the updater again.",
    ]
    raise UpdaterError("\n".join(lines))


def _describe_damage(records, replaced):
    for record in records:
        line = (
            f"  {paint(record['name'], 'strong')} "
            f"(Conda {record['version']}, build {record['build']})"
        )
        for entry in replaced.get(record["name"], ()):
            line += (
                f": pip installed {entry['distribution']} {entry['pip_version']} "
                f"over Conda's {entry['conda_version']}"
            )
        print(line)


def _conda_install(prefix, spec, *, download_only):
    """Force-reinstall one exact Conda spec without touching its dependencies."""
    command = [conda_executable(), "install", "-p", str(prefix), "--yes"]
    command += ["--force-reinstall", "--no-deps"]
    if download_only:
        command.append("--download-only")
    return run_command([*command, spec], capture_output=True, timeout=1800)


def _fetch_conda_package(prefix, record):
    """Put Conda's recorded build in Conda's package cache; return its spec.

    Falls back to another build of the same version.  Nothing in the
    environment changes, so a failure here leaves it exactly as it was.
    """
    name, version = record["name"], record["version"]
    spec = f"{name}=={version}={record['build']}"
    if _conda_install(prefix, spec, download_only=True).returncode == 0:
        return spec
    announce(
        "INFO",
        f"Build {record['build']} is unavailable; using another build "
        f"of {name} {version}.",
        flush=True,
    )
    spec = f"{name}=={version}"
    result = _conda_install(prefix, spec, download_only=True)
    if result.returncode != 0:
        raise command_failure(f"Fetching Conda's {name} {version}", result)
    return spec


def repair_conda_file_damage(prefix, sections, *, dry_run):
    """Restore Conda's damaged packages, removing pip's overwrite first.

    Reinstalling with Conda alone would leave pip's INSTALLER marker inside
    Conda's metadata, so pip would keep treating Conda's files as its own;
    pip's copy is therefore uninstalled first.  Each package is reinstalled at
    the exact version Conda recorded, without touching its dependencies.
    """
    records = damaged_conda_records(prefix, sections)
    if not records:
        raise UpdaterError(
            "Conda reports damaged files but does not say which packages own "
            "them, so the updater cannot repair them safely."
        )
    replaced = pip_replaced_conda_packages(prefix, [r["name"] for r in records])
    _refuse_breaking_restore(prefix, replaced)
    announce("REPAIR", "Conda's files are damaged in:")
    _describe_damage(records, replaced)
    if dry_run:
        announce("PREVIEW", "A real run repairs this automatically before updating.")
        return
    # Fetch first: once pip's copy is removed, a failed download would leave
    # the environment without the package at all.
    announce(
        "INFO", "Fetching Conda's packages before changing anything...", flush=True
    )
    specs = [_fetch_conda_package(prefix, record) for record in records]
    distributions = [e["distribution"] for es in replaced.values() for e in es]
    if distributions:
        announce(
            "INFO", f"Removing pip's copy of {', '.join(distributions)}...", flush=True
        )
        result = run_command(
            [*pip_command(prefix), "uninstall", "-y", *distributions],
            capture_output=True,
            timeout=300,
        )
        if result.returncode != 0:
            raise command_failure("Removing pip's copy", result)
    for record, spec in zip(records, specs):
        announce(
            "INFO", f"Reinstalling Conda's {record['name']} {record['version']}..."
        )
        result = _conda_install(prefix, spec, download_only=False)
        if result.returncode != 0:
            raise command_failure(f"Reinstalling Conda's {record['name']}", result)


def explain_unknown_doctor_report(snapshot):
    """Fail closed without inventing a diagnosis for unfamiliar Conda output."""
    return (
        "Conda returned a health report this updater could not interpret safely.\n\n"
        "No package names or repair commands are shown because the report does\n"
        "not provide enough verified information to identify the problem. Update\n"
        "Conda or inspect the full report below, then run this command again.\n\n"
        "Conda's full report:\n" + snapshot
    )


def _checked_doctor_sections(snapshot):
    """Split a doctor report, failing closed on one this updater cannot read."""
    sections = doctor_sections(snapshot)
    reported_checks = {section["kind"] for section in sections}
    if reported_checks != {"altered-files", "missing-files", "consistency"}:
        raise UpdaterError(explain_unknown_doctor_report(snapshot))
    return sections


def _file_damage(sections):
    return [
        section
        for section in sections
        if section["failed"] and section["kind"] in {"altered-files", "missing-files"}
    ]


def preflight_health(prefix, *, repair=False, dry_run=False):
    """Snapshot dependency health and return the baseline mutation fingerprint.

    With ``repair``, stale duplicate records and damaged Conda files are fixed
    first (``dry_run`` only describes the fixes); without it, damage stops the
    run.  A repair is proven by a fresh Conda health report, never assumed.
    """
    if repair:
        repair_stale_duplicate_metadata(prefix, dry_run=dry_run)
    snapshot = doctor_snapshot(prefix)
    sections = _checked_doctor_sections(snapshot)
    blocking = _file_damage(sections)
    if blocking and not repair:
        raise UpdaterError(explain_conda_file_damage(blocking, snapshot))
    repair_pending = bool(blocking) and dry_run
    if blocking:
        repair_conda_file_damage(prefix, blocking, dry_run=dry_run)
        if not dry_run:
            snapshot = doctor_snapshot(prefix)
            sections = _checked_doctor_sections(snapshot)
            if _file_damage(sections):
                raise UpdaterError(
                    "The automatic repair finished, but Conda still reports "
                    "damaged files, so nothing will be updated.\n\n"
                    "Conda's full report:\n" + snapshot
                )
            announce("OK", "Repaired: Conda's health check now passes.")
    ownership = load_conda_ownership(prefix)
    inconsistent = any(
        section["failed"] and section["kind"] == "consistency" for section in sections
    )
    return {
        "doctor": snapshot,
        "conda_records_digest": ownership["records_digest"],
        # A preview found damage a real run would repair first.
        "repair_pending": repair_pending,
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
    """Pin every installed package outside the selection at its exact version.

    The solve passes these to pip as constraints, which bind only the packages
    it actually reaches: a selection's dependencies stay as installed, so the
    plan never moves a package the user did not select, and conflicts among
    packages the selections never reach stay out of the solve.
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


def marker_environment(prefix):
    """Return the target interpreter's PEP 508 marker values, or None.

    Requirement markers must be judged against the environment being updated,
    not the updater's own interpreter, which can be a different Python version.
    """
    helper = r"""
import json, os, platform, sys
impl = sys.implementation
version = f"{impl.version.major}.{impl.version.minor}.{impl.version.micro}"
if impl.version.releaselevel != "final":
    version += impl.version.releaselevel[0] + str(impl.version.serial)
print(json.dumps({
    "implementation_name": impl.name,
    "implementation_version": version,
    "os_name": os.name,
    "platform_machine": platform.machine(),
    "platform_python_implementation": platform.python_implementation(),
    "platform_release": platform.release(),
    "platform_system": platform.system(),
    "platform_version": platform.version(),
    "python_full_version": platform.python_version(),
    "python_version": ".".join(platform.python_version_tuple()[:2]),
    "sys_platform": sys.platform,
}))
"""
    try:
        result = run_command(
            [environment_python(prefix), "-I", "-c", helper],
            capture_output=True,
            timeout=60,
        )
        if result.returncode != 0:
            return None
        values = json.loads(result.stdout)
    except (UpdaterError, OSError, ValueError):
        return None
    if not isinstance(values, dict) or not all(
        isinstance(value, str) for value in values.values()
    ):
        return None
    return values


def inventory_fingerprint(versions):
    """Digest an exact name-to-version map of every installed distribution."""
    digest = hashlib.sha256()
    for name, version in sorted(versions.items()):
        digest.update(f"{name}=={version}\n".encode())
    return digest.hexdigest()


def _requirement_sources(inventory, plan):
    """Return ``(name, version, requires)`` for every package after the plan."""
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
    return sources


def _parsed_requirement_sources(inventory, plan):
    """Return ``(name, version, [Requirement])`` for every post-plan package.

    Each installed package contributes its planned version's requirements if
    the plan moves it; packages the plan introduces are added.  Returns None
    when the ``packaging`` library is unavailable.
    """
    # Imported here so a missing `packaging` only drops the explanation.
    try:
        # pylint: disable=import-outside-toplevel
        from packaging.requirements import InvalidRequirement, Requirement
    except ImportError:
        return None
    parsed = []
    for name, version, requires in _requirement_sources(inventory, plan):
        requirements = []
        for raw in requires:
            with contextlib.suppress(InvalidRequirement):
                requirements.append(Requirement(str(raw)))
        parsed.append((name, version, requirements))
    return parsed


def _marker_applies(requirement, extras, marker_env):
    """Whether ``requirement`` applies without an extra or with one of ``extras``."""
    if requirement.marker is None:
        return True
    for extra in ("", *sorted(extras)):
        environment = dict(marker_env or {})
        environment["extra"] = extra
        try:
            if requirement.marker.evaluate(environment):
                return True
        except ValueError:
            # UndefinedComparison / UndefinedEnvironmentName: the marker
            # cannot be judged here, so it cannot explain the cap.
            return False
    return False


def _active_extras(parsed, marker_env):
    """Return the extras some installed package requests, per package name.

    An extra-gated requirement constrains the install only when some package
    asks for that extra.  torch requires `cuda-toolkit[cublas,...]`, and the
    extras are what pin every nvidia-* library, so ignoring them left most
    CUDA holds unexplained.  Extras can enable further extras; iterate.
    """
    active = {}
    changed = True
    while changed:
        changed = False
        for capper_name, _, requirements in parsed:
            own = active.get(canonicalize_name(str(capper_name)), set())
            for requirement in requirements:
                if not requirement.extras or not _marker_applies(
                    requirement, own, marker_env
                ):
                    continue
                known = active.setdefault(canonicalize_name(requirement.name), set())
                if not requirement.extras <= known:
                    known |= requirement.extras
                    changed = True
    return active


def _caps_rejecting(normalized, latest_version, parsed, active_extras, marker_env):
    """Return a cause for each applicable requirement that rejects the version."""
    causes = []
    for capper_name, capper_version, requirements in parsed:
        extras = active_extras.get(canonicalize_name(str(capper_name)), set())
        for requirement in requirements:
            if (
                canonicalize_name(requirement.name) == normalized
                and _marker_applies(requirement, extras, marker_env)
                and requirement.specifier
                and latest_version not in requirement.specifier
            ):
                causes.append(
                    {
                        "capper": str(capper_name),
                        "capper_version": str(capper_version),
                        "text": (
                            f"{capper_name} {capper_version} requires "
                            f"{requirement.name}{requirement.specifier}"
                        ),
                    }
                )
    return causes


def broken_installed_requirements(inventory, marker_env):
    """Find installed versions that an installed package's requirement rejects.

    `pip check` misses these when the requirement sits behind an extra that
    another package asks for (discord-ext-voice-recv -> discord.py[voice] ->
    PyNaCl<1.6), yet pip's resolver enforces them.  Returns
    {normalized name: [cause]} in the holdback_reasons cause format.
    """
    parsed = _parsed_requirement_sources(inventory, [])
    if parsed is None:
        return {}
    # packaging is importable: _parsed_requirement_sources just imported it.
    from packaging.version import (  # pylint: disable=import-outside-toplevel
        InvalidVersion,
        Version,
    )

    active_extras = _active_extras(parsed, marker_env)
    broken = {}
    for capper_name, capper_version, requirements in parsed:
        extras = active_extras.get(canonicalize_name(str(capper_name)), set())
        for requirement in requirements:
            normalized = canonicalize_name(requirement.name)
            row = inventory.get(normalized)
            if row is None or not requirement.specifier:
                continue
            try:
                installed = Version(str(row.get("version") or ""))
            except InvalidVersion:
                continue
            if installed in requirement.specifier or not _marker_applies(
                requirement, extras, marker_env
            ):
                continue
            broken.setdefault(normalized, []).append(
                {
                    "capper": str(capper_name),
                    "capper_version": str(capper_version),
                    "text": (
                        f"{capper_name} {capper_version} requires "
                        f"{requirement.name}{requirement.specifier}"
                    ),
                }
            )
    return broken


@dataclasses.dataclass(frozen=True)
class PlannedVersion:
    """A package's version once the plan is applied."""

    name: str
    text: str  # as installed; recorded holds compare this text verbatim
    version: object  # packaging.version.Version
    moved: bool


def _planned_versions(parsed, plan):
    """Map each post-plan package to its PlannedVersion, skipping bad versions."""
    # packaging is importable: holdback_reasons calls this only after using it.
    from packaging.version import Version  # pylint: disable=import-outside-toplevel

    moved = {canonicalize_name(item["name"]) for item in plan}
    planned = {}
    for name, text, _ in parsed:
        normalized = canonicalize_name(str(name))
        try:
            version = Version(str(text))
        except ValueError:  # packaging's InvalidVersion is a ValueError
            continue
        planned[normalized] = PlannedVersion(
            str(name), str(text), version, normalized in moved
        )
    return planned


def _unmet_newest_requirements(label, requires, planned, extras, marker_env):
    """Return a cause for each requirement of a newest release the plan leaves unmet.

    ``label`` is the newest release as "name version".  The cause names the
    dependency as the capper: the hold stands exactly as long as that
    dependency's version does.
    """
    # packaging is importable: holdback_reasons calls this only after using it.
    from packaging.requirements import (  # pylint: disable=import-outside-toplevel
        InvalidRequirement,
        Requirement,
    )

    causes = []
    for raw in requires:
        try:
            requirement = Requirement(str(raw))
        except InvalidRequirement:
            continue
        dependency = planned.get(canonicalize_name(requirement.name))
        if (
            dependency is None
            or not requirement.specifier
            or not _marker_applies(requirement, extras, marker_env)
            or requirement.specifier.contains(dependency.version, prereleases=True)
        ):
            continue
        causes.append(
            {
                "capper": dependency.name,
                "capper_version": dependency.text,
                "text": (
                    f"{label} requires {requirement.name}{requirement.specifier}, "
                    f"and {dependency.name} "
                    f"{'moves only to' if dependency.moved else 'stays at'} "
                    f"{dependency.text}"
                ),
            }
        )
    return causes


def holdback_reasons(held, inventory, plan, marker_env=None, newest_requires=None):
    """Name the requirements that keep each held package from its newest release.

    A newest release is kept out either by an installed package's cap on it,
    or by its own requirement on a package whose version the plan keeps out
    of range (``newest_requires`` gives each newest release's requirements).
    The hold itself is already a fact established by the resolver; this only
    explains it.  When the `packaging` library is unavailable the holds are
    reported without naming the cap rather than re-implementing PEP 440.
    """
    parsed = _parsed_requirement_sources(inventory, plan)
    if parsed is None:
        return {}
    # packaging is importable: _parsed_requirement_sources just imported it.
    from packaging.version import Version  # pylint: disable=import-outside-toplevel

    active_extras = _active_extras(parsed, marker_env)
    planned = _planned_versions(parsed, plan)
    reasons = {}
    for normalized, (name, latest) in held.items():
        try:
            latest_version = Version(latest)
        except ValueError:  # packaging's InvalidVersion is a ValueError
            continue
        causes = _caps_rejecting(
            normalized, latest_version, parsed, active_extras, marker_env
        ) + _unmet_newest_requirements(
            f"{name} {latest}",
            (newest_requires or {}).get(normalized, ()),
            planned,
            active_extras.get(normalized, set()),
            marker_env,
        )
        if causes:
            reasons[normalized] = causes
    return reasons


def print_held_back(held, inventory, reasons):
    """Explain selected updates the resolver kept at their installed versions.

    A hold is not an error: the newest release of a selected package is
    rejected by a requirement of a package that is staying as it is, or needs
    a version of another package that the environment keeps, so the resolver
    keeps the installed version instead of breaking the environment.  The cap
    is named so the user knows which package must move before the hold can
    lift.
    """
    announce(
        "INFO",
        f"{count_label(len(held), 'selected package')} held back to stay "
        "compatible with packages not being updated:",
    )
    for normalized, (name, latest) in sorted(held.items()):
        installed = str((inventory.get(normalized) or {}).get("version") or "")
        line = (
            f"  {paint(name, 'strong')} stays at "
            f"{installed or 'its current version'} instead of {latest}"
        )
        print(line + _cause_suffix(reasons.get(normalized, ())), flush=True)


def print_capped(capped, plan, reasons):
    """Explain selected updates the resolver moves, but not to the newest release.

    pip keeps listing such a package as outdated afterward, so without this the
    summary reads as a full update and the next scan looks like it failed.
    """
    versions = {canonicalize_name(item["name"]): item["version"] for item in plan}
    announce(
        "INFO",
        f"{count_label(len(capped), 'selected package')} can only update "
        "as far as other packages allow:",
    )
    for normalized, (name, latest) in sorted(capped.items()):
        line = (
            f"  {paint(name, 'strong')} goes to "
            f"{paint(str(versions.get(normalized)), 'new')} instead of {latest}"
        )
        print(line + _cause_suffix(reasons.get(normalized, ())), flush=True)


def _cause_suffix(causes):
    texts = list(dict.fromkeys(cause["text"] for cause in causes))[:3]
    return " " + paint("(" + "; ".join(texts) + ")", "note") if texts else ""


def _ownership_refusal(name, inventory, ownership, prefix):
    """Return why the updater must not or cannot replace ``name``, or None."""
    normalized = canonicalize_name(name)
    installed = inventory.get(normalized)
    if normalized in PROTECTED_BOOTSTRAP_PACKAGES:
        return f"Refusing to update protected bootstrap package {name}."
    if normalized in ownership["distributions"]:
        return f"Refusing to update Conda-owned package {name}."
    if not installed or installed.get("installer") not in UPDATABLE_INSTALLERS:
        return f"{name} is not an unambiguous pip- or uv-installed distribution."
    if not _is_within(installed.get("metadata_path", ""), prefix):
        return f"{name} is outside the selected environment."
    if installed.get("direct_url"):
        return f"{name} is an editable/direct-URL install and cannot be reproduced."
    return None


def _check_selected_ownership(names, inventory, ownership, prefix):
    """Refuse selections the updater must not or cannot reproducibly replace."""
    for name in names:
        refusal = _ownership_refusal(name, inventory, ownership, prefix)
        if refusal:
            raise UpdaterError(refusal)


def _compatible_wheel_targets(prefix, names, hooks):
    """Ask pip for each selection's newest compatible wheel, ignoring deps.

    Returns ``(targets, newest_requires)``: ``targets`` maps each selection
    that has a newer wheel to ``(name, version)``, and ``newest_requires``
    maps it to that wheel's requirements.
    """
    report = pip_install_report(
        prefix,
        [
            "--upgrade",
            "--no-deps",
            "--only-binary=:all:",
            "--disable-pip-version-check",
            *names,
        ],
        action=f"Finding compatible wheels for {prefix}",
        report_name="candidate",
        timeout=300,
        hooks=hooks,
    )
    items = report_install_items(
        report, "pip's candidate report did not contain an install list."
    )
    selected_names = {canonicalize_name(name) for name in names}
    targets = {}
    newest_requires = {}
    for item in items:
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
        newest_requires[normalized] = list(metadata.get("requires_dist") or [])
    return targets, newest_requires


def _dependency_closure(start, graph):
    """Return ``start`` and every package its requirements reach in ``graph``."""
    reached = {start}
    pending = [start]
    while pending:
        for dependency in graph.get(pending.pop(), ()):
            if dependency not in reached:
                reached.add(dependency)
                pending.append(dependency)
    return reached


def _selection_spec(name, installed, newest, extras):
    """Return ``name[extras]>=installed,<=newest``, leaving out unusable bounds.

    PEP 440 forbids local labels (``+cu130``) in range bounds, so each bound
    uses the public version, which still admits every local build of it.
    """
    requested = [extra for extra in extras if SAFE_PROJECT_NAME.fullmatch(extra)]
    spec = name + (f"[{','.join(requested)}]" if requested else "")
    bounds = []
    if SAFE_VERSION.fullmatch(installed):
        bounds.append(">=" + installed.split("+", 1)[0])
    if SAFE_VERSION.fullmatch(newest):
        bounds.append("<=" + newest.split("+", 1)[0])
    return spec + ",".join(bounds)


@dataclasses.dataclass(frozen=True)
class RepairOption:
    """One way to repair an existing conflict.

    ``packages`` are installed packages to update, ``specs`` missing
    requirements to install, and ``tags`` names the conflict each package
    the option moves or installs repairs.
    """

    packages: tuple
    specs: tuple
    tags: dict


@dataclasses.dataclass(frozen=True)
class InstalledRequirements:
    """What the installed environment requires, as the update solve sees it.

    ``edges`` pairs each package with every requirement it makes that applies
    here (markers judged for the target interpreter, extras only when some
    package requests them); ``broken`` holds installed versions a requirement
    already rejects, in the holdback_reasons cause format.
    """

    inventory: dict
    marker_env: object
    edges: list
    extras: dict
    broken: dict

    @classmethod
    def load(cls, inventory, marker_env):
        """Read the applicable requirements of every installed package."""
        parsed = _parsed_requirement_sources(inventory, [])
        if parsed is None:
            raise UpdaterError(
                "Planning an update needs the Python 'packaging' library."
            )
        extras = _active_extras(parsed, marker_env)
        edges = []
        for name, _, requirements in parsed:
            owner = canonicalize_name(str(name))
            edges.extend(
                (owner, requirement)
                for requirement in requirements
                if _marker_applies(requirement, extras.get(owner, set()), marker_env)
            )
        broken = broken_installed_requirements(inventory, marker_env)
        return cls(inventory, marker_env, edges, extras, broken)

    def specs(self, targets):
        """Let each selection settle from its installed version to its newest.

        The newest wheel was found ignoring dependencies, so it can need a
        version of another package the environment keeps (sentence-transformers
        6.1.0 needs transformers>=5 while vllm holds transformers<5); pinned to
        it, the whole solve was impossible, while a range lets pip hold that
        selection back or stop at an older release.  The floor stops the plan
        from downgrading a selection.  Extras another package requests stay
        installed.
        """
        return [
            _selection_spec(
                name,
                str((self.inventory.get(normalized) or {}).get("version") or ""),
                newest,
                sorted(self.extras.get(normalized, ())),
            )
            for normalized, (name, newest) in targets.items()
        ]

    def constraints(self, targets, fixed=()):
        """Pin every other package, and keep each cap it places on the solve.

        pip checks only the requirements of packages its solve reaches, so a
        package that depends on a selection would otherwise never be asked:
        its cap on that selection, or on a package the plan might add, is
        passed explicitly.  Its requirements on other pinned packages cannot
        change and are left out.  A cap the installed version already breaks
        is kept too, so a selection moves only to repair that conflict.
        ``fixed`` names packages the request pins itself to a planned version.
        """
        moving = set(targets) | set(fixed)
        caps = {
            f"{requirement.name}{requirement.specifier}"
            for owner, requirement in self.edges
            if owner not in moving
            and requirement.specifier
            and (
                canonicalize_name(requirement.name) in moving
                or canonicalize_name(requirement.name) not in self.inventory
            )
        }
        return retained_environment_pins(self.inventory, moving) + sorted(caps)

    def exposure(self, targets):
        """Return the conflicts each selection that touches one cannot escape.

        pip rechecks every requirement in the dependency graph it walks.  A
        selection whose installed version a requirement already rejects, or
        whose installed dependencies (itself included) reach a package with
        an unmet requirement, therefore has no answer that leaves it as it is:
        the solve repairs that conflict or fails.  Any other selection can
        always stay installed.  Each conflict is named twice, once per side,
        so a recorded hold lifts when either side moves.
        """
        graph = {}
        for owner, requirement in self.edges:
            graph.setdefault(owner, set()).add(canonicalize_name(requirement.name))
        unmet = {}
        for package, causes in self.broken.items():
            for cause in causes:
                holder = canonicalize_name(cause["capper"])
                unmet.setdefault(holder, []).append((package, cause))
        exposure = {}
        for normalized, (name, _) in targets.items():
            touched = [(normalized, cause) for cause in self.broken.get(normalized, ())]
            for holder in sorted(_dependency_closure(normalized, graph) & set(unmet)):
                touched.extend(unmet[holder])
            if touched:
                exposure[normalized] = [
                    conflict_cause
                    for package, cause in touched
                    for conflict_cause in self._conflict_causes(
                        (normalized, name), package, cause
                    )
                ]
        return exposure

    def repair_units(self, selected, updatable, blocked):
        """List the ways to repair each existing conflict without a downgrade.

        A missing requirement is repaired by installing it.  A version conflict
        is repaired by updating the package whose requirement is unmet, or else
        the package that requirement rejects; each update has a floor, so
        neither moves down.  A conflict a selection takes part in is left to
        that selection.  Returns ``(units, unrepairable)``: each unit is
        ``(reason, [RepairOption])``, and ``unrepairable`` names conflicts
        whose packages the updater may not touch (``blocked`` names may not be
        installed; only ``updatable`` ones may move).
        """
        units, unrepairable = self._missing_units(selected, blocked)
        for (holder, package), reason in sorted(self._conflicts(selected).items()):
            options = [
                RepairOption((name,), (), {name: reason})
                for name in (holder, package)
                if name in updatable
            ]
            if options:
                units.append((reason, options))
            else:
                unrepairable.append(reason)
        return units, unrepairable

    def _missing_units(self, selected, blocked):
        """Return one unit per package with missing requirements to install."""
        unrepairable = []
        missing = {}
        for owner, requirement in self.edges:
            dependency = canonicalize_name(requirement.name)
            if dependency in self.inventory or owner in selected:
                continue
            row = self.inventory[owner]
            text = (
                f"{row['name']} {row['version']} requires "
                f"{requirement.name}{requirement.specifier}, which is not installed"
            )
            if dependency in blocked:
                unrepairable.append(text)
                continue
            extras = ",".join(sorted(requirement.extras))
            spec = requirement.name + (f"[{extras}]" if extras else "")
            missing.setdefault(owner, {})[dependency] = (
                spec + str(requirement.specifier),
                text,
            )
        units = [
            (
                "; ".join(text for _, text in entries.values()),
                [
                    RepairOption(
                        (),
                        tuple(spec for spec, _ in entries.values()),
                        {name: text for name, (_, text) in entries.items()},
                    )
                ],
            )
            for _, entries in sorted(missing.items())
        ]
        return units, unrepairable

    def _conflicts(self, selected):
        """Map each version conflict no selection takes part in to its reason."""
        conflicts = {}
        for package, causes in self.broken.items():
            row = self.inventory[package]
            for cause in causes:
                holder = canonicalize_name(cause["capper"])
                if package not in selected and holder not in selected:
                    conflicts[(holder, package)] = (
                        f"{cause['text']}, which installed {row['name']} "
                        f"{row['version']} fails"
                    )
        return conflicts

    def _conflict_causes(self, selection, package, cause):
        """Name both sides of the conflict ``cause`` describes on ``package``."""
        normalized, name = selection
        row = self.inventory[package]
        text = f"{cause['text']}, which installed {row['name']} {row['version']} fails"
        if normalized not in (package, canonicalize_name(cause["capper"])):
            text = f"{name} needs {cause['capper']}; {text}"
        return [
            {**cause, "text": text},
            {
                "capper": str(row["name"]),
                "capper_version": str(row["version"]),
                "text": text,
            },
        ]


def _plan_item(raw_item, inventory, ownership, prefix):
    """Validate one item of pip's resolver report and return its plan entry."""
    metadata = raw_item.get("metadata") or {}
    name = str(metadata.get("name") or "")
    version = str(metadata.get("version") or "")
    normalized = canonicalize_name(name)
    if normalized in PROTECTED_BOOTSTRAP_PACKAGES:
        raise UpdaterError(f"The update would modify protected package {name}.")
    if normalized in ownership["distributions"]:
        raise UpdaterError(
            f"The update would overwrite Conda-owned dependency {name} {version}."
        )

    installed = inventory.get(normalized)
    if installed:
        if installed.get("installer") not in UPDATABLE_INSTALLERS or not _is_within(
            installed.get("metadata_path", ""), prefix
        ):
            raise UpdaterError(
                f"The update would replace {name}, which pip or uv did not install."
            )
        if installed.get("direct_url"):
            raise UpdaterError(f"The update would replace direct-URL package {name}.")

    url, sha256 = report_download(raw_item)
    if not is_index_artifact(raw_item):
        raise UpdaterError(f"The update plan contains non-reproducible source {name}.")
    if raw_item.get("is_yanked"):
        raise UpdaterError(f"The update plan contains yanked release {name} {version}.")
    if not sha256:
        raise UpdaterError(f"The update artifact for {name} lacks a SHA-256 digest.")
    return {
        "name": name,
        "current_version": installed.get("version") if installed else None,
        "version": version,
        "sha256": sha256,
        # Kept only in memory. Transaction journals store versions and
        # hashes, never private-index URLs that may contain credentials.
        "url": url,
        "filename": wheel_filename_from_url(url),
        "requested": bool(raw_item.get("requested")),
        "requires": list(metadata.get("requires_dist") or []),
    }


def _plan_from_report(raw_plan, inventory, ownership, prefix):
    """Validate pip's whole resolver report into the ordered update plan."""
    plan = []
    seen = set()
    for raw_item in raw_plan:
        metadata = raw_item.get("metadata") or {}
        name = str(metadata.get("name") or "")
        version = str(metadata.get("version") or "")
        if not name or not version or not SAFE_PROJECT_NAME.fullmatch(name):
            raise UpdaterError(
                "pip proposed an item with invalid name/version metadata."
            )
        normalized = canonicalize_name(name)
        if normalized in seen:
            raise UpdaterError(f"pip proposed {name} more than once.")
        seen.add(normalized)
        plan.append(_plan_item(raw_item, inventory, ownership, prefix))
    return plan


def _limited_selections(targets, plan):
    """Split selections the plan does not take to their newest wheel.

    Returns ``(held, capped)``: held selections stay installed as they are;
    capped ones move, but not to the newest compatible wheel, and pip will
    still list them as outdated after a successful update (CUDA wheels
    pinned by torch through cuda-toolkit are the common case).  Each capped
    plan item gains a ``newest`` key.
    """
    planned = {canonicalize_name(item["name"]) for item in plan}
    held = {
        normalized: candidate
        for normalized, candidate in targets.items()
        if normalized not in planned
    }
    capped = {}
    for item in plan:
        normalized = canonicalize_name(item["name"])
        if normalized in targets and item["version"] != targets[normalized][1]:
            capped[normalized] = targets[normalized]
            item["newest"] = targets[normalized][1]
    return held, capped


def _hold_records(limited, reasons, inventory, plan):
    """Describe each limited selection so a later scan can trust the hold."""
    after_plan = {
        normalized: str(row.get("version") or "")
        for normalized, row in inventory.items()
    }
    after_plan.update(
        {canonicalize_name(item["name"]): item["version"] for item in plan}
    )
    records = {}
    for normalized, (name, latest) in limited.items():
        cappers = {
            cause["capper"]: cause["capper_version"]
            for cause in reasons.get(normalized, ())
        }
        records[normalized] = {
            "name": name,
            "installed": after_plan.get(normalized, ""),
            "latest": latest,
        }
        if cappers:
            records[normalized]["cappers"] = cappers
        else:
            # pip saw a cap this explanation cannot name.  Every other package
            # is pinned at its installed version during the solve, so the same
            # installed set gives the same answer; trust the hold only while
            # the environment is exactly the one this plan produces.
            records[normalized]["environment"] = inventory_fingerprint(after_plan)
    return records


def _limitation_reasons(limited, outcome, plan, installed):
    """Name what keeps each limited selection from its newest release."""
    reasons = holdback_reasons(
        limited,
        installed.inventory,
        plan,
        installed.marker_env,
        outcome.newest_requires,
    )
    for normalized, causes in outcome.set_aside.items():
        # A cap the installed version already breaks is named once, in the
        # set-aside cause that says so.
        conflicts = {cause["text"] for cause in causes}
        reasons[normalized] = [
            cause
            for cause in reasons.get(normalized, [])
            if not any(text.startswith(cause["text"] + ",") for text in conflicts)
        ] + causes
    return reasons


def _report_holds(prefix, outcome, plan, installed):
    """Explain new holds and caps, and remember them for the next scan.

    ``outcome`` is the ResolverOutcome, ``plan`` what pip actually chose.
    """
    held, capped = _limited_selections(outcome.targets, plan)
    limited = {**held, **capped}
    reasons = _limitation_reasons(limited, outcome, plan, installed) if limited else {}
    records = _hold_records(limited, reasons, installed.inventory, plan)
    cached_holds = get_cached_holds(prefix)
    # A hold is announced when it is news; a hold identical to the recorded one
    # was already explained (and the scan normally filters it out earlier).
    fresh = {
        normalized
        for normalized in limited
        if cached_holds.get(normalized) != records[normalized]
    }
    if fresh & held.keys():
        print_held_back(
            {name: held[name] for name in fresh & held.keys()},
            installed.inventory,
            reasons,
        )
    if fresh & capped.keys():
        print_capped(
            {name: capped[name] for name in fresh & capped.keys()}, plan, reasons
        )
    merged = {
        normalized: record
        for normalized, record in cached_holds.items()
        if normalized not in outcome.targets and isinstance(record, dict)
    }
    merged.update(records)
    if merged != cached_holds:
        set_cached_holds(prefix, merged)


def _announce_conflict_repairs(plan, broken):
    """Say which selected updates also satisfy a requirement they already broke."""
    for item in plan:
        causes = broken.get(canonicalize_name(item["name"]))
        if causes and item["requested"]:
            reasons = "; ".join(dict.fromkeys(cause["text"] for cause in causes))
            announce(
                "INFO",
                "Also repairs an existing conflict: "
                f"{item['name']} {item['current_version']} -> {item['version']} "
                f"({reasons})",
                flush=True,
            )


def _announce_missing_wheels(names, outcome):
    """Name selections pip found no newer installable wheel for."""
    no_wheel = sorted(
        name
        for name in names
        if canonicalize_name(name) not in outcome.targets
        and canonicalize_name(name) not in outcome.rebuilt
    )
    if no_wheel:
        announce(
            "INFO",
            "No newer wheel is available for this environment: "
            + ", ".join(no_wheel)
            + " (a newer source-only release needs a manual build)",
            flush=True,
        )


@dataclasses.dataclass(frozen=True)
class ResolverOutcome:
    """What the solve found: each selection's newest wheel and pip's plan.

    ``newest_requires`` holds each newest wheel's requirements;
    ``set_aside`` maps each selection left out of the plan because it touches
    an existing conflict to that conflict's causes; ``rebuilt`` holds the
    selections whose newest wheel is a different build, as
    ``(name, installed, newest)``; ``repairs`` names the conflict each
    repaired package fixes, and ``unrepairable`` the conflicts left as they
    are.
    """

    targets: dict
    newest_requires: dict
    report: dict
    set_aside: dict
    rebuilt: dict
    repairs: dict
    unrepairable: list


# pip settings that change where packages come from; uv cannot see them.
PIP_INDEX_SETTINGS = ("index-url", "extra-index-url", "find-links", "no-index")

# One line of uv's dry-run plan: " + name==version".
UV_PLANNED_LINE = re.compile(r"^ \+ ([A-Za-z0-9][A-Za-z0-9._-]*)==(\S+)$")


def uv_resolver(prefix):
    """Return uv's path when it can choose versions from pip's own index.

    pip's resolver backtracks through version combinations one at a time and,
    on a large environment (vllm's, with 85 selections), gives up after
    minutes with ResolutionTooDeep; uv solves the same request in seconds.
    uv is only used when pip is configured with no index of its own, since
    uv reads neither pip.conf nor PIP_* variables.
    """
    uv = shutil.which("uv")
    if uv is None:
        return None
    result = run_command(
        [*pip_command(prefix), "config", "list"], capture_output=True, timeout=60
    )
    if result.returncode != 0 or any(
        setting in result.stdout for setting in PIP_INDEX_SETTINGS
    ):
        return None
    return uv


def _uv_plan(output):
    """Read uv's dry-run plan as ``{normalized: (name, version)}``.

    Returns None when a planned package is not an exact version (a direct
    URL), since pip could not be pinned to it.
    """
    planned = {}
    for line in output.splitlines():
        if line.startswith(" + "):
            match = UV_PLANNED_LINE.match(line)
            if not match:
                return None
            planned[canonicalize_name(match.group(1))] = match.groups()
    return planned


def _uv_versions(uv, prefix, request, hooks):
    """Ask uv which version each package of ``request`` should end at.

    ``request`` is ``(requirements, constraints, upgradable)``.  Returns
    ``{normalized: (name, version)}`` for every package uv would install, or
    None when uv's plan cannot be read as exact versions.  Raises
    UnsolvableError when uv proves the request impossible.
    """
    requirements, constraints, upgradable = request
    with tempfile.TemporaryDirectory(prefix="pip-updater-uv-") as tmp:
        requirements_path = Path(tmp) / "requirements.txt"
        requirements_path.write_text("\n".join(requirements) + "\n", encoding="utf-8")
        constraints_path = Path(tmp) / "constraints.txt"
        constraints_path.write_text("\n".join(constraints) + "\n", encoding="utf-8")
        result = stream_command(
            [
                uv,
                "pip",
                "install",
                "--dry-run",
                "--no-config",
                "--color=never",
                f"--python={environment_python(prefix)}",
                "--only-binary=:all:",
                *(f"--upgrade-package={name}" for name in sorted(upgradable)),
                "-c",
                str(constraints_path),
                "-r",
                str(requirements_path),
            ],
            timeout=600,
            hooks=hooks,
        )
    output = f"{result.stdout}\n{result.stderr}"
    if result.returncode == 0:
        return _uv_plan(output)
    if "No solution found" in output:
        raise UnsolvableError(output.strip())
    return None


def _pinned_choice(targets, installed, planned):
    """Pin every target and every package uv plans at uv's chosen version.

    A target uv leaves alone is pinned at its installed version, so pip
    checks one exact assignment instead of searching the ranges again.
    """
    pins = []
    for normalized, (name, _newest) in targets.items():
        extras = sorted(
            extra
            for extra in installed.extras.get(normalized, ())
            if SAFE_PROJECT_NAME.fullmatch(extra)
        )
        version = planned.pop(normalized, (name, ""))[1] or str(
            (installed.inventory.get(normalized) or {}).get("version") or ""
        )
        spec = name + (f"[{','.join(extras)}]" if extras else "")
        pins.append(f"{spec}=={version}" if SAFE_VERSION.fullmatch(version) else spec)
    pins.extend(f"{name}=={version}" for name, version in planned.values())
    return pins


def _pip_solve(prefix, requirements, constraints, hooks):
    """Return pip's dry-run install report for ``requirements``."""
    return pip_install_report(
        prefix,
        [
            "--upgrade",
            "--upgrade-strategy",
            "only-if-needed",
            "--only-binary=:all:",
            "--disable-pip-version-check",
            *requirements,
        ],
        constraints=constraints,
        action=f"Resolving updates for {prefix}",
        report_name="resolver",
        timeout=600,
        hooks=hooks,
    )


def _solve(prefix, request, installed, hooks, uv):
    """Ask for the joint plan that moves only what ``request`` names.

    ``request`` is ``(targets, specs, fixed)``: packages that may move within
    their range, extra requirement specs, and the names ``specs`` pin exactly.
    With ``uv``, uv chooses the versions and pip checks exactly those and
    writes the report; pip searches the ranges itself only when uv is
    unavailable or pip rejects uv's choice.
    """
    targets, specs, fixed = request
    requirements = [*installed.specs(targets), *specs]
    constraints = installed.constraints(targets, fixed)
    if uv is not None:
        planned = _uv_versions(uv, prefix, (requirements, constraints, targets), hooks)
        if planned is not None:
            try:
                return _pip_solve(
                    prefix,
                    [*_pinned_choice(targets, installed, planned), *specs],
                    constraints,
                    hooks,
                )
            except UnsolvableError:
                pass
    return _pip_solve(prefix, requirements, constraints, hooks)


def _split_rebuilt(found, inventory):
    """Split newest wheels into targets and swaps of the installed build."""
    targets = {}
    rebuilt = {}
    for normalized, (name, newest) in found.items():
        installed_version = str(inventory[normalized].get("version"))
        if build_change(installed_version, newest):
            rebuilt[normalized] = (name, installed_version, newest)
        else:
            targets[normalized] = (name, newest)
    return targets, rebuilt


def _plan_pins(report):
    """Pin every package a pip report plans at its planned version."""
    items = [item.get("metadata") or {} for item in report.get("install", [])]
    return (
        [f"{item.get('name')}=={item.get('version')}" for item in items],
        {canonicalize_name(str(item.get("name"))) for item in items},
    )


def _grow_plan(solve, base, units):
    """Solve the selections, then add each unit that fits around that plan.

    ``solve(request, label)`` returns pip's report for a ``(targets, specs,
    fixed)`` request.  ``base`` holds the selections that can always stay as
    installed.  Each unit ``(key, label, [RepairOption])`` is then tried with
    everything planned so far pinned, so the solve searches only that unit's
    own versions and rejects an impossible one quickly.  A unit that did not
    fit is tried again after a later unit changed the plan (fastapi-cli fits
    only once typer has moved).  Returns ``(report, kept options, keys of
    units that did not fit)``.
    """
    report = {"install": []}
    if base:
        report = solve(
            (base, [], ()), f"Solving {count_label(len(base), 'selected package')}"
        )
    kept = []
    pending = list(enumerate(units, 1))
    retry = ""
    while pending:
        failed = []
        for position, (key, label, options) in pending:
            for option in options:
                pins, fixed = _plan_pins(report)
                try:
                    report = solve(
                        (dict(option.packages), [*pins, *option.specs], fixed),
                        f"[{position}/{len(units)}] {label}{retry}",
                    )
                except UnsolvableError:
                    continue
                kept.append(option)
                break
            else:
                failed.append((position, (key, label, options)))
        if len(failed) == len(pending):
            break
        pending = failed
        retry = " (retry after the plan changed)"
    return report, kept, [key for _, (key, _label, _options) in pending]


def _resolver_units(installed, found, selected, repairable):
    """Build the units the plan grows by: repairs first, then selections.

    ``repairable`` is ``(repair units, unrepairable)`` from repair_units;
    ``found`` maps every candidate to its newest wheel.  A repair option is
    usable only when each package it moves has a newer wheel of the same build.
    Returns ``(base targets, units, exposure, unrepairable)``.
    """
    units = repairable[0]
    unrepairable = list(repairable[1])
    exposure = installed.exposure(selected)
    grown = []
    for reason, options in units:
        usable = [
            RepairOption(
                tuple((name, found[name]) for name in option.packages),
                option.specs,
                option.tags,
            )
            for option in options
            if all(name in found for name in option.packages)
        ]
        if usable:
            grown.append((("repair", reason), f"repair: {reason}", usable))
        else:
            unrepairable.append(reason)
    grown.extend(
        (
            ("selection", normalized),
            (
                f"{selected[normalized][0]} -> {selected[normalized][1]}, "
                "which touches an existing conflict"
            ),
            [RepairOption(((normalized, selected[normalized]),), (), {})],
        )
        for normalized in sorted(exposure)
    )
    base = {name: target for name, target in selected.items() if name not in exposure}
    return base, grown, exposure, unrepairable


def _repair_candidates(repairable, inventory, wanted):
    """Return the display names of packages a repair may update."""
    return [
        inventory[normalized]["name"]
        for normalized in sorted(
            {
                package
                for _, options in repairable[0]
                for option in options
                for package in option.packages
            }
            - wanted
        )
    ]


def _outcome(found, selected, grown, exposure):
    """Assemble the ResolverOutcome from what the plan kept and dropped.

    ``found`` is ``(newest_requires, rebuilt selections)`` from the wheel search;
    ``grown`` is ``(report, kept options, failed unit keys, unrepairable)``.
    """
    newest_requires, rebuilt = found
    report, kept, failed, unrepairable = grown
    repairs = {}
    for option in kept:
        repairs.update(option.tags)
    return ResolverOutcome(
        targets=selected,
        newest_requires=newest_requires,
        report=report,
        set_aside={key: exposure[key] for kind, key in failed if kind == "selection"},
        rebuilt=rebuilt,
        repairs=repairs,
        unrepairable=unrepairable + [key for kind, key in failed if kind == "repair"],
    )


def _newest_wheels(prefix, names, inventory, repairable, hooks):
    """Find the newest same-build wheel of every selection and repair candidate.

    Returns ``(found, (newest_requires, rebuilt selections), selected)``:
    every candidate's target, the requirements of each newest wheel with the
    selections whose newest wheel is a different build, and the selections'
    targets.
    """
    wanted = {canonicalize_name(name) for name in names}
    found, newest_requires = _compatible_wheel_targets(
        prefix, [*names, *_repair_candidates(repairable, inventory, wanted)], hooks
    )
    found, rebuilt = _split_rebuilt(found, inventory)
    return (
        found,
        (
            newest_requires,
            {name: value for name, value in rebuilt.items() if name in wanted},
        ),
        {name: target for name, target in found.items() if name in wanted},
    )


def _logged_solve(progress, label, solve):
    """Run one solve as a named step, logging whether it found a plan."""
    progress.begin_step(label)
    try:
        report = solve()
    except UnsolvableError:
        progress.end_step("no solution, left out")
        raise
    progress.end_step("solved")
    return report


def _run_resolver(prefix, names, installed, repairable):
    """Find each candidate's newest wheel, then grow the joint plan with pip.

    The plan starts from the selections that can always stay as installed.
    Repairs of existing conflicts (``repairable``, from repair_units) and then
    the selections that touch an existing conflict are tried one at a time
    around that plan, each kept only if pip can solve it with everything kept
    before it.  Every solve is logged as a step, so a long one stays visible.
    """
    progress = ResolverProgress(names)
    progress.phase = "Discovering compatible wheels"
    progress.tick()
    hooks = StreamHooks(progress.watch, progress.note, progress.tick)
    uv = uv_resolver(prefix)
    try:
        found, searched, selected = _newest_wheels(
            prefix, names, installed.inventory, repairable, hooks
        )
        base, units, exposure, unrepairable = _resolver_units(
            installed, found, selected, repairable
        )
        grown = ({"install": []}, [], [])
        if base or units:
            progress.phase = "Resolving dependencies"
            grown = _grow_plan(
                lambda request, label: _logged_solve(
                    progress,
                    label,
                    lambda: _solve(prefix, request, installed, hooks, uv),
                ),
                base,
                units,
            )
    except BaseException:
        progress.finish(False)
        raise
    progress.finish(True)
    return _outcome(searched, selected, (*grown, unrepairable), exposure)


def _announce_unrepairable(outcome):
    """Name the existing conflicts no update the updater may make repairs."""
    if outcome.unrepairable:
        announce(
            "INFO",
            "These conflicts already existed, and no update of the packages "
            "involved repairs them (the updater never downgrades):",
            flush=True,
        )
        for reason in sorted(set(outcome.unrepairable)):
            print(f"      {reason}", flush=True)


def _announce_rebuilt(outcome):
    """Name selections whose newest wheel would swap their installed build."""
    for name, installed, newest in sorted(outcome.rebuilt.values()):
        announce(
            "INFO",
            f"{name} stays at {installed}: the newest wheel pip finds, {newest}, "
            "is a different build",
            flush=True,
        )


def _announce_set_aside(outcome):
    """Say which selections were left out because of an existing conflict."""
    if outcome.set_aside:
        names = sorted(
            outcome.targets[normalized][0] for normalized in outcome.set_aside
        )
        announce(
            "INFO",
            ", ".join(names)
            + " could not be planned with the rest: each touches a dependency "
            "conflict this environment already has, so they stay as they are.",
            flush=True,
        )


def resolve_update_plan(prefix, names):
    """Resolve an update without mutation and enforce package ownership."""
    if not names:
        raise UpdaterError("No package names were selected.")
    for name in names:
        if not SAFE_PROJECT_NAME.fullmatch(name):
            raise UpdaterError(f"Unsafe project name in selection: {name!r}")

    inventory = index_inventory(get_environment_inventory(prefix), prefix)
    ownership = load_conda_ownership(prefix)
    _check_selected_ownership(names, inventory, ownership, prefix)
    installed = InstalledRequirements.load(inventory, marker_environment(prefix))
    updatable = {
        normalized
        for normalized, row in inventory.items()
        if not _ownership_refusal(str(row.get("name")), inventory, ownership, prefix)
    }
    repairable = installed.repair_units(
        {canonicalize_name(name) for name in names},
        updatable,
        PROTECTED_BOOTSTRAP_PACKAGES | set(ownership["distributions"]),
    )

    outcome = _run_resolver(prefix, names, installed, repairable)
    raw_plan = report_install_items(
        outcome.report, "pip's install report did not contain an install list."
    )
    _announce_missing_wheels(names, outcome)
    _announce_rebuilt(outcome)
    _announce_set_aside(outcome)
    plan = _plan_from_report(raw_plan, inventory, ownership, prefix)
    for item in plan:
        normalized = canonicalize_name(item["name"])
        item["requested"] = normalized in outcome.targets
        if normalized in outcome.repairs:
            item["repair"] = outcome.repairs[normalized]
    _announce_conflict_repairs(plan, installed.broken)
    _announce_unrepairable(outcome)
    _report_holds(prefix, outcome, plan, installed)
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


def _wheel_identity(archive, names, wheel_name):
    """Return ``(dist_info, name, version)`` from a wheel's own METADATA."""
    # Anchor to the archive root: a wheel may legitimately ship a vendored
    # ``foo/bar.dist-info/METADATA`` as package data, which must not be
    # mistaken for the wheel's own identity.
    metadata_names = [
        name
        for name in names
        if name.lower().endswith(".dist-info/metadata") and name.count("/") == 1
    ]
    if len(metadata_names) != 1:
        raise UpdaterError(f"Wheel {wheel_name} has ambiguous METADATA.")
    metadata_text = archive.read(metadata_names[0]).decode("utf-8", errors="replace")
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
        raise UpdaterError(f"Wheel {wheel_name} lacks Name/Version metadata.")
    return PurePosixPath(metadata_names[0]).parent.as_posix(), project_name, version


def _wheel_member_target(info, wheel_name, prefix, bases):
    """Map one archive member to its prefix-relative install target.

    ``bases`` maps "root" and each supported ``.data`` category to its
    installation directory.
    """
    file_type = (info.external_attr >> 16) & 0o170000
    if file_type == stat.S_IFLNK:
        raise UpdaterError(f"Wheel {wheel_name} contains a symbolic link.")
    member = PurePosixPath(info.filename)
    if member.is_absolute() or ".." in member.parts:
        raise UpdaterError(f"Wheel {wheel_name} contains unsafe path {info.filename}.")
    parts = member.parts
    if not (parts and parts[0].lower().endswith(".data")):
        return _safe_relative_target(prefix, bases["root"], member.as_posix())
    if len(parts) < 3:
        raise UpdaterError(f"Wheel {wheel_name} has malformed .data path.")
    category = parts[1].lower()
    if category == "root" or category not in bases:
        raise UpdaterError(
            f"Wheel {wheel_name} uses unsupported .data category {category}."
        )
    rest = PurePosixPath(*parts[2:]).as_posix()
    return _safe_relative_target(prefix, bases[category], rest)


def _wheel_root_is_purelib(archive, names, dist_info, wheel_name):
    """Read the WHEEL file's Root-Is-Purelib flag."""
    wheel_metadata = f"{dist_info}/WHEEL"
    if wheel_metadata not in names:
        raise UpdaterError(f"Wheel {wheel_name} lacks WHEEL metadata.")
    wheel_text = archive.read(wheel_metadata).decode("utf-8", errors="replace")
    return any(
        line.lower() == "root-is-purelib: true" for line in wheel_text.splitlines()
    )


def _entry_point_script_targets(archive, names, dist_info, prefix, scripts_dir):
    """Return ``(entry_points_name, targets)`` of scripts pip will generate."""
    entry_points_name = f"{dist_info}/entry_points.txt"
    if entry_points_name not in names:
        return entry_points_name, []
    entry_points_text = archive.read(entry_points_name).decode(
        "utf-8", errors="replace"
    )
    return entry_points_name, [
        _safe_relative_target(prefix, scripts_dir, script)
        for script in generated_script_names(entry_points_text)
    ]


def _install_bases(layout, *, pure):
    """Map "root" and each supported ``.data`` category to its install dir."""
    return {
        "root": layout["purelib" if pure else "platlib"],
        "purelib": layout["purelib"],
        "platlib": layout["platlib"],
        "scripts": layout["scripts"],
        "data": layout["data"],
        "headers": layout["include"],
    }


def _member_targets(archive, wheel_name, prefix, bases):
    """Map each file member's install target to its archive name."""
    target_sources = {}
    for info in archive.infolist():
        if info.is_dir():
            continue
        target = _wheel_member_target(info, wheel_name, prefix, bases)
        if target in target_sources:
            raise UpdaterError(f"Wheel {wheel_name} maps multiple members to {target}.")
        target_sources[target] = info.filename
    return target_sources


def inspect_wheel(wheel_path, prefix, layout):
    """Read wheel identity, hash, and exact installation targets."""
    digest = file_sha256(wheel_path)

    try:
        archive = zipfile.ZipFile(wheel_path)
    except (OSError, zipfile.BadZipFile) as exc:
        raise UpdaterError(f"Invalid wheel {wheel_path}: {exc}") from exc
    with archive:
        names = archive.namelist()
        dist_info, project_name, version = _wheel_identity(
            archive, names, wheel_path.name
        )
        pure = _wheel_root_is_purelib(archive, names, dist_info, wheel_path.name)
        target_sources = _member_targets(
            archive, wheel_path.name, prefix, _install_bases(layout, pure=pure)
        )
        entry_points_name, scripts = _entry_point_script_targets(
            archive, names, dist_info, prefix, layout["scripts"]
        )
        for target in scripts:
            # setdefault, not _member_targets' duplicate check: a generated
            # script may legitimately coincide with a packaged script of the
            # same name, and pip still writes exactly one file.
            target_sources.setdefault(target, entry_points_name)
    return {
        "name": project_name,
        "version": version,
        "sha256": digest.hexdigest(),
        "path": str(wheel_path),
        "targets": set(target_sources),
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


def _record_claims(metadata_path, prefix_path, prefix):
    """Return the prefix-relative paths one RECORD claims, in RECORD order."""
    record_path = metadata_path / "RECORD"
    try:
        with open(
            record_path, newline="", encoding="utf-8", errors="replace"
        ) as handle:
            rows = list(csv.reader(handle))
    except OSError as exc:
        raise UpdaterError(f"Could not read {record_path}: {exc}") from exc
    claims = []
    for row in rows:
        if not row or not row[0]:
            continue
        target = (metadata_path.parent / Path(row[0])).resolve(strict=False)
        try:
            claims.append(target.relative_to(prefix_path).as_posix())
        except ValueError as exc:
            raise UpdaterError(
                f"Installed RECORD path escapes {prefix}: {row[0]}"
            ) from exc
    return claims


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
        for relative in _record_claims(metadata_path, prefix_path, prefix):
            previous = owners.get(relative)
            if previous and previous != name:
                shared_claims.setdefault(relative, {previous}).add(name)
                continue
            owners[relative] = name
    return owners, distributions_with_records, shared_claims


def current_copy_owners(prefix, inventory, claimants, paths):
    """Return the sharers whose recorded hashes match every shared file on disk.

    Each sharer is judged by its installer's own ledger (see InstallLedgers).
    A sharer counts only if it hashes at least one of the files.  Both match
    when their copies are identical; neither matches when the files differ
    from every recorded copy, or when one package's copy was only partly
    overwritten.
    """
    ledgers = InstallLedgers(prefix)
    prefix_path = ledgers.prefix_path
    hashes = {name: ledgers.hashes(inventory[name])[1] for name in claimants}
    checked = dict.fromkeys(claimants, 0)
    matching = set(claimants)
    for relative in paths:
        actual = _file_hash_field(prefix_path / relative)
        for name in claimants:
            expected = hashes[name].get(relative)
            if expected is None:
                continue
            checked[name] += 1
            if expected != actual:
                matching.discard(name)
    return {name for name in matching if checked[name]}


def declared_dependents(rows):
    """Map each distribution to the installed ones whose requirements name it.

    Requirements that apply only with an extra are left out: installing the
    requiring package does not by itself pull them in.
    """
    dependents = {}
    for row in rows:
        holder = canonicalize_name(str(row.get("name") or ""))
        for requirement in row.get("requires") or []:
            text = str(requirement)
            if re.search(r"\bextra\s*==", text):
                continue
            name = re.split(r"[\s\[<>=!~;(]", text, maxsplit=1)[0]
            if name and holder:
                dependents.setdefault(canonicalize_name(name), set()).add(holder)
    return dependents


def shared_file_report(prefix, plan):
    """Describe files a planned package shares with a package staying as it is.

    The overlap is a property of the installed environment, not of the update,
    so it is surfaced while the user can still decline rather than raised as an
    error once the downloads have already run.  Each group records whose copy
    is on disk now (by installer file hash) and which installed packages declare each
    sharer as a requirement.  Neither is used to recommend a removal: absence
    from requirement metadata does not prove that nothing loads a package's
    files directly.
    """
    planned = {canonicalize_name(item["name"]) for item in plan}
    rows = get_environment_inventory(prefix)
    inventory = index_inventory(rows, prefix)
    _, _, shared_claims = installed_file_owners(prefix, inventory)
    paths_by_group = {}
    for relative, claimants in shared_claims.items():
        if not claimants & planned or claimants <= planned:
            continue
        paths_by_group.setdefault(frozenset(claimants), []).append(relative)
    dependents = declared_dependents(rows)
    details = {
        key: {
            "on_disk": current_copy_owners(prefix, inventory, key, paths),
            "required_by": {name: dependents.get(name, set()) for name in key},
        }
        for key, paths in paths_by_group.items()
    }
    return {
        "groups": {key: len(paths) for key, paths in paths_by_group.items()},
        "details": details,
    }


def _sharer_line(name, required_by):
    """One sharer and the installed packages that declare it, for the warning."""
    if required_by:
        shown = sorted(required_by)
        listed = ", ".join(shown[:3])
        if len(shown) > 3:
            listed += f" and {len(shown) - 3} more"
        need = f"required by {listed}"
    else:
        need = paint("no installed package declares it as a requirement", "muted")
    return f"      {paint(name, 'strong')}: {need}"


def _on_disk_line(claimants, owners):
    if len(owners) == 1:
        (owner,) = owners
        return f"      Files on disk now: {paint(owner, 'strong')}'s copy"
    if owners and owners == claimants:
        return "      Files on disk now: identical in every package"
    return "      Files on disk now: " + paint(
        "a mix that matches no single package's copy", "note"
    )


def print_shared_file_warning(report):
    """Explain pre-existing file overlap in terms a non-expert can act on."""
    groups = report["groups"]
    if not groups:
        return
    details = report.get("details") or {}
    total = sum(groups.values())
    print_section(f"SHARED FILES ({count_label(total, 'file')})")
    wrap = functools.partial(
        textwrap.fill, width=76, initial_indent="  ", subsequent_indent="  "
    )
    print(
        wrap(
            "Some files are installed by more than one package. Only one copy of "
            "each can exist on disk, so whichever package was installed last "
            "provides them. This was already the case before this update."
        )
    )
    for claimants, count in sorted(
        groups.items(), key=lambda entry: (-entry[1], sorted(entry[0]))
    ):
        print(
            f"\n    {paint(count_label(count, 'file'), 'strong')} shared by "
            + " and ".join(sorted(claimants))
        )
        group = details.get(claimants)
        if group:
            print(_on_disk_line(claimants, group["on_disk"]))
            for name in sorted(claimants):
                print(_sharer_line(name, group["required_by"].get(name)))
    print()
    print(
        wrap(
            "Safe to continue: the updater inspects the new wheels first and "
            "stops before changing anything if an update would leave a shared "
            "file missing or replaced by the wrong copy."
        )
    )
    print(
        wrap(
            "This warning does not prove either package is unused: programs can "
            "load a package's files without declaring it (bitsandbytes, for "
            "example, loads CUDA 12 libraries directly), so the updater never "
            "removes either one. Do not uninstall either package solely because "
            "it appears in this list."
        )
    )


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


def pip_install_report(
    prefix, arguments, *, action, report_name, constraints=(), **stream_options
):
    """Run ``pip install --dry-run --report`` and return pip's parsed report.

    Nothing is installed.  ``constraints`` lines reach pip as a constraints
    file.  ``action`` names the step in errors ("Resolving updates for /env");
    ``report_name`` names the report pip failed to write.  Raises
    UnsolvableError when pip proves the requirements impossible.
    """
    with tempfile.TemporaryDirectory(prefix="pip-updater-report-") as tmp:
        report_path = Path(tmp) / "report.json"
        options = ["--report", str(report_path)]
        if constraints:
            constraints_path = Path(tmp) / "constraints.txt"
            constraints_path.write_text("\n".join(constraints) + "\n", encoding="utf-8")
            options += ["-c", str(constraints_path)]
        result = stream_command(
            pip_command(prefix) + ["install", "--dry-run", *options] + list(arguments),
            **stream_options,
        )
        if result.returncode != 0:
            failure = command_failure(action, result, max_lines=60)
            output = f"{result.stdout}{result.stderr}"
            if "ResolutionImpossible" in output or "ResolutionTooDeep" in output:
                raise UnsolvableError(str(failure))
            raise failure
        try:
            raw_report = report_path.read_text(encoding="utf-8")
        except OSError as exc:
            raise UpdaterError(
                f"pip completed without writing its {report_name} report."
            ) from exc
    return parse_json_output(raw_report, action[:1].lower() + action[1:])


def report_install_items(report, message):
    """Return a pip report's install list, or raise ``message``."""
    items = report.get("install", [])
    if not isinstance(items, list):
        raise UpdaterError(message)
    return items


def report_download(raw_item):
    """Return ``(url, sha256)`` from a pip report item; sha256 None if unusable.

    A usable digest is a 64-digit hex SHA-256, returned lowercased.
    """
    download = raw_item.get("download_info") or {}
    sha256 = ((download.get("archive_info") or {}).get("hashes") or {}).get("sha256")
    if not isinstance(sha256, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", sha256):
        sha256 = None
    return download.get("url"), sha256.lower() if sha256 else None


def is_index_artifact(raw_item):
    """True unless a report item comes from a direct URL, VCS, or directory."""
    download = raw_item.get("download_info") or {}
    return not (
        raw_item.get("is_direct")
        or download.get("vcs_info")
        or download.get("dir_info")
    )


def _rollback_artifact(raw_item, expected):
    """Validate one rollback report item against ``expected`` exact versions.

    A yanked release is accepted here, unlike in the update plan: the rollback
    copy restores the version that is already installed, pip honours an exact
    ``==`` pin on a yanked release, and the file is still pinned by SHA-256.
    Refusing it would block every update of a package whose installed release
    was later withdrawn, which is exactly when updating matters most.
    """
    metadata = raw_item.get("metadata") or {}
    name = str(metadata.get("name") or "")
    version = str(metadata.get("version") or "")
    expected_name, expected_version = expected[canonicalize_name(name)]
    if version != expected_version:
        raise UpdaterError(
            f"pip selected {name} {version}, not rollback version {expected_version}."
        )
    url, sha256 = report_download(raw_item)
    if not is_index_artifact(raw_item):
        raise UpdaterError(
            f"pip did not select a package-index rollback wheel for {name} {version}."
        )
    if not sha256:
        raise UpdaterError(
            f"The rollback wheel for {name} {version} lacks a SHA-256 digest."
        )
    return {
        "name": expected_name,
        "version": version,
        "sha256": sha256,
        "url": url,
        "filename": wheel_filename_from_url(url),
        "yanked": bool(raw_item.get("is_yanked")),
    }


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

    report = pip_install_report(
        prefix,
        [
            "--ignore-installed",
            "--no-deps",
            "--only-binary=:all:",
            "--disable-pip-version-check",
            *specs,
        ],
        action="Locating exact rollback wheels",
        report_name="rollback-wheel",
        timeout=300,
    )
    raw_items = report_install_items(
        report, "pip's rollback-wheel report had no install list."
    )
    found = {}
    for raw_item in raw_items:
        metadata = raw_item.get("metadata") or {}
        normalized = canonicalize_name(str(metadata.get("name") or ""))
        if normalized not in expected or normalized in found:
            raise UpdaterError(
                "pip returned an invalid or unexpected rollback-wheel candidate."
            )
        found[normalized] = _rollback_artifact(raw_item, expected)
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
        hooks=StreamHooks(on_tick=progress.tick),
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
            " ",
            paint("[INFO]", "info"),
            "Parallel transfer was unavailable; retrying these files with pip.",
            file=progress.display.stream,
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
        hooks=StreamHooks(progress.watch, progress.note, progress.tick),
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
        ordered = _artifacts_in_spec_order(specs, artifacts)
        if ordered is not None:
            misses = _copy_cached_wheels(prefix, ordered, destination, progress)
            if not misses or download_with_aria2(misses, destination, progress):
                remaining_specs = []
            else:
                missed = {canonicalize_name(item["name"]) for item in misses}
                remaining_specs = [
                    spec
                    for spec in specs
                    if canonicalize_name(spec.split("==", 1)[0]) in missed
                ]
        if remaining_specs:
            _download_with_pip(prefix, remaining_specs, destination, progress)
    finally:
        progress.finish()


def _artifacts_in_spec_order(specs, artifacts):
    """Return ``artifacts`` ordered like ``specs``, or None if any is missing.

    Without an artifact for every spec, pip's own downloader must fetch them.
    """
    if not artifacts or len(artifacts) != len(specs):
        return None
    by_name = {canonicalize_name(item["name"]): item for item in artifacts}
    filenames = [item.get("filename") for item in artifacts]
    if len(by_name) != len(artifacts) or len(set(filenames)) != len(filenames):
        raise UpdaterError(
            "The resolved download set contains duplicate names or filenames."
        )
    ordered = [by_name.get(canonicalize_name(spec.split("==", 1)[0])) for spec in specs]
    return None if None in ordered else ordered


def _copy_cached_wheels(prefix, ordered, destination, progress):
    """Copy hash-verified wheels out of pip's HTTP cache; return the misses."""
    cache_root = pip_cache_root(prefix)
    misses = []
    for item in ordered:
        target = Path(destination) / item["filename"]
        body = cached_http_body(cache_root, item["url"])
        if copy_verified_cache_body(body, target, item["sha256"]):
            progress.cache_hit(item["filename"])
            progress.tick()
        else:
            misses.append(item)
    return misses


def _reverse_requirements(plan):
    """Map each dependency name to the plan items that unconditionally need it."""
    reverse = {}
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
                reverse.setdefault(canonicalize_name(dependency), set()).add(parent)
    return reverse


def _selected_causes(name, reverse_requirements, items):
    """Return the user-selected updates that transitively pull in ``name``."""
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
    reverse_requirements = _reverse_requirements(plan)

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
        skip_updates.update(_selected_causes(name, reverse_requirements, items))

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


def _check_downloaded_artifacts(plan, new_wheels, *, require_complete):
    """Require downloaded wheels to be exactly the plan's reported artifacts."""
    planned_names = {canonicalize_name(item["name"]) for item in plan}
    downloaded_names = set(new_wheels)
    invalid = downloaded_names - planned_names
    if invalid or (require_complete and downloaded_names != planned_names):
        missing = planned_names - downloaded_names
        raise UpdaterError(
            "Downloaded wheel set differs from plan "
            f"(missing={sorted(missing)}, extra={sorted(invalid)})."
        )
    for item in plan:
        wheel = new_wheels.get(canonicalize_name(item["name"]))
        if wheel is None:
            continue
        if wheel["version"] != item["version"] or wheel["sha256"] != item["sha256"]:
            raise UpdaterError(
                f"Downloaded artifact for {item['name']} does not match the "
                "resolved report."
            )


class _WheelOwnershipCheck:
    """File-ownership rules for installing one transaction's new wheels.

    Ownership decisions always use the complete plan, so a package already
    scheduled for replacement is never mistaken for a fixed external owner.
    """

    def __init__(self, prefix, plan, new_wheels, inventory, ownership):
        self.prefix = prefix
        self.planned = {canonicalize_name(item["name"]) for item in plan}
        self.downloaded = set(new_wheels)
        self.conda_paths = ownership["paths"]
        self.owners, with_records, self.shared = installed_file_owners(
            prefix, inventory
        )
        self.proposed = {}
        self._check_installed_records(inventory, with_records)

    def _check_installed_records(self, inventory, with_records):
        for name in self.downloaded:
            if name in inventory and name not in with_records:
                raise UpdaterError(
                    f"Cannot safely replace {name}: installed RECORD is missing."
                )
        for target, installed_owner in self.owners.items():
            claimants = self.shared.get(target, {installed_owner})
            implicated = sorted(claimants & self.downloaded)
            if implicated and target in self.conda_paths:
                raise UpdaterError(
                    f"Installed pip RECORD for {implicated[0]} claims Conda-owned "
                    f"file {target}."
                )

    def claim_targets(self, new_wheels):
        """Claim every new wheel target; return ownership collisions found.

        Collisions map ``(updating, owner)`` to the files both claim.  Every
        other unsafe target raises UpdaterError immediately.
        """
        collisions = {}
        prefix_path = Path(self.prefix).resolve(strict=False)
        for normalized, wheel in new_wheels.items():
            for target in wheel["targets"]:
                self._claim(normalized, wheel, target, prefix_path, collisions)
        return collisions

    def _claim(self, normalized, wheel, target, prefix_path, collisions):
        """Record ``wheel`` as the new owner of ``target``, or reject it."""
        if target in self.conda_paths:
            raise UpdaterError(
                f"Wheel {wheel['name']} would overwrite Conda-owned file {target}."
            )
        installed_owner = self.owners.get(target)
        claimants = self.shared.get(target) or (
            {installed_owner} if installed_owner else set()
        )
        # The wheel's own predecessor being a claimant makes this an
        # in-place replacement, not a takeover -- generated console
        # scripts especially are claimed by every distribution that
        # declares them, in whichever order RECORDs were read.
        if claimants and normalized not in claimants and not claimants & self.planned:
            # Gathered rather than raised one at a time: a single filename
            # says nothing, but the whole set names the two packages that
            # cannot both stay installed.
            for owner in sorted(claimants):
                collisions.setdefault((wheel["name"], owner), []).append(target)
            return
        previous = self.proposed.get(target)
        # Two wheels that already share installed files (cu12/cu13 builds of
        # one NVIDIA library install into the same directory) may extend that
        # overlap when a new release adds a file the other build already had;
        # only a first overlap between packages is a new conflict.
        if (
            previous
            and previous != normalized
            and target not in self.shared
            and not any(
                {previous, normalized} <= claimants
                for claimants in self.shared.values()
            )
        ):
            raise UpdaterError(
                f"Planned wheels {previous} and {normalized} both install {target}."
            )
        self.proposed[target] = normalized
        target_path = prefix_path / Path(*PurePosixPath(target).parts)
        if (
            target_path.exists()
            and installed_owner not in self.planned
            and target not in self.shared
        ):
            raise UpdaterError(
                f"Wheel {wheel['name']} would overwrite unowned existing file {target}."
            )

    def check_stranded_shared_files(self):
        """Reject deleting a shared file that no planned wheel puts back."""
        # A path claimed by several installed distributions is already decided
        # by whichever wheel was written last; this transaction did not create
        # that ambiguity and refusing to run would strand the environment
        # forever (the NVIDIA cu12/cu13 wheels share one `nvidia/` namespace by
        # design).  The one outcome that is genuinely worse than the status quo
        # is a shared file that disappears: --force-reinstall removes every path
        # the planned package's own RECORD lists, so if no planned wheel ships
        # it back, the other claimants silently lose a file that nothing will
        # restore.
        for target, claimants in sorted(self.shared.items()):
            if target in self.proposed or not claimants & self.downloaded:
                continue
            stranded = sorted(claimants - self.planned)
            if not stranded:
                continue
            updating = ", ".join(sorted(claimants & self.planned))
            raise UpdaterError(
                f"Updating {updating} would delete {target}, which "
                f"{', '.join(stranded)} also needs and no updated package puts "
                "back.\n"
                f"Update {', '.join(sorted(claimants))} together, or none of them."
            )


def _check_wheel_ownership(prefix, plan, new_wheels, inventory, ownership):
    check = _WheelOwnershipCheck(prefix, plan, new_wheels, inventory, ownership)
    collisions = check.claim_targets(new_wheels)
    if collisions:
        raise UpdaterError(explain_owner_collisions(prefix, collisions, plan))
    check.check_stranded_shared_files()


def validate_new_wheels(prefix, plan, new_wheels, inventory, ownership):
    """Require the complete wheelhouse and reject every ownership collision."""
    _check_downloaded_artifacts(plan, new_wheels, require_complete=True)
    _check_wheel_ownership(prefix, plan, new_wheels, inventory, ownership)


def validate_introduced_wheels(prefix, plan, new_wheels, inventory, ownership):
    """Check newly introduced dependencies before the large main download.

    Only part of the plan is downloaded yet, so the wheel set may be partial;
    ownership is still judged against the complete plan.  The assembled
    wheelhouse is always checked again by validate_new_wheels.
    """
    _check_downloaded_artifacts(plan, new_wheels, require_complete=False)
    _check_wheel_ownership(prefix, plan, new_wheels, inventory, ownership)


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
    inventory = index_inventory(get_environment_inventory(prefix), prefix)
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
        announce("INFO", "Removing the newly introduced packages...", flush=True)
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
        announce("INFO", "Restoring the previous package versions...", flush=True)
        specs = [f"{name}=={version}" for name, version in sorted(old_versions.items())]
        result = _install_local_wheels(
            prefix, Path(transaction_dir) / "old", specs, "Restoring        "
        )
        if result.returncode != 0:
            raise command_failure("Restoring previous wheels", result)
    announce("INFO", "Verifying the restored environment...", flush=True)
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
                announce(
                    "INFO",
                    f"Removing abandoned download workspace "
                    f"{transaction_dir.name} ({int(age // 3600)}h old, no journal).",
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


def _initialize_transaction(transaction_dir, prefix):
    """Journal the prefix and create the wheelhouses of a new transaction."""
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
    for name in ("new", "new-dependency-preflight", "old"):
        (transaction_dir / name).mkdir(mode=0o700)


def _exact_specs(items):
    return [f"{item['name']}=={item['version']}" for item in items]


def _download_new_wheels(prefix, plan, transaction_dir, inventory, ownership):
    """Download and validate every new wheel into ``transaction_dir/new``."""
    new_dir = transaction_dir / "new"
    preflight_dir = transaction_dir / "new-dependency-preflight"
    introduced = [
        item
        for item in plan
        if "current_version" in item and item["current_version"] is None
    ]
    remaining = [item for item in plan if item not in introduced]
    if introduced:
        announce(
            "INFO",
            "Checking newly introduced dependencies before the large download...",
            flush=True,
        )
        download_exact_wheels(
            prefix,
            _exact_specs(introduced),
            preflight_dir,
            "New dependencies ",
            artifacts=introduced,
        )
        validate_introduced_wheels(
            prefix,
            plan,
            inspect_wheelhouse(preflight_dir, prefix),
            inventory,
            ownership,
        )

    download_exact_wheels(
        prefix,
        _exact_specs(remaining),
        new_dir,
        "New packages     ",
        artifacts=remaining,
    )
    for wheel in preflight_dir.glob("*.whl"):
        os.replace(wheel, new_dir / wheel.name)
    # Nothing has touched the environment yet, so reject an unsafe new
    # wheel as soon as its exact paths are known.  In particular, do not
    # make the user fetch a second multi-gigabyte rollback batch for a
    # transaction that can never be applied.
    validate_new_wheels(
        prefix, plan, inspect_wheelhouse(new_dir, prefix), inventory, ownership
    )


def _download_rollback_wheels(prefix, old_versions, old_dir):
    """Download exact wheels of the installed versions an update replaces."""
    old_specs = [f"{name}=={version}" for name, version in old_versions.items()]
    if old_specs:
        announce("INFO", "Locating exact rollback wheels...", flush=True)
    old_artifacts = resolve_exact_download_artifacts(prefix, old_specs)
    withdrawn = [item for item in old_artifacts if item.get("yanked")]
    if withdrawn:
        announce(
            "INFO",
            "Installed "
            + ", ".join(f"{item['name']} {item['version']}" for item in withdrawn)
            + (" was" if len(withdrawn) == 1 else " were")
            + " withdrawn (yanked) from the package index; the exact copy is"
            " still used as the rollback copy.",
            flush=True,
        )
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


def prepare_transaction(prefix, plan, baseline):
    """Download new and rollback wheels, then validate all target paths."""
    transaction_dir = None
    try:
        transaction_dir = Path(tempfile.mkdtemp(prefix="txn-", dir=transaction_root()))
        _initialize_transaction(transaction_dir, prefix)
        inventory = index_inventory(get_environment_inventory(prefix), prefix)
        ownership = load_conda_ownership(prefix)
        old_versions = {}
        new_only = []
        for item in plan:
            installed = inventory.get(canonicalize_name(item["name"]))
            if installed:
                old_versions[item["name"]] = installed["version"]
            else:
                new_only.append(item["name"])

        _download_new_wheels(prefix, plan, transaction_dir, inventory, ownership)
        _download_rollback_wheels(prefix, old_versions, transaction_dir / "old")
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
            hooks=StreamHooks(on_start=progress.watch, on_tick=progress.tick),
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
        announce("INFO", "Verifying the updated environment...", flush=True)
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
    announce(
        "INFO",
        "Downloading both the new packages and rollback copies first.",
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
        announce(
            "OK",
            "Downloads, checksums, and file-ownership checks passed.",
            flush=True,
        )
        announce(
            "INFO",
            f"Installing the verified packages into '{env_label}'...",
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


def format_plan_change(item, name_width=0, version_width=0):
    """Format one package change in user-facing current-to-new form.

    The widths pad the name and current version into columns so a group's
    arrows line up.
    """
    current = item.get("current_version") or "not installed"
    name = paint(f"{item['name'] + ':':<{name_width}}", "strong")
    arrow = paint("→" if paint.enabled else "->", "muted")
    line = (
        f"  {name} {paint(f'{current:<{version_width}}', 'muted')} {arrow} "
        f"{paint(item['version'], 'new')}"
    )
    if item.get("newest"):
        note = f"(newest is {item['newest']}; capped by another package)"
        line += " " + paint(note, "note")
    if item.get("repair"):
        line += " " + paint(f"(repairs: {item['repair']})", "note")
    return line


def print_plan_group(title, items):
    """Print one logically grouped set of package changes."""
    if not items:
        return
    print_section(f"{title} ({len(items)}):")
    # A single very long name should not push every other row far right.
    name_width = min(40, max(len(item["name"]) + 1 for item in items))
    version_width = min(
        20, max(len(item.get("current_version") or "not installed") for item in items)
    )
    for item in sorted(items, key=lambda value: value["name"].lower()):
        print(format_plan_change(item, name_width, version_width))


def print_resolved_plan(plan, *, show_details=False):
    """Explain direct, dependency, and major-version changes in plain language."""
    selected = [item for item in plan if item["requested"]]
    repairs = [item for item in plan if item.get("repair")]
    dependencies = [
        item for item in plan if not item["requested"] and not item.get("repair")
    ]
    major_changes = [item for item in selected if is_major_version_change(item)]
    routine_changes = [item for item in selected if item not in major_changes]

    print_section("PACKAGE CHANGES")
    print(
        f"  {count_label(len(selected), 'package')} you selected; "
        + (
            count_label(
                len(repairs),
                "repair of an existing conflict",
                "repairs of existing conflicts",
            )
            + "; "
            if repairs
            else ""
        )
        + f"{count_label(len(dependencies), 'required dependency change')}."
    )
    print_plan_group(
        "Review carefully — major-version updates can change behavior",
        major_changes,
    )
    print_plan_group("Other selected updates", routine_changes)
    print_plan_group("Repairs of conflicts that already existed", repairs)
    print_plan_group("Extra dependencies required automatically", dependencies)

    if show_details:
        print_section("Technical artifact checksums:")
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
    command = [sys.executable, display_script_command(), env_name]
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
        sys.executable,
        display_script_command(),
        env_name,
        "--packages",
        package_name,
        "--refresh",
    ]
    if show_details:
        command.append("--details")
    return shlex.join(command)


PIP_MISSING_PATTERN = re.compile(
    r"^(?P<holder>\S+) (?P<holder_version>\S+) requires (?P<missing>\S+), "
    r"which is not installed\.?$"
)


def conflict_package_names(line):
    """Return the package names one raw `pip check` line is about."""
    line = line.strip()
    match = PIP_CONFLICT_PATTERN.match(line)
    if match:
        return {
            canonicalize_name(match["holder"]),
            canonicalize_name(match["installed"]),
        }
    match = PIP_MISSING_PATTERN.match(line)
    if match:
        return {canonicalize_name(match["holder"]), canonicalize_name(match["missing"])}
    return set()


def _print_conflict_outlook(existing_conflicts, plan):
    """Say how many pre-existing conflicts this plan addresses."""
    planned = {canonicalize_name(item["name"]) for item in plan}
    covered = [
        line for line in existing_conflicts if conflict_package_names(line) & planned
    ]
    if covered:
        pronoun = "it" if len(covered) == 1 else "them"
        announce(
            "OK",
            "This plan installs or updates the packages behind "
            f"{len(covered)} of "
            f"{count_label(len(existing_conflicts), 'existing conflict')}, "
            f"which should repair {pronoun}.",
        )
    remaining = len(existing_conflicts) - len(covered)
    if remaining:
        verb, pronoun = ("involves", "it") if remaining == 1 else ("involve", "they")
        announce(
            "!",
            f"{count_label(remaining, 'existing conflict')} {verb} packages "
            f"this plan does not touch, so {pronoun} will still be there afterward.",
        )


def print_dry_run_result(env_name, args, selected, plan, baseline=None):
    """End a preview with an interpretation and a concrete next action.

    ``baseline`` is the environment health check's result, when there is one.
    """
    baseline = baseline or {}
    existing_conflicts = set(baseline.get("pip_broken") or ())
    repair_pending = bool(baseline.get("repair_pending"))
    major_changes = [item for item in plan if is_major_version_change(item)]
    print_banner("PREVIEW COMPLETE — NO CHANGES WERE MADE", "preview")
    if repair_pending:
        announce(
            "REPAIR",
            "A real run first repairs the damaged Conda files described "
            "above, automatically.",
        )
    if existing_conflicts:
        if not repair_pending:
            announce(
                "OK", "Conda-managed packages are healthy and will stay untouched."
            )
        _print_conflict_outlook(existing_conflicts, plan)
    elif not repair_pending:
        announce("OK", "The environment health and package-ownership checks passed.")
    announce("OK", "pip found a compatible installation plan.")
    untouched = "Conda-managed packages and core update tools will stay untouched."
    if repair_pending:
        untouched = "Apart from that repair, " + untouched[0].lower() + untouched[1:]
    announce("OK", f"{untouched}")
    announce(
        "INFO", "Package files are downloaded and inspected only during a real update."
    )
    if major_changes:
        names = ", ".join(
            item["name"]
            for item in sorted(major_changes, key=lambda value: value["name"].lower())
        )
        verb = "needs" if len(major_changes) == 1 else "need"
        announce(
            "REVIEW",
            f"{count_label(len(major_changes), 'major-version change')} "
            f"{verb} extra care: {names}.",
        )

    print_section("What to do next:")
    if major_changes:
        print(
            "  Safest approach: update and test the major-version packages "
            "one at a time:"
        )
        for item in sorted(major_changes, key=lambda value: value["name"].lower()):
            command = build_single_package_command(
                env_name, item["name"], show_details=args.details
            )
            print("\n    " + paint(command, "command"))
        print("\n  After each update, start the application or run its tests.")
        print("  Then run your preview command again to see what remains.")
        print("\n  Faster but higher risk: apply every update at once:")
        print(
            "\n    " + paint(build_apply_command(env_name, args, selected), "command")
        )
    else:
        print("  To apply this selection, run:")
        print(
            "\n    " + paint(build_apply_command(env_name, args, selected), "command")
        )
        print("\n  Afterward, start the application or run its tests.")
    print("\nThe updater will recheck everything and ask before installing.")
    print(
        "\n"
        + paint(
            "Note: these checks protect package integrity; they cannot predict "
            "every application-level behavior change.",
            "muted",
        )
    )


def print_no_updates_result(env_name, *, all_held=False):
    """Explain a clean scan as a successful no-op."""
    print_banner("NOTHING TO UPDATE", "ok")
    if all_held:
        announce(
            "OK",
            "Every selected package is already as new as this updater can "
            "install (see the reasons above).",
        )
    else:
        announce(
            "OK", f"All eligible pip packages in '{env_name}' are already current."
        )
    announce(
        "INFO", "Automatically skipped Conda-managed/core packages need no action."
    )


def print_update_success(env_name, plan, before_conflicts=(), after_conflicts=()):
    """Report a successful transaction and its recommended follow-up."""
    before = set(before_conflicts)
    after = set(after_conflicts)
    selected_count = sum(bool(item["requested"]) for item in plan)
    repair_count = sum(bool(item.get("repair")) for item in plan)
    dependency_count = len(plan) - selected_count - repair_count
    repaired = (
        count_label(
            repair_count,
            "package that repairs an existing conflict",
            "packages that repair existing conflicts",
        )
        + ", and "
        if repair_count
        else "and "
    )
    print_banner("UPDATE COMPLETED SUCCESSFULLY", "ok")
    announce(
        "OK",
        f"Updated {count_label(selected_count, 'selected package')}"
        f"{', ' if repair_count else ' '}{repaired}"
        f"{count_label(dependency_count, 'required dependency package')} "
        f"in '{env_name}'.",
    )
    capped = sorted(item["name"] for item in plan if item.get("newest"))
    if capped:
        announce(
            "INFO",
            f"{count_label(len(capped), 'package')} went only as far as other "
            f"packages allow: {', '.join(capped)}.",
        )
        print(
            "       pip still lists newer releases for them; the updater shows them "
            "as version-capped until the capping package changes."
        )
    if after:
        if before - after:
            announce(
                "OK",
                f"Repaired {count_label(len(before - after), 'conflict')} "
                "that existed before this update.",
            )
        one = len(after) == 1
        announce(
            "!",
            f"{count_label(len(after), 'conflict')} still "
            f"{'needs' if one else 'need'} attention:",
        )
        for line in sorted(after):
            print(f"      {describe_pip_conflict(line)}")
        print(
            f"    This update did not cause {'it' if one else 'them'} "
            f"and did not make {'it' if one else 'them'} worse."
        )
    else:
        announce("OK", "pip reports no broken requirements.")
        if before:
            announce(
                "OK",
                f"The {count_label(len(before), 'conflict')} that existed "
                "before this update is now resolved.",
            )
    announce("OK", "Conda-managed files and environment health are unchanged.")
    print(
        "\n" + paint("Next:", "strong"),
        "start the application or run its tests to confirm normal behavior.",
    )


@dataclasses.dataclass
class _UpdateTarget:
    """The environment one pass of main() works on, and the run's options."""

    args: argparse.Namespace
    env_name: str
    prefix: str
    fixed: bool
    env_key: str = dataclasses.field(init=False)
    # Set when this pass updated the environment or found nothing to update;
    # the picker then shows it in green with a check mark.
    finished: bool = dataclasses.field(default=False, init=False)

    def __post_init__(self):
        self.env_key = str(Path(self.prefix).resolve())


def _fixed_environment(args, environments, root_prefix):
    """Return the ``(name, prefix)`` named on the command line, if any."""
    if not args.env_name:
        return None
    fixed = resolve_environment(args.env_name, environments)
    if fixed[1] == root_prefix:
        raise UpdaterError(
            "Refusing to update Conda's base environment. Base contains Conda's own "
            "control plane; create or select a named environment instead."
        )
    return fixed


def _choose_environment(selectable, environments, finished):
    """Let the user pick an environment; None when they quit."""
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise UpdaterError(
            "env_name is required in non-interactive mode. Available named "
            "environments: " + ", ".join(selectable)
        )
    try:
        env_name = curses.wrapper(interactive_select_env, selectable, finished)
    except curses.error as exc:
        raise UpdaterError(
            f"Failed to initialize environment selector ({exc}). "
            "Run the script directly in a local terminal session."
        ) from exc
    if not env_name:
        return None
    return env_name, environments[env_name]


def _check_environment(prefix, root_prefix, *, dry_run):
    """Activate, health-check and repair the environment.

    Returns the health check's baseline (see preflight_health).
    """
    print_step("1/3", "Activating and checking the environment...")
    activate_environment(prefix, root_prefix)
    with environment_lock(prefix):
        recover_incomplete_transactions(prefix)
        baseline = preflight_health(prefix, repair=True, dry_run=dry_run)
    existing_conflicts = set(baseline["pip_broken"])
    conda_issues = baseline.get("conda_issues") or {}
    if baseline.get("repair_pending"):
        pass  # The preview already said what a real run repairs first.
    elif existing_conflicts or conda_issues:
        announce("OK", "Conda's own files are all present and unaltered.")
    else:
        announce("OK", "Environment health checks passed.")
    print_conda_inconsistencies(conda_issues)
    if existing_conflicts:
        print_existing_conflicts(existing_conflicts)
    return baseline


def _live_scan(target, *, report_exclusions=True):
    packages = scan_outdated_packages(
        target.prefix, report_exclusions=report_exclusions
    )
    set_cached_packages(target.env_key, packages)
    return packages


def _find_outdated(target):
    """Return ``(packages, from_cache, live)``, or None when nothing is outdated.

    ``live`` means the list came from a scan performed moments ago in this run,
    with no user interaction since.
    """
    args = target.args
    print_step("2/3", "Looking for pip packages that can be safely updated...")
    packages, from_cache = get_outdated_packages(
        target.env_key, target.prefix, refresh=args.refresh
    )
    if from_cache:
        announce("OK", "Loaded the previous package scan; it will be rechecked live.")
    else:
        announce("OK", "Fresh package scan completed.")
    if args.details:
        announce("DETAIL", f"Scan cache: {CACHE_FILE}")
    if packages:
        announce(
            "OK", f"Found {count_label(len(packages), 'package')} that can be updated."
        )
        return packages, from_cache, not from_cache
    if not from_cache or args.refresh:
        print_no_updates_result(target.env_name)
        return None
    print("Cached result is empty; verifying with a live scan...")
    packages = _live_scan(target)
    if not packages:
        print_no_updates_result(target.env_name)
        return None
    announce(
        "OK",
        f"Live scan found {count_label(len(packages), 'package')} that can be updated.",
    )
    return packages, from_cache, True


def _choose_non_interactive(target, packages, live):
    """Apply --all/--packages; return ``(selected, packages)``, or None."""
    # For non-interactive modes, prefer correctness over stale cache.
    if not live:
        announce("INFO", "Confirming the cached list with a live scan...")
        packages = _live_scan(target)
        if not packages:
            print_no_updates_result(target.env_name)
            return None
    selected = select_non_interactive(
        packages,
        select_all=target.args.all,
        requested_csv=target.args.packages,
    )
    return selected, packages


def _start_background_refresh(target, package_state):
    """Rescan in a thread while the user chooses from the cached list."""
    package_state["scan_in_progress"] = True
    package_state["scan_done"] = False
    progress = PackageScanProgress(
        cached_count=len(package_state["packages"]), render=False
    )
    package_state["scan_progress"] = progress
    thread = threading.Thread(
        target=refresh_packages_background,
        args=(target.env_key, target.prefix, package_state, progress),
        daemon=True,
    )
    thread.start()
    return thread, progress


def _choose_interactive(target, packages, from_cache):
    """Run the selector; return ``(selected, packages, live)`` or BACK_TO_ENV."""
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print(
            paint("Error:", "error"), "interactive selection requires a TTY terminal."
        )
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
    refresh_thread = refresh_progress = None
    if from_cache and not target.args.refresh:
        refresh_thread, refresh_progress = _start_background_refresh(
            target, package_state
        )

    print(f"Opening the selector with {len(packages)} available update(s)...")
    try:
        selected = curses.wrapper(interactive_select, package_state, not target.fixed)
    except curses.error as exc:
        raise UpdaterError(
            f"Failed to initialize terminal UI ({exc}). Run this in a local terminal."
        ) from exc
    waited_for_refresh = wait_for_background_scan(refresh_thread, refresh_progress)
    if selected == BACK_TO_ENV:
        return BACK_TO_ENV

    # The user spent an unbounded amount of time in the selector, so the list
    # they saw is live only if the background scan finished cleanly just now.
    live = False
    if refresh_thread:
        with package_state["lock"]:
            packages = list(package_state["packages"])
            had_mismatch = package_state["cache_mismatch"]
            scan_ok = package_state["scan_error"] is None
        if had_mismatch:
            selected, dropped = reconcile_selected(selected, packages)
            if dropped:
                print_section("Removed stale selections no longer outdated:")
                print("  " + ", ".join(dropped))
        live = waited_for_refresh and scan_ok
    return selected, packages, live


def _read_key():
    """Return one keypress as soon as it is typed, or "" at end of input.

    Echo is off while waiting, and any unread remainder of a multi-byte key
    (an arrow's escape sequence) is discarded so it cannot leak into the next
    prompt or selector.  Signals stay enabled, so Ctrl-C still interrupts.
    """
    if not sys.stdin.isatty():
        return sys.stdin.readline()[:1]
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd, termios.TCSANOW)
        return os.read(fd, 1).decode("utf-8", "replace")
    finally:
        termios.tcsetattr(fd, termios.TCSAFLUSH, saved)


def _another_environment_wanted(target):
    """After a result, wait for a key before the environment picker returns.

    The picker takes over the whole terminal, so reopening it at once would
    wipe the result off the screen before it could be read.  A named
    environment has no picker to return to, so the run simply ends.
    """
    if target.fixed:
        return False
    print(
        f"\nPress {paint('Enter', 'strong')} to choose another environment, "
        f"or {paint('q', 'strong')} to quit: ",
        end="",
        flush=True,
    )
    while True:
        key = _read_key()
        if key in {"\n", "\r"}:
            print()
            return True
        # Ctrl-D and a closed input end the run, like q.
        if key in {"q", "Q", "\x04", ""}:
            print("q")
            return False


def _confirmed(env_name):
    if not sys.stdin.isatty():
        print(
            paint("Error:", "error"),
            "confirmation prompt requires a TTY. Re-run with --yes.",
        )
        raise UpdaterError("Confirmation requires a TTY; re-run with --yes.")
    answer = input(f"\nApply these changes to '{env_name}'? [y/N] ")
    return answer.strip().lower() == "y"


def _plan_and_apply(target, selected, live_packages, baseline):
    """Resolve, confirm, and apply; return True to choose another environment.

    ``live_packages`` is the outdated list when it is fresh from this run,
    otherwise None and it is rescanned first.
    """
    args = target.args
    print_step("3/3", "Building and checking the exact update plan...")
    if live_packages is None:
        live_packages = _live_scan(target, report_exclusions=False)
    selected, dropped = reconcile_selected(selected, live_packages)
    if dropped:
        announce("INFO", "No longer need an update: " + ", ".join(dropped))
    if not selected:
        print_no_updates_result(target.env_name)
        return _another_environment_wanted(target)

    plan = resolve_update_plan(target.prefix, selected)
    if not plan:
        print_no_updates_result(target.env_name, all_held=True)
        return _another_environment_wanted(target)
    announce("OK", "pip found a compatible update plan.")
    print_resolved_plan(plan, show_details=args.details)
    try:
        print_shared_file_warning(shared_file_report(target.prefix, plan))
    except (UpdaterError, OSError) as exc:
        # Advisory only; validate_new_wheels enforces the real guarantee
        # before anything is installed, so this must never end the run.
        announce("INFO", f"Could not check for shared files ({exc}).")

    if args.dry_run:
        print_dry_run_result(target.env_name, args, selected, plan, baseline)
        return _another_environment_wanted(target)
    # Choosing GO in the selector is the confirmation; only --all/--packages
    # reach this point without the user having confirmed anything.
    non_interactive = args.all or args.packages
    if non_interactive and not args.yes and not _confirmed(target.env_name):
        print(paint("Cancelled. No packages were changed.", "warn"))
        return _another_environment_wanted(target)

    update_packages(target.prefix, target.env_name, selected, plan)
    remove_cached_packages(target.env_key, selected)
    print_update_success(
        target.env_name,
        plan,
        set(baseline["pip_broken"]),
        pip_check_report(target.prefix),
    )
    target.finished = True
    return _another_environment_wanted(target)


def _update_environment(target, root_prefix):
    """One full pass over an environment; True means choose another one."""
    args = target.args
    print_banner("PIP PACKAGE UPDATE PREVIEW" if args.dry_run else "PIP PACKAGE UPDATE")
    print(paint("Environment:", "strong"), paint(target.env_name, "env"))
    if args.dry_run:
        print(
            paint("Mode:", "strong"),
            "preview only — this command will not change any packages",
        )
    baseline = _check_environment(target.prefix, root_prefix, dry_run=args.dry_run)

    found = _find_outdated(target)
    if found is None:
        target.finished = True
        return _another_environment_wanted(target)
    packages, from_cache, live = found
    if args.all or args.packages:
        chosen = _choose_non_interactive(target, packages, live)
        if chosen is None:
            return _another_environment_wanted(target)
        (selected, packages), live = chosen, True
    else:
        chosen = _choose_interactive(target, packages, from_cache)
        if chosen == BACK_TO_ENV:
            return True
        selected, packages, live = chosen

    if not selected:
        print("\nNo packages selected. Exiting.")
        return False
    # A list from a scan seconds ago in this same run is not rescanned: that
    # only repeats a network round trip (measured at ~2.6s, about a quarter of
    # total runtime).  The authoritative time-of-use checks are unchanged:
    # resolve_update_plan queries pip live, and update_packages re-resolves
    # under the environment lock and refuses to proceed if the plan moved.
    return _plan_and_apply(target, selected, packages if live else None, baseline)


def main():
    """Select an environment, choose updates, and apply them transactionally."""
    args = parse_args()
    paint.configure(sys.stdout)
    install_termination_handlers()
    with contextlib.suppress(UpdaterError):
        prune_stale_locks()

    environments, root_prefix = get_known_environments()
    selectable = sorted(
        name for name, prefix in environments.items() if prefix != root_prefix
    )
    if not selectable:
        raise UpdaterError(
            "No named Conda environments were found. Base is intentionally never "
            "an update target."
        )

    fixed_environment = _fixed_environment(args, environments, root_prefix)
    # Remembered for this run only; the next run scans every environment anew.
    finished = set()
    while True:
        chosen = fixed_environment or _choose_environment(
            selectable, environments, finished
        )
        if chosen is None:
            print("No environment selected. Exiting.")
            return
        env_name, prefix = chosen
        target = _UpdateTarget(args, env_name, prefix, fixed=bool(fixed_environment))
        if not _update_environment(target, root_prefix):
            return
        if target.finished:
            finished.add(env_name)
        else:
            finished.discard(env_name)


def report_fatal(label, *details, lead=""):
    """Print why the run ended to stderr, colored only when stderr is a terminal."""
    styled = paint.enabled and sys.stderr.isatty()
    print(
        lead + (paint(label, "error") if styled else label), *details, file=sys.stderr
    )


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        report_fatal("Cancelled.", lead="\n")
        sys.exit(130)
    except UpdateInterrupted as exc:
        report_fatal("Stopped:", f"{exc}.", lead="\n")
        sys.exit(143)
    except UpdaterError as exc:
        report_fatal("Error:", exc)
        sys.exit(1)
