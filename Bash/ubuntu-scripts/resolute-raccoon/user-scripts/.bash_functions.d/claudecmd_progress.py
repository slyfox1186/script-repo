"""Run `claude -p` with stream-json output and show its progress live.

Usage: claudecmd_progress.py [--quiet] claude [ARGS...]

--quiet hides the step log and status line but keeps errors, warnings, claude's own
stderr and unexpected output.

The command must emit `--output-format stream-json --verbose
--include-partial-messages` events on stdout. stdout of this script receives only the
final answer; all progress goes to stderr. claudecmd in 13_ai_tools.sh is the caller.
"""

from __future__ import annotations

import fcntl
import json
import math
import os
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import textwrap
import time
from typing import Any

SPINNER = "-\\|/"
TICK_SECONDS = 0.2
# A descendant that inherited claude's stdout or stderr keeps the pipe open after claude
# exits; read only this long after claude's own exit so it cannot withhold the answer.
DRAIN_SECONDS = 2.0
MAX_MALFORMED_REPORTS = 3
MAX_STATUS_TOOLS = 2
DECIMAL_SECONDS_BELOW = 10
ELLIPSIS = "..."
# Tools whose input has one field worth showing as the progress summary.
SUMMARY_FIELDS = {"WebSearch": "query", "WebFetch": "url", "Read": "file_path"}

# C0 controls except tab and newline, DEL, and C1 controls. These can start terminal
# escape sequences (CSI, OSC 52 clipboard writes), so model text never reaches a
# terminal raw.
_CONTROL = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f]")
_WHITESPACE = re.compile(r"\s+")
_SURROGATE = re.compile("[\ud800-\udfff]")


def escape_surrogates(text: str) -> str:
    """Spell out unpaired surrogates: invalid Unicode that cannot be encoded."""
    return _SURROGATE.sub(lambda match: f"\\u{ord(match.group()):04x}", text)


def escape_controls(text: str) -> str:
    text = escape_surrogates(text)
    return _CONTROL.sub(lambda match: f"\\x{ord(match.group()):02x}", text)


def one_line(text: str, limit: int) -> str:
    flat = escape_controls(_WHITESPACE.sub(" ", text).strip())
    if len(flat) <= limit:
        return flat
    if limit <= len(ELLIPSIS):
        return flat[: max(limit, 0)]
    return flat[: limit - len(ELLIPSIS)] + ELLIPSIS


def seconds(value: float) -> str:
    minutes, secs = divmod(int(value), 60)
    if minutes > 0:
        return f"{minutes}m{secs:02d}s"
    return f"{value:.1f}s" if value < DECIMAL_SECONDS_BELOW else f"{value:.0f}s"


