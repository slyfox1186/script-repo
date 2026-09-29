#!/usr/bin/env python3
"""Build and install a signed GNU GCC release tuned for this computer (Debian/Ubuntu).

Run ``install_gcc.py --help`` for usage.  Standard library only; Python 3.9 or newer.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as _dt
import errno
import fcntl
import glob
import hashlib
import http.client
import json
import os
import queue
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from collections.abc import Callable, Sequence
from typing import IO, TYPE_CHECKING, Any, ClassVar, NoReturn

SCRIPT_NAME = "install_gcc.py"
MIN_PYTHON = (3, 9)
MIN_MAJOR = 11

GNU_INDEX_URL = "https://ftp.gnu.org/gnu/gcc/"
TARBALL_URL_BASES = ("https://ftpmirror.gnu.org/gcc/", "https://ftp.gnu.org/gnu/gcc/")
SIGNATURE_URL_BASE = "https://ftp.gnu.org/gnu/gcc/"
KEYRING_URL = "https://ftp.gnu.org/gnu/gnu-keyring.gpg"
# The GNU keyring holds hundreds of maintainers' keys, so a good signature alone is not enough.
# gcc.gnu.org/mirrors.html: "The archives there will be signed by one of the following GnuPG
# keys". Fingerprints as listed there; Richard Guenther's entry is his RSA signing subkey. Every
# release from 11.1.0 to 16.2.0 is signed by 7F74…A641 or D3A9…FA62.
RELEASE_KEYS_PAGE = "https://gcc.gnu.org/mirrors.html"
GCC_RELEASE_KEYS = {
    "B215C1633BCA0477615F1B35A5B3A004745C015A": "Gerald Pfeifer",
    "B3C42148A44E6983B3E4CC0793FA9B1AB75C61B8": "Mark Mitchell",
    "90AA470469D3965A87A5DCB494D03953902C9419": "Gabriel Dos Reis",
    "80F98B2E0DAB6C8281BDF541A7C8C3B2F71EDF1C": "Joseph Myers",
    "7F74F97C103468EE5D750B583AB00996FC26A641": "Richard Guenther (Biener)",
    "33C235A34C46AA3FFB293709A328C3A2C3C45C06": "Jakub Jelinek (2004 key)",
    "D3A93CAD751C2AF4F8C7AD516C35B99309B5FA62": "Jakub Jelinek",
}
FINGERPRINT_RE = re.compile(r"^[0-9A-F]{40}$")
HTTP_TIMEOUT = 60
HTTP_ATTEMPTS = 3
USER_AGENT = f"{SCRIPT_NAME} (+https://gcc.gnu.org/install/)"

DEFAULT_PREFIX_ROOT = "/usr/local"
# Debian's default PATH; /usr/local is excluded from the *build* PATH so locally installed tools
# (make, as, ld wrappers, ccache) cannot leak into the bootstrap.
DEFAULT_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
BUILD_PATH = "/usr/sbin:/usr/bin:/sbin:/bin"
HOST_CC = "/usr/bin/gcc"
HOST_CXX = "/usr/bin/g++"
HOST_MAKE = "/usr/bin/make"
CONFIG_SHELL = "/bin/bash"  # INSTALL/prerequisites.html: "use bash to be sure"

BUILD_PACKAGES = (
    "build-essential",
    "dpkg-dev",
    "libgmp-dev",
    "libmpfr-dev",
    "libmpc-dev",
    "libisl-dev",
    "libzstd-dev",
    "zlib1g-dev",
    "flex",
    "bison",
    "m4",
    "gawk",
    "xz-utils",
    "gpgv",
    "file",
)
# INSTALL/prerequisites.html: DejaGnu, Expect and Tcl run the test suite; autogen is "Necessary
# to run 'make check' for fixinc".
TEST_PACKAGES = ("dejagnu", "expect", "autogen")
# INSTALL/prerequisites.html: "Binutils 2.35 or newer is required for LTO to work correctly with
# GNU libtool that includes doing a bootstrap with LTO enabled."
MIN_LTO_BINUTILS = (2, 35)

DEFAULT_LANGUAGES = ("c", "c++", "fortran", "objc")
# Language name -> directory under gcc/ in the source tree.
LANGUAGE_DIRS = {
    "c": "c",
    "c++": "cp",
    "fortran": "fortran",
    "objc": "objc",
    "obj-c++": "objcp",
    "go": "go",
    "d": "d",
    "ada": "ada",
    "m2": "m2",
    "rust": "rust",
    "cobol": "cobol",
    "algol68": "algol68",
}
# INSTALL/prerequisites.html: these front ends need an existing toolchain for their language.
LANGUAGE_PREREQS = {"ada": "gnat", "d": "gdc", "rust": "cargo"}

# Heuristics, reported as such in the plan output and replaced by measurements in the manifest.
GIB = 1024**3
MEM_GIB_PER_JOB = 2
MEM_GIB_PER_LINK = 8
MAX_LINK_SERIALIZATION = 4
MIN_BUILD_DISK_GIB = 40
MIN_PREFIX_DISK_GIB = 3
LOW_MEMORY_GIB = 8

ALT_GROUP = "local-gcc"
ALT_BIN_DIR = "/usr/local/bin"
# Slave tool -> which tool of the candidate provides it (cc/c++ are the C and C++ drivers).
ALT_SLAVES = (
    ("g++", "g++"),
    ("cc", "gcc"),
    ("c++", "g++"),
    ("cpp", "cpp"),
    ("gfortran", "gfortran"),
    ("gcc-ar", "gcc-ar"),
    ("gcc-nm", "gcc-nm"),
    ("gcc-ranlib", "gcc-ranlib"),
    ("gcov", "gcov"),
    ("gcov-dump", "gcov-dump"),
    ("gcov-tool", "gcov-tool"),
    ("lto-dump", "lto-dump"),
)
CANDIDATE_ROOTS = ("/usr/local", "/usr/local/programs", "/opt")

STATE_FILE = ".install_gcc-state.json"
SOURCE_MARKER = ".install_gcc-source.json"
BUILD_MARKER = ".install_gcc-build.json"
LOCK_FILE = ".lock"
INSTALLER_DIR_RE = re.compile(r"^gcc_\d+\.\d+\.\d+_installer$")
STAGE_MARKER = ".install_gcc-stage.json"
SAFE_PATH_RE = re.compile(r"^/[A-Za-z0-9._+/-]+$")
VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")

# Aliases exist only for the type checker, so importing on an old Python still reaches the
# friendly version message in main() instead of failing on a subscripted builtin.
if TYPE_CHECKING:
    Version = tuple[int, int, int]
    Milestone = tuple[re.Pattern[str], Callable[[re.Match[str]], str]]


class InstallerError(Exception):
    """A failure that is reported to the user without a traceback."""

    def __init__(self, message: str, hint: str = "") -> None:
        super().__init__(message)
        self.hint = hint


class UsageError(InstallerError):
    pass


class Terminated(KeyboardInterrupt):
    """SIGTERM or SIGHUP: unwinds through the same cleanup as Ctrl-C."""

    def __init__(self, signum: int) -> None:
        super().__init__(signum)
        self.signum = signum


def _raise_terminated(signum: int, _frame: object) -> None:
    raise Terminated(signum)


def install_signal_handlers() -> None:
    """Without this, SIGTERM/SIGHUP would kill Python but orphan the make tree in its session."""
    for signum in (signal.SIGTERM, signal.SIGHUP):
        if signal.getsignal(signum) is not signal.SIG_IGN:  # respect nohup
            signal.signal(signum, _raise_terminated)


# ───────────────────────────────────────────────────────────────────────────── terminal output


def color_enabled(no_color_flag: bool, stream: IO[str], environ: dict[str, str]) -> bool:
    """--no-color > NO_COLOR (https://no-color.org) > FORCE_COLOR > TTY and TERM != dumb."""
    if no_color_flag or environ.get("NO_COLOR"):
        return False
    force = environ.get("FORCE_COLOR")
    if force and force != "0":
        return True
    return stream.isatty() and environ.get("TERM", "") != "dumb"


class Style:
    CODES: ClassVar[dict[str, str]] = {
        "bold": "1",
        "dim": "2",
        "italic": "3",
        "underline": "4",
        "red": "31",
        "green": "32",
        "yellow": "33",
        "blue": "34",
        "magenta": "35",
        "cyan": "36",
        "white": "37",
        "bred": "91",
        "bgreen": "92",
        "byellow": "93",
        "bblue": "94",
        "bmagenta": "95",
        "bcyan": "96",
    }

    def __init__(self, enabled: bool, unicode_ok: bool) -> None:
        self.enabled = enabled
        self.unicode = unicode_ok

    def __call__(self, text: str, *styles: str) -> str:
        if not self.enabled or not styles:
            return text
        codes = ";".join(self.CODES[s] for s in styles)
        return f"\033[{codes}m{text}\033[0m"

    def configure(self, enabled: bool, unicode_ok: bool) -> None:
        self.enabled = enabled
        self.unicode = unicode_ok

    def sym(self, fancy: str, plain: str) -> str:
        return fancy if self.unicode else plain


def _unicode_ok(stream: IO[str]) -> bool:
    encoding = (getattr(stream, "encoding", None) or "").lower().replace("-", "")
    return encoding in ("utf8", "utf8sig")


S = Style(False, False)
_ANSI_RE = re.compile(r"\033\[[0-9;]*m")


def visible_len(text: str) -> int:
    return len(_ANSI_RE.sub("", text))


def out(text: str = "") -> None:
    print(text, flush=True)


def info(text: str) -> None:
    out(f"  {S(S.sym('•', '*'), 'bcyan')} {text}")


def ok(text: str) -> None:
    out(f"  {S(S.sym('✔', 'OK'), 'bgreen', 'bold')} {text}")


def warn(text: str) -> None:
    out(f"  {S(S.sym('▲', '!'), 'byellow', 'bold')} {S(text, 'yellow')}")


def fail(text: str) -> None:
    print(f"  {S(S.sym('✘', 'X'), 'bred', 'bold')} {S(text, 'red')}", file=sys.stderr, flush=True)


class Phases:
    def __init__(self) -> None:
        self.number = 0

    def start(self, title: str) -> None:
        self.number += 1
        rule = S.sym("─", "-") * max(4, min(term_width(), 100) - len(title) - 10)
        out()
        out(f"{S(f' {self.number:>2} ', 'bold', 'bcyan')}{S(title, 'bold')} {S(rule, 'dim')}")


def term_width() -> int:
    return max(40, shutil.get_terminal_size((100, 24)).columns)


def fmt_duration(seconds: float) -> str:
    seconds = int(seconds)
    return f"{seconds // 3600:d}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}"


def fmt_bytes(n: float) -> str:
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if n < 1024 or unit == "TiB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024
    return f"{n:.1f} TiB"


# ───────────────────────────────────────────────────────────────────────────── help screen


@dataclass(frozen=True)
class Opt:
    flags: tuple[str, ...]
    help: str
    metavar: str = ""
    kind: str = "flag"  # flag | int | str
    dest: str = ""
    default: Any = None


OPTION_GROUPS: tuple[tuple[str, tuple[Opt, ...]], ...] = (
    (
        "Version selection",
        (
            Opt(
                ("--major",),
                "GCC release series to build (11 up to the newest published). "
                "Prompted for when omitted.",
                "N",
                "int",
                "major",
            ),
            Opt(
                ("--gcc-version",),
                "Exact stable release, e.g. 16.2.0. Skips both prompts.",
                "X.Y.Z",
                "str",
                "gcc_version",
            ),
            Opt(
                ("--latest",),
                "Take the newest release (of --major, or of the newest series) without asking.",
                dest="latest",
            ),
            Opt(
                ("--trust-key",),
                "Also accept signatures from this key (40-hex fingerprint; comma-separate "
                f"several). Only for a new GCC release key: check it on {RELEASE_KEYS_PAGE} "
                "first.",
                "FPR",
                "str",
                "trust_key",
            ),
        ),
    ),
    (
        "Build tuning",
        (
            Opt(
                ("--languages",),
                "Comma-separated front ends. c and c++ are always built "
                "(bootstrap needs them). Extra: obj-c++, go, d, ada, m2, rust, cobol, algol68 "
                "where the release has them.",
                "LIST",
                "str",
                "languages",
                ",".join(DEFAULT_LANGUAGES),
            ),
            Opt(
                ("--jobs",),
                "Parallel make jobs. Default: CPUs available to this process, capped "
                f"at one job per {MEM_GIB_PER_JOB} GiB of available memory.",
                "N",
                "int",
                "jobs",
            ),
            Opt(
                ("--portable",),
                "Build a compiler that runs on any CPU of this architecture and "
                "emits generic code (no -march=native anywhere).",
                dest="portable",
            ),
            Opt(
                ("--no-pgo",),
                "Use 'make bootstrap' (stage2/stage3 comparison) instead of the "
                "profile-guided 'make profiledbootstrap'.",
                dest="no_pgo",
            ),
            Opt(
                ("--run-tests",),
                "Run the GCC test suite (make -k check) before installing and "
                "report its summary. Installs dejagnu, expect and autogen. Adds hours.",
                dest="run_tests",
            ),
            Opt(
                ("--resume",),
                "Continue an interrupted or failed build of the same release with the same "
                "settings instead of asking (runs without a terminal or with --yes otherwise "
                "start over).",
                dest="resume",
            ),
            Opt(
                ("--clean",),
                "Delete every gcc_X.Y.Z_installer/ folder earlier runs left beside this script "
                "(build and source trees, logs, manifests), report success or failure, and "
                "exit. Downloaded tarballs, other files beside the script and installed "
                "compilers are kept. Runs on its own; with --dry-run it only lists.",
                dest="clean",
            ),
        ),
    ),
    (
        "Installation",
        (
            Opt(
                ("--prefix-root",),
                "Directory that receives gcc-X.Y.Z/.",
                "DIR",
                "str",
                "prefix_root",
                DEFAULT_PREFIX_ROOT,
            ),
            Opt(
                ("--keep-cache",),
                "Answer the final 'delete the leftover build files?' prompt with no: keep the "
                "source and build trees after a verified install.",
                dest="keep_cache",
            ),
        ),
    ),
    (
        "Default compiler",
        (
            Opt(
                ("--switch-only",),
                "Skip building: show every GCC on this computer and choose "
                "which one 'gcc', 'cc', 'g++' … run by default.",
                dest="switch_only",
            ),
        ),
    ),
    (
        "General",
        (
            Opt(
                ("-y", "--yes"),
                "Answer yes to download/dependency/build confirmations, and to installing "
                "despite unexpected test-suite failures (GCC releases normally have some; "
                "they are reported). Never deletes an installed compiler and never changes "
                "the default compiler.",
                dest="yes",
            ),
            Opt(
                ("-v", "--verbose"),
                "Stream the complete, unfiltered output of configure, make, the test suite and "
                "apt to the terminal while it runs. Without it you see one line per key step "
                "(each bootstrap stage and component) under a live status line. Everything is "
                "always saved in logs/.",
                dest="verbose",
            ),
            Opt(
                ("--dry-run",),
                "Select, download, verify and extract, then print the exact "
                "configure/make plan. No sudo, no apt, no build, no install.",
                dest="dry_run",
            ),
            Opt(
                ("--no-color",),
                "Disable colors (also honoured: NO_COLOR, FORCE_COLOR).",
                dest="no_color",
            ),
            Opt(("-h", "--help"), "Show this help and exit.", dest="help"),
        ),
    ),
)

EXAMPLES = (
    ("", "Interactive: pick a series, press Enter for its newest release"),
    ("--major 15", "Choose among the GCC 15 releases (Enter = newest)"),
    ("--gcc-version 16.2.0 --yes", "Unattended build of an exact release"),
    ("--latest --run-tests", "Newest release, with the full test suite"),
    ("--latest --verbose", "Newest release; show the full compiler output"),
    ("--dry-run --major 13 --latest", "Show exactly what would be configured"),
    ("--switch-only", "Just change which GCC is the default"),
    ("--clean", "Delete all leftover build folders, then exit"),
)

WORKFLOW = (
    "Finds stable releases on ftp.gnu.org (no git, no snapshots) and asks which one you want.",
    "Downloads gcc-X.Y.Z.tar.xz next to this script, checks its GnuPG signature and requires "
    "the signer to be one of GCC's published release keys.",
    "Installs missing build packages with apt (after asking).",
    "Extracts into gcc_X.Y.Z_installer/ beside the script; builds out of tree in its build/ "
    "directory; logs go to its logs/ directory.",
    "Configures for this machine: native CPU for GCC itself and for the code it generates, "
    "LTO + profile-guided bootstrap, shared runtime libraries, release checking. Stage 1 is "
    "compiled by the OS gcc; GCC then rebuilds itself.",
    "Runs 'make install-strip' as you into a staging directory, copies the result into "
    "<prefix-root>/gcc-X.Y.Z with sudo, and adds a RUNPATH rule so programs find its newer "
    "libstdc++ without touching the system loader.",
    "Verifies the installed compiler with real compile-and-run tests.",
    "Offers to make it (or any other GCC here) the default via update-alternatives in "
    "/usr/local/bin; the OS compiler in /usr/bin is never modified.",
    "Finally asks whether to delete the leftover source and build trees (logs are kept); "
    "--keep-cache answers no.",
    "If a build was interrupted or failed, the next run with the same settings offers to "
    "resume it: make continues where it stopped and keeps the finished work.",
)


def render_help() -> str:
    width = min(term_width(), 110)
    lines: list[str] = []
    h, v = S.sym("─", "-"), S.sym("│", "|")
    tl, tr, bl, br = (S.sym(c, "+") for c in ("╭", "╮", "╰", "╯"))
    dot = S.sym("·", "-")
    titles = (
        f"{SCRIPT_NAME}  {dot}  GNU GCC from source, tuned for this computer",
        f"{SCRIPT_NAME}  {dot}  GNU GCC from source",
        SCRIPT_NAME,
    )
    title = next((t for t in titles if len(t) + 4 <= width - 2), titles[-1])
    inner = len(title) + 4
    lines.append(S(f"{tl}{h * inner}{tr}", "cyan"))
    pad = inner - len(title) - 2
    lines.append(S(v, "cyan") + "  " + S(title, "bold", "bcyan") + " " * max(pad, 0) + S(v, "cyan"))
    lines.append(S(f"{bl}{h * inner}{br}", "cyan"))
    lines.append("")
    lines.extend(
        textwrap.wrap(
            "Downloads a signed stable GCC release, builds it optimized for the CPU it runs on, "
            "installs it under /usr/local/gcc-X.Y.Z (shared runtime libraries) and lets you "
            "choose the system's default gcc. For Debian and Ubuntu.",
            width=width - 2,
            initial_indent="  ",
            subsequent_indent="  ",
        )
    )
    lines.append("")
    lines.append(S("USAGE", "bold", "bmagenta"))
    lines.append(f"  {S(SCRIPT_NAME, 'bold')} {S('[options]', 'yellow')}")

    flag_texts: list[tuple[str, str, Opt]] = []
    for _, opts in OPTION_GROUPS:
        for opt in opts:
            plain = ", ".join(opt.flags) + (f" {opt.metavar}" if opt.metavar else "")
            colored = ", ".join(S(f, "bgreen") for f in opt.flags)
            if opt.metavar:
                colored += " " + S(opt.metavar, "byellow")
            flag_texts.append((plain, colored, opt))
    col = min(max(len(p) for p, _, _ in flag_texts) + 4, 28)
    narrow = width < 72
    desc_width = max(30, width - col - 4)

    for group, opts in OPTION_GROUPS:
        lines.append("")
        lines.append(S(group.upper(), "bold", "bmagenta"))
        for opt in opts:
            plain, colored, _ = next(t for t in flag_texts if t[2] is opt)
            text = opt.help
            if opt.default:
                text += f" [default: {opt.default}]"
            if narrow:
                lines.append(f"  {colored}")
                for w in textwrap.wrap(text, width=width - 8):
                    lines.append(f"      {_color_default(w)}")
                continue
            wrapped = textwrap.wrap(text, width=desc_width) or [""]
            if len(plain) + 2 > col:
                lines.append(f"  {colored}")
                lines.extend(" " * (col + 2) + _color_default(w) for w in wrapped)
            else:
                lines.append(f"  {colored}{' ' * (col - len(plain))}{_color_default(wrapped[0])}")
                lines.extend(" " * (col + 2) + _color_default(w) for w in wrapped[1:])

    lines.append("")
    lines.append(S("EXAMPLES", "bold", "bmagenta"))
    commands = [f"$ ./{SCRIPT_NAME}" + (f" {a}" if a else "") for a, _ in EXAMPLES]
    ex_col = max(len(c) for c in commands) + 3
    stacked = narrow or ex_col + 30 > width
    for cmd, (args, what) in zip(commands, EXAMPLES):
        colored_cmd = (
            S("$ ", "dim")
            + S(f"./{SCRIPT_NAME}", "bold")
            + (" " + S(args, "bgreen") if args else "")
        )
        if stacked:
            lines.append(f"  {colored_cmd}")
            lines.extend(f"      {S(w, 'dim')}" for w in textwrap.wrap(what, width=width - 8))
            continue
        wrapped = textwrap.wrap(what, width=width - ex_col - 3) or [""]
        lines.append(f"  {colored_cmd}{' ' * (ex_col - len(cmd))}{S(wrapped[0], 'dim')}")
        lines.extend(" " * (ex_col + 2) + S(w, "dim") for w in wrapped[1:])

    lines.append("")
    lines.append(S("WHAT IT DOES", "bold", "bmagenta"))
    for i, step in enumerate(WORKFLOW, 1):
        bullet = S(f"{i}", "bold", "bcyan") + " " + S(S.sym("▸", ">"), "cyan")
        wrapped = textwrap.wrap(step, width=width - 8) or [""]
        lines.append(f"  {bullet} {wrapped[0]}")
        lines.extend(f"      {w}" for w in wrapped[1:])

    lines.append("")
    lines.append(S("GOOD TO KNOW", "bold", "bmagenta"))
    notes = (
        "Run as your normal user; sudo is requested only for apt, copying the finished "
        "installation into place, the RUNPATH specs file and update-alternatives. make never "
        "runs as root.",
        "An existing installation directory is never overwritten. An incomplete one an earlier "
        "run left behind is deleted only after you confirm.",
        "GCC is built against glibc's iconv even when GNU libiconv's iconv.h is in "
        "/usr/local/include: the build alone gets an include directory that puts glibc's header "
        "first, so the compiler and libstdc++ never depend on /usr/local/lib/libiconv.so.2. "
        "Nothing on the system is moved or changed.",
        "Resuming relies on make deleting half-written files when it is stopped. After Ctrl-C, "
        "SIGTERM or a closed terminal that is safe; after kill -9, a crash or a power loss the "
        "script suggests starting over instead.",
        "Default PIE and -fstack-protector-strong match the distro compiler. Ubuntu's gcc also "
        "defaults to -D_FORTIFY_SOURCE (when optimizing), -Wformat -Wformat-security, "
        "-fstack-clash-protection, -fcf-protection and -z relro -z now through distribution "
        "patches that upstream GCC has no configure switch for: pass them explicitly, or use "
        "-fhardened (GCC 14+), which enables most of them.",
        "Programs you compile default to this computer's CPU (-march=native) and find this "
        "GCC's runtime libraries through a RUNPATH into its prefix. For binaries that run "
        "elsewhere, pass an explicit -march (e.g. x86-64-v2) and -static-libstdc++ "
        "-static-libgcc.",
        "The build takes a long time (hours with --run-tests) and tens of GiB of disk.",
    )
    for note in notes:
        wrapped = textwrap.wrap(note, width=width - 6)
        lines.append(f"  {S(S.sym('•', '*'), 'cyan')} {wrapped[0]}")
        lines.extend(f"    {w}" for w in wrapped[1:])
    lines.append("")
    return "\n".join(lines)


def _color_default(text: str) -> str:
    match = re.search(r"\[default: [^\]]*\]", text)
    if not match or not S.enabled:
        return text
    return text[: match.start()] + S(match.group(0), "dim") + text[match.end() :]


class _HelpAction(argparse.Action):
    def __call__(
        self,
        parser: argparse.ArgumentParser,
        namespace: argparse.Namespace,
        values: Any,
        option_string: str | None = None,
    ) -> None:
        out(render_help())
        parser.exit(0)


class _Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        fail(message)
        print(f"  Run {SCRIPT_NAME} --help for usage.", file=sys.stderr)
        self.exit(2)


def build_parser() -> argparse.ArgumentParser:
    parser = _Parser(prog=SCRIPT_NAME, add_help=False, allow_abbrev=False)
    for _, opts in OPTION_GROUPS:
        for opt in opts:
            if opt.dest == "help":
                parser.add_argument(*opt.flags, action=_HelpAction, nargs=0)
            elif opt.kind == "flag":
                parser.add_argument(*opt.flags, dest=opt.dest, action="store_true")
            else:
                parser.add_argument(
                    *opt.flags,
                    dest=opt.dest,
                    metavar=opt.metavar,
                    type=int if opt.kind == "int" else str,
                    default=opt.default,
                )
    return parser


# ───────────────────────────────────────────────────────────────────────────── subprocess helpers


def clean_env(extra: dict[str, str] | None = None, path: str = BUILD_PATH) -> dict[str, str]:
    """A minimal, explicit environment: nothing from the caller's toolchain setup leaks in."""
    env = {"PATH": path, "LC_ALL": "C"}
    for key in ("HOME", "USER", "LOGNAME", "TMPDIR", "TERM"):
        if key in os.environ:
            env[key] = os.environ[key]
    if extra:
        env.update(extra)
    return env


def capture(
    cmd: Sequence[str],
    *,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
    input_text: str | None = None,
    timeout: float = 120,
) -> subprocess.CompletedProcess[str]:
    """Run a short probe and capture its output; never raises for a nonzero exit."""
    try:
        return subprocess.run(
            list(cmd),
            env=env if env is not None else clean_env(path=DEFAULT_PATH),
            cwd=cwd,
            input=input_text,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError:
        return subprocess.CompletedProcess(list(cmd), 127, "", f"{cmd[0]}: not found")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(list(cmd), 124, "", f"{cmd[0]}: timed out")


def is_root() -> bool:
    return os.geteuid() == 0


def privileged(cmd: Sequence[str]) -> list[str]:
    return list(cmd) if is_root() else ["sudo", "--", *cmd]


class SudoKeeper:
    """Refreshes the sudo timestamp while a long build runs so the final install does not stall."""

    def __init__(self) -> None:
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self, reason: str) -> None:
        if is_root() or self._thread is not None:
            return
        if shutil.which("sudo") is None:
            raise InstallerError("sudo is required for " + reason + " but is not installed.")
        info(f"sudo is needed for {reason}.")
        if subprocess.run(["sudo", "-v"], check=False).returncode != 0:
            raise InstallerError(
                "sudo authentication failed.",
                "Run the script from a terminal so sudo can ask for your password.",
            )
        self._thread = threading.Thread(target=self._loop, name="sudo-keepalive", daemon=True)
        self._thread.start()

    def _loop(self) -> None:
        while not self._stop.wait(60):
            subprocess.run(
                ["sudo", "-n", "-v"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)
            self._thread = None


class MemorySampler:
    """Records the lowest MemAvailable seen while a step runs (reported as measured headroom)."""

    def __init__(self) -> None:
        self.minimum: int | None = None
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, name="mem-sampler", daemon=True)

    def __enter__(self) -> MemorySampler:
        self._thread.start()
        return self

    def __exit__(self, *_: object) -> None:
        self._stop.set()
        self._thread.join(timeout=10)

    def _loop(self) -> None:
        while True:
            avail = read_meminfo().get("MemAvailable")
            if avail is not None and (self.minimum is None or avail < self.minimum):
                self.minimum = avail
            if self._stop.wait(5):
                return


def _component(path: str) -> str:
    """'./gcc' -> 'gcc'; 'x86_64-linux-gnu/libstdc++-v3' -> 'libstdc++-v3 (runtime library)'."""
    parts = [p for p in path.split("/") if p not in ("", ".")]
    if len(parts) < 2:
        return parts[0] if parts else path
    if parts[0].startswith("build-"):
        return f"{parts[-1]} (build-machine tool)"
    return f"{parts[-1]} (runtime library)"


# Progress lines printed by GCC's own top-level Makefile.in and DejaGnu summaries.
BUILD_MILESTONES: tuple[Milestone, ...] = (
    (
        re.compile(r"^Configuring stage (\S+) in (\S+)"),
        lambda m: f"stage {m.group(1)}: configuring {_component(m.group(2))}",
    ),
    (re.compile(r"^Configuring in (\S+)"), lambda m: f"configuring {_component(m.group(1))}"),
    (
        re.compile(r"^Comparing stages (\d+) and (\d+)"),
        lambda m: f"comparing stage {m.group(1)} and stage {m.group(2)} object files",
    ),
    (re.compile(r"^Bootstrap comparison failure!"), lambda m: "bootstrap comparison FAILED"),
)
CHECK_MILESTONES: tuple[Milestone, ...] = (
    (re.compile(r"^\s*=== (\S+) Summary ===?"), lambda m: f"{m.group(1)} test suite finished"),
)
STAGE_NAMES = {
    "stage1": "stage 1 — minimal compiler built by the host compiler",
    "stage2": "stage 2 — compiler rebuilt by itself",
    "stage3": "stage 3 — rebuilt again for the comparison",
    "stage4": "stage 4",
    "stageprofile": "profile stage — instrumented compiler",
    "stagetrain": "training stage — the instrumented compiler builds GCC to record profiles",
    "stagefeedback": "feedback stage — final compiler optimized with the recorded profiles",
    "stageautoprofile": "autoprofile stage",
    "stageautofeedback": "autofeedback stage",
}


class Runner:
    """Runs long commands; output always goes to a log file.

    Quiet mode shows one line per key step (stages, components, test suites) under a live status
    line; verbose mode streams the complete, unfiltered output to the terminal as well.
    """

    def __init__(self, log_dir: Path, verbose: bool) -> None:
        self.log_dir = log_dir
        self.verbose = verbose
        self.counter = 0
        # True once stopping a command needed SIGKILL, which gives make no chance to delete
        # half-written targets.
        self.forced_stop = False

    def run(
        self,
        name: str,
        cmd: Sequence[str],
        *,
        env: dict[str, str] | None = None,
        cwd: Path | None = None,
        privileged_cmd: bool = False,
        stage_file: Path | None = None,
        milestones: Sequence[Milestone] = (),
        check: bool = True,
        umask: int = -1,
    ) -> int:
        self.counter += 1
        log_path = self.log_dir / f"{self.counter:02d}-{name}.log"
        full = privileged(cmd) if privileged_cmd else list(cmd)
        tail: deque[str] = deque(maxlen=40)
        events: queue.Queue[str] = queue.Queue()
        started = time.monotonic()
        if self.verbose:
            out(S(f"  $ {shlex.join(full)}", "dim"))
        with open(log_path, "w", encoding="utf-8", errors="replace") as log:
            log.write(f"$ {shlex.join(full)}\n# cwd: {cwd or os.getcwd()}\n\n")
            log.flush()
            try:
                proc = subprocess.Popen(
                    full,
                    env=env,
                    cwd=cwd,
                    stdin=None if privileged_cmd else subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    # Unprivileged children get their own session so Ctrl-C can stop the whole
                    # make tree; sudo stays in the terminal's process group so it gets SIGINT.
                    start_new_session=not privileged_cmd,
                    umask=umask,
                )
            except FileNotFoundError as exc:
                raise InstallerError(f"Cannot run {full[0]}: {exc}") from exc
            if proc.stdout is None:
                raise InstallerError(f"No output pipe for {full[0]}.")
            pump = _Pump(proc.stdout, log, tail, events, milestones, echo=self.verbose)
            reader = threading.Thread(target=pump.run, name=f"pump-{name}", daemon=True)
            reader.start()
            status = _StatusLine(
                name, log_path, started, stage_file, events, quiet=not self.verbose
            )
            try:
                while True:
                    try:
                        rc = proc.wait(timeout=1)
                        break
                    except subprocess.TimeoutExpired:
                        status.tick()
            except KeyboardInterrupt:
                # Stop the children first: after a hangup, writing to the terminal can fail.
                self.forced_stop = _terminate(proc, own_group=not privileged_cmd)
                with contextlib.suppress(OSError):
                    status.clear()
                raise
            finally:
                reader.join(timeout=30)
                pump.close()
                # A leftover process that still holds the pipe keeps the reader blocked; closing
                # the pipe under it would block too, so it is left to the daemon thread.
                if not reader.is_alive():
                    proc.stdout.close()
            status.finish(success=rc == 0)
            if reader.is_alive():
                warn(f"{name}: a leftover process still holds its output; the rest is not logged.")
        elapsed = time.monotonic() - started
        if rc != 0 and check:
            fail(f"{name} failed (exit {rc}) after {fmt_duration(elapsed)}.")
            if not self.verbose:
                print("    Last lines of output:", file=sys.stderr)
                for line in tail:
                    print(f"    {S(line.rstrip(), 'dim')}", file=sys.stderr)
            raise InstallerError(f"{name} failed.", f"Full log: {log_path}")
        if rc == 0:
            ok(f"{name} {S(f'({fmt_duration(elapsed)})', 'dim')}")
        return rc


class _Pump:
    """Copies child output to the log (and terminal in verbose mode); queues milestones."""

    def __init__(
        self,
        stream: IO[bytes],
        log: IO[str],
        tail: deque[str],
        events: queue.Queue[str],
        milestones: Sequence[Milestone],
        *,
        echo: bool,
    ) -> None:
        self.stream, self.log, self.tail, self.events = stream, log, tail, events
        self.milestones, self.echo = milestones, echo
        self._lock = threading.Lock()
        self._closed = False

    def close(self) -> None:
        """Stop writing before the caller closes the log; later output is only drained."""
        with self._lock:
            self._closed = True
            self.log.flush()

    def run(self) -> None:
        last = ""
        for raw in iter(self.stream.readline, b""):
            line = raw.decode("utf-8", errors="replace")
            with self._lock:
                if self._closed:
                    continue
                self.log.write(line)
            self.tail.append(line)
            if self.echo:
                sys.stdout.write(line)
                sys.stdout.flush()
                continue
            for pattern, describe in self.milestones:
                match = pattern.match(line)
                if match:
                    text = describe(match)
                    if text != last:
                        self.events.put(text)
                        last = text
                    break


def _terminate(proc: subprocess.Popen[bytes], own_group: bool) -> bool:
    """Stop a child after Ctrl-C, SIGTERM or SIGHUP; True if its group had to be SIGKILLed.

    An unprivileged child leads its own session, so its whole process group gets TERM, then KILL.
    sudo shares the terminal's process group, so Ctrl-C already reached it. It relays SIGTERM to
    its command, but a SIGKILL would orphan that root process, so sudo is never killed.
    """
    if proc.poll() is not None:
        return False
    if own_group:
        with contextlib.suppress(ProcessLookupError, PermissionError):
            os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.killpg(proc.pid, signal.SIGKILL)
            with contextlib.suppress(subprocess.TimeoutExpired):
                proc.wait(timeout=10)
            return True
        return False
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        with contextlib.suppress(ProcessLookupError, PermissionError):
            proc.terminate()
        with contextlib.suppress(subprocess.TimeoutExpired):
            proc.wait(timeout=10)
    return False


class _StatusLine:
    """Quiet-mode display: milestone lines scroll above a single live status line."""

    PLAIN_HEARTBEAT = 300  # seconds between "still running" lines when stdout is not a terminal

    def __init__(
        self,
        name: str,
        log: Path,
        started: float,
        stage_file: Path | None,
        events: queue.Queue[str],
        *,
        quiet: bool,
    ) -> None:
        self.name, self.log, self.started = name, log, started
        self.stage_file, self.events, self.quiet = stage_file, events, quiet
        self.tty = sys.stdout.isatty()
        self.last_plain = started
        self.spin = 0
        self.stage = ""
        self.stage_started = started

    def _read_stage(self) -> str:
        if self.stage_file is None:
            return ""
        try:
            return self.stage_file.read_text(encoding="ascii").strip()
        except OSError:
            return ""

    def _milestone(self, symbol: str, text: str, style: str) -> None:
        self.clear()
        stamp = fmt_duration(time.monotonic() - self.started)
        out(f"    {S(symbol, style)} {S(stamp, 'dim')}  {text}")

    def _drain(self) -> None:
        while True:
            try:
                text = self.events.get_nowait()
            except queue.Empty:
                return
            style = "bred" if "FAILED" in text else "cyan"
            self._milestone(S.sym("·", "-"), text, style)

    def _check_stage(self) -> None:
        stage = self._read_stage()
        if not stage or stage == self.stage:
            return
        self._end_stage()
        self.stage, self.stage_started = stage, time.monotonic()
        self._milestone(S.sym("▶", ">"), S(STAGE_NAMES.get(stage, stage), "bold"), "bmagenta")

    def _end_stage(self) -> None:
        if self.stage:
            took = fmt_duration(time.monotonic() - self.stage_started)
            label = STAGE_NAMES.get(self.stage, self.stage).split(" — ")[0]
            self._milestone(S.sym("✔", "OK"), f"{label} done ({took})", "bgreen")

    def tick(self) -> None:
        if not self.quiet:
            return
        self._drain()
        self._check_stage()
        elapsed = time.monotonic() - self.started
        stage_txt = f" [{self.stage}]" if self.stage else ""
        if self.tty:
            frames = S.sym("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏", "|/-\\")
            self.spin = (self.spin + 1) % len(frames)
            line = (
                f"  {S(frames[self.spin], 'bcyan')} {self.name}{S(stage_txt, 'bmagenta')} "
                f"{S(fmt_duration(elapsed), 'bold')}  {S(str(self.log), 'dim')}"
            )
            if visible_len(line) > term_width() - 1:
                line = f"  {frames[self.spin]} {self.name}{stage_txt} {fmt_duration(elapsed)}"
            sys.stdout.write("\r\033[2K" + line)
            sys.stdout.flush()
        elif time.monotonic() - self.last_plain >= self.PLAIN_HEARTBEAT:
            self.last_plain = time.monotonic()
            out(f"    … {self.name}{stage_txt} still running ({fmt_duration(elapsed)})")

    def finish(self, *, success: bool) -> None:
        if self.quiet:
            self._drain()
            if success:
                self._end_stage()
        self.clear()

    def clear(self) -> None:
        if self.quiet and self.tty:
            sys.stdout.write("\r\033[2K")
            sys.stdout.flush()


# ───────────────────────────────────────────────────────────────────────────── prompts


def interactive() -> bool:
    return sys.stdin.isatty() and sys.stdout.isatty()


def ask(prompt: str, default: str = "") -> str:
    if not interactive():
        raise InstallerError(
            f"Input needed ({prompt.strip()}) but no terminal is attached.",
            "Pass the matching command-line option (see --help).",
        )
    suffix = f" [{S(default, 'bold')}]" if default else ""
    try:
        answer = input(f"  {S('?', 'bmagenta', 'bold')} {prompt}{suffix}: ").strip()
    except EOFError as exc:
        raise InstallerError("Input closed; cancelled.") from exc
    return answer or default


def confirm(prompt: str, *, default: bool, assume_yes: bool = False) -> bool:
    if assume_yes:
        info(f"{prompt} {S('yes (--yes)', 'dim')}")
        return True
    if not interactive():
        raise InstallerError(
            f"Confirmation needed ({prompt}) but no terminal is attached.",
            "Re-run with --yes to accept, or run it in a terminal.",
        )
    choices = "Y/n" if default else "y/N"
    while True:
        answer = ask(f"{prompt} ({choices})").lower()
        if not answer:
            return default
        if answer in ("y", "yes"):
            return True
        if answer in ("n", "no"):
            return False
        warn("Please answer y or n.")


# ───────────────────────────────────────────────────────────────────────────── system facts


def read_os_release(path: Path = Path("/etc/os-release")) -> dict[str, str]:
    data: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return data
    for raw in text.splitlines():
        entry = raw.strip()
        if not entry or entry.startswith("#") or "=" not in entry:
            continue
        key, _, value = entry.partition("=")
        try:
            parts = shlex.split(value)
        except ValueError:
            continue
        data[key] = parts[0] if parts else ""
    return data


def check_os(os_release: dict[str, str]) -> str:
    """Return a description of the distribution; raise unless it is Debian-family."""
    distro_id = os_release.get("ID", "").lower()
    like = os_release.get("ID_LIKE", "").lower().split()
    pretty = os_release.get("PRETTY_NAME") or distro_id or "unknown"
    if distro_id in ("debian", "ubuntu"):
        return pretty
    if "debian" in like or "ubuntu" in like:
        warn(f"{pretty} is a Debian/Ubuntu derivative: supported on a best-effort basis.")
        return pretty
    raise InstallerError(
        f"Unsupported operating system: {pretty}.",
        "This installer supports Debian and Ubuntu (it relies on apt, dpkg and multiarch paths).",
    )


def read_meminfo() -> dict[str, int]:
    values: dict[str, int] = {}
    try:
        with open("/proc/meminfo", encoding="ascii") as fh:
            for line in fh:
                key, _, rest = line.partition(":")
                parts = rest.split()
                if parts and parts[0].isdigit():
                    values[key] = int(parts[0]) * 1024
    except OSError:
        pass
    return values


def cgroup_memory_limit() -> int | None:
    """Tightest cgroup v2 memory headroom (max - current) along this process's cgroup path."""
    try:
        text = Path("/proc/self/cgroup").read_text(encoding="ascii")
    except OSError:
        return None
    rel = next((ln[3:] for ln in text.splitlines() if ln.startswith("0::")), None)
    if rel is None:
        return None
    best: int | None = None
    path = Path("/sys/fs/cgroup") / rel.lstrip("/")
    root = Path("/sys/fs/cgroup")
    while True:
        try:
            limit = (path / "memory.max").read_text().strip()
            current = int((path / "memory.current").read_text().strip())
            if limit != "max":
                headroom = max(0, int(limit) - current)
                best = headroom if best is None else min(best, headroom)
        except (OSError, ValueError):
            pass
        if path in (root, path.parent):
            return best
        path = path.parent


@dataclass
class Resources:
    cpus: int
    mem_available: int
    jobs: int
    link_serialization: int
    jobs_source: str
    heuristic_jobs: int = 0


def plan_resources(requested_jobs: int | None) -> Resources:
    try:
        cpus = len(os.sched_getaffinity(0))
    except (AttributeError, OSError):
        cpus = os.cpu_count() or 1
    avail = read_meminfo().get("MemAvailable", 0)
    cg = cgroup_memory_limit()
    if cg is not None:
        avail = min(avail, cg) if avail else cg
    mem_gib = avail // GIB
    heuristic = max(1, min(cpus, mem_gib // MEM_GIB_PER_JOB))
    link = max(1, min(MAX_LINK_SERIALIZATION, mem_gib // MEM_GIB_PER_LINK))
    if requested_jobs is not None:
        return Resources(cpus, avail, requested_jobs, link, "--jobs", heuristic)
    return Resources(cpus, avail, heuristic, link, "heuristic", heuristic)


def free_space(path: Path) -> int:
    probe = path
    while not probe.exists():
        probe = probe.parent
    st = os.statvfs(probe)
    return st.f_bavail * st.f_frsize


def dpkg_installed(packages: Sequence[str]) -> set[str]:
    """Packages whose dpkg status is exactly 'install ok installed' (config-files is not)."""
    result = capture(["dpkg-query", "-W", "-f=${Package}\t${Status}\n", *packages])
    installed: set[str] = set()
    for line in result.stdout.splitlines():
        name, _, status = line.partition("\t")
        if status.strip() == "install ok installed":
            installed.add(name.split(":")[0])
    return installed


def native_triplet() -> str:
    """Debian multiarch triplet of this host, cross-checked against the distro compiler."""
    env = clean_env()  # built from scratch, so DEB_HOST_* overrides cannot leak in
    arch = capture(["dpkg-architecture", "-qDEB_HOST_GNU_TYPE"], env=env)
    if arch.returncode != 0 or not arch.stdout.strip():
        raise InstallerError(
            "dpkg-architecture failed: " + (arch.stderr.strip() or "no output"),
            "Install dpkg-dev.",
        )
    triplet = arch.stdout.strip()
    machine = capture([HOST_CC, "-dumpmachine"], env=env).stdout.strip()
    if machine != triplet:
        raise InstallerError(
            f"Host compiler {HOST_CC} targets '{machine}' but dpkg reports '{triplet}'.",
            "Only native builds are supported; check the build-essential installation.",
        )
    return triplet


@dataclass
class HostToolchain:
    cc: str
    cxx: str
    version: str
    real_cc: str
    make: str
    make_version: str
    ld_version: str
    linker_plugin: bool
    ssp_strong_default: bool
    iconv_header: str
    iconv_shim: str  # include directory that makes the build use glibc's iconv.h, or ''


def binutils_version(ld_version: str) -> tuple[int, int] | None:
    """Binutils release from the first line of 'ld --version'.

    'GNU ld (GNU Binutils for Ubuntu) 2.42' -> (2, 42); gold prints the binutils release inside
    the parentheses: 'GNU gold (GNU Binutils for Ubuntu 2.42) 1.16' -> (2, 42).
    """
    match = re.search(r"\(GNU Binutils[^)]*?(\d+)\.(\d+)[^)]*\)", ld_version) or re.search(
        r"(\d+)\.(\d+)(?:\.\d+)*\s*$", ld_version
    )
    return (int(match.group(1)), int(match.group(2))) if match else None


def host_toolchain(target_major: int, iconv_shim_dir: Path) -> HostToolchain:
    """The OS gcc/g++ pair that builds stage 1; later stages are built by the new GCC itself.

    INSTALL/build.html recommends only GCC for building stage 1 of 'make profiledbootstrap'.
    """
    env = clean_env()
    cc, cxx = HOST_CC, HOST_CXX
    for tool in (cc, cxx, HOST_MAKE):
        if not os.access(tool, os.X_OK):
            raise InstallerError(f"{tool} is missing.", "Install build-essential.")
    cc_ver = capture([cc, "-dumpfullversion"], env=env).stdout.strip()
    cxx_ver = capture([cxx, "-dumpfullversion"], env=env).stdout.strip()
    if not cc_ver or cc_ver != cxx_ver:
        raise InstallerError(
            f"{cc} ({cc_ver or '?'}) and {cxx} ({cxx_ver or '?'}) are not the same release.",
            "Make both commands point at the same gcc version.",
        )
    # INSTALL/prerequisites.html: GCC 15+ needs C++14 to build; earlier releases need C++11.
    std = "c++14" if target_major >= 15 else "c++11"
    probe = capture(
        [cxx, f"-std={std}", "-x", "c++", "-", "-o", os.devnull],
        env=env,
        input_text="#include <memory>\nint main(){auto p=std::unique_ptr<int>(new int(0));"
        "return *p;}\n",
    )
    if probe.returncode != 0:
        raise InstallerError(f"{cxx} cannot build {std} programs:\n{probe.stderr.strip()}")
    ld_help = capture(["ld", "--help"], env=env).stdout
    iconv_header, iconv_shim = glibc_iconv(cc, env, iconv_shim_dir)
    ssp = capture([HOST_CC, "-Q", "--help=common"], env=env).stdout
    return HostToolchain(
        cc=cc,
        cxx=cxx,
        version=cc_ver,
        real_cc=os.path.realpath(cc),
        make=HOST_MAKE,
        make_version=capture([HOST_MAKE, "--version"], env=env).stdout.split("\n")[0],
        ld_version=capture(["ld", "--version"], env=env).stdout.split("\n")[0],
        linker_plugin="-plugin" in ld_help,
        ssp_strong_default=re.search(r"^\s*-fstack-protector-strong\s+\[enabled\]", ssp, re.M)
        is not None,
        iconv_header=iconv_header,
        iconv_shim=iconv_shim,
    )


ICONV_PROBE = "#include <iconv.h>\n#ifdef _LIBICONV_VERSION\ninstall_gcc_gnu_libiconv\n#endif\n"
GLIBC_ICONV_H = "/usr/include/iconv.h"
# Searched like -isystem, so before the standard directories such as /usr/local/include
# (GCC manual, "Environment Variables Affecting GCC"); read by the OS gcc and by every stage.
INCLUDE_PATH_VARS = ("C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "OBJC_INCLUDE_PATH")


def _probe_iconv(cc: str, env: dict[str, str]) -> tuple[str, bool]:
    """The <iconv.h> that cc finds, and whether it is GNU libiconv's."""
    probe = capture([cc, "-E", "-H", "-x", "c", "-"], env=env, input_text=ICONV_PROBE)
    # -H prints each header on stderr; ". " marks one included directly by the input.
    header = next((ln[2:].strip() for ln in probe.stderr.splitlines() if ln.startswith(". ")), "")
    if probe.returncode != 0 or not header:
        raise InstallerError(f"{cc} cannot find <iconv.h>.", "Install libc6-dev.")
    return header, "install_gcc_gnu_libiconv" in probe.stdout


def iconv_include_env(shim: str) -> dict[str, str]:
    return {var: shim for var in INCLUDE_PATH_VARS} if shim else {}


def glibc_iconv(cc: str, env: dict[str, str], shim_dir: Path) -> tuple[str, str]:
    """(the <iconv.h> every stage compiles against, include directory that selects it or '').

    Both the OS gcc and the new GCC search /usr/local/include before /usr/include, so a GNU
    libiconv installed there replaces glibc's iconv for the whole build. The libstdc++ manual
    (Prerequisites, PR libstdc++/93602) says libstdc++.so.6 then needs libiconv.so.2 at run
    time; the compiler binaries do too, and -static-libstdc++ links fail. A directory holding
    only a link to glibc's header, passed to the build alone, puts glibc's first again without
    touching the system.
    """
    header, gnu = _probe_iconv(cc, env)
    if not gnu:
        return os.path.realpath(header), ""
    if shim_dir.is_symlink() or (shim_dir.exists() and not shim_dir.is_dir()):
        raise InstallerError(f"{shim_dir} is not a plain directory.")
    shim_dir.mkdir(exist_ok=True)
    link = shim_dir / "iconv.h"
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(GLIBC_ICONV_H)
    shimmed, still_gnu = _probe_iconv(cc, {**env, **iconv_include_env(str(shim_dir))})
    if still_gnu or os.path.realpath(shimmed) != GLIBC_ICONV_H:
        raise InstallerError(
            f"{cc} finds GNU libiconv's {header}, and glibc's {GLIBC_ICONV_H} could not be "
            "used in its place.",
            "A GCC built now would need libiconv.so.2 at run time. Check that libc6-dev "
            f"provides {GLIBC_ICONV_H}.",
        )
    info(
        f"{header} is GNU libiconv's; the build uses glibc's {GLIBC_ICONV_H} instead, so GCC "
        "will not depend on libiconv.so.2. Nothing on the system is changed."
    )
    return GLIBC_ICONV_H, str(shim_dir)


# ───────────────────────────────────────────────────────────────────────────── release discovery


class InsecureRedirect(urllib.error.URLError):
    """A server tried to move the download off HTTPS."""


class _HttpsOnlyRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: IO[bytes],
        code: int,
        msg: str,
        headers: Any,
        newurl: str,
    ) -> urllib.request.Request | None:
        if urllib.parse.urlsplit(newurl).scheme != "https":
            raise InsecureRedirect(f"refusing non-HTTPS redirect to {newurl}")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_OPENER = urllib.request.build_opener(_HttpsOnlyRedirects())


def _open(url: str) -> Any:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    return _OPENER.open(request, timeout=HTTP_TIMEOUT)


def fetch_text(url: str) -> str:
    last: Exception | None = None
    for attempt in range(1, HTTP_ATTEMPTS + 1):
        try:
            with _open(url) as resp:
                data: bytes = resp.read()
                return data.decode("utf-8", errors="replace")
        except (urllib.error.URLError, http.client.HTTPException, OSError) as exc:
            last = exc
            if attempt < HTTP_ATTEMPTS:
                time.sleep(2 * attempt)
    raise InstallerError(f"Could not fetch {url}: {last}", "Check the network connection.")


def parse_release_index(html: str) -> list[Version]:
    found = {
        (int(a), int(b), int(c)) for a, b, c in re.findall(r'href="gcc-(\d+)\.(\d+)\.(\d+)/"', html)
    }
    return sorted(v for v in found if v[0] >= MIN_MAJOR)


def vstr(version: Version) -> str:
    return ".".join(map(str, version))


def parse_version(text: str) -> Version:
    match = VERSION_RE.match(text.strip())
    if not match:
        raise UsageError(f"'{text}' is not a release number like 16.2.0.")
    a, b, c = (int(x) for x in match.groups())
    return (a, b, c)


def by_major(releases: Sequence[Version]) -> dict[int, list[Version]]:
    grouped: dict[int, list[Version]] = {}
    for v in releases:
        grouped.setdefault(v[0], []).append(v)
    for versions in grouped.values():
        versions.sort()
    return dict(sorted(grouped.items()))


def select_version(
    releases: Sequence[Version],
    *,
    major: int | None,
    exact: str | None,
    latest: bool,
    prompt: Callable[[str, str], str] = ask,
) -> Version:
    grouped = by_major(releases)
    if not grouped:
        raise InstallerError("No GCC releases found on the GNU server.")
    if exact is not None:
        wanted = parse_version(exact)
        if major is not None and wanted[0] != major:
            raise UsageError(f"--gcc-version {exact} is not in the --major {major} series.")
        if wanted not in releases:
            raise UsageError(
                f"GCC {exact} is not a published stable release.",
                "Available: " + ", ".join(vstr(v) for v in grouped.get(wanted[0], [])),
            )
        return wanted
    if major is not None and major not in grouped:
        raise UsageError(
            f"GCC {major} has no published release.",
            "Available series: " + ", ".join(map(str, grouped)),
        )
    if major is None and latest:
        major = max(grouped)
    if major is None:
        newest = max(grouped)
        out(f"  {S('Stable GCC release series on ftp.gnu.org:', 'bold')}")
        for m, versions in grouped.items():
            tag = S("  ← newest", "bgreen") if m == newest else ""
            count = f"{len(versions)} release{'s' if len(versions) != 1 else ''}"
            out(
                f"    {S(f'{m:>3}', 'bold', 'bcyan')}  {S(S.sym('→', '->'), 'dim')}  "
                f"latest {S(vstr(versions[-1]), 'bold')}  {S(f'({count})', 'dim')}{tag}"
            )
        while True:
            answer = prompt("Which GCC version series do you want", str(newest))
            if answer.isdigit() and int(answer) in grouped:
                major = int(answer)
                break
            warn(f"Choose one of: {', '.join(map(str, grouped))}")
    versions = grouped[major]
    if latest:
        return versions[-1]
    out(f"  Releases in GCC {major}: " + ", ".join(vstr(v) for v in versions))
    while True:
        answer = prompt(
            f"Exact version, or press Enter for the latest ({vstr(versions[-1])})",
            vstr(versions[-1]),
        )
        try:
            chosen = parse_version(answer)
        except UsageError:
            warn("Type a version such as " + vstr(versions[-1]) + ".")
            continue
        if chosen in versions:
            return chosen
        warn(f"{answer} is not a GCC {major} release.")


# ───────────────────────────────────────────────────────────────────────────── download & verify


def download(urls: Sequence[str], dest: Path, label: str) -> None:
    """Stream to a unique temporary file beside dest, then rename it into place atomically."""
    last: Exception | None = None
    for url in urls:
        for attempt in range(1, HTTP_ATTEMPTS + 1):
            fd, tmp_name = tempfile.mkstemp(
                prefix=f".{dest.name}.", suffix=".part", dir=dest.parent
            )
            tmp = Path(tmp_name)
            try:
                with os.fdopen(fd, "wb") as fh, _open(url) as resp:
                    total = int(resp.headers.get("Content-Length") or 0)
                    _stream(resp, fh, total, label)
                    fh.flush()
                    os.fsync(fh.fileno())
                    if total and fh.tell() != total:
                        raise OSError(f"short read: {fh.tell()} of {total} bytes")
                # mkstemp creates 0600 files; downloads get the normal umask-based mode.
                os.chmod(tmp, 0o666 & ~_umask())
                os.replace(tmp, dest)
                return
            except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError) as exc:
                last = exc
                tmp.unlink(missing_ok=True)
                if _permanent(exc):
                    # Retrying cannot help: a downgrade redirect or a 4xx answer is deterministic.
                    info(
                        f"{label}: {urllib.parse.urlsplit(url).netloc} unusable ({exc}); "
                        "trying the next source."
                    )
                    break
                warn(f"{label}: {url} attempt {attempt} failed: {exc}")
                if attempt < HTTP_ATTEMPTS:
                    time.sleep(2 * attempt)
            except BaseException:
                tmp.unlink(missing_ok=True)
                raise
    raise InstallerError(f"Could not download {label}: {last}")


def _umask() -> int:
    mask = os.umask(0)
    os.umask(mask)
    return mask


def _permanent(exc: BaseException) -> bool:
    if isinstance(exc, InsecureRedirect):
        return True
    return isinstance(exc, urllib.error.HTTPError) and 400 <= exc.code < 500


def _stream(resp: Any, fh: IO[bytes], total: int, label: str) -> None:
    done = 0
    tty = sys.stdout.isatty()
    next_report = 0.25
    started = time.monotonic()
    while True:
        chunk = resp.read(1 << 20)
        if not chunk:
            break
        fh.write(chunk)
        done += len(chunk)
        if total and tty:
            frac = done / total
            bar_w = max(10, min(40, term_width() - 50))
            filled = int(bar_w * frac)
            bar = S(S.sym("█", "#") * filled, "bcyan") + S(
                S.sym("░", ".") * (bar_w - filled), "dim"
            )
            rate = done / max(time.monotonic() - started, 1e-6)
            sys.stdout.write(
                f"\r\033[2K  {label} {bar} {frac * 100:5.1f}%  {fmt_bytes(done)}  "
                f"{fmt_bytes(rate)}/s"
            )
            sys.stdout.flush()
        elif total and done / total >= next_report:
            out(f"    {label}: {int(done / total * 100)}% of {fmt_bytes(total)}")
            next_report += 0.25
    if tty and total:
        sys.stdout.write("\r\033[2K")
        sys.stdout.flush()
    ok(f"{label} downloaded ({fmt_bytes(done)})")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


@dataclass
class Signature:
    signing_key: str
    primary_key: str
    signer: str


def parse_fingerprints(text: str | None) -> dict[str, str]:
    """--trust-key value -> {fingerprint: label}; spaces inside a fingerprint are ignored."""
    keys: dict[str, str] = {}
    for item in (text or "").split(","):
        fpr = re.sub(r"\s+", "", item).upper()
        if not fpr:
            continue
        if not FINGERPRINT_RE.match(fpr):
            raise UsageError(f"--trust-key: '{item.strip()}' is not a 40-hex-digit fingerprint.")
        keys[fpr] = "--trust-key"
    return keys


def parse_validsig(status: str) -> list[tuple[str, str]]:
    """(signing key, primary key) fingerprints from gpgv's VALIDSIG status lines.

    Fields after VALIDSIG: fpr, date, timestamp, expiry, version, reserved, pubkey-algo,
    hash-algo, class, primary-key fpr (the last one is absent when it equals the first).
    """
    found: list[tuple[str, str]] = []
    for line in status.splitlines():
        parts = line.split()
        if parts[:2] == ["[GNUPG:]", "VALIDSIG"] and len(parts) > 2:
            fields = [p.upper() for p in parts[2:]]
            found.append((fields[0], fields[9] if len(fields) > 9 else fields[0]))
    return found


def gpgv_verify(tarball: Path, sig: Path, keyring: Path, trusted: dict[str, str]) -> Signature:
    """Verify with gpgv against a real keyring file (a pipe/fd keyring is rejected by gpgv).

    gpgv trusts every key in the keyring, so the signer must also be in `trusted`, matched on
    the signing (sub)key or its primary key.
    """
    with tempfile.TemporaryDirectory(prefix="install_gcc-gnupg.") as home:
        os.chmod(home, 0o700)
        result = capture(
            [
                "gpgv",
                "--homedir",
                home,
                "--status-fd",
                "1",
                "--keyring",
                str(keyring.resolve()),
                str(sig),
                str(tarball),
            ],
            timeout=300,
        )
    status = result.stdout
    rejected = re.search(r"^\[GNUPG:\] (BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG)\b", status, re.M)
    valid = parse_validsig(status)
    if result.returncode != 0 or rejected or "[GNUPG:] GOODSIG" not in status or not valid:
        detail = (result.stderr or status).strip().splitlines()
        raise InstallerError(
            f"GnuPG signature check FAILED for {tarball.name}.",
            "\n".join(detail[-6:]),
        )
    for signing, primary in valid:
        signer = trusted.get(signing) or trusted.get(primary)
        if signer:
            return Signature(signing_key=signing, primary_key=primary, signer=signer)
    primary = valid[0][1]
    raise InstallerError(
        f"{tarball.name} has a valid signature, but from key {primary}, which is not a GCC "
        "release key.",
        f"GCC's release keys are listed on {RELEASE_KEYS_PAGE}. Only if that page lists this "
        f"key, re-run with --trust-key {primary}.",
    )


# ───────────────────────────────────────────────────────────────────────────── filesystem safety


def write_json(path: Path, data: dict[str, Any]) -> None:
    tmp = path.with_name(f".{path.name}.tmp{os.getpid()}")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def ensure_plain_dir(path: Path) -> None:
    """Create path (not through a symlink) or confirm it is a real directory."""
    if path.is_symlink():
        raise InstallerError(f"{path} is a symbolic link; refusing to use it.")
    path.mkdir(exist_ok=True)
    if not path.is_dir():
        raise InstallerError(f"{path} exists and is not a directory.")


def remove_owned_tree(path: Path, container: Path, marker: str) -> None:
    """Delete a directory this installer created (directly inside container, carrying marker)."""
    if path.is_symlink() or not path.is_dir():
        raise InstallerError(f"{path} is not a plain directory; refusing to delete it.")
    if path.resolve().parent != container.resolve():
        raise InstallerError(f"{path} is outside {container}; refusing to delete it.")
    if marker and not (path / marker).is_file():
        raise InstallerError(
            f"{path} was not created by this installer (no {marker}); refusing to delete it.",
            "Remove it yourself if it is not needed.",
        )
    shutil.rmtree(path)


def privileged_rmtree(path: Path) -> None:
    cmd = privileged(["rm", "-rf", "--one-file-system", "--", str(path)])
    if subprocess.run(cmd, check=False).returncode != 0:
        raise InstallerError(f"Could not delete {path}.")


class DirLock:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.fh: IO[str] | None = None

    def __enter__(self) -> DirLock:
        self.fh = open(self.path, "a+", encoding="utf-8")
        try:
            fcntl.flock(self.fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            self.fh.close()
            if exc.errno in (errno.EAGAIN, errno.EACCES):
                raise InstallerError(
                    f"Another {SCRIPT_NAME} run is using {self.path.parent}.",
                    "Wait for it to finish.",
                ) from None
            raise
        return self

    def __exit__(self, *_: object) -> None:
        if self.fh is not None:
            fcntl.flock(self.fh.fileno(), fcntl.LOCK_UN)
            self.fh.close()


def check_tar_members(tarball: Path, root: str) -> int:
    """Every member must live under root/ and no link may point outside it."""
    count = 0
    try:
        with tarfile.open(tarball, "r:xz") as tar:
            for member in tar:
                count += 1
                name = member.name.rstrip("/")
                parts = Path(name).parts
                if name.startswith("/") or ".." in parts or not parts or parts[0] != root:
                    raise InstallerError(
                        f"Unsafe archive member '{member.name}' in {tarball.name}."
                    )
                if member.isdev() or member.isfifo():
                    raise InstallerError(f"Unexpected device member '{member.name}'.")
                if member.issym() or member.islnk():
                    target = member.linkname
                    if member.issym():
                        target = os.path.normpath(os.path.join(os.path.dirname(name), target))
                    tparts = Path(target).parts
                    if target.startswith("/") or ".." in tparts or not tparts or tparts[0] != root:
                        raise InstallerError(
                            f"Archive link '{member.name}' -> '{member.linkname}' escapes {root}/."
                        )
    except (tarfile.TarError, EOFError, OSError) as exc:
        raise InstallerError(f"{tarball.name} is not a readable .tar.xz archive: {exc}") from exc
    if count == 0:
        raise InstallerError(f"{tarball.name} is empty.")
    return count


def extract_source(tarball: Path, installer: Path, version: str, digest: str) -> Path:
    src = installer / f"gcc-{version}"
    if src.exists() or src.is_symlink():
        marker = read_json(src / SOURCE_MARKER) if src.is_dir() and not src.is_symlink() else None
        if marker and marker.get("tarball_sha256") == digest and marker.get("version") == version:
            ok(f"Reusing verified extraction {src}")
            return src
        raise InstallerError(
            f"{src} exists but does not match the verified tarball.",
            f"Delete it (rm -rf '{src}') and run again.",
        )
    for stale in installer.glob(".extract-*"):
        if stale.is_dir() and not stale.is_symlink():
            shutil.rmtree(stale)
    info("Checking archive members …")
    count = check_tar_members(tarball, f"gcc-{version}")
    staging = Path(tempfile.mkdtemp(prefix=".extract-", dir=installer))
    try:
        info(f"Extracting {count:,} files into {installer} …")
        result = capture(
            ["tar", "-xJf", str(tarball), "-C", str(staging), "--no-same-owner"],
            env=clean_env(),
            timeout=3600,
        )
        if result.returncode != 0:
            raise InstallerError("tar failed: " + result.stderr.strip()[-2000:])
        tree = staging / f"gcc-{version}"
        base_ver = (tree / "gcc" / "BASE-VER").read_text(encoding="ascii").strip()
        if base_ver != version:
            raise InstallerError(f"Archive gcc/BASE-VER says {base_ver}, expected {version}.")
        write_json(tree / SOURCE_MARKER, {"version": version, "tarball_sha256": digest})
        os.rename(tree, src)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    ok(f"Source ready: {src}")
    return src


# ───────────────────────────────────────────────────────────────────────────── configure options


def ac_user_opts(configure: Path) -> set[str]:
    """The exact option variables an autoconf configure script accepts."""
    try:
        text = configure.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return set()
    match = re.search(r"^ac_user_opts='\n(.*?)'", text, re.M | re.S)
    return set(match.group(1).split()) if match else set()


def config_gcc_list(src: Path, variable: str) -> set[str]:
    try:
        text = (src / "gcc" / "config.gcc").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return set()
    match = re.search(rf'^{variable}="(.*?)"', text, re.M | re.S)
    return set(match.group(1).replace("\\\n", " ").split()) if match else set()


def resolve_languages(requested: str, src: Path | None) -> list[str]:
    names = [n.strip().lower() for n in requested.split(",") if n.strip()]
    if not names:
        raise UsageError("--languages is empty.")
    languages: list[str] = []
    for name in names:
        if name == "lto":
            continue  # INSTALL/configure.html: built by default via --enable-lto
        if name in ("all", "jit"):
            raise UsageError(f"--languages {name} is not supported by this installer.")
        if name not in LANGUAGE_DIRS:
            raise UsageError(
                f"Unknown language '{name}'.",
                "Choose from: " + ", ".join(LANGUAGE_DIRS),
            )
        if name not in languages:
            languages.append(name)
    for required in ("c++", "c"):
        if required not in languages:
            languages.insert(0, required)
    order = list(LANGUAGE_DIRS)
    languages.sort(key=order.index)
    if src is not None:
        missing = [n for n in languages if not (src / "gcc" / LANGUAGE_DIRS[n]).is_dir()]
        if missing:
            raise UsageError(f"This GCC release has no front end for: {', '.join(missing)}.")
    for name in languages:
        tool = LANGUAGE_PREREQS.get(name)
        if tool and shutil.which(tool, path=DEFAULT_PATH) is None:
            raise UsageError(
                f"Building {name} needs an existing '{tool}' (INSTALL/prerequisites.html).",
                f"Install it first or drop {name} from --languages.",
            )
    return languages


@dataclass
class BuildPlan:
    version: str
    triplet: str
    prefix: Path
    languages: list[str]
    configure_args: list[str]
    make_target: str
    make_vars: list[str]
    jobs: int
    notes: list[str] = field(default_factory=list)


def build_plan(
    *,
    src: Path,
    version: Version,
    triplet: str,
    prefix: Path,
    languages: list[str],
    toolchain: HostToolchain,
    resources: Resources,
    portable: bool,
    pgo: bool,
) -> BuildPlan:
    gcc_opts = ac_user_opts(src / "gcc" / "configure")
    lib_opts = ac_user_opts(src / "libstdc++-v3" / "configure")
    notes: list[str] = []
    args = [
        f"--build={triplet}",
        f"--host={triplet}",
        f"--target={triplet}",
        f"--prefix={prefix}",
        f"--enable-languages={','.join(languages)}",
        "--enable-shared",
        "--enable-lto",
        "--enable-plugin",
        "--disable-multilib",
        "--enable-checking=release",
        "--disable-werror",
        "--enable-threads=posix",
        "--enable-__cxa_atexit",
        "--enable-clocale=gnu",
        "--enable-gnu-unique-object",
        "--enable-linker-build-id",
        "--with-linker-hash-style=gnu",
        "--with-system-zlib",
        "--enable-multiarch",
    ]
    if "enable_default_pie" in gcc_opts:
        args.append("--enable-default-pie")
    if "enable_default_ssp" in gcc_opts and toolchain.ssp_strong_default:
        args.append("--enable-default-ssp")
        notes.append("--enable-default-ssp: the distro compiler enables -fstack-protector-strong.")
    if "enable_libstdcxx_backtrace" in lib_opts:
        args.append("--enable-libstdcxx-backtrace")
    if "enable_link_serialization" in gcc_opts:
        args.append(f"--enable-link-serialization={resources.link_serialization}")

    x86_64 = triplet.startswith("x86_64-")
    make_vars: list[str] = []
    build_config: list[str] = []
    binutils = binutils_version(toolchain.ld_version)
    if binutils is None or binutils < MIN_LTO_BINUTILS:
        found = (
            "an unknown binutils" if binutils is None else f"binutils {binutils[0]}.{binutils[1]}"
        )
        notes.append(
            f"No LTO bootstrap: the linker is {found}; INSTALL/prerequisites.html requires "
            "binutils 2.35 or newer for it."
        )
    elif (src / "config" / "bootstrap-lto.mk").is_file() and toolchain.linker_plugin:
        build_config.append("bootstrap-lto")
    elif (src / "config" / "bootstrap-lto-noplugin.mk").is_file():
        build_config.append("bootstrap-lto-noplugin")
        notes.append("The linker has no plugin support: using bootstrap-lto-noplugin.")
    if portable:
        if x86_64:
            args.append("--with-tune=generic")
        notes.append("--portable: no -march=native for GCC itself or for generated code.")
    elif x86_64:
        if "native" not in config_gcc_list(src, "x86_64_archs"):
            raise InstallerError(
                f"GCC {vstr(version)} does not accept --with-arch=native on x86_64.",
                "Use --portable.",
            )
        args += ["--with-arch=native", "--with-tune=native"]
        if (src / "config" / "bootstrap-native.mk").is_file():
            build_config.append("bootstrap-native")
        else:
            # INSTALL/build.html: stage2+ compiler flags go into BOOT_CFLAGS (default -g -O2).
            make_vars.append("BOOT_CFLAGS=-g -O2 -march=native -mtune=native")
    else:
        notes.append(f"No CPU-specific tuning on {triplet}: only x86_64 tuning is validated.")
    if build_config:
        args.append(f"--with-build-config={' '.join(build_config)}")
    return BuildPlan(
        version=vstr(version),
        triplet=triplet,
        prefix=prefix,
        languages=languages,
        configure_args=args,
        make_target="profiledbootstrap" if pgo else "bootstrap",
        make_vars=make_vars,
        jobs=resources.jobs,
        notes=notes,
    )


# ───────────────────────────────────────────────────────────────────────────── install & verify


def prefix_state(prefix: Path) -> dict[str, Any] | None:
    return read_json(prefix / STATE_FILE)


def privileged_write(path: Path, content: str, scratch: Path) -> None:
    fd, tmp = tempfile.mkstemp(prefix=".install_gcc.", dir=scratch)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(content)
    try:
        cmd = ["install", "-D", "-m", "0644", tmp, str(path)]
        result = subprocess.run(privileged(cmd), check=False)
        if result.returncode != 0:
            raise InstallerError(f"Could not write {path}.")
    finally:
        os.unlink(tmp)


def claim_prefix(prefix: Path) -> None:
    """Create the prefix; fails if it already exists, so two runs can never share one."""
    parent = prefix.parent
    mkdir_parent = privileged(["mkdir", "-p", "--", str(parent)])
    if not parent.is_dir() and subprocess.run(mkdir_parent, check=False).returncode:
        raise InstallerError(f"Could not create {parent}.")
    result = subprocess.run(privileged(["mkdir", "-m", "0755", "--", str(prefix)]), check=False)
    if result.returncode != 0:
        raise InstallerError(f"Could not create {prefix} (does it already exist?).")


def runpath_specs(builtin: str, libdir: str) -> str:
    """The compiler's own specs plus a RUNPATH on every dynamic link (not -static/-static-pie).

    A specs file in the compiler's install directory replaces the built-in specs rather than
    adding to them: set_up_specs() in gcc/gcc.cc then skips init_spec(), which registers the
    target's EXTRA_SPECS such as the x86 cc1_cpu spec that resolves -march=native. So the file
    starts from 'gcc -dumpspecs', as the GCC FAQ (#rpath) describes, and a later "*link:" body
    starting with "+ " is appended to the dumped link spec (set_spec() in gcc/gcc.cc).
    """
    rpath = f"*link:\n+ %{{!static:%{{!static-pie:-rpath={libdir} --enable-new-dtags}}}}\n\n"
    return builtin.rstrip("\n") + "\n\n" + rpath


def install_specs(prefix: Path, scratch: Path) -> tuple[Path, str]:
    gcc = str(prefix / "bin" / "gcc")
    env = clean_env()
    libgcc_s = capture([gcc, "-print-file-name=libgcc_s.so.1"], env=env).stdout.strip()
    libdir = os.path.dirname(os.path.realpath(libgcc_s)) if os.path.isabs(libgcc_s) else ""
    real_prefix = prefix.resolve()
    if not libdir or not Path(libdir).is_relative_to(real_prefix):
        raise InstallerError(f"libgcc_s.so.1 resolved to '{libgcc_s}', outside {prefix}.")
    if not SAFE_PATH_RE.match(libdir):
        raise InstallerError(f"Library path {libdir} contains characters unsafe in GCC specs.")
    search = capture([gcc, "-print-search-dirs"], env=env).stdout
    match = re.search(r"^install: (.+)$", search, re.M)
    if not match:
        raise InstallerError("Could not find the compiler's install directory.")
    specs = Path(match.group(1).strip()) / "specs"
    if not specs.resolve().is_relative_to(real_prefix):
        raise InstallerError(f"Specs location {specs} is outside {prefix}.")
    if specs.exists():
        raise InstallerError(f"{specs} already exists; refusing to overwrite it.")
    # Dumped while no specs file exists, so these are the built-in specs.
    builtin = capture([gcc, "-dumpspecs"], env=env)
    if builtin.returncode != 0 or "*link:" not in builtin.stdout:
        raise InstallerError(f"'{gcc} -dumpspecs' did not print the built-in specs.")
    privileged_write(specs, runpath_specs(builtin.stdout, libdir), scratch)
    reading = capture([gcc, "-v"], env=env).stderr
    if f"Reading specs from {specs}" not in reading:
        raise InstallerError(f"{gcc} does not read the new specs file {specs}.")
    return specs, libdir


@dataclass
class Check:
    name: str
    passed: bool
    detail: str = ""


SMOKE_SOURCES = {
    "hello.c": '#include <stdio.h>\nint main(void){puts("c-ok");return 0;}\n',
    "hello.cc": (
        "#include <filesystem>\n#include <iostream>\n#include <stdexcept>\n#include <string>\n"
        "#include <thread>\n#include <vector>\n"
        "int main(){std::vector<std::thread> t;int v[4]={0,0,0,0};\n"
        " for(int i=0;i<4;++i)t.emplace_back([&v,i]{v[i]=i+1;});\n"
        " for(auto&x:t)x.join();\n"
        ' try{throw std::runtime_error("x");}catch(const std::exception&e){}\n'
        ' std::cout<<"cxx-ok "<<(v[0]+v[1]+v[2]+v[3])<<" "\n'
        '  <<std::filesystem::path("/a/b").filename().string()<<std::endl;}\n'
    ),
    "hello.f90": 'program hello\n  print "(a)", "fortran-ok"\nend program hello\n',
    "hello.m": (
        "#include <objc/runtime.h>\n#include <stdio.h>\n"
        "@interface G { Class isa; } + (int) answer; @end\n"
        "@implementation G + (int) answer { return 42; } @end\n"
        'int main(void){ printf("objc-ok %d\\n", [G answer]); return 0; }\n'
    ),
    "omp.c": (
        "#include <omp.h>\n#include <stdio.h>\n"
        "int main(void){long s=0;\n#pragma omp parallel for reduction(+:s)\n"
        ' for(int i=1;i<=1000;++i)s+=i;printf("omp-ok %ld\\n",s);return 0;}\n'
    ),
    "lto_a.c": "int twice(int x);\nint main(void){return twice(21)==42?0:1;}\n",
    "lto_b.c": "int twice(int x){return 2*x;}\n",
    "lib.cc": '#include <string>\nstd::string greet(){return std::string("shared-ok");}\n',
    "uselib.cc": "#include <iostream>\n#include <string>\nstd::string greet();\n"
    "int main(){std::cout<<greet()<<std::endl;}\n",
}

RUNTIME_LIBS = (
    "libstdc++",
    "libgcc_s",
    "libgfortran",
    "libquadmath",
    "libgomp",
    "libobjc",
    "libatomic",
    "libitm",
)


OS_LIBRARY_DIRS = ("/lib/", "/lib64/", "/usr/lib/", "/usr/lib64/")


def foreign_libraries(prefix: Path, libdir: str) -> list[str]:
    """Shared libraries that the installed programs and runtimes load from anywhere but the
    OS library directories and this GCC, such as a hand-built library in /usr/local/lib."""
    real = prefix.resolve()
    home = f"{real}/"
    found: list[str] = []
    for root in (real / "bin", real / "libexec", Path(libdir)):
        for path in sorted(root.rglob("*") if root.is_dir() else ()):
            if path.is_symlink() or not path.is_file():
                continue
            with path.open("rb") as handle:
                if handle.read(4) != b"\x7fELF":
                    continue
            ldd = capture(["ldd", str(path)], env=clean_env()).stdout
            for m in re.finditer(r"^\s*(\S+) => (/\S+)", ldd, re.M):
                if not os.path.realpath(m.group(2)).startswith((home, *OS_LIBRARY_DIRS)):
                    found.append(f"{path.relative_to(real)}: {m.group(1)} => {m.group(2)}")
    return found


def smoke_test(prefix: Path, libdir: str, languages: Sequence[str], work: Path) -> list[Check]:
    bindir = prefix / "bin"
    env = clean_env(path=f"{bindir}:{BUILD_PATH}")
    checks: list[Check] = []
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    for name, text in SMOKE_SOURCES.items():
        (work / name).write_text(text, encoding="utf-8")

    def step(name: str, cmds: Sequence[Sequence[str]], expect: str = "") -> None:
        output = ""
        for cmd in cmds:
            res = capture(cmd, env=env, cwd=work, timeout=600)
            output = res.stdout + res.stderr
            if res.returncode != 0:
                # The first lines carry the error; later ones are often long notes.
                head = [line[:240] for line in output.strip().splitlines()[:8]]
                checks.append(Check(name, False, "\n".join([f"$ {shlex.join(cmd)}", *head])))
                return
        if expect and expect not in output:
            checks.append(Check(name, False, f"expected '{expect}', got: {output.strip()[-300:]}"))
            return
        checks.append(Check(name, True, expect))

    gcc, gxx = str(bindir / "gcc"), str(bindir / "g++")
    step("C compile and run", [[gcc, "-O2", "hello.c", "-o", "c.out"], ["./c.out"]], "c-ok")
    step(
        "C++17 threads, exceptions, <filesystem>",
        [[gxx, "-std=c++17", "-O2", "-pthread", "hello.cc", "-o", "cxx.out"], ["./cxx.out"]],
        "cxx-ok 10 b",
    )
    if "fortran" in languages:
        step(
            "Fortran compile and run",
            [[str(bindir / "gfortran"), "hello.f90", "-o", "f.out"], ["./f.out"]],
            "fortran-ok",
        )
    if "objc" in languages:
        step(
            "Objective-C compile and run",
            [[gcc, "hello.m", "-lobjc", "-o", "m.out"], ["./m.out"]],
            "objc-ok 42",
        )
    step("OpenMP", [[gcc, "-fopenmp", "-O2", "omp.c", "-o", "omp.out"], ["./omp.out"]], "500500")
    step(
        "LTO through a gcc-ar archive",
        [
            [gcc, "-flto", "-O2", "-c", "lto_a.c", "lto_b.c"],
            [str(bindir / "gcc-ar"), "rcs", "libtwice.a", "lto_b.o"],
            [gcc, "-flto", "-O2", "lto_a.o", "-L.", "-ltwice", "-o", "lto.out"],
            ["./lto.out"],
        ],
    )
    step(
        "C++ shared library",
        [
            [gxx, "-fPIC", "-shared", "lib.cc", "-o", "libgreet.so"],
            [gxx, "uselib.cc", "-L.", "-lgreet", "-Wl,-rpath,$ORIGIN", "-o", "uselib.out"],
            ["./uselib.out"],
        ],
        "shared-ok",
    )
    step(
        "Static libstdc++/libgcc",
        [
            [gxx, "-static-libstdc++", "-static-libgcc", "hello.cc", "-pthread", "-o", "st.out"],
            ["./st.out"],
        ],
        "cxx-ok",
    )
    step(
        "Relocatable link (-r)",
        [[gcc, "-c", "lto_b.c", "-o", "r1.o"], [gcc, "-r", "r1.o", "-o", "r.o"]],
    )
    # Without ISL, gcc/toplev.cc rejects the Graphite options with a "sorry" error.
    step(
        "Graphite loop optimizer (ISL)",
        [[gcc, "-O2", "-floop-nest-optimize", "-c", "lto_b.c", "-o", "graphite.o"]],
    )

    if (work / "cxx.out").exists():
        elf = capture(["readelf", "-h", "-d", str(work / "cxx.out")], env=env).stdout
        elf_type = re.search(r"^\s*Type:\s+(\S+)", elf, re.M)
        checks.append(
            Check(
                "Default PIE executable",
                "DYN (" in elf,
                f"ELF type {elf_type.group(1) if elf_type else 'unknown'}",
            )
        )
        runpath = re.search(r"\((?:RUNPATH|RPATH)\)\s+Library r(?:un)?path: \[(.*?)\]", elf)
        checks.append(
            Check(
                "RUNPATH points at this GCC",
                bool(runpath and libdir in runpath.group(1).split(":")),
                runpath.group(1) if runpath else "no RUNPATH",
            )
        )
    else:
        not_built = "not checked: the C++ test program was not built"
        checks.append(Check("Default PIE executable", False, not_built))
        checks.append(Check("RUNPATH points at this GCC", False, not_built))
    binaries = ["c.out", "cxx.out", "omp.out", "uselib.out"]
    binaries += ["f.out"] if "fortran" in languages else []
    binaries += ["m.out"] if "objc" in languages else []
    stray: list[str] = []
    seen: set[str] = set()
    for binary in binaries:
        if not (work / binary).exists():
            continue
        ldd = capture(["ldd", str(work / binary)], env=clean_env()).stdout
        for line in ldd.splitlines():
            m = re.match(r"\s*(\S+) => (\S+)", line)
            if not m or not m.group(1).startswith(RUNTIME_LIBS):
                continue
            seen.add(m.group(1))
            if not os.path.realpath(m.group(2)).startswith(libdir + "/"):
                stray.append(f"{binary}: {m.group(1)} => {m.group(2)}")
    checks.append(
        Check(
            "GCC runtimes load from this installation",
            not stray and bool(seen),
            "; ".join(stray)
            if stray
            else ", ".join(sorted(seen)) or "not checked: no test program was built",
        )
    )
    foreign = foreign_libraries(prefix, libdir)
    checks.append(
        Check(
            "Installed programs load only OS and GCC libraries",
            not foreign,
            "; ".join(foreign[:4]) + (f" (+{len(foreign) - 4} more)" if len(foreign) > 4 else ""),
        )
    )
    version_text = capture([gcc, "-v"], env=env).stderr
    zstd = re.search(r"Supported LTO compression algorithms: (.*)", version_text)
    checks.append(
        Check(
            "LTO zstd compression",
            bool(zstd and "zstd" in zstd.group(1).split()),
            zstd.group(1) if zstd else "not reported",
        )
    )
    return checks


@dataclass
class TestSummary:
    ran: bool
    counts: dict[str, int]
    per_suite: dict[str, dict[str, int]]


SUM_KEYS = (
    "expected passes",
    "unexpected failures",
    "unexpected successes",
    "expected failures",
    "unresolved testcases",
    "unsupported tests",
    "untested testcases",
)


def parse_test_summaries(build: Path) -> TestSummary:
    per_suite: dict[str, dict[str, int]] = {}
    for sum_file in sorted(build.rglob("*.sum")):
        try:
            text = sum_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        counts: dict[str, int] = {}
        for key in SUM_KEYS:
            match = re.search(rf"^# of {key}\s+(\d+)", text, re.M)
            if match:
                counts[key] = int(match.group(1))
        if counts:
            per_suite[str(sum_file.relative_to(build))] = counts
    total: dict[str, int] = {}
    for counts in per_suite.values():
        for key, value in counts.items():
            total[key] = total.get(key, 0) + value
    return TestSummary(ran=bool(per_suite), counts=total, per_suite=per_suite)


# ───────────────────────────────────────────────────────────────────────────── default compiler


@dataclass
class Candidate:
    version: str
    gcc: str
    tools: dict[str, str]
    origin: str
    machine: str

    @property
    def complete(self) -> bool:
        return "g++" in self.tools

    @property
    def priority(self) -> int:
        a, b, c = parse_version(self.version)
        return a * 10000 + b * 100 + c


def discover_candidates(extra_roots: Sequence[str] = ()) -> list[Candidate]:
    """Every native GCC on this computer, found read-only."""
    env = clean_env()
    host_machine = capture([HOST_CC, "-dumpmachine"], env=env).stdout.strip()
    found: dict[str, Candidate] = {}

    def consider(gcc: str, tool_paths: dict[str, str], origin: str) -> None:
        real = os.path.realpath(gcc)
        if real in found or not os.access(gcc, os.X_OK):
            return
        version = capture([gcc, "-dumpfullversion"], env=env).stdout.strip()
        machine = capture([gcc, "-dumpmachine"], env=env).stdout.strip()
        if not VERSION_RE.match(version) or not machine:
            return
        if host_machine and machine != host_machine:
            return
        tools = {t: p for t, p in tool_paths.items() if os.access(p, os.X_OK)}
        found[real] = Candidate(version, gcc, tools, origin, machine)

    tool_list = sorted({src for _, src in ALT_SLAVES} | {"gcc"})
    for gcc in sorted(glob.glob("/usr/bin/gcc-[0-9]*")):
        m = re.fullmatch(r"/usr/bin/gcc-(\d+)", gcc)
        if m:
            suffix = f"-{m.group(1)}"
            paths = {t: f"/usr/bin/{t}{suffix}" for t in tool_list}
            consider(gcc, paths, "distribution package")
    roots = list(dict.fromkeys([*extra_roots, *CANDIDATE_ROOTS]))
    for root in roots:
        for prefix in sorted(glob.glob(os.path.join(root, "gcc-[0-9]*"))):
            bindir = os.path.join(prefix, "bin")
            gcc = os.path.join(bindir, "gcc")
            if os.path.isfile(gcc):
                paths = {t: os.path.join(bindir, t) for t in tool_list}
                consider(gcc, paths, prefix)
    return sorted(found.values(), key=lambda c: c.priority, reverse=True)


@dataclass
class AltState:
    status: str
    value: str
    alternatives: list[str]


class Alternatives:
    """update-alternatives group 'local-gcc' with its links in /usr/local/bin."""

    def __init__(
        self,
        bin_dir: str = ALT_BIN_DIR,
        altdir: str | None = None,
        admindir: str | None = None,
        log: str | None = None,
        use_sudo: bool = True,
    ) -> None:
        self.bin_dir = bin_dir
        self.altdir = altdir or "/etc/alternatives"
        self.base = ["update-alternatives"]
        for opt, value in (("--altdir", altdir), ("--admindir", admindir), ("--log", log)):
            if value:
                self.base += [opt, value]
        self.use_sudo = use_sudo

    def _run(self, args: Sequence[str], mutate: bool) -> subprocess.CompletedProcess[str]:
        cmd = self.base + list(args)
        if mutate and self.use_sudo:
            cmd = privileged(cmd)
        return capture(cmd, env=clean_env(path=DEFAULT_PATH))

    def links(self) -> list[tuple[str, str]]:
        """(link path, alternative name) for the master and every slave."""
        pairs = [(os.path.join(self.bin_dir, "gcc"), ALT_GROUP)]
        pairs += [(os.path.join(self.bin_dir, tool), f"local-{tool}") for tool, _ in ALT_SLAVES]
        return pairs

    def query(self, name: str = ALT_GROUP) -> AltState | None:
        res = self._run(["--query", name], mutate=False)
        if res.returncode != 0:
            return None
        status = re.search(r"^Status: (\S+)", res.stdout, re.M)
        value = re.search(r"^Value: (.*)$", res.stdout, re.M)
        alts = re.findall(r"^Alternative: (.*)$", res.stdout, re.M)
        return AltState(
            status.group(1) if status else "",
            value.group(1).strip() if value else "",
            [a.strip() for a in alts],
        )

    def conflicts(self) -> list[str]:
        problems: list[str] = []
        for link, name in self.links():
            expected = os.path.join(self.altdir, name)
            if os.path.lexists(link):
                if not os.path.islink(link):
                    problems.append(f"{link} is a regular file, not an alternatives link")
                elif os.readlink(link) != expected:
                    problems.append(f"{link} -> {os.readlink(link)} is not managed by {ALT_GROUP}")
            if name != ALT_GROUP and self.query(name) is not None:
                problems.append(f"alternative name '{name}' already belongs to another group")
        return problems

    def slave_args(self, cand: Candidate) -> list[str]:
        args: list[str] = []
        for tool, source in ALT_SLAVES:
            target = cand.gcc if source == "gcc" else cand.tools.get(source)
            if target:
                args += ["--slave", os.path.join(self.bin_dir, tool), f"local-{tool}", target]
        return args

    def apply(self, cand: Candidate) -> None:
        if not cand.complete:
            raise InstallerError(f"GCC {cand.version} at {cand.gcc} has no g++; not selectable.")
        problems = self.conflicts()
        if problems:
            raise InstallerError(
                "Refusing to change the default compiler:\n    " + "\n    ".join(problems)
            )
        prior = self.query()
        master = os.path.join(self.bin_dir, "gcc")
        install = ["--install", master, ALT_GROUP, cand.gcc, str(cand.priority)]
        steps = [install + self.slave_args(cand), ["--set", ALT_GROUP, cand.gcc]]
        try:
            for args in steps:
                res = self._run(args, mutate=True)
                if res.returncode != 0:
                    raise InstallerError("update-alternatives failed: " + res.stderr.strip())
            self.verify(cand)
        except InstallerError:
            self._restore(prior)
            raise

    def verify(self, cand: Candidate) -> None:
        expected = {os.path.join(self.bin_dir, "gcc"): cand.gcc}
        for tool, source in ALT_SLAVES:
            target = cand.gcc if source == "gcc" else cand.tools.get(source)
            link = os.path.join(self.bin_dir, tool)
            if target:
                expected[link] = target
            elif os.path.lexists(link):
                raise InstallerError(
                    f"{link} still exists although GCC {cand.version} has no {tool}."
                )
        for link, target in expected.items():
            if os.path.realpath(link) != os.path.realpath(target):
                raise InstallerError(f"{link} resolves to {os.path.realpath(link)}, not {target}.")

    def _restore(self, prior: AltState | None) -> None:
        if prior is None:
            self._run(["--remove-all", ALT_GROUP], mutate=True)
        elif prior.value and prior.status == "manual":
            self._run(["--set", ALT_GROUP, prior.value], mutate=True)
        else:
            self._run(["--auto", ALT_GROUP], mutate=True)

    def remove(self) -> bool:
        if self.query() is None:
            return False
        res = self._run(["--remove-all", ALT_GROUP], mutate=True)
        if res.returncode != 0:
            raise InstallerError("update-alternatives --remove-all failed: " + res.stderr.strip())
        if os.path.lexists(os.path.join(self.bin_dir, "gcc")):
            raise InstallerError(f"{self.bin_dir}/gcc still exists after restoring the OS default.")
        return True


def kernel_compiler_major() -> int | None:
    try:
        text = Path("/proc/version").read_text(encoding="ascii", errors="replace")
    except OSError:
        return None
    m = re.search(r"gcc(?:-\d+)? \([^)]*\) (\d+)\.", text) or re.search(
        r"gcc version (\d+)\.", text
    )
    return int(m.group(1)) if m else None


def kernel_cc_name(config: Path | None = None) -> str | None:
    """The compiler command named by the running kernel's CONFIG_CC_VERSION_TEXT, if installed.

    DKMS 3.x (/usr/sbin/dkms) builds modules with this command when it exists, not with 'gcc'.
    """
    if config is None:
        config = Path("/lib/modules") / os.uname().release / "build" / ".config"
    try:
        text = config.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    m = re.search(r'^CONFIG_CC_VERSION_TEXT="?(\S+) ', text, re.M)
    if not m or shutil.which(m.group(1), path=DEFAULT_PATH) is None:
        return None
    return m.group(1)


def cuda_gcc_limits(roots: Sequence[str] | None = None) -> list[tuple[str, int]]:
    """(CUDA toolkit, newest host GCC major its nvcc accepts), from crt/host_config.h."""
    if roots is None:
        roots = sorted(glob.glob("/usr/local/cuda-*"))
    limits: dict[str, int] = {}
    for root in roots:
        real = os.path.realpath(root)
        headers = glob.glob(os.path.join(real, "targets", "*", "include", "crt", "host_config.h"))
        for header in headers[:1]:
            try:
                text = Path(header).read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            m = re.search(r"^#if __GNUC__ > (\d+)", text, re.M)
            if m:
                limits[real] = int(m.group(1))
    return sorted(limits.items())


def report_kernel_and_cuda(major: int) -> None:
    kcc = kernel_cc_name()
    kmajor = kernel_compiler_major()
    if kcc and kcc not in ("gcc", "cc"):
        info(
            f"Kernel modules: the running kernel's configuration names {kcc}, which DKMS uses "
            "instead of 'gcc', so this switch does not change how modules are built."
        )
    elif kmajor is not None and kmajor != major:
        warn(
            f"The running kernel was built with GCC {kmajor} and its configuration does not "
            f"name a versioned compiler, so DKMS may now build modules with GCC {major}, which "
            "can fail. If a module build fails, restore the OS default first."
        )
    for root, limit in cuda_gcc_limits():
        if major > limit:
            warn(
                f"{root}: nvcc rejects host GCC newer than {limit}. Pass -ccbin {HOST_CXX} "
                "(the OS compiler) to nvcc, or restore the OS default."
            )


def report_resolution() -> None:
    clean = shutil.which("gcc", path=DEFAULT_PATH)
    info(
        "System default (PATH used by sudo, cron and new logins): gcc → "
        + S(os.path.realpath(clean) if clean else "not found", "bold")
    )
    mine = shutil.which("gcc")
    if mine and clean and os.path.realpath(mine) != os.path.realpath(clean):
        warn(
            f"Your current shell PATH finds {mine} first (→ {os.path.realpath(mine)}). That entry "
            "(e.g. from ~/.bashrc or conda) still wins in your shell; this script does not edit "
            "your dotfiles."
        )
    info("Already-open shells may cache the old location: run 'hash -r' or open a new terminal.")


def switch_menu(prefix_roots: Sequence[str], highlight: str | None = None) -> None:
    alts = Alternatives()
    candidates = discover_candidates(prefix_roots)
    state = alts.query()
    current = os.path.realpath(state.value) if state and state.value else None
    out()
    out(f"  {S('Compilers found on this computer', 'bold')}")
    selectable: dict[str, Candidate] = {}
    for idx, cand in enumerate(candidates, 1):
        key = str(idx)
        marks = []
        if current and os.path.realpath(cand.gcc) == current:
            marks.append(S("current default", "bgreen"))
        if highlight and os.path.realpath(cand.gcc) == os.path.realpath(highlight):
            marks.append(S("just installed", "bmagenta"))
        if not cand.complete:
            marks.append(S("C only — no g++, not selectable", "yellow"))
        else:
            selectable[key] = cand
        missing = [t for t in ("gfortran", "cpp") if t not in cand.tools]
        detail = f"{cand.origin}" + (f"; no {', '.join(missing)}" if missing else "")
        num = S(f"{key:>3})", "bold", "bcyan") if cand.complete else S(f"{key:>3})", "dim")
        out(f"   {num} GCC {S(cand.version, 'bold'):<10}  {cand.gcc}")
        out(f"        {S(detail, 'dim')}" + (f"  {'  '.join(marks)}" if marks else ""))
    os_default = os.path.realpath(HOST_CC) if os.path.exists(HOST_CC) else "none"
    out(f"   {S('  R)', 'bold', 'bcyan')} Restore the OS default ({os_default})")
    out(f"   {S('  K)', 'bold', 'bcyan')} Keep the current setting")
    while True:
        answer = ask("Choose the default compiler", "K").strip().upper()
        if answer == "K":
            info("Default compiler unchanged.")
            return
        if answer == "R":
            if alts.remove():
                ok("Removed the /usr/local/bin override; the OS default applies again.")
            else:
                info("No override was active; the OS default already applies.")
            report_resolution()
            return
        if answer in selectable:
            cand = selectable[answer]
            alts.apply(cand)
            ok(f"gcc, g++, cc, c++ … in {ALT_BIN_DIR} now point to GCC {cand.version}.")
            missing = [t for t, s in ALT_SLAVES if s != "gcc" and s not in cand.tools]
            if missing:
                warn("Not provided by this GCC, so found elsewhere on PATH: " + ", ".join(missing))
            report_resolution()
            report_kernel_and_cuda(parse_version(cand.version)[0])
            info(f"To undo later: {SCRIPT_NAME} --switch-only, then R.")
            return
        warn("Enter a number from the list, R or K.")


# ───────────────────────────────────────────────────────────────────────────── main flow


def show_plan(plan: BuildPlan, src: Path, build: Path, res: Resources, tc: HostToolchain) -> None:
    def row(label: str, value: str) -> None:
        out(f"  {S(label.ljust(17), 'bold')} {value}")

    row("Prefix", str(plan.prefix))
    row("Languages", f"{', '.join(plan.languages)} (+ LTO)")
    row(
        "Stage-1 compiler",
        f"{tc.cc} / {tc.cxx} (gcc {tc.version}"
        + (f", {tc.real_cc})" if tc.real_cc != tc.cc else ")"),
    )
    row("Make", f"{tc.make} ({tc.make_version})")
    row("Linker", tc.ld_version)
    row(
        "Parallel jobs",
        f"{plan.jobs} ({res.jobs_source}; {res.cpus} CPUs, "
        f"{fmt_bytes(res.mem_available)} memory available)",
    )
    out(f"  {S('Configure', 'bold')}")
    out(f"    {S('cd', 'dim')} {build}")
    out(f"    {S(CONFIG_SHELL, 'dim')} {src}/configure \\")
    for i, arg in enumerate(plan.configure_args):
        tail = " \\" if i < len(plan.configure_args) - 1 else ""
        out(f"      {S(shlex.quote(arg), 'bgreen')}{tail}")
    make = [HOST_MAKE, f"-j{plan.jobs}", *plan.make_vars, plan.make_target]
    out(f"  {S('Build', 'bold')}\n    {S(shlex.join(make), 'bgreen')}")
    for note in plan.notes:
        info(note)


LINK_SERIALIZATION_ARG = "--enable-link-serialization="
BUILD_SETTING_LABELS = {
    "tarball_sha256": "GCC source tarball",
    "configure_args": "configure options",
    "make_target": "make target",
    "make_vars": "make variables",
    "host_compiler": "stage-1 compiler",
    "iconv_header": "<iconv.h>",
}
# configure finished in these states, so make can continue in the tree.
RESUMABLE_STATES = ("configured", "building", "stopped", "failed", "built")


def build_settings(
    plan: BuildPlan, toolchain: HostToolchain, tarball_sha256: str
) -> dict[str, Any]:
    """What a resumed build must share with the build it continues.

    Link serialization follows the memory free at planning time and only limits how many large
    links run at once, so a different value does not make a configured tree stale.
    """
    return {
        "tarball_sha256": tarball_sha256,
        "configure_args": [
            a for a in plan.configure_args if not a.startswith(LINK_SERIALIZATION_ARG)
        ],
        "make_target": plan.make_target,
        "make_vars": list(plan.make_vars),
        "host_compiler": [toolchain.version, toolchain.cc, toolchain.cxx],
        "iconv_header": toolchain.iconv_header,
    }


@dataclass(frozen=True)
class PriorBuild:
    """The build directory an earlier run left behind, as recorded in its marker."""

    state: str
    stage: str
    stopped_by: str
    forced: bool
    configure_args: tuple[str, ...]
    differs: tuple[str, ...]
    recorded: bool  # the marker holds the settings the tree was configured with

    @property
    def resumable(self) -> bool:
        return self.recorded and not self.differs and self.state in RESUMABLE_STATES

    def obstacle(self) -> str:
        """Why it cannot be resumed ('' if it can)."""
        if not self.recorded:
            return "its build settings were not recorded, so they cannot be compared"
        if self.differs:
            verb = "differs" if len(self.differs) == 1 else "differ"
            return f"its {', '.join(self.differs)} {verb} from this run"
        if self.state not in RESUMABLE_STATES:
            return "configure had not finished"
        return ""

    @property
    def clean(self) -> bool:
        """make had the chance to delete any half-written target (GNU make manual, 5.6)."""
        if self.state == "stopped":
            return not self.forced
        return self.state in ("configured", "failed", "built")

    def describe(self) -> str:
        during = f" during {self.stage}" if self.stage else ""
        if self.state == "configuring":
            return "configure did not finish"
        if self.state == "configured":
            return "configured, but the build had not started"
        if self.state == "building":
            return (
                f"cut off{during} without this script recording why (killed with -9, crashed, "
                "or the computer stopped)"
            )
        if self.state == "stopped":
            how = "Ctrl-C" if self.stopped_by == "SIGINT" else self.stopped_by or "a signal"
            forced = "; its processes had to be force-killed" if self.forced else ""
            return f"stopped by {how}{during}{forced}"
        if self.state == "failed":
            return f"failed{during}"
        if self.state == "built":
            return "finished building; testing or installing did not complete"
        return "its state was not recorded"


def current_stage(build: Path) -> str:
    """The bootstrap stage the top-level Makefile records in stage_current, or ''."""
    try:
        return (build / "stage_current").read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def read_prior_build(build: Path, settings: dict[str, Any]) -> PriorBuild | None:
    if not build.exists() and not build.is_symlink():
        return None
    marker = (read_json(build / BUILD_MARKER) if build.is_dir() else None) or {}
    recorded = marker.get("settings")
    if isinstance(recorded, dict):
        differs = tuple(
            label
            for key, label in BUILD_SETTING_LABELS.items()
            if recorded.get(key) != settings[key]
        )
    else:
        differs = ()
    args = marker.get("configure_args")
    return PriorBuild(
        state=str(marker.get("state", "")),
        stage=current_stage(build) or str(marker.get("stage", "")),
        stopped_by=str(marker.get("stopped_by", "")),
        forced=bool(marker.get("forced", False)),
        configure_args=tuple(str(a) for a in args) if isinstance(args, list) else (),
        differs=differs,
        recorded=isinstance(recorded, dict),
    )


def run_install(args: argparse.Namespace) -> int:
    phases = Phases()
    script_dir = Path(__file__).resolve().parent
    prefix_root = Path(args.prefix_root)
    if not prefix_root.is_absolute() or not SAFE_PATH_RE.match(str(prefix_root)):
        raise UsageError(
            f"--prefix-root must be an absolute path of plain characters: {prefix_root}"
        )
    languages = resolve_languages(args.languages, None)
    if args.jobs is not None and args.jobs < 1:
        raise UsageError("--jobs must be at least 1.")

    phases.start("Checking this computer")
    distro = check_os(read_os_release())
    ok(f"{distro}, Python {sys.version.split()[0]}")

    phases.start("Choosing the GCC release")
    releases = parse_release_index(fetch_text(GNU_INDEX_URL))
    version = select_version(releases, major=args.major, exact=args.gcc_version, latest=args.latest)
    ver = vstr(version)
    ok(f"Selected GCC {S(ver, 'bold')}")
    prefix = prefix_root / f"gcc-{ver}"
    if prefix.exists() and not args.dry_run:
        _occupied_prefix(prefix, prefix_state(prefix))

    installer = script_dir / f"gcc_{ver}_installer"
    ensure_plain_dir(installer)
    with DirLock(installer / LOCK_FILE):
        return Session(args, phases, script_dir, installer, version, prefix, languages).run()


def clean_build_files(script_dir: Path, *, dry_run: bool) -> int:
    """--clean: delete every gcc_X.Y.Z_installer/ beside the script; returns the exit code."""
    Phases().start("Cleaning earlier build files")
    candidates = sorted(p for p in script_dir.iterdir() if INSTALLER_DIR_RE.match(p.name))
    folders = []
    for path in candidates:
        if path.is_symlink() or not path.is_dir():
            warn(f"Skipped {path.name}: not a plain folder, so this script did not create it.")
        else:
            folders.append(path)
    if not folders:
        out()
        ok(f"Nothing to clean: no gcc_X.Y.Z_installer folders in {script_dir}.")
        return 0
    failed, freed = 0, 0
    for folder in folders:
        size = _du(folder)
        if dry_run:
            info(f"Would delete {folder.name}/ ({fmt_bytes(size)})")
            continue
        try:
            _delete_installer_dir(folder)
        except InstallerError as exc:
            failed += 1
            fail(str(exc))
            for line in exc.hint.splitlines():
                print(f"    {line}", file=sys.stderr)
            continue
        freed += size
        ok(f"Deleted {folder.name}/ ({fmt_bytes(size)})")
    out()
    if dry_run:
        ok(f"Dry run: nothing was deleted ({len(folders)} folder(s) would be).")
        return 0
    if failed:
        fail(
            f"Clean FAILED: {failed} of {len(folders)} folder(s) could not be deleted "
            f"(freed {fmt_bytes(freed)})."
        )
        return 1
    ok(f"Clean succeeded: deleted {len(folders)} folder(s), freed {fmt_bytes(freed)}.")
    return 0


def _delete_installer_dir(folder: Path) -> None:
    """Delete folder, holding its lock so a build running there is never pulled out from under."""
    try:
        with DirLock(folder / LOCK_FILE):
            for entry in folder.iterdir():
                if entry.name == LOCK_FILE:
                    continue
                if entry.is_dir() and not entry.is_symlink():
                    shutil.rmtree(entry)
                else:
                    entry.unlink()
            (folder / LOCK_FILE).unlink()
        folder.rmdir()
    except OSError as exc:
        raise InstallerError(
            f"Could not delete {folder}: {exc.strerror or exc} ({exc.filename or folder}).",
            "It may hold files owned by root from an older version of this script; remove "
            f"it with: sudo rm -rf -- '{folder}'",
        ) from exc


def _occupied_prefix(prefix: Path, state: dict[str, Any] | None) -> None:
    if state and state.get("state") == "complete":
        raise InstallerError(
            f"GCC is already installed in {prefix}.",
            f"Use --switch-only to make it the default, or remove it (sudo rm -rf '{prefix}') "
            "to rebuild.",
        )
    if state and state.get("state") in ("installing", "unverified"):
        warn(f"{prefix} holds an incomplete installation from an earlier run of this script.")
        if interactive() and confirm(
            f"Delete {prefix} so it can be installed again?", default=False
        ):
            privileged_rmtree(prefix)
            ok(f"Deleted {prefix}")
            return
        raise InstallerError(
            f"{prefix} is not empty.",
            f"Remove it (sudo rm -rf '{prefix}') and run again; a finished build can be resumed "
            "without compiling again.",
        )
    raise InstallerError(
        f"{prefix} already exists and was not created by this script.",
        "Choose another --prefix-root or move that directory away.",
    )


class Session:
    """One locked installer run for one GCC release, split into its phases."""

    def __init__(
        self,
        args: argparse.Namespace,
        phases: Phases,
        script_dir: Path,
        installer: Path,
        version: Version,
        prefix: Path,
        languages: list[str],
    ) -> None:
        self.args, self.phases = args, phases
        self.version, self.ver = version, vstr(version)
        self.installer, self.prefix, self.languages = installer, prefix, languages
        self.logs = installer / "logs"
        self.verify_dir = installer / "verify"
        self.build = installer / "build"
        self.src = installer / f"gcc-{self.ver}"
        self.tarball = script_dir / f"gcc-{self.ver}.tar.xz"
        self.sig = self.verify_dir / f"gcc-{self.ver}.tar.xz.sig"
        self.keyring = self.verify_dir / "gnu-keyring.gpg"
        self.trusted = {**GCC_RELEASE_KEYS, **parse_fingerprints(args.trust_key)}
        self.stage = installer / "stage"
        self.tarball_urls = [f"{b}gcc-{self.ver}/gcc-{self.ver}.tar.xz" for b in TARBALL_URL_BASES]
        self.timings: dict[str, float] = {}
        self.manifest: dict[str, Any] = {
            "version": self.ver,
            "script": SCRIPT_NAME,
            "started": _now(),
            "timings_seconds": self.timings,
        }
        self.keeper = SudoKeeper()
        self.runner = Runner(self.logs, verbose=args.verbose)
        self.cached = False
        self.tests = TestSummary(False, {}, {})

    def save_manifest(self) -> None:
        write_json(self.installer / "manifest.json", self.manifest)

    def run(self) -> int:
        ensure_plain_dir(self.logs)
        ensure_plain_dir(self.verify_dir)
        try:
            self.download()
            self.dependencies()
            self.verify()
            self.extract()
            plan, toolchain, resources = self.plan_build()
            settings = build_settings(plan, toolchain, str(self.manifest["tarball_sha256"]))
            prior = read_prior_build(self.build, settings)
            if self.args.dry_run:
                if prior:
                    info(f"{self.build} holds an earlier build: {prior.describe()}.")
                    info(
                        "A real run would offer to resume it."
                        if prior.resumable
                        else "A real run would start over."
                    )
                out()
                ok(f"Dry run complete. Source: {self.src}")
                info("Nothing was configured, built or installed.")
                return 0
            mode = self.choose_resume(prior)
            if mode == "cancel" or not self.confirm_build(resources):
                info("Cancelled before building.")
                return 0
            env = clean_env(
                {
                    "CC": toolchain.cc,
                    "CXX": toolchain.cxx,
                    "CONFIG_SHELL": CONFIG_SHELL,
                    **iconv_include_env(toolchain.iconv_shim),
                }
            )
            if mode == "fresh":
                self.configure(plan, env, settings)
            if mode != "built":
                self.make(plan, toolchain, env, resumed=mode == "resume")
            if self.args.run_tests and not self.test_suite(plan, toolchain, env):
                return 1
            libdir = self.install(toolchain, env)
            self.verify_install(libdir)
        finally:
            self.keeper.stop()
        self.finish()
        return 0

    def download(self) -> None:
        self.phases.start("Downloading")
        t0 = time.monotonic()
        if self.tarball.is_symlink() or (self.tarball.exists() and not self.tarball.is_file()):
            raise InstallerError(f"{self.tarball} is not a regular file.")
        self.cached = self.tarball.exists()
        if self.cached:
            info(f"Found {self.tarball.name}; it will be re-verified.")
        else:
            download(self.tarball_urls, self.tarball, self.tarball.name)
        sig_url = f"{SIGNATURE_URL_BASE}gcc-{self.ver}/gcc-{self.ver}.tar.xz.sig"
        download([sig_url], self.sig, self.sig.name)
        download([KEYRING_URL], self.keyring, self.keyring.name)
        self.timings["download"] = time.monotonic() - t0

    def dependencies(self) -> None:
        self.phases.start("Build dependencies")
        wanted = list(BUILD_PACKAGES) + (list(TEST_PACKAGES) if self.args.run_tests else [])
        installed = dpkg_installed(wanted)
        missing = [p for p in wanted if p not in installed]
        if not missing:
            ok("All build packages are installed.")
            return
        info("Missing packages: " + S(" ".join(missing), "bold"))
        if self.args.dry_run:
            warn("--dry-run: not installing them.")
            return
        if not confirm("Install them with apt now?", default=True, assume_yes=self.args.yes):
            raise InstallerError("Cannot build without: " + " ".join(missing))
        self.keeper.start("installing packages with apt")
        # Its output goes to a log, not a terminal, so apt would print its "does not have a
        # stable CLI interface" warning; apt reads this option since at least 2.0.2.
        apt = [
            "env",
            "DEBIAN_FRONTEND=noninteractive",
            "apt",
            "-o",
            "Apt::Cmd::Disable-Script-Warning=true",
        ]
        if self.runner.run("apt-update", [*apt, "update"], privileged_cmd=True, check=False):
            warn("apt update reported errors (often an unrelated repository); continuing.")
        self.runner.run(
            "apt-install",
            [*apt, "install", "-y", "--no-install-recommends", *missing],
            privileged_cmd=True,
        )
        installed = dpkg_installed(missing)
        still = [p for p in missing if p not in installed]
        if still:
            raise InstallerError("Still not installed: " + " ".join(still))

    def verify(self) -> None:
        self.phases.start("Verifying the signature")
        if shutil.which("gpgv", path=BUILD_PATH) is None:
            raise InstallerError(
                "gpgv is not installed, so the download cannot be verified.",
                "Install the gpgv package (a dry run does not install packages).",
            )
        try:
            signature = _verify_or_quarantine(self.tarball, self.sig, self.keyring, self.trusted)
        except InstallerError:
            if not self.cached:
                raise
            warn("The cached tarball failed verification; downloading a fresh copy.")
            download(self.tarball_urls, self.tarball, self.tarball.name)
            signature = _verify_or_quarantine(self.tarball, self.sig, self.keyring, self.trusted)
        digest = sha256_file(self.tarball)
        ok(f"Good signature from GCC release key {signature.primary_key} ({signature.signer})")
        info(f"sha256 {digest}")
        self.manifest.update(
            tarball=str(self.tarball),
            tarball_sha256=digest,
            signing_subkey=signature.signing_key,
            signing_primary_key=signature.primary_key,
            signer=signature.signer,
        )

    def extract(self) -> None:
        self.phases.start("Extracting")
        t0 = time.monotonic()
        if shutil.which("xz", path=BUILD_PATH) is None:
            raise InstallerError("xz is not installed.", "Install xz-utils.")
        digest = str(self.manifest["tarball_sha256"])
        self.src = extract_source(self.tarball, self.installer, self.ver, digest)
        self.timings["extract"] = time.monotonic() - t0
        self.languages = resolve_languages(",".join(self.languages), self.src)

    def plan_build(self) -> tuple[BuildPlan, HostToolchain, Resources]:
        self.phases.start("Planning the build")
        triplet = native_triplet()
        toolchain = host_toolchain(self.version[0], self.installer / "iconv-glibc")
        resources = plan_resources(self.args.jobs)
        if resources.jobs > resources.heuristic_jobs:
            warn(
                f"--jobs {resources.jobs} is above the {resources.heuristic_jobs} jobs that "
                f"{fmt_bytes(resources.mem_available)} of available memory allows at "
                f"~{MEM_GIB_PER_JOB} GiB per job; the build may run out of memory."
            )
        plan = build_plan(
            src=self.src,
            version=self.version,
            triplet=triplet,
            prefix=self.prefix,
            languages=self.languages,
            toolchain=toolchain,
            resources=resources,
            portable=self.args.portable,
            pgo=not self.args.no_pgo,
        )
        show_plan(plan, self.src, self.build, resources, toolchain)
        self.manifest.update(
            prefix=str(self.prefix),
            triplet=triplet,
            languages=self.languages,
            configure_args=plan.configure_args,
            make_target=plan.make_target,
            make_vars=plan.make_vars,
            jobs=plan.jobs,
            jobs_source=resources.jobs_source,
            link_serialization=resources.link_serialization,
            host_compiler=f"gcc {toolchain.version} ({toolchain.real_cc})",
            make=f"{toolchain.make} ({toolchain.make_version})",
            linker=toolchain.ld_version,
            distro=read_os_release().get("PRETTY_NAME", ""),
        )
        self.save_manifest()
        return plan, toolchain, resources

    def confirm_build(self, resources: Resources) -> bool:
        _preflight_space(self.installer, self.prefix, resources, self.args.yes)
        if self.prefix.exists():
            _occupied_prefix(self.prefix, prefix_state(self.prefix))
        question = f"Build and install GCC {self.ver} now?"
        if not confirm(question, default=True, assume_yes=self.args.yes):
            return False
        self.keeper.start(f"copying the finished build into {self.prefix}")
        return True

    def choose_resume(self, prior: PriorBuild | None) -> str:
        """'fresh', 'resume' (make continues), 'built' (skip make) or 'cancel'.

        Continuing in the same build directory is how GCC's bootstrap is designed to recover
        (gccint, "Makefile": each stage is reused if it had been built). Like Spack's
        --dont-restage and crosstool-NG's RESTART, resuming is opt-in when nobody is asked.
        """
        if prior is None:
            if self.args.resume:
                info("--resume: there is no earlier build to continue; starting fresh.")
            return "fresh"
        self.phases.start("Earlier build found")
        info(f"{self.build} holds an earlier build of GCC {self.ver}: {prior.describe()}.")
        reason = prior.obstacle()
        if reason:
            if self.args.resume:
                raise InstallerError(
                    f"Cannot resume it: {reason}.",
                    "Run again with the same options as the interrupted run (--jobs may "
                    "change), or without --resume to start over, which deletes that build.",
                )
            info(f"Starting over: {reason}.")
            return "fresh"
        choice = self._ask_resume(prior)
        if choice != "fresh":
            self.manifest["resumed"] = {
                "state": prior.state,
                "stage": prior.stage,
                "stopped_by": prior.stopped_by,
                "forced": prior.forced,
            }
            self.manifest["configure_args"] = list(prior.configure_args)
            info(f"Continuing with the configure options recorded in {self.build}.")
        if choice == "resume" and prior.state == "built":
            return "built"
        return choice

    def _ask_resume(self, prior: PriorBuild) -> str:
        if self.args.resume:
            info(f"Resume it? {S('yes (--resume)', 'dim')}")
            return "resume"
        if self.args.yes or not interactive():
            info("Starting over; pass --resume to continue that build instead.")
            return "fresh"
        if not prior.clean:
            warn(
                "Files that were being written when it stopped may be incomplete, and make "
                "cannot tell. Starting over is the safe choice."
            )
        out(f"    {S('R', 'bold')}  Resume: make continues where it stopped, finished work is kept")
        out(f"    {S('S', 'bold')}  Start over: delete the build directory and configure again")
        out(f"    {S('C', 'bold')}  Cancel")
        default = "R" if prior.clean else "S"
        while True:
            answer = ask("Resume, start over or cancel? (R/S/C)", default).strip().lower()
            if answer in ("r", "resume"):
                return "resume"
            if answer in ("s", "start over"):
                return "fresh"
            if answer in ("c", "cancel"):
                return "cancel"
            warn("Please answer R, S or C.")

    def _mark_build(
        self, state: str, *, stage: str = "", stopped_by: str = "", forced: bool = False
    ) -> None:
        """Record in the build marker how far the build got (read by read_prior_build)."""
        marker = read_json(self.build / BUILD_MARKER) or {"version": self.ver}
        marker.update(
            state=state, stage=stage, stopped_by=stopped_by, forced=forced, updated=_now()
        )
        write_json(self.build / BUILD_MARKER, marker)

    def configure(self, plan: BuildPlan, env: dict[str, str], settings: dict[str, Any]) -> None:
        self.phases.start("Configuring")
        if self.build.exists() or self.build.is_symlink():
            info(f"Removing the previous build directory {self.build}")
            remove_owned_tree(self.build, self.installer, BUILD_MARKER)
        self.build.mkdir()
        write_json(
            self.build / BUILD_MARKER,
            {
                "version": self.ver,
                "created": _now(),
                "settings": settings,
                "configure_args": plan.configure_args,
                "state": "configuring",
            },
        )
        t0 = time.monotonic()
        self.runner.run(
            "configure",
            [CONFIG_SHELL, str(self.src / "configure"), *plan.configure_args],
            env=env,
            cwd=self.build,
        )
        self._mark_build("configured")
        self.timings["configure"] = time.monotonic() - t0

    def make(
        self, plan: BuildPlan, toolchain: HostToolchain, env: dict[str, str], *, resumed: bool
    ) -> None:
        verb = "Resuming the build" if resumed else "Building"
        self.phases.start(f"{verb} ({plan.make_target}, -j{plan.jobs})")
        info(f"This is the long part. Complete output: {self.logs}")
        if not self.args.verbose:
            info("Showing key steps only; add --verbose to watch the full compiler output.")
        t0 = time.monotonic()
        # Until make returns, the marker says "building": a run that dies without reaching
        # the handlers below (kill -9, crash, power loss) is recognised as an unclean stop.
        self._mark_build("building", stage=current_stage(self.build))
        try:
            with MemorySampler() as mem:
                self.runner.run(
                    "build",
                    [toolchain.make, f"-j{plan.jobs}", *plan.make_vars, plan.make_target],
                    env=env,
                    cwd=self.build,
                    stage_file=self.build / "stage_current",
                    milestones=BUILD_MILESTONES,
                )
        except KeyboardInterrupt as exc:
            signum = exc.signum if isinstance(exc, Terminated) else signal.SIGINT
            self._mark_build(
                "stopped",
                stage=current_stage(self.build),
                stopped_by=signal.Signals(signum).name,
                forced=self.runner.forced_stop,
            )
            with contextlib.suppress(OSError):  # the terminal may be gone after SIGHUP
                info(
                    f"Run {SCRIPT_NAME} again with the same options (--jobs may change) to "
                    "resume this build."
                )
            raise
        except InstallerError as exc:
            self._mark_build("failed", stage=current_stage(self.build))
            advice = (
                "This build was resumed. If the failure is unexpected, run again and choose S "
                "(start over) to rule out leftovers from the earlier stop."
                if resumed
                else "After fixing the cause, run again with the same options to resume; "
                "--jobs may change (lower it if memory ran out)."
            )
            raise InstallerError(str(exc), f"{exc.hint}\n{advice}".strip()) from exc
        self._mark_build("built")
        self.timings["build"] = time.monotonic() - t0
        self.manifest["build_min_mem_available"] = mem.minimum
        self.manifest["build_dir_bytes"] = _du(self.build)
        self.save_manifest()

    def test_suite(self, plan: BuildPlan, toolchain: HostToolchain, env: dict[str, str]) -> bool:
        self.phases.start("Running the test suite (make -k check)")
        t0 = time.monotonic()
        self.runner.run(
            "check",
            [toolchain.make, "-k", f"-j{plan.jobs}", "check"],
            env=env,
            cwd=self.build,
            milestones=CHECK_MILESTONES,
            check=False,
        )
        self.timings["tests"] = time.monotonic() - t0
        self.tests = parse_test_summaries(self.build)
        _report_tests(self.tests)
        self.manifest["tests"] = {
            "ran": self.tests.ran,
            "totals": self.tests.counts,
            "per_suite": self.tests.per_suite,
        }
        if self.tests.ran:
            report = self._test_report()
            if report:
                self.manifest["tests"]["report"] = str(report)
        self.save_manifest()
        bad = self.tests.counts.get("unexpected failures", 0)
        if not (self.tests.ran and bad):
            return True
        info(
            "GCC releases normally show some unexpected failures; compare the report with the "
            f"posts for GCC {self.ver} on {plan.triplet} at "
            "https://gcc.gnu.org/pipermail/gcc-testresults/"
        )
        question = f"{bad} unexpected test failures. Install anyway?"
        return confirm(question, default=True, assume_yes=self.args.yes)

    def _test_report(self) -> Path | None:
        """contrib/test_summary: the report format used on the gcc-testresults list.

        -t keeps it from renaming the .sum files; its output is a mail script that is only saved.
        """
        report = self.logs / "test_summary.txt"
        result = capture(
            ["/bin/sh", str(self.src / "contrib" / "test_summary"), "-t"],
            env=clean_env(),
            cwd=self.build,
            timeout=900,
        )
        if result.returncode != 0 or not result.stdout:
            warn("contrib/test_summary failed: " + (result.stderr.strip() or "no output"))
            return None
        report.write_text(result.stdout, encoding="utf-8")
        info(f"Test report (gcc-testresults format): {report}")
        return report

    def install(self, toolchain: HostToolchain, env: dict[str, str]) -> str:
        """Stage 'make install-strip' as the user (DESTDIR), then copy it into place as root.

        No make recipe runs as root, so the build tree never gets root-owned files, and the
        prefix is created only once a complete staged tree exists.
        """
        self.phases.start(f"Installing into {self.prefix}")
        t0 = time.monotonic()
        if self.stage.exists() or self.stage.is_symlink():
            remove_owned_tree(self.stage, self.installer, STAGE_MARKER)
        self.stage.mkdir()
        write_json(self.stage / STAGE_MARKER, {"version": self.ver, "created": _now()})
        self.runner.run(
            "install-staged",
            [toolchain.make, f"DESTDIR={self.stage}", "install-strip"],
            env=env,
            cwd=self.build,
            umask=0o022,
        )
        if "objc" in self.languages:
            # libobjc/Makefile.in declares install-strip as an empty rule, so install-strip
            # skips libobjc entirely; its plain install target installs it (unstripped).
            self.runner.run(
                "install-libobjc",
                [toolchain.make, f"DESTDIR={self.stage}", "install-target-libobjc"],
                env=env,
                cwd=self.build,
                umask=0o022,
            )
        staged = self.stage / self.prefix.relative_to("/")
        if not (staged / "bin" / "gcc").is_file():
            raise InstallerError(f"The staged installation has no {staged}/bin/gcc.")
        claim_prefix(self.prefix)
        self.manifest["state"] = "installing"
        self._write_state("installing")
        self.runner.run(
            "install",
            ["cp", "-a", "--no-preserve=ownership", "--", f"{staged}/.", str(self.prefix)],
            privileged_cmd=True,
        )
        remove_owned_tree(self.stage, self.installer, STAGE_MARKER)
        specs, libdir = install_specs(self.prefix, self.installer)
        ok(f"RUNPATH rule written to {specs}")
        self.timings["install"] = time.monotonic() - t0
        self.manifest.update(specs=str(specs), runtime_libdir=libdir, prefix_bytes=_du(self.prefix))
        return libdir

    def _write_state(self, state: str) -> None:
        payload = json.dumps({"state": state, "version": self.ver})
        privileged_write(self.prefix / STATE_FILE, payload, self.installer)

    def verify_install(self, libdir: str) -> None:
        self.phases.start("Verifying the installed compiler")
        checks = smoke_test(self.prefix, libdir, self.languages, self.installer / "smoke")
        for check in checks:
            detail = f" {S('— ' + check.detail, 'dim')}" if check.detail else ""
            (ok if check.passed else fail)(check.name + detail)
        self.manifest["smoke_tests"] = [c.__dict__ for c in checks]
        gcc_v = capture([str(self.prefix / "bin" / "gcc"), "-v"], env=clean_env()).stderr
        self.manifest["gcc_v"] = gcc_v.strip()
        passed = all(c.passed for c in checks)
        self.manifest["state"] = "complete" if passed else "unverified"
        self.manifest["finished"] = _now()
        self.save_manifest()
        self._write_state(self.manifest["state"])
        privileged_write(
            self.prefix / "share" / "install_gcc" / "manifest.json",
            json.dumps(self.manifest, indent=2, sort_keys=True) + "\n",
            self.installer,
        )
        if not passed:
            raise InstallerError(
                f"GCC {self.ver} is installed in {self.prefix} but failed verification.",
                f"Build tree and logs are kept in {self.installer}.",
            )

    def finish(self) -> None:
        _summary(self.ver, self.prefix, self.timings, self.tests, self.installer)
        self.phases.start("Default compiler")
        if interactive():
            switch_menu([str(self.prefix.parent)], highlight=str(self.prefix / "bin" / "gcc"))
        else:
            info(f"No terminal: default compiler unchanged. Later: {SCRIPT_NAME} --switch-only")
        _offer_cleanup(self.args, self.installer, self.src, self.build)


def _verify_or_quarantine(
    tarball: Path, sig: Path, keyring: Path, trusted: dict[str, str]
) -> Signature:
    """A tarball that fails verification is renamed aside (never deleted) before re-raising."""
    try:
        return gpgv_verify(tarball, sig, keyring, trusted)
    except InstallerError:
        quarantine = tarball.with_name(f"{tarball.name}.invalid-{int(time.time())}")
        os.replace(tarball, quarantine)
        fail(f"Signature check failed; moved the tarball aside as {quarantine.name}")
        raise


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds")


def _du(path: Path) -> int:
    res = capture(["du", "-sb", "--", str(path)], env=clean_env(), timeout=1800)
    try:
        return int(res.stdout.split()[0])
    except (IndexError, ValueError):
        return 0


def _preflight_space(installer: Path, prefix: Path, res: Resources, assume_yes: bool) -> None:
    build_free = free_space(installer)
    prefix_free = free_space(prefix.parent)
    short = []
    if build_free < MIN_BUILD_DISK_GIB * GIB:
        short.append(
            f"{installer}: {fmt_bytes(build_free)} free, ~{MIN_BUILD_DISK_GIB} GiB advised"
        )
    if prefix_free < MIN_PREFIX_DISK_GIB * GIB:
        short.append(
            f"{prefix.parent}: {fmt_bytes(prefix_free)} free, ~{MIN_PREFIX_DISK_GIB} GiB advised"
        )
    if res.mem_available < LOW_MEMORY_GIB * GIB:
        short.append(f"only {fmt_bytes(res.mem_available)} of memory available")
    for line in short:
        warn(line)
    if short and not confirm(
        "Resources look tight. Continue anyway?", default=False, assume_yes=assume_yes
    ):
        raise InstallerError("Stopped: not enough free resources.")


def _report_tests(tests: TestSummary) -> None:
    if not tests.ran:
        warn("No test summaries (*.sum) were produced: the test suite did NOT run.")
        return
    totals = ", ".join(f"{k}: {v}" for k, v in tests.counts.items())
    info("Test totals — " + totals)
    for suite, counts in tests.per_suite.items():
        bad = counts.get("unexpected failures", 0) + counts.get("unexpected successes", 0)
        if bad:
            warn(
                f"{suite}: {counts.get('unexpected failures', 0)} unexpected failures, "
                f"{counts.get('unexpected successes', 0)} unexpected successes"
            )


def _summary(
    ver: str, prefix: Path, timings: dict[str, float], tests: TestSummary, installer: Path
) -> None:
    out()
    out(S(f"  GCC {ver} is installed and verified.", "bold", "bgreen"))
    out(f"    {S('Compiler', 'bold')}   {prefix}/bin/gcc  (g++, gfortran, …)")
    out(f"    {S('Use it', 'bold')}     export PATH={prefix}/bin:$PATH  (or choose it below)")
    total = sum(timings.values())
    out(
        f"    {S('Time', 'bold')}       {fmt_duration(total)} "
        + S("(" + ", ".join(f"{k} {fmt_duration(v)}" for k, v in timings.items()) + ")", "dim")
    )
    if tests.ran:
        out(
            f"    {S('Tests', 'bold')}      {tests.counts.get('expected passes', 0)} passed, "
            f"{tests.counts.get('unexpected failures', 0)} unexpected failures"
        )
    out(f"    {S('Record', 'bold')}     {prefix}/share/install_gcc/manifest.json")
    out(f"    {S('Logs', 'bold')}       {installer / 'logs'}")
    out(
        f"    {S('gdb', 'bold')}        add 'add-auto-load-safe-path {prefix}' to ~/.gdbinit "
        "to load its libstdc++ pretty-printers"
    )
    for note in shell_environment_notes(prefix, dict(os.environ)):
        warn(note)


def shell_environment_notes(prefix: Path, environ: dict[str, str]) -> list[str]:
    """Settings in the caller's shell that change how the new compiler and its programs behave.

    The build and smoke tests run in a clean environment, so they cannot see these.
    """
    notes: list[str] = []
    if environ.get("LD_LIBRARY_PATH"):
        notes.append(
            "LD_LIBRARY_PATH is set in this shell. The loader searches it before RUNPATH, so an "
            "older libstdc++ there can win ('GLIBCXX_… not found')."
        )
    conda = environ.get("CONDA_PREFIX")
    if conda and (Path(conda) / "lib" / "libstdc++.so.6").exists():
        notes.append(
            f"Conda environment {conda} has its own libstdc++. Python extensions built with this "
            "g++ and loaded into that environment's Python get the libstdc++ it already "
            "loaded, which may be older."
        )
    path = environ.get("PATH", "")
    for tool in ("as", "ld"):
        found = shutil.which(tool, path=path)
        system = f"/usr/bin/{tool}"
        if found and os.path.realpath(found) != os.path.realpath(system):
            notes.append(
                f"Your PATH finds '{tool}' at {found}, not {system}. {prefix}/bin/gcc runs the "
                f"first '{tool}' on PATH, so it would use that one."
            )
    return notes


def _offer_cleanup(args: argparse.Namespace, installer: Path, src: Path, build: Path) -> None:
    kept = f"Build files kept in {installer} (delete gcc-*/ and build/ there to free space)."
    if args.keep_cache:
        info(f"Delete the leftover source and build trees? {S('no (--keep-cache)', 'dim')}")
        info(kept)
        return
    if not interactive():
        info(kept)
        return
    size = _du(build) + _du(src)
    question = f"Delete the leftover source and build trees ({fmt_bytes(size)})? Logs are kept."
    if confirm(question, default=True):
        remove_owned_tree(build, installer, BUILD_MARKER)
        remove_owned_tree(src, installer, SOURCE_MARKER)
        ok("Freed " + fmt_bytes(size))
    else:
        info(kept)


def validate_args(args: argparse.Namespace) -> None:
    if args.gcc_version is not None and args.latest:
        raise UsageError("--gcc-version and --latest contradict each other.")
    if args.gcc_version is not None:
        parse_version(args.gcc_version)
    if args.major is not None and args.major < MIN_MAJOR:
        raise UsageError(f"--major must be {MIN_MAJOR} or newer.")
    parse_fingerprints(args.trust_key)
    build_flags = {
        "--major": args.major is not None,
        "--gcc-version": args.gcc_version is not None,
        "--latest": args.latest,
        "--trust-key": args.trust_key is not None,
        "--languages": args.languages != ",".join(DEFAULT_LANGUAGES),
        "--jobs": args.jobs is not None,
        "--portable": args.portable,
        "--no-pgo": args.no_pgo,
        "--run-tests": args.run_tests,
        "--keep-cache": args.keep_cache,
        "--resume": args.resume,
    }
    if args.clean:
        used = [f for f, on in {**build_flags, "--switch-only": args.switch_only}.items() if on]
        if used:
            raise UsageError(
                "--clean runs on its own; it cannot be combined with " + ", ".join(used) + "."
            )
    if args.switch_only:
        used = [f for f, on in {**build_flags, "--dry-run": args.dry_run}.items() if on]
        if used:
            raise UsageError("--switch-only cannot be combined with " + ", ".join(used) + ".")


def main(argv: Sequence[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    S.configure(
        color_enabled("--no-color" in argv, sys.stdout, dict(os.environ)), _unicode_ok(sys.stdout)
    )
    if sys.version_info < MIN_PYTHON:
        fail(f"Python {'.'.join(map(str, MIN_PYTHON))} or newer is required.")
        return 1
    args = build_parser().parse_args(argv)
    install_signal_handlers()
    try:
        validate_args(args)
        if sys.platform != "linux":
            raise InstallerError("This installer runs on Linux (Debian or Ubuntu) only.")
        if args.clean:
            return clean_build_files(Path(__file__).resolve().parent, dry_run=args.dry_run)
        if args.switch_only:
            check_os(read_os_release())
            if not interactive():
                raise InstallerError("--switch-only needs an interactive terminal.")
            switch_menu([args.prefix_root])
            return 0
        return run_install(args)
    except UsageError as exc:
        fail(str(exc))
        if exc.hint:
            print(f"    {exc.hint}", file=sys.stderr)
        return 2
    except InstallerError as exc:
        fail(str(exc))
        if exc.hint:
            for line in exc.hint.splitlines():
                print(f"    {line}", file=sys.stderr)
        return 1
    except OSError as exc:
        fail(f"{exc.strerror or exc}: {exc.filename or ''}".rstrip(": "))
        return 1
    except KeyboardInterrupt as exc:
        signum = exc.signum if isinstance(exc, Terminated) else signal.SIGINT
        with contextlib.suppress(OSError):  # the terminal may be gone after SIGHUP
            print(file=sys.stderr)
            fail(f"Stopped by {signal.Signals(signum).name}.")
        return 128 + signum


if __name__ == "__main__":
    sys.exit(main())