def duration_seconds(value: object) -> float | None:
    """Return a millisecond field as seconds, or None if it is not a usable duration."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    try:
        millis = float(value)
    except OverflowError:
        return None
    if not math.isfinite(millis) or millis < 0:
        return None
    return millis / 1000


def string_field(mapping: dict[str, Any], key: str) -> str:
    value = mapping.get(key)
    return value if isinstance(value, str) else ""


def tool_summary(name: str, tool_input: object) -> str:
    if not isinstance(tool_input, dict):
        return ""

    def field(key: str) -> str:
        return string_field(tool_input, key)

    if name in SUMMARY_FIELDS:
        return field(SUMMARY_FIELDS[name])
    if name == "Bash":
        description = field("description")
        return field("command") + (f"  ({description})" if description else "")
    if name in ("Grep", "Glob"):
        path = field("path")
        return field("pattern") + (f" in {path}" if path else "")
    return field("description")


class Display:
    """Sole writer to the terminal: log lines plus one status line redrawn in place."""

    def __init__(self, quiet: bool = False) -> None:
        stderr_tty = os.isatty(2)
        self.quiet = quiet
        self.live = stderr_tty and os.environ.get("TERM", "") != "dumb" and not quiet
        self.color = self.live and os.environ.get("NO_COLOR", "") == ""
        self.status_shown = False
        self.broken = False

    def write(self, text: str) -> None:
        if self.broken:
            return
        try:
            sys.stderr.write(text)
            sys.stderr.flush()
        except BrokenPipeError:
            # Whoever read the progress went away; keep going so the answer still
            # prints, and point fd 2 at /dev/null so the exit flush cannot fail.
            self.broken = True
            self.live = False
            self.status_shown = False
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, 2)
            os.close(devnull)

    def width(self) -> int:
        try:
            columns = os.get_terminal_size(2).columns
        except OSError:
            columns = 0
        # A pty that never had its size set reports 0 columns, which means unknown.
        return max(columns, 20) if columns > 0 else 120

    def paint(self, code: str, text: str) -> str:
        return f"\033[{code}m{text}\033[0m" if self.color and code else text

    def clear(self) -> None:
        if self.status_shown:
            self.status_shown = False
            self.write("\r\033[K")

    def log(self, text: str, code: str = "", always: bool = False) -> None:
        # Quiet mode drops ordinary progress only; anything explaining a failure stays.
        if self.quiet and not (always or code in (RED, YELLOW)):
            return
        self.clear()
        self.write(self.paint(code, escape_controls(text)) + "\n")

    def status(self, text: str) -> None:
        if not self.live:
            return
        self.write("\r\033[K" + self.paint("2", one_line(text, self.width() - 1)))
        self.status_shown = not self.broken


DIM, RED, YELLOW, CYAN = "2", "31", "33", "36"


class Run:
    """Turns stream-json events into progress output and keeps the final answer."""

    def __init__(self, display: Display) -> None:
        self.display = display
        self.started = time.monotonic()
        self.activity = "starting Claude"
        self.activity_since = self.started
        self.tools: dict[str, dict[str, Any]] = {}
        self.pending_text: str | None = None
        self.thinking_tokens: int | None = None
        self.thinking_since = self.started
        self.written_chars = 0
        self.answer: str | None = None
        self.last_result_ok: bool | None = None
        self.turns: int | None = None
        self.malformed = 0
        self.frame = 0

    # Output helpers

    def indent(self, parent: object) -> str:
        return "    " if isinstance(parent, str) else ""

    def set_activity(self, activity: str) -> None:
        if activity != self.activity:
            self.activity = activity
            self.activity_since = time.monotonic()

    def report_malformed(self, kind: str) -> None:
        self.malformed += 1
        if self.malformed <= MAX_MALFORMED_REPORTS:
            self.display.log(f"claudecmd: skipped malformed {kind} event", YELLOW)

    def log_block(self, text: str, prefix: str, always: bool = False) -> None:
        wrap_width = max(self.display.width() - len(prefix), 20)
        for raw_line in text.splitlines() or [""]:
            safe = escape_controls(raw_line.replace("\t", "    "))
            for piece in textwrap.wrap(safe, wrap_width) or [""]:
                self.display.log(prefix + piece, DIM, always)

    def flush_pending(self) -> None:
        if self.pending_text is not None:
            self.log_block(self.pending_text, "  | ")
            self.pending_text = None

    def tick(self) -> None:
        now = time.monotonic()
        parts = [f"{SPINNER[self.frame % len(SPINNER)]} {self.activity}"]
        self.frame += 1
        if self.activity == "thinking" and self.thinking_tokens is not None:
            parts[0] += f" ~{self.thinking_tokens:,} tokens"
        if self.activity == "writing" and self.written_chars > 0:
            parts[0] += f" {self.written_chars:,} chars"
        parts[0] += f" {seconds(now - self.activity_since)}"
        running = [tool for tool in self.tools.values() if tool["parent"] is None]
        for tool in running[:MAX_STATUS_TOOLS]:
            parts.append(f"running {tool['name']} {seconds(now - tool['started'])}")
        if len(running) > MAX_STATUS_TOOLS:
            parts.append(f"+{len(running) - MAX_STATUS_TOOLS} more")
        others = len(self.tools) - len(running)
        if others > 0:
            parts.append(f"{others} subagent tool{'s' if others > 1 else ''}")
        parts.append(f"total {seconds(now - self.started)}")
        self.display.status(" | ".join(parts))

    # Input handlers

    def handle_stderr_line(self, line: str) -> None:
        if line.strip():
            self.display.log(
                "claude: " + one_line(line, self.display.width() - 8), DIM, always=True
            )

    def handle_line(self, line: str) -> None:
        if not line.strip():
            return
        try:
            event = json.loads(line)
        except ValueError:
            self.display.log(
                "claude: " + one_line(line, self.display.width() - 8), DIM, always=True
            )
            return
        if not isinstance(event, dict):
            self.report_malformed("non-object")
            return
        handler = {
            "system": self.on_system,
            "stream_event": self.on_stream_event,
            "assistant": self.on_assistant,
            "user": self.on_user,
            "rate_limit_event": self.on_rate_limit,
            "result": self.on_result,
        }.get(string_field(event, "type"))
        if handler is not None:
            handler(event)

    def on_system(self, event: dict[str, Any]) -> None:
        subtype = string_field(event, "subtype")
        if subtype == "init":
            version = string_field(event, "claude_code_version") or "?"
            model = string_field(event, "model") or "?"
            cwd = string_field(event, "cwd") or "?"
            line = f"claude {version}, model {model}, in {cwd}"
            self.display.log(one_line(line, self.display.width()), DIM)
            self.set_activity("waiting for Claude")
        elif subtype == "status" and string_field(event, "status") == "requesting":
            self.set_activity("waiting for Claude")
        elif subtype == "hook_started":
            self.set_activity(f"running {string_field(event, 'hook_name') or 'a'} hook")
        elif subtype == "hook_response":
            self.set_activity("starting Claude")
        elif subtype == "thinking_tokens":
            tokens = event.get("estimated_tokens")
            if isinstance(tokens, int):
                self.thinking_tokens = tokens

    def on_stream_event(self, event: dict[str, Any]) -> None:
        inner = event.get("event")
        if not isinstance(inner, dict):
            self.report_malformed("stream_event")
            return
        kind = string_field(inner, "type")
        if kind == "message_start":
            self.flush_pending()
        elif kind == "content_block_start":
            self.flush_pending()
            block = inner.get("content_block")
            block_type = string_field(block, "type") if isinstance(block, dict) else ""
            if block_type == "thinking":
                self.thinking_tokens = None
                self.thinking_since = time.monotonic()
                self.set_activity("thinking")
            elif block_type == "text":
                self.written_chars = 0
                self.set_activity("writing")
            elif block_type == "tool_use" and isinstance(block, dict):
                self.set_activity(
                    f"preparing {string_field(block, 'name') or 'a tool'}"
                )
        elif kind == "content_block_delta":
            delta = inner.get("delta")
            if isinstance(delta, dict) and string_field(delta, "type") == "text_delta":
                self.written_chars += len(string_field(delta, "text"))
        elif kind == "content_block_stop":
            self.set_activity("waiting for Claude")

    def on_assistant(self, event: dict[str, Any]) -> None:
        message = event.get("message")
        content = message.get("content") if isinstance(message, dict) else None
        if not isinstance(content, list):
            self.report_malformed("assistant")
            return
        parent = event.get("parent_tool_use_id")
        prefix = self.indent(parent)
        for block in content:
            if not isinstance(block, dict):
                continue
            block_type = string_field(block, "type")
            if block_type == "thinking":
                elapsed = duration_seconds(event.get("thinking_duration_ms"))
                if elapsed is None:
                    if "thinking_duration_ms" in event:
                        self.report_malformed("thinking duration")
                    elapsed = time.monotonic() - self.thinking_since
                tokens = (
                    f" (~{self.thinking_tokens:,} tokens)"
                    if self.thinking_tokens
                    else ""
                )
                self.display.log(
                    f"{prefix}  thought for {seconds(elapsed)}{tokens}", DIM
                )
            elif block_type == "text":
                text = string_field(block, "text")
                if parent is not None:
                    self.log_block(text, prefix + "  | ")
                else:
                    self.flush_pending()
                    self.pending_text = text
            elif block_type == "tool_use":
                if parent is None:
                    self.flush_pending()
                name = string_field(block, "name") or "tool"
                width = self.display.width() - len(prefix) - len(name) - 4
                summary = one_line(tool_summary(name, block.get("input")), width)
                self.display.log(f"{prefix}> {name}  {summary}".rstrip(), CYAN)
                tool_id = string_field(block, "id")
                if tool_id:
                    self.tools[tool_id] = {
                        "name": name,
                        "started": time.monotonic(),
                        "parent": parent if isinstance(parent, str) else None,
                    }
                self.set_activity("waiting for Claude")

    def on_user(self, event: dict[str, Any]) -> None:
        message = event.get("message")
        content = message.get("content") if isinstance(message, dict) else None
        if not isinstance(content, list):
            return
        prefix = self.indent(event.get("parent_tool_use_id"))
        for block in content:
            if (
                not isinstance(block, dict)
                or string_field(block, "type") != "tool_result"
            ):
                continue
            tool = self.tools.pop(string_field(block, "tool_use_id"), None)
            name = tool["name"] if tool else "tool"
            took = seconds(time.monotonic() - tool["started"]) if tool else "?"
            body = block.get("content")
            if isinstance(body, list):
                body = "\n".join(
                    string_field(part, "text")
                    for part in body
                    if isinstance(part, dict)
                )
            text = body if isinstance(body, str) else ""
            if block.get("is_error") is True:
                first = text.strip().splitlines()[0] if text.strip() else "no details"
                width = self.display.width() - len(prefix) - len(name) - 20
                line = f"{prefix}  {name} error, {took}: {one_line(first, width)}"
                self.display.log(line, RED)
            else:
                count = len(text.splitlines())
                lines = f", {count} line{'s' if count != 1 else ''}" if text else ""
                self.display.log(f"{prefix}  {name} ok, {took}{lines}", DIM)

    def on_rate_limit(self, event: dict[str, Any]) -> None:
        info = event.get("rate_limit_info")
        if not isinstance(info, dict):
            return
        status = string_field(info, "status")
        if status and status != "allowed":
            window = string_field(info, "rateLimitType") or "usage"
            self.display.log(
                f"claudecmd: rate limit {status} ({window} window)", YELLOW
            )

    def on_result(self, event: dict[str, Any]) -> None:
        self.pending_text = None
        turns = event.get("num_turns")
        if isinstance(turns, int):
            self.turns = turns
        denials = event.get("permission_denials")
        if isinstance(denials, list):
            for denial in denials:
                if isinstance(denial, dict):
                    name = string_field(denial, "tool_name") or "tool"
                    summary = tool_summary(name, denial.get("tool_input"))
                    line = f"denied: {name} {summary}".rstrip()
                    self.display.log(one_line(line, self.display.width()), YELLOW)
        result = event.get("result")
        if event.get("is_error") is False and isinstance(result, str):
            self.answer = result
            self.last_result_ok = True
            return
        self.last_result_ok = False
        if not isinstance(event.get("is_error"), bool):
            self.display.log("claudecmd: Claude sent a malformed result", RED)
            return
        subtype = string_field(event, "subtype") or "error"
        self.display.log(f"claudecmd: Claude reported an error ({subtype})", RED)
        errors = event.get("errors")
        messages = (
            [item for item in errors if isinstance(item, str)]
            if isinstance(errors, list)
            else []
        )
        if isinstance(result, str) and result.strip():
            messages.append(result)
        for item in messages:
            self.log_block(item, "  ", always=True)

    def finish(self, exit_code: int) -> int:
        self.display.clear()
        total = seconds(time.monotonic() - self.started)
        if self.last_result_ok is None:
            self.display.log("claudecmd: Claude ended without sending a result", RED)
        turns = (
            f", {self.turns} turn{'s' if self.turns != 1 else ''}" if self.turns else ""
        )
        if exit_code == 0 and self.last_result_ok is True:
            self.display.log(f"done in {total}{turns}", DIM)
        else:
            self.display.log(f"failed after {total}{turns}", RED)
        if self.answer is not None:
            answer = escape_surrogates(self.answer)
            text = escape_controls(answer) if os.isatty(1) else answer
            sys.stdout.write(text if text.endswith("\n") else text + "\n")
            sys.stdout.flush()
        if exit_code != 0:
            return 128 - exit_code if exit_code < 0 else exit_code
        return 0 if self.last_result_ok else 1


class Terminated(Exception):
    pass


def raise_terminated(signum: int, frame: object) -> None:
    raise Terminated


def stop_child(process: subprocess.Popen[bytes], signum: int) -> None:
    if process.poll() is None:
        process.send_signal(signum)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def queued_bytes(fd: int) -> int:
    try:
        raw = fcntl.ioctl(fd, termios.FIONREAD, b"\0\0\0\0")
    except OSError:
        return 0
    return struct.unpack("i", raw)[0]


def pump(process: subprocess.Popen[bytes], run: Run) -> None:
    assert process.stdout is not None and process.stderr is not None
    handlers = {
        process.stdout.fileno(): run.handle_line,
        process.stderr.fileno(): run.handle_stderr_line,
    }
    buffers = {fd: bytearray() for fd in handlers}

    def consume(fd: int, size: int = 65536) -> int:
        chunk = os.read(fd, size)
        buffer = buffers[fd]
        if not chunk:
            if buffer:
                handlers[fd](buffer.decode("utf-8", "replace"))
            del buffers[fd]
            return 0
        buffer += chunk
        newline = buffer.find(b"\n")
        while newline >= 0:
            line = bytes(buffer[:newline])
            del buffer[: newline + 1]
            handlers[fd](line.decode("utf-8", "replace"))
            newline = buffer.find(b"\n")
        return len(chunk)

    last_tick = 0.0
    exited_at: float | None = None
    while buffers:
        ready, _, _ = select.select(list(buffers), [], [], TICK_SECONDS)
        for fd in ready:
            consume(fd)
        now = time.monotonic()
        if now - last_tick >= TICK_SECONDS:
            run.tick()
            last_tick = now
        if exited_at is None and process.poll() is not None:
            exited_at = now
        if exited_at is not None and now - exited_at >= DRAIN_SECONDS:
            break
    # Past the drain window: take only the bytes already queued in each pipe, then the
    # unterminated tails, without waiting for a descendant to close or stop writing.
    for fd in list(buffers):
        queued = queued_bytes(fd)
        while fd in buffers and queued > 0:
            got = consume(fd, min(queued, 65536))
            if got == 0:
                break
            queued -= got
        if buffers.get(fd):
            handlers[fd](buffers[fd].decode("utf-8", "replace"))


def main(argv: list[str]) -> int:
    quiet = len(argv) > 1 and argv[1] == "--quiet"
    command = argv[2:] if quiet else argv[1:]
    if not command:
        sys.stderr.write("usage: claudecmd_progress.py [--quiet] claude [ARGS...]\n")
        return 2
    display = Display(quiet)
    run = Run(display)
    signal.signal(signal.SIGTERM, raise_terminated)
    try:
        process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
    except OSError as error:
        display.log(f"claudecmd: cannot start {command[0]}: {error.strerror}", RED)
        return 127
    try:
        run.tick()
        pump(process, run)
        return run.finish(process.wait())
    except KeyboardInterrupt:
        display.clear()
        stop_child(process, signal.SIGINT)
        display.log("claudecmd: cancelled", YELLOW)
        return 130
    except Terminated:
        display.clear()
        stop_child(process, signal.SIGTERM)
        return 143
    except BrokenPipeError:
        # Point stdout at /dev/null so the interpreter's final flush cannot raise again.
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
        stop_child(process, signal.SIGTERM)
        return 141


if __name__ == "__main__":
    sys.exit(main(sys.argv))
