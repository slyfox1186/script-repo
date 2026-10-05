#!/usr/bin/env python3
"""
Build and install these CUDA-enabled llama.cpp binaries: llama, llama-cli,
llama-server and install the latest llama-swap release binary alongside them.

Tuned for this host: AMD Ryzen 9 7900X (Zen 4), NVIDIA RTX 4090
(compute capability 8.9), Ubuntu 24.04, system CUDA under /usr/local/cuda.

Run without sudo. The script escalates only for apt and for installing into a
folder the caller cannot write to, and it primes the sudo timestamp up front so
a long compile cannot strand the install behind a password prompt. After the
installed binaries pass their checks, obsolete APT-managed CUDA toolkits and
replaced NVIDIA driver packages are purged, preserving the active versions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import time
import urllib.error
import urllib.request
from collections.abc import Sequence
from dataclasses import dataclass
from types import TracebackType
from typing import Any, ClassVar

REPO_URL = "https://github.com/ggml-org/llama.cpp"
REPO_DIR = "llama.cpp"
LLAMA_SWAP_DIR = "llama-swap"
INSTALL_DIR = "/usr/local/bin"  # default for --install-dir
CUDA_HOME = "/usr/local/cuda"

# Relative to the install folder, so the default /usr/local/bin gets
# /usr/local/lib/llama.cpp. Holds a private copy of the clang OpenMP runtime the
# binaries were linked against, reached only through their RUNPATH. ld.so.conf
# and the loader cache stay untouched, and removing or upgrading that LLVM
# install cannot break the installed binaries.
PRIVATE_LIB_SUBDIR = os.path.join(os.pardir, "lib", "llama.cpp")

# Written into the build tree after each configure. The CMake cache keeps a
# -D value after the flag that set it is dropped, so a kept tree would silently
# reuse a previous run's --cmake-arg values without this record to compare.
CMAKE_ARGS_RECORD = "llama-cpp-installer-cmake-args.json"

SYSTEM_PACKAGES = (
    "build-essential",
    "ccache",  # upstream: "for faster repeated compilation, install ccache"
    "cmake",
    "git",
    "libssl-dev",  # upstream: HTTPS/TLS support (LLAMA_OPENSSL is ON by default)
    "ninja-build",
)

# CMake target -> binary it produces. llama-app is upstream's unified `llama`
# binary, which the README now leads with: `llama serve`, `llama cli`, `llama
# download`, plus bench, batched-bench, quantize, perplexity, fit-params and
# completion (`llama help all`). llama-cli and llama-server remain for callers
# that use those names; all three link the same llama-*-impl libraries, so the
# extra binaries cost little compile time.
BUILD_TARGETS = {
    "llama-app": "llama",
    "llama-cli": "llama-cli",
    "llama-server": "llama-server",
}

# llama-swap is a separate Go project, not a llama.cpp CMake target, so it is
# installed from its GitHub release (linux_<arch> tarball, verified against the
# release's own checksums file) rather than compiled here.
LLAMA_SWAP_REPO = "mostlygeek/llama-swap"
LLAMA_SWAP_BINARY = "llama-swap"
LLAMA_SWAP_ARCHES = {"x86_64": "amd64", "aarch64": "arm64"}
HTTP_TIMEOUT_SECONDS = 60

# Host-compiler warnings turned off for CUDA sources only, per compiler family.
# Clang enables -Wtautological-compare by default, and fattn.cu's
# FATTN_VEC_CASE macro compares GGML_TYPE_F16 with itself by design. nvcc hands
# clang preprocessed host code, so clang cannot tell the comparison came from a
# macro and warns on every expansion.
CUDA_HOST_WARNING_OPT_OUTS = {"Clang": ("-Wno-tautological-compare",)}

# Runtime hardening per the OpenSSF Compiler Options Hardening Guide: the set
# GCC's -fhardened enables, spelled out because clang has no -fhardened. The
# self-built GCC and clang this script prefers lack Ubuntu's built-in defaults,
# and llama-server parses network input. PIE is omitted: both compilers default
# to it. _FORTIFY_SOURCE is undefined first because Ubuntu's GCC predefines it,
# and redefining it warns in every file. _GLIBCXX_ASSERTIONS bounds-checks
# libstdc++ containers in C++ code, at a small CPU-side cost.
HARDENING_COMPILE_FLAGS = (
    "-U_FORTIFY_SOURCE",
    "-D_FORTIFY_SOURCE=3",
    "-D_GLIBCXX_ASSERTIONS",
    "-ftrivial-auto-var-init=zero",
    "-fstack-protector-strong",
    "-fstack-clash-protection",
    "-fcf-protection=full",
)
HARDENING_LINK_FLAGS = ("-Wl,-z,relro", "-Wl,-z,now")

# With both UI options off, scripts/ui-assets.cmake always ends in this
# message(WARNING). It runs as a `cmake -P` build step whose command line is
# fixed upstream, so it is filtered out of ninja's output instead.
UI_NO_ASSETS_WARNING = "UI: no assets available"
NINJA_STATUS_RE = re.compile(r"\[\d+/\d+\] ")

# Directories checked, in order, for build tools before falling back to a PATH
# search, so a local install under /usr/local wins over the distro package.
# Copies inside a conda or venv prefix are skipped so the build does not depend
# on which environment was active.
SYSTEM_TOOL_DIRS = ("/usr/local/bin", "/usr/bin")

TOTAL_STEPS = 9

# Heuristic, not a measured requirement: a single-architecture CUDA build plus
# its ccache growth runs to several GiB, so anything under this is worth a look
# before spending twenty minutes on a compile.
LOW_DISK_WARN_GIB = 10


class Log:
    """Timestamped, labelled console output with step banners."""

    LABEL_WIDTH = 5
    INDENT = " " * 14  # len("[mm:ss] ") + LABEL_WIDTH + 1
    RULE_WIDTH = 78
    COLORS: ClassVar[dict[str, str]] = {
        "RUN": "36",
        "OK": "32",
        "WARN": "33",
        "ERROR": "31",
        "STEP": "1;36",
        "DIM": "2",
        "SUCCESS": "1;37;42",
        "FAILURE": "1;37;41",
    }

    def __init__(self, *, total_steps: int) -> None:
        self.total_steps = total_steps
        self.warnings: list[str] = []
        self._color = sys.stdout.isatty() and "NO_COLOR" not in os.environ
        self._t0 = time.monotonic()
        self._step_index = 0
        self._step_t0 = self._t0
        self._step_title: str | None = None

    @staticmethod
    def format_duration(seconds: float) -> str:
        if seconds < 60:
            return f"{seconds:.1f}s"
        minutes, secs = divmod(round(seconds), 60)
        if minutes < 60:
            return f"{minutes}m{secs:02d}s"
        hours, minutes = divmod(minutes, 60)
        return f"{hours}h{minutes:02d}m{secs:02d}s"

    @property
    def elapsed(self) -> float:
        return time.monotonic() - self._t0

    def _paint(self, text: str, key: str) -> str:
        code = self.COLORS.get(key)
        if not self._color or code is None:
            return text
        return f"\033[{code}m{text}\033[0m"

    def _stamp(self) -> str:
        total = int(self.elapsed)
        return f"[{total // 60:02d}:{total % 60:02d}]"

    def _emit(self, label: str, message: str) -> None:
        painted = self._paint(label.ljust(self.LABEL_WIDTH), label)
        print(f"{self._stamp()} {painted} {message}", flush=True)

    def info(self, message: str) -> None:
        self._emit("INFO", message)

    def ok(self, message: str) -> None:
        self._emit("OK", message)

    def warning(self, message: str) -> None:
        self.warnings.append(message)
        self._emit("WARN", message)

    def error(self, message: str) -> None:
        self._emit("ERROR", message)

    def command(self, display: str) -> None:
        self._emit("RUN", display)

    def table(self, rows: Sequence[tuple[str, str]]) -> None:
        """Key/value lines aligned to the widest key in this group only.

        A fixed column width leaves a short key like "device" stranded far from
        its value, so the width is computed per group instead.
        """
        if not rows:
            return
        width = min(max(len(key) for key, _ in rows), 26)
        for key, value in rows:
            print(f"{self.INDENT}{key.ljust(width)}  {value}", flush=True)

    def bullet(self, text: str) -> None:
        print(f"{self.INDENT}{self._paint(text, 'DIM')}", flush=True)

    def result_banner(
        self, succeeded: bool, segments: Sequence[str], *, verdict: str | None = None
    ) -> None:
        """Final, unmissable verdict. Always the last output of the run.

        Segments are packed onto lines at the " | " separators, so a fact is
        never split across a line break the way "1" / "warning(s)" was.
        """
        if verdict is None:
            verdict = "BUILD SUCCEEDED" if succeeded else "BUILD FAILED"
        key = "SUCCESS" if succeeded else "FAILURE"
        width = self.RULE_WIDTH
        inner = width - 6  # leading "## " and trailing " ##"

        lines = [verdict]
        current = ""
        for segment in segments:
            candidate = segment if not current else f"{current} | {segment}"
            if len(candidate) <= inner:
                current = candidate
                continue
            if current:
                lines.append(current)
            if len(segment) <= inner:
                current = segment
            else:
                wrapped = textwrap.wrap(segment, inner) or [segment[:inner]]
                lines.extend(wrapped[:-1])
                current = wrapped[-1]
        if current:
            lines.append(current)

        print()
        print(self._paint("#" * width, key), flush=True)
        for line in lines:
            print(self._paint(f"## {line.ljust(inner)} ##", key), flush=True)
        print(self._paint("#" * width, key), flush=True)

    def output(self, text: str, *, limit: int = 20) -> None:
        """Show a captured command's output, indented and length-capped."""
        lines = [line.rstrip() for line in text.splitlines() if line.strip()]
        for line in lines[:limit]:
            self.bullet(line)
        if len(lines) > limit:
            hidden = len(lines) - limit
            self.bullet(f"[{plural(hidden, 'further line')} not shown]")

    def step(self, title: str) -> None:
        self.finish_step()
        self._step_index += 1
        self._step_title = title
        self._step_t0 = time.monotonic()
        rule = "=" * self.RULE_WIDTH
        heading = f"[{self._step_index}/{self.total_steps}] {title}"
        print()
        print(self._paint(rule, "STEP"), flush=True)
        print(self._paint(heading, "STEP"), flush=True)
        print(self._paint(rule, "STEP"), flush=True)

    def finish_step(self) -> None:
        if self._step_title is None:
            return
        title, self._step_title = self._step_title, None
        self.ok(f"{title} in {self.format_duration(time.monotonic() - self._step_t0)}")

    def heading(self, title: str) -> None:
        print()
        print(self._paint(f"{title}", "STEP"), flush=True)
        print(self._paint("-" * self.RULE_WIDTH, "DIM"), flush=True)


log = Log(total_steps=TOTAL_STEPS)


@dataclass(frozen=True)
class CompilerFamily:
    """How to find and version-check one compiler family's C/C++ pair."""

    name: str
    cc: str
    cxx: str
    # GCC 7+ needs -dumpfullversion for the full version; clang rejects that
    # flag but answers -dumpversion with its real version.
    version_flags: tuple[str, ...]


GCC = CompilerFamily("GCC", "gcc", "g++", ("-dumpfullversion", "-dumpversion"))
CLANG = CompilerFamily("Clang", "clang", "clang++", ("-dumpversion",))


@dataclass(frozen=True)
class Toolchain:
    """A version-matched C/C++ compiler pair."""

    family: str
    major: int
    cc: str
    cxx: str
    version: str


@dataclass(frozen=True)
class HostCompiler:
    """The toolchain for C/C++ and nvcc's host side, plus nvcc flags it needs."""

    toolchain: Toolchain
    nvcc_flags: tuple[str, ...] = ()


@dataclass(frozen=True)
class Gpu:
    """One NVIDIA device as reported by the driver."""

    index: int
    name: str
    driver: str
    memory_mib: int
    compute_cap: str

    @property
    def arch(self) -> str:
        """Compute capability as a CMAKE_CUDA_ARCHITECTURES entry (8.9 -> 89)."""
        return self.compute_cap.replace(".", "")


def run(
    cmd: Sequence[str] | str,
    *,
    check: bool = True,
    capture: bool = False,
    env: dict[str, str] | None = None,
    timeout: float | None = None,
    quiet: bool = False,
    show_output: bool = True,
    output_limit: int = 20,
    slow_after: float = 5.0,
    report_duration: bool = True,
) -> subprocess.CompletedProcess[Any]:
    """Run a command with logging.

    capture=True collects stdout/stderr and echoes them indented instead of
    letting them interleave with the script's own output. quiet=True suppresses
    the command echo for high-volume plumbing calls whose result is summarised
    by the caller instead.
    """
    display = cmd if isinstance(cmd, str) else shlex.join(cmd)
    if not quiet:
        log.command(display)

    started = time.monotonic()
    result = subprocess.run(
        cmd,
        check=False,
        env=env,
        timeout=timeout,
        capture_output=capture,
        text=True if capture else None,
    )
    duration = time.monotonic() - started

    if capture and show_output and not quiet:
        combined = (result.stdout or "") + (result.stderr or "")
        if combined.strip():
            log.output(combined, limit=output_limit)

    if report_duration and not quiet and duration >= slow_after:
        log.info(f"finished in {log.format_duration(duration)}")

    if check and result.returncode != 0:
        if capture:
            stderr = (result.stderr or "").strip()
            if stderr:
                log.error(stderr.splitlines()[-1])
        raise subprocess.CalledProcessError(
            result.returncode, cmd, result.stdout, result.stderr
        )
    return result


def capture(
    cmd: Sequence[str],
    *,
    env: dict[str, str] | None = None,
    quiet: bool = False,
    show_output: bool = True,
    output_limit: int = 10,
) -> str:
    """Run a command and return stripped stdout."""
    result = run(
        cmd,
        env=env,
        capture=True,
        quiet=quiet,
        show_output=show_output,
        output_limit=output_limit,
    )
    return str(result.stdout or "").strip()


def capture_all(
    cmd: Sequence[str], *, env: dict[str, str] | None = None
) -> tuple[int, str]:
    """Run a command and return (exit code, stdout and stderr together).

    Some llama.cpp binaries print version and device banners on stderr, so a
    stdout-only read would come back empty. Output is not echoed here; callers
    format it, which avoids printing the same block twice.
    """
    result = run(cmd, env=env, capture=True, check=False, show_output=False)
    return result.returncode, ((result.stdout or "") + (result.stderr or "")).strip()


def require_executable(command: str, *, env: dict[str, str] | None = None) -> str:
    """Resolve an executable or raise a clear preflight error."""
    search_path = env.get("PATH") if env is not None else None
    executable = shutil.which(command, path=search_path)
    if executable is None:
        raise RuntimeError(f"Required executable not found: {command}")
    return executable


def read_first_match(path: str, pattern: str) -> str | None:
    """Return the first regex group matched in a file, or None."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                match = re.search(pattern, line)
                if match is not None:
                    return match.group(1).strip()
    except OSError:
        return None
    return None


def free_disk_gib(path: str) -> float | None:
    """Free space at a path in GiB, or None if it cannot be read."""
    try:
        return shutil.disk_usage(path).free / (1024 ** 3)
    except OSError as error:
        log.info(f"could not read free space for {path}: {error}")
        return None


def host_inventory(*, free_gib: float | None) -> dict[str, str]:
    """Collect host facts worth having in a build log."""
    facts: dict[str, str] = {}
    facts["os"] = read_first_match("/etc/os-release", r'^PRETTY_NAME="?([^"\n]+)') or "unknown"
    facts["kernel"] = os.uname().release
    facts["cpu"] = read_first_match("/proc/cpuinfo", r"^model name\s*:\s*(.+)") or "unknown"
    facts["cores"] = f"{os.cpu_count() or '?'} logical"

    mem_kib = read_first_match("/proc/meminfo", r"^MemTotal:\s*(\d+)")
    if mem_kib is not None:
        facts["memory"] = f"{int(mem_kib) / (1024 * 1024):.1f} GiB"

    if free_gib is not None:
        facts["free disk"] = f"{free_gib:.1f} GiB at {os.getcwd()}"

    facts["python"] = sys.version.split()[0]
    return facts


def gpu_inventory(*, env: dict[str, str]) -> list[Gpu]:
    """Query the driver once for everything the build and the log need."""
    nvidia_smi = shutil.which("nvidia-smi", path=env.get("PATH"))
    if nvidia_smi is None:
        log.warning("nvidia-smi not found; cannot inventory GPUs or query compute capability.")
        return []

    result = run(
        [
            nvidia_smi,
            "--query-gpu=index,name,driver_version,memory.total,compute_cap",
            "--format=csv,noheader,nounits",
        ],
        check=False,
        capture=True,
        env=env,
        show_output=False,
    )
    if result.returncode != 0:
        log.warning("nvidia-smi failed; GPU details unavailable.")
        return []

    gpus: list[Gpu] = []
    for line in str(result.stdout or "").splitlines():
        fields = [field.strip() for field in line.split(",")]
        if len(fields) != 5:
            continue
        try:
            gpus.append(
                Gpu(
                    index=int(fields[0]),
                    name=fields[1],
                    driver=fields[2],
                    memory_mib=int(float(fields[3])),
                    compute_cap=fields[4],
                )
            )
        except ValueError:
            log.warning(f"Could not parse nvidia-smi row: {line!r}")
    return gpus


def cuda_architectures(gpus: Sequence[Gpu]) -> tuple[str, str]:
    """Return (CMAKE_CUDA_ARCHITECTURES value, how it was decided).

    Upstream defaults to -arch=native, which asks nvcc to detect the attached
    hardware and silently falls back to a default architecture when detection
    fails ("nvcc warning : Cannot find valid GPU for '-arch=native'"). The docs
    recommend listing compute capabilities explicitly, so the driver's own
    answer is used and "native" is only a fallback.
    """
    architectures: list[str] = []
    for gpu in gpus:
        if gpu.arch and gpu.arch not in architectures:
            architectures.append(gpu.arch)
    if not architectures:
        return "native", "fallback, no compute capability from the driver"
    return ";".join(architectures), "reported by the driver"


def cuda_release(nvcc: str, *, env: dict[str, str]) -> tuple[tuple[int, int], str]:
    """Return ((major, minor), full nvcc version line)."""
    output = capture([nvcc, "--version"], env=env, show_output=False)
    match = re.search(r"\brelease\s+(\d+)\.(\d+)\b", output)
    if match is None:
        raise RuntimeError(f"Could not determine the CUDA version from {nvcc} --version")
    line = next(
        (item.strip() for item in output.splitlines() if "release" in item),
        output.splitlines()[0] if output else "unknown",
    )
    return (int(match.group(1)), int(match.group(2))), line


def _managed_prefixes() -> list[str]:
    """Environment prefixes whose tools should be ignored.

    Deliberately not sys.prefix on its own: under the system interpreter that is
    /usr, which would flag every tool in /usr/bin and /usr/local/bin. Only an
    active venv (prefix differs from base_prefix) or conda's own CONDA_PREFIX
    identifies a real environment.
    """
    prefixes: list[str] = []
    if sys.prefix != sys.base_prefix:
        prefixes.append(sys.prefix)
    conda_prefix = os.environ.get("CONDA_PREFIX")
    if conda_prefix:
        prefixes.append(conda_prefix)
    return [os.path.realpath(prefix) for prefix in prefixes]


def _is_env_managed_tool(path: str) -> bool:
    """True if a tool lives inside a conda/venv prefix rather than the system.

    The build PATH inherits the caller's, and this script is typically launched
    from a conda base env, so a bare PATH search picks up whatever cmake or
    ninja that env ships. That makes the build depend on which env was sourced.
    """
    resolved = os.path.realpath(path)
    for prefix in _managed_prefixes():
        if resolved.startswith(prefix + os.sep):
            return True
    parts = set(resolved.split(os.sep))
    return bool(
        parts & {"conda", "miniconda3", "anaconda3", "miniforge3", "micromamba"}
    ) or ".venv" in parts


def _is_ccache_shim(executable: str) -> bool:
    """True if a compiler path is really a ccache wrapper.

    Ubuntu ships /usr/lib/ccache/gcc-N symlinks pointing at ccache itself. Using
    one as CMAKE_C_COMPILER while GGML_CCACHE=ON wraps it a second time.
    """
    if "ccache" in os.path.normpath(executable).split(os.sep):
        return True
    return os.path.basename(os.path.realpath(executable)) == "ccache"


def tool_version(executable: str, *, env: dict[str, str]) -> tuple[int, ...]:
    """Return a tool's version tuple from its --version output, or ()."""
    result = subprocess.run(
        [executable, "--version"], check=False, capture_output=True, text=True, env=env
    )
    if result.returncode != 0:
        return ()
    match = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", result.stdout)
    if match is None:
        return ()
    return tuple(int(part) for part in match.groups() if part is not None)


def plural(count: int, noun: str, plural_form: str | None = None) -> str:
    """Count with a correctly inflected noun: 1 warning, 2 warnings."""
    if count == 1:
        return f"{count} {noun}"
    return f"{count} {plural_form or noun + 's'}"


def version_text(version: tuple[int, ...]) -> str:
    return ".".join(str(part) for part in version) if version else "unknown"


def require_build_tool(
    command: str, *, env: dict[str, str]
) -> tuple[str, tuple[int, ...]]:
    """Resolve a build tool from SYSTEM_TOOL_DIRS, then PATH, skipping conda/venv copies."""
    candidates: list[str] = []
    for directory in SYSTEM_TOOL_DIRS:
        candidate = os.path.join(directory, command)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            candidates.append(candidate)

    on_path = shutil.which(command, path=env.get("PATH"))
    if on_path is not None and on_path not in candidates:
        candidates.append(on_path)

    if not candidates:
        raise RuntimeError(f"Required executable not found: {command}")

    usable = [item for item in candidates if not _is_env_managed_tool(item)]
    skipped = [item for item in candidates if _is_env_managed_tool(item)]
    for item in skipped:
        log.info(f"ignoring environment-managed {command}: {item}")

    if usable:
        chosen = usable[0]
    else:
        chosen = candidates[0]
        log.warning(f"Only environment-managed copies of {command} found; using {chosen}.")
    return chosen, tool_version(chosen, env=env)


def _compiler_major(
    executable: str, family: CompilerFamily, *, env: dict[str, str]
) -> int:
    output = capture([executable, *family.version_flags], env=env, quiet=True)
    match = re.match(r"(\d+)", output)
    if match is None:
        raise RuntimeError(
            f"Could not determine the {family.name} version from {executable}"
        )
    return int(match.group(1))


def _compiler_version_string(executable: str, *, env: dict[str, str]) -> str:
    output = capture([executable, "--version"], env=env, quiet=True)
    return output.splitlines()[0].strip() if output else "unknown"


def _make_toolchain(
    family: CompilerFamily,
    cc: str,
    cxx: str,
    *,
    expected_major: int | None,
    env: dict[str, str],
    label: str,
) -> Toolchain | None:
    """Validate a compiler pair and return a toolchain, or None with a reason."""
    try:
        cc_major = _compiler_major(cc, family, env=env)
        cxx_major = _compiler_major(cxx, family, env=env)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        log.info(f"skipping {label}: could not query version ({error})")
        return None

    if cc_major != cxx_major:
        log.info(
            f"skipping {label}: {family.cc} reports {cc_major} but "
            f"{family.cxx} reports {cxx_major}"
        )
        return None
    if expected_major is not None and cc_major != expected_major:
        log.info(f"skipping {label}: mislabeled, reports {cc_major}")
        return None

    return Toolchain(
        family=family.name,
        major=cc_major,
        cc=cc,
        cxx=cxx,
        version=_compiler_version_string(cc, env=env),
    )


def _which_compiler(command: str, search_path: str) -> str | None:
    """First executable named command on search_path that is not a ccache shim.

    shutil.which stops at the first hit, and Ubuntu's ccache setup puts
    /usr/lib/ccache ahead of /usr/bin on PATH, so the real compiler behind a
    shim has to be found by continuing down the path.
    """
    for directory_name in search_path.split(os.pathsep):
        candidate = os.path.join(directory_name or os.curdir, command)
        if (
            os.path.isfile(candidate)
            and os.access(candidate, os.X_OK)
            and not _is_ccache_shim(candidate)
        ):
            return candidate
    return None


def installed_toolchains(
    family: CompilerFamily, *, env: dict[str, str]
) -> list[Toolchain]:
    """Find usable toolchains of one family, newest major version first."""
    search_path = env.get("PATH", os.defpath)
    version_pattern = re.compile(rf"^{re.escape(family.cc)}-(\d+)$")
    installed_majors: set[int] = set()

    for directory_name in search_path.split(os.pathsep):
        directory = directory_name or os.curdir
        try:
            entries = os.scandir(directory)
        except OSError:
            continue
        with entries:
            for entry in entries:
                match = version_pattern.match(entry.name)
                if match is not None:
                    installed_majors.add(int(match.group(1)))

    log.info(
        f"versioned {family.name} candidates on PATH: "
        + (
            ", ".join(
                f"{family.cc}-{major}"
                for major in sorted(installed_majors, reverse=True)
            )
            or "none"
        )
    )

    toolchains: list[Toolchain] = []
    for major in sorted(installed_majors, reverse=True):
        cc = _which_compiler(f"{family.cc}-{major}", search_path)
        cxx = _which_compiler(f"{family.cxx}-{major}", search_path)
        if cc is None or cxx is None:
            log.info(f"skipping {family.cc}-{major}: no matching {family.cxx}-{major}")
            continue
        toolchain = _make_toolchain(
            family,
            cc,
            cxx,
            expected_major=major,
            env=env,
            label=f"{family.cc}-{major} ({cc})",
        )
        if toolchain is not None:
            toolchains.append(toolchain)

    # Some installs expose only unversioned executables, which is how a
    # hand-built GCC under /usr/local shows up. It is also the OS default
    # (update-alternatives), which may be newer than any versioned name.
    cc = _which_compiler(family.cc, search_path)
    cxx = _which_compiler(family.cxx, search_path)
    if cc is not None and cxx is not None:
        toolchain = _make_toolchain(
            family,
            cc,
            cxx,
            expected_major=None,
            env=env,
            label=f"unversioned {family.cc} ({cc})",
        )
        if toolchain is not None and all(
            existing.major != toolchain.major for existing in toolchains
        ):
            toolchains.append(toolchain)

    return sorted(toolchains, key=lambda item: item.major, reverse=True)


def nvcc_probe(nvcc: str, flags: Sequence[str], *, env: dict[str, str]) -> tuple[bool, str]:
    """Compile an empty kernel with extra nvcc flags; return (accepted, reason)."""
    with tempfile.TemporaryDirectory(prefix="llama-cpp-nvcc-probe-") as temp_dir:
        source_path = os.path.join(temp_dir, "probe.cu")
        with open(source_path, "w", encoding="utf-8") as source_file:
            source_file.write('extern "C" __global__ void probe() {}\n')
        result = run(
            [nvcc, *flags, "-c", source_path, "-o", os.path.join(temp_dir, "probe.o")],
            check=False,
            capture=True,
            env=env,
            quiet=True,
        )

    if result.returncode == 0:
        return True, ""
    lines = ((result.stderr or "") + (result.stdout or "")).strip().splitlines()
    if not lines:
        return False, "nvcc exited without diagnostics"
    # clang ends with a "1 error generated." summary, so the last line is not
    # the reason.
    return False, next((line for line in lines if "error" in line), lines[-1]).strip()


def nvcc_rejects_architectures(
    nvcc: str, architectures: str, *, env: dict[str, str]
) -> list[str]:
    """Return the architectures in the list that this nvcc will not compile for.

    The host-compiler probe uses nvcc's default architecture, so a toolkit too
    old for the installed GPU passes it and only fails once the real compile
    reaches a CUDA source. One probe per architecture catches that in about a
    second. Reported as a warning rather than a hard stop: the probe uses a
    plain sm_<n> name and newer parts also accept suffixed variants, so a
    rejection here is a strong signal but not proof.
    """
    if architectures == "native":
        return []
    return [
        arch
        for arch in architectures.split(";")
        if arch and not nvcc_probe(nvcc, [f"-arch=sm_{arch}"], env=env)[0]
    ]


def select_gcc_toolchain(nvcc: str, *, env: dict[str, str]) -> HostCompiler:
    """Select the newest installed GCC toolchain accepted by nvcc."""
    toolchains = installed_toolchains(GCC, env=env)
    if not toolchains:
        raise RuntimeError(
            "No usable GCC toolchain was found. Install matching gcc and g++ packages."
        )

    log.info(f"probing {plural(len(toolchains), 'toolchain')} against nvcc")
    rejected: list[str] = []
    for toolchain in toolchains:
        accepted, reason = nvcc_probe(nvcc, ["-ccbin", toolchain.cxx], env=env)
        if accepted:
            log.ok(f"selected {toolchain.version} ({toolchain.cc})")
            return HostCompiler(toolchain)
        log.info(f"GCC {toolchain.major} rejected by nvcc: {reason}")
        rejected.append(f"GCC {toolchain.major}: {reason}")

    details = "\n".join(f"  - {failure}" for failure in rejected)
    raise RuntimeError(
        f"nvcc rejected every installed GCC toolchain:\n{details}\n"
        "Install a host compiler supported by this CUDA toolkit."
    )


def select_clang_toolchain(nvcc: str, *, env: dict[str, str]) -> HostCompiler:
    """Select the newest clang on PATH for C/C++ and nvcc's host side.

    The newest clang is used even when it is newer than this CUDA toolkit
    supports. nvcc enforces its supported clang range only through a version
    check in crt/host_config.h, which -allow-unsupported-compiler lifts.
    That flag is added only when a probe compile shows nvcc rejects the
    compiler without it and accepts it with it. NVIDIA does not support the
    combination, so it is reported as a warning on every run.
    """
    toolchains = installed_toolchains(CLANG, env=env)
    if not toolchains:
        raise RuntimeError(
            "No usable clang toolchain was found on PATH. Install matching clang "
            "and clang++, or run without --clang to build with GCC."
        )
    toolchain = toolchains[0]

    accepted, reason = nvcc_probe(nvcc, ["-ccbin", toolchain.cxx], env=env)
    if accepted:
        log.ok(f"selected {toolchain.version} ({toolchain.cc})")
        return HostCompiler(toolchain)

    override = ("-allow-unsupported-compiler",)
    log.info(f"Clang {toolchain.major} rejected by nvcc: {reason}")
    accepted, override_reason = nvcc_probe(
        nvcc, [*override, "-ccbin", toolchain.cxx], env=env
    )
    if not accepted:
        raise RuntimeError(
            f"nvcc rejected {toolchain.version} ({toolchain.cxx}) as its host "
            f"compiler, even with {override[0]}: {override_reason}"
        )
    log.ok(f"selected {toolchain.version} ({toolchain.cc})")
    log.warning(
        f"Clang {toolchain.major} is newer than this CUDA toolkit supports; nvcc's "
        f"version check is overridden with {override[0]}. NVIDIA warns this may "
        "cause compilation failure or incorrect run time execution."
    )
    return HostCompiler(toolchain, override)


def clang_openmp_runtime(toolchain: Toolchain, *, env: dict[str, str]) -> str | None:
    """Resolved path of the libomp clang links for -fopenmp, or None.

    clang links libomp from its own library directory but does not record that
    directory in the binary, so a clang built from source under /opt produces
    binaries the loader cannot start ("libomp.so: cannot open shared object
    file"). None means this clang ships no libomp, and ggml then builds without
    OpenMP.
    """
    reported = capture(
        [toolchain.cc, "-print-file-name=libomp.so"], env=env, quiet=True
    )
    if not os.path.isabs(reported) or not os.path.isfile(reported):
        return None
    return os.path.realpath(reported)


def elf_dynamic(readelf: str, path: str, tag: str, *, env: dict[str, str]) -> list[str]:
    """Values of one dynamic-section tag (NEEDED, SONAME, RUNPATH) of an ELF file.

    Matched on the "(TAG)" column and the bracketed value, not on readelf's
    descriptive text, which is translated under a non-English locale.
    """
    output = capture([readelf, "-d", path], env=env, quiet=True)
    return re.findall(rf"\({re.escape(tag)}\)[^\[]*\[([^\]]*)\]", output)


def reset_stale_cmake_cache(
    build_dir: str, compilers: dict[str, str], extra_args: Sequence[str]
) -> None:
    """Drop the CMake cache when it was configured with other compilers or --cmake-arg values.

    CMake identifies compilers, nvcc's host compiler included, only on a build
    tree's first configure, so a tree kept with --keep-source would otherwise
    switch between GCC and clang on stale detection results.
    """
    cache = os.path.join(build_dir, "CMakeCache.txt")
    try:
        with open(cache, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except FileNotFoundError:
        return

    cached: dict[str, str] = {}
    for line in lines:
        match = re.match(r"([A-Za-z0-9_]+):[A-Z]+=(.*)$", line)
        if match is not None and match.group(1) in compilers:
            cached[match.group(1)] = match.group(2)
    changed = [name for name, value in compilers.items() if cached.get(name) != value]
    if list(extra_args) != recorded_cmake_args(build_dir):
        changed.append("--cmake-arg values")
    if not changed:
        return
    log.info(
        f"{', '.join(changed)} changed since the last configure; "
        "starting a fresh CMake cache"
    )
    remove_path(cache)
    remove_path(os.path.join(build_dir, "CMakeFiles"))


def recorded_cmake_args(build_dir: str) -> list[str] | None:
    """--cmake-arg values of the build tree's last configure.

    [] when no record exists, which is also how a tree configured before the
    record existed reads. None when the record is unreadable, so the caller
    treats it as changed rather than as empty.
    """
    try:
        with open(os.path.join(build_dir, CMAKE_ARGS_RECORD), encoding="utf-8") as handle:
            recorded = json.load(handle)
    except FileNotFoundError:
        return []
    except (OSError, ValueError):
        return None
    if not isinstance(recorded, list) or not all(isinstance(arg, str) for arg in recorded):
        return None
    return recorded


def record_cmake_args(build_dir: str, extra_args: Sequence[str]) -> None:
    with open(os.path.join(build_dir, CMAKE_ARGS_RECORD), "w", encoding="utf-8") as handle:
        json.dump(list(extra_args), handle)


def ccache_counters(*, env: dict[str, str]) -> dict[str, int]:
    """Snapshot ccache's cumulative counters, or {} if unavailable."""
    ccache = shutil.which("ccache", path=env.get("PATH"))
    if ccache is None:
        return {}
    result = run(
        [ccache, "--print-stats"], check=False, capture=True, env=env, quiet=True
    )
    if result.returncode != 0:
        return {}

    counters: dict[str, int] = {}
    for line in str(result.stdout or "").splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1].lstrip("-").isdigit():
            counters[fields[0]] = int(fields[1])
    return counters


def report_ccache_delta(before: dict[str, int], after: dict[str, int]) -> list[tuple[str, str]]:
    """Report how much of this compile came out of the cache.

    Counter names come from ccache's own --print-stats vocabulary
    (direct_cache_hit, preprocessed_cache_hit, cache_miss). The
    cache_hit_direct spelling belongs to third-party exporters, not to ccache,
    and reading those keys silently yields zero for every build.
    """
    if not before or not after:
        log.info("ccache statistics unavailable; skipping cache accounting")
        return []

    def delta(*keys: str) -> int:
        return sum(after.get(key, 0) - before.get(key, 0) for key in keys)

    hits = delta("direct_cache_hit", "preprocessed_cache_hit")
    misses = delta("cache_miss")
    total = hits + misses
    if total <= 0:
        log.info("ccache recorded no cacheable compilations for this build")
        return []
    return [
        ("ccache hits", f"{hits} of {total} ({hits / total:.0%})"),
        ("ccache misses", str(misses)),
    ]


def remove_path(path: str) -> bool:
    """Delete a file, symlink or directory tree; return whether anything was there."""
    if not os.path.lexists(path):
        return False
    if os.path.islink(path) or not os.path.isdir(path):
        os.remove(path)
    else:
        shutil.rmtree(path)
    return True


def remove_work_dirs(paths: Sequence[str]) -> list[str]:
    """Delete working folders after a successful install; return those left behind.

    Runs only once the binaries are installed and verified, so a folder that
    cannot be deleted is a warning, not a failed install.
    """
    remaining: list[str] = []
    for path in paths:
        location = os.path.abspath(path)
        try:
            removed = remove_path(path)
        except OSError as error:
            log.warning(f"could not remove {location}: {error}; run with --clean to retry")
            remaining.append(path)
            continue
        if removed:
            log.ok(f"removed {location}")
    return remaining


def describe_head(repo_dir: str, *, env: dict[str, str]) -> dict[str, str]:
    """Return identifying details for the checked-out commit."""
    separator = "\x1f"
    fields = capture(
        [
            "git",
            "-C",
            repo_dir,
            "log",
            "-1",
            f"--pretty=format:%H{separator}%h{separator}%s{separator}%an{separator}%aI",
        ],
        env=env,
        quiet=True,
    ).split(separator)
    keys = ("sha", "short_sha", "subject", "author", "authored")
    head = dict(zip(keys, fields, strict=False))
    for key in keys:
        head.setdefault(key, "unknown")
    return head


def sync_repo(
    repo_dir: str, repo_url: str, ref: str, local_branch: str, *, env: dict[str, str]
) -> None:
    """Check out the newest commit of ref, reusing repo_dir when it exists.

    A shallow fetch into an existing checkout downloads only what changed and
    keeps the build tree, so ninja and ccache rebuild only what changed too.
    """
    if not os.path.lexists(repo_dir):
        run(["git", "init", "--quiet", repo_dir], env=env)
    elif not os.path.isdir(os.path.join(repo_dir, ".git")):
        raise RuntimeError(
            f"{os.path.abspath(repo_dir)} exists but is not a git checkout; "
            "remove it or run with --clean"
        )
    else:
        log.info(f"reusing existing checkout at {os.path.abspath(repo_dir)}")
        # Tracked edits only: checkout -B would carry them onto the new commit or
        # refuse, and the ignored build/ tree must not count as a change.
        dirty = capture(
            ["git", "-C", repo_dir, "status", "--porcelain", "--untracked-files=no"],
            env=env,
            quiet=True,
        )
        if dirty:
            raise RuntimeError(
                f"{os.path.abspath(repo_dir)} has local changes to tracked files; "
                "commit or discard them, or run with --clean"
            )

    run(["git", "-C", repo_dir, "fetch", "--depth", "1", repo_url, ref], env=env)
    run(
        ["git", "-C", repo_dir, "checkout", "--quiet", "-B", local_branch, "FETCH_HEAD"],
        env=env,
    )


def upstream_build_number(
    repo_dir: str, repo_url: str, *, env: dict[str, str]
) -> tuple[int | None, int | None]:
    """Return (build number for HEAD, newest b tag upstream has).

    llama.cpp derives LLAMA_BUILD_NUMBER from `git rev-list --count HEAD`, which
    a --depth 1 clone reports as 1. Upstream tags master commits as b<NUM> via
    its release workflow, so ask the remote which tag points at this exact
    commit and pass the real number through instead of shipping a binary that
    claims "build 1".
    """
    head = capture(["git", "-C", repo_dir, "rev-parse", "HEAD"], env=env, quiet=True)

    # Thousands of refs, so the listing is summarised rather than echoed.
    log.info("querying upstream b<NUM> tags for a build number")
    output = capture(
        ["git", "ls-remote", "--tags", repo_url, "refs/tags/b*"], env=env, quiet=True
    )

    matched: int | None = None
    newest: int | None = None
    tag_count = 0
    for line in output.splitlines():
        parts = line.split("\t")
        if len(parts) != 2:
            continue
        sha = parts[0].strip()
        # Annotated tags also list a dereferenced "<ref>^{}" line.
        ref = parts[1].strip().removesuffix("^{}")
        match = re.fullmatch(r"refs/tags/b(\d+)", ref)
        if match is None:
            continue
        tag_count += 1
        number = int(match.group(1))
        if newest is None or number > newest:
            newest = number
        if sha == head:
            matched = number

    log.info(
        f"scanned {tag_count} build tags"
        + (f", newest is b{newest}" if newest is not None else "")
    )
    return matched, newest


def missing_packages(packages: Sequence[str]) -> list[str]:
    """The packages dpkg does not record as installed, in the order given."""
    # dpkg-query exits 1 when any name is unknown but still reports the rest.
    result = run(
        ["dpkg-query", "-W", "-f=${Package} ${db:Status-Abbrev}\n", *packages],
        check=False,
        capture=True,
        quiet=True,
    )
    installed = {
        fields[0]
        for fields in (line.split() for line in str(result.stdout or "").splitlines())
        if len(fields) >= 2 and fields[1] == "ii"
    }
    return [package for package in packages if package not in installed]


def obsolete_cuda_packages(
    inventory: str, cuda_version: tuple[int, int], driver_branch: int
) -> list[str]:
    """Select older toolkit packages and driver packages with installed replacements.

    Keep architecture-qualified names for APT. Unversioned driver packages use
    their Debian version to establish the replacement branch. CUDA packages
    must be NVIDIA-maintained; Ubuntu's versioned driver packages also qualify.
    """
    records = [line.split("\t") for line in inventory.splitlines()]
    if any(len(record) != 5 for record in records):
        raise RuntimeError("Unexpected dpkg inventory; refusing CUDA cleanup")
    installed = [record for record in records if record[3] == "installed"]
    active_toolkit = f"cuda-toolkit-{cuda_version[0]}-{cuda_version[1]}"
    if not any(record[0].split(":")[0] == active_toolkit for record in installed):
        raise RuntimeError("Active CUDA toolkit is not APT-managed; refusing package cleanup")

    def driver_family(package: str) -> tuple[str, str]:
        name, _, arch = package.partition(":")
        name = re.sub(r"-\d+(?:-server)?(?:-open)?$", "", name)
        name = name.removesuffix("-open")
        if name in {"nvidia", "cuda-drivers"}:
            name = "nvidia-driver"
        return name, arch

    replacements = set()
    for package, version, _, _, _ in installed:
        if package.startswith(("nvidia-", "libnvidia-", "xserver-xorg-video-nvidia")):
            branch = re.match(r"(?:\d+:)?(\d+)\.", version)
            if branch and int(branch[1]) == driver_branch:
                replacements.add(driver_family(package))

    targets: set[str] = set()
    nsight_needed: set[str] = set()
    for package, _, maintainer, status, dependencies in records:
        if status not in {"installed", "config-files"}:
            continue
        name = package.split(":")[0]
        if re.fullmatch(r"cuda-nsight-(?:compute|systems)-\d+-\d+", name):
            series = tuple(map(int, name.rsplit("-", 2)[1:]))
            if series >= cuda_version and status == "installed":
                nsight_needed.update(re.findall(r"nsight-(?:compute|systems)-[\d.]+", dependencies))
        cuda_series = re.search(r"-(\d+)-(\d+)(?:-config-common|-local)?$", name)
        if (
            cuda_series
            and tuple(map(int, cuda_series.groups())) < cuda_version
            and re.search(r"@nvidia\.com>\s*$", maintainer)
            and name.startswith(("cuda-", "cccl-", "libcu", "libnv", "libnpp-", "gds-tools-"))
        ):
            targets.add(package)
        old_driver = re.search(r"-(\d+)(?:-server)?(?:-open)?$", name)
        if (
            name.startswith(("nvidia-", "libnvidia-", "xserver-xorg-video-nvidia"))
            and old_driver
            and int(old_driver[1]) < driver_branch
            and driver_family(package) in replacements
        ):
            targets.add(package)

    # Retire versioned Nsight tools only when the retained toolkit has a newer
    # counterpart. APT's preview below protects any other installed consumer.
    for package, _, _, status, _ in records:
        name = package.split(":")[0]
        tool = re.fullmatch(r"(nsight-(?:compute|systems))-([\d.]+)", name)
        if tool and status in {"installed", "config-files"}:
            nsight_version = tuple(map(int, tool[2].split(".")))
            if any(
                needed.startswith(tool[1] + "-")
                and tuple(map(int, needed.removeprefix(tool[1] + "-").split("."))) > nsight_version
                for needed in nsight_needed
            ):
                targets.add(package)
    return sorted(targets)


def cuda_cleanup_inventory() -> str:
    """Read package ownership/state without stripping empty dependency fields."""
    result = run(
        [
            "dpkg-query", "-W",
            "-f=${binary:Package}\t${Version}\t${Maintainer}\t${db:Status-Status}\t${Depends}\n",
        ],
        capture=True, quiet=True,
    )
    return str(result.stdout or "")


def remove_unused_cuda_keys() -> None:
    """Retire only unowned local-installer keys no active APT source references."""
    source_paths = ["/etc/apt/sources.list"]
    source_dir = "/etc/apt/sources.list.d"
    source_paths.extend(
        os.path.join(source_dir, name)
        for name in os.listdir(source_dir)
        if name.endswith((".list", ".sources"))
    )
    source_text = ""
    for path in source_paths:
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as source:
                source_text += source.read() + "\n"
    for name in os.listdir("/usr/share/keyrings"):
        if not re.fullmatch(r"cuda-[0-9A-Fa-f]{8}-keyring\.gpg", name) or name in source_text:
            continue
        path = os.path.join("/usr/share/keyrings", name)
        owner = run(["dpkg-query", "-S", path], capture=True, check=False, quiet=True)
        if owner.returncode == 1:
            ensure_sudo(reason="removing an unused CUDA local-repository key")
            run(["sudo", "rm", "--", path])
        elif owner.returncode != 0:
            raise RuntimeError(f"Could not verify package ownership of {path}; key retained")


def cleanup_old_cuda(
    cuda_version: tuple[int, int], nvcc: str, *, env: dict[str, str]
) -> str:
    """Purge obsolete system packages only after the installed GPU build works.

    APT owns file removal and alternatives updates. Never autoremove, delete
    arbitrary toolkit trees, or accept a preview affecting unrelated packages.
    Package-manager failures remain fatal and leave the build tree for retry.
    """
    if cuda_release(nvcc, env=env)[0] != cuda_version:
        raise RuntimeError("Active CUDA changed during the build; refusing cleanup")
    driver_versions = capture(
        ["nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader"], quiet=True
    ).splitlines()
    if not driver_versions or any(not re.fullmatch(r"\d+(?:\.\d+)+", value) for value in driver_versions):
        raise RuntimeError("Could not verify the active NVIDIA driver; refusing cleanup")
    driver_branches = {int(value.split(".")[0]) for value in driver_versions}
    if len(driver_branches) != 1:
        raise RuntimeError("GPU driver branches differ; refusing cleanup")
    inventory = cuda_cleanup_inventory()
    targets = obsolete_cuda_packages(inventory, cuda_version, driver_branches.pop())
    if not targets:
        remove_unused_cuda_keys()
        log.ok("no obsolete CUDA or replaced NVIDIA driver packages")
        return "nothing obsolete"

    cleanup_env = {**os.environ, "LC_ALL": "C"}
    native_arch = capture(["dpkg", "--print-architecture"], quiet=True)
    preview = capture(["apt-get", "-s", "purge", *targets], env=cleanup_env, quiet=True)
    planned = {
        package.removesuffix(f":{native_arch}")
        for package in re.findall(r"^(?:Purg|Remv) (\S+)", preview, re.MULTILINE)
    }
    if planned != {package.removesuffix(f":{native_arch}") for package in targets} or re.search(r"^Inst ", preview, re.MULTILINE):
        raise RuntimeError("APT would change packages outside the cleanup list; nothing purged")
    if cuda_cleanup_inventory() != inventory:
        raise RuntimeError("Package inventory changed during cleanup planning; nothing purged")
    log.info(f"purging obsolete CUDA/driver packages: {' '.join(targets)}")
    ensure_sudo(reason="removing obsolete CUDA and NVIDIA driver packages")
    # Retain driver meta packages that older CUDA releases installed as automatic
    # dependencies, so a later user-initiated autoremove cannot retire the driver.
    automatic = capture(["apt-mark", "showauto"], quiet=True).splitlines()
    driver_roots = [name for name in automatic if name in {"nvidia-open", "cuda-drivers"}]
    if driver_roots:
        run(["sudo", "apt-mark", "manual", *driver_roots])
    run(["sudo", "apt-get", "-y", "-o", "DPkg::Lock::Timeout=60", "purge", *targets])
    run(["sudo", "apt-get", "check"])
    if cuda_release(nvcc, env=env)[0] != cuda_version:
        raise RuntimeError("CUDA toolkit verification failed after cleanup")
    run(["nvidia-smi"], capture=True, output_limit=4)
    remaining = cuda_cleanup_inventory()
    leftovers = {line.split("\t")[0] for line in remaining.splitlines() if "\tinstalled\t" in line or "\tconfig-files\t" in line}
    if leftovers.intersection(targets):
        raise RuntimeError("Some obsolete CUDA/driver packages remain after cleanup")
    remove_unused_cuda_keys()
    log.ok(f"purged {plural(len(targets), 'obsolete CUDA/driver package')}")
    return f"purged {len(targets)} obsolete packages"


def nearest_existing(path: str) -> str:
    """The path itself if it exists, otherwise its closest existing ancestor."""
    while not os.path.lexists(path):
        parent = os.path.dirname(path)
        if parent == path:
            break
        path = parent
    return path


def needs_sudo(directory: str) -> bool:
    """Whether creating directory if missing and writing into it needs root."""
    return not os.access(nearest_existing(directory), os.W_OK | os.X_OK)


def check_install_dir(install_dir: str) -> None:
    """Reject an install folder this run could not use, before anything is built."""
    existing = nearest_existing(install_dir)
    if not os.path.isdir(existing):
        raise RuntimeError(
            f"--install-dir {install_dir} cannot be used: {existing} exists and is not a folder"
        )
    resolved = os.path.realpath(install_dir)
    for work_dir in (REPO_DIR, LLAMA_SWAP_DIR):
        work = os.path.realpath(work_dir)
        if os.path.commonpath([resolved, work]) == work:
            raise RuntimeError(
                f"--install-dir {install_dir} is inside the {work} working folder, "
                "which is deleted after a successful install and by --clean"
            )


def ensure_dir(path: str, *, sudo: bool) -> None:
    """Create a folder, with sudo if needed; an existing one is left as it is."""
    if os.path.isdir(path):
        return
    run([*(["sudo"] if sudo else []), "install", "-d", "-m", "0755", path])


def ensure_sudo(*, reason: str) -> None:
    """Prime the sudo timestamp so later escalation does not block on a prompt."""
    cached = subprocess.run(
        ["sudo", "-n", "true"], check=False, capture_output=True
    ).returncode == 0
    if cached:
        log.info(f"sudo credentials already cached ({reason})")
        return
    log.info(f"sudo password required now so it is not requested later ({reason})")
    run(["sudo", "-v"])


def install_atomically(source: str, target: str, *, sudo: bool) -> None:
    """Install a binary via staged file plus rename.

    A plain `install` opens the destination for writing, which fails with
    ETXTBSY if that binary is currently running (llama-server as a service, for
    instance). Staging next to the target and renaming over it swaps the
    directory entry instead, leaving any running process on the old inode.
    """
    directory, name = os.path.split(target)
    staged = os.path.join(directory, f".{name}.new")
    prefix = ["sudo"] if sudo else []
    run([*prefix, "install", "-m", "0755", source, staged])
    try:
        run([*prefix, "mv", "-f", staged, target])
    except subprocess.CalledProcessError:
        # Do not leave a half-installed dotfile sitting in the install dir.
        run([*prefix, "rm", "-f", staged], check=False, quiet=True)
        raise


def http_get(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "llama-cpp-installer"})
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return response.read()
    except urllib.error.URLError as error:
        raise RuntimeError(f"download failed: {url}: {error}") from error


def fetch_llama_swap(cache_dir: str) -> tuple[str, str]:
    """Download and verify the latest llama-swap release; return (binary path, tag).

    A tarball already in cache_dir that matches the release checksum is reused
    instead of downloaded again.
    """
    machine = platform.machine()
    arch = LLAMA_SWAP_ARCHES.get(machine)
    if arch is None:
        raise RuntimeError(f"no llama-swap release build for this CPU: {machine}")

    release_url = f"https://api.github.com/repos/{LLAMA_SWAP_REPO}/releases/latest"
    log.command(f"GET {release_url}")
    release = json.loads(http_get(release_url))
    tag = str(release["tag_name"])
    assets = {asset["name"]: asset["browser_download_url"] for asset in release["assets"]}

    number = tag.removeprefix("v")
    tarball_name = f"llama-swap_{number}_linux_{arch}.tar.gz"
    checksums_name = f"llama-swap_{number}_checksums.txt"
    for name in (tarball_name, checksums_name):
        if name not in assets:
            raise RuntimeError(f"llama-swap {tag} has no release asset named {name}")

    expected: str | None = None
    for line in http_get(assets[checksums_name]).decode().splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1] == tarball_name:
            expected = fields[0].lower()
    if expected is None:
        raise RuntimeError(f"{checksums_name} lists no checksum for {tarball_name}")

    os.makedirs(cache_dir, exist_ok=True)
    tarball = os.path.join(cache_dir, tarball_name)
    if os.path.isfile(tarball) and _sha256(tarball) == expected:
        log.info(f"reusing verified {tarball}")
    else:
        log.command(f"GET {assets[tarball_name]}")
        data = http_get(assets[tarball_name])
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            raise RuntimeError(
                f"{tarball_name} checksum mismatch: expected {expected}, got {actual}"
            )
        with open(tarball, "wb") as handle:
            handle.write(data)
        log.ok(f"downloaded {tarball_name} ({len(data) / (1024 ** 2):.1f} MiB), sha256 verified")

    for name in os.listdir(cache_dir):
        if name.startswith("llama-swap_") and name.endswith(".tar.gz") and name != tarball_name:
            os.remove(os.path.join(cache_dir, name))

    binary = os.path.join(cache_dir, LLAMA_SWAP_BINARY)
    with tarfile.open(tarball, "r:gz") as archive:
        member = archive.getmember(LLAMA_SWAP_BINARY)
        source = archive.extractfile(member) if member.isfile() else None
        if source is None:
            raise RuntimeError(f"{tarball_name} has no regular file named {LLAMA_SWAP_BINARY}")
        with source, open(binary, "wb") as handle:
            shutil.copyfileobj(source, handle)
    os.chmod(binary, 0o755)
    return binary, tag


def _sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def run_ninja(cmd: Sequence[str], *, env: dict[str, str], hide_ui_warning: bool) -> None:
    """Run ninja, dropping upstream's expected no-UI warning block from its output.

    Piping ninja's output to filter it turns off ninja's own one-line progress
    display, so on a terminal the progress line is redrawn here the same way.
    """
    log.command(shlex.join(cmd))
    interactive = sys.stdout.isatty()
    child_env = {**env, "NINJA_STATUS": "[%f/%t] "}
    if interactive:
        # ninja strips compiler colors when its stdout is not a terminal.
        child_env["CLICOLOR_FORCE"] = "1"

    progress_shown = False

    def emit(line: str) -> None:
        nonlocal progress_shown
        if interactive and NINJA_STATUS_RE.match(line):
            width = shutil.get_terminal_size().columns
            if len(line) >= width:
                line = line[: max(width - 4, 0)] + "..."
            sys.stdout.write(f"\r{line}\x1b[K")
            sys.stdout.flush()
            progress_shown = True
            return
        if progress_shown:
            sys.stdout.write("\n")
            progress_shown = False
        print(line, flush=True)

    # Lines of a "CMake Warning at .../ui-assets.cmake" block, held until its
    # closing blank line shows which warning it is.
    block: list[str] | None = None
    with subprocess.Popen(
        cmd,
        env=child_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    ) as process:
        assert process.stdout is not None
        try:
            for raw in process.stdout:
                line = raw.rstrip("\n")
                if block is None and line.startswith("CMake Warning at ") and "ui-assets.cmake" in line:
                    block = [line]
                elif block is not None:
                    block.append(line)
                    if not line.strip():
                        if not (hide_ui_warning and any(UI_NO_ASSETS_WARNING in item for item in block)):
                            for item in block:
                                emit(item)
                        block = None
                else:
                    emit(line)
            for item in block or []:
                emit(item)
        finally:
            if progress_shown:
                sys.stdout.write("\n")
                sys.stdout.flush()
    if process.returncode != 0:
        raise subprocess.CalledProcessError(process.returncode, list(cmd))


def parse_devices(text: str) -> list[str]:
    """Extract unique device lines from `--list-devices` output.

    Upstream currently prints each device twice; the duplicates are collapsed
    here so the log states the real count.
    """
    devices: list[str] = []
    for line in text.splitlines():
        match = re.match(r"\s*([A-Za-z]+\d*):\s*(.+)", line.strip())
        if match is None:
            continue
        entry = f"{match.group(1)}: {match.group(2).strip()}"
        if entry not in devices:
            devices.append(entry)
    return devices


# ─── Help screen ─────────────────────────────────────────────────────────────
# The same block is pasted into each standalone script in this folder; keep the copies identical.

_HELP_MAX_WIDTH = 100
_HELP_FLAG_MAX_WIDTH = 28
_HELP_DEFAULT_RE = re.compile(r'\s*(\(default: [^)]*\))$')
_HELP_STYLES = {
    'heading': '\033[1m\033[96m',
    'flag': '\033[92m',
    'value': '\033[93m',
    'bold': '\033[1m',
    'dim': '\033[2m',
}


def _metavar(action: argparse.Action) -> str:
    """Display name for an action's value; argparse also allows a tuple metavar."""
    if isinstance(action.metavar, tuple):
        return ' '.join(action.metavar)
    return action.metavar or action.dest.upper()


def _help_color_enabled() -> bool:
    """Color help on a terminal unless NO_COLOR, TERM=dumb or --no-color opts out; FORCE_COLOR opts in."""
    if os.environ.get('NO_COLOR') or '--no-color' in sys.argv:
        return False
    if os.environ.get('FORCE_COLOR'):
        return True
    return sys.stdout.isatty() and os.environ.get('TERM') != 'dumb'


class HelpParser(argparse.ArgumentParser):
    """ArgumentParser with a short usage line and a grouped, colored help screen.

    Sections are the parser's argument groups, in order. ``examples`` holds
    ``(what it does, arguments after the program name)`` pairs. Automatic -h is
    off, so add ``-h/--help`` with ``action='help'`` to the group it belongs in.
    """

    def __init__(self, *, title: str, version: str = '',
                 examples: Sequence[tuple[str, str]] = (), **kwargs: Any) -> None:
        super().__init__(add_help=False, **kwargs)
        self.help_title = title
        self.help_version = version
        self.help_examples = examples

    def _positional_usage(self) -> list[str]:
        parts = []
        for action in self._actions:
            if action.option_strings or action.help == argparse.SUPPRESS:
                continue
            name = _metavar(action)
            forms: dict[object, str] = {'?': f'[{name}]', '*': f'[{name} ...]', '+': f'{name} ...'}
            parts.append(forms.get(action.nargs, name))
        return parts

    def format_usage(self) -> str:
        return f"usage: {' '.join([self.prog, '[OPTIONS]', *self._positional_usage()])}\n"

    def error(self, message: str):
        self.print_usage(sys.stderr)
        self.exit(2, f"{self.prog}: error: {message}\nRun '{self.prog} --help' to see all options.\n")

    def format_help(self) -> str:
        use_color = _help_color_enabled()

        def paint(text: str, style: str) -> str:
            return f"{_HELP_STYLES[style]}{text}\033[0m" if use_color and text else text

        def help_text(action) -> str:
            text = action.help or ''
            return text % {**vars(action), 'prog': self.prog} if '%' in text else text

        width = min(shutil.get_terminal_size((_HELP_MAX_WIDTH, 24)).columns, _HELP_MAX_WIDTH)
        # Action groups are argparse's only record of section membership and order.
        sections = [
            (group.title or '', [a for a in group._group_actions
                           if a.option_strings and a.help != argparse.SUPPRESS])
            for group in self._action_groups
        ]
        sections = [(title, actions) for title, actions in sections if actions]
        all_options = [a for _, actions in sections for a in actions]

        def split_flags(action) -> tuple[str, str, str]:
            shorts = [o for o in action.option_strings if not o.startswith('--')]
            longs = [o for o in action.option_strings if o.startswith('--')]
            short = ', '.join(shorts) + (', ' if shorts and longs else '')
            metavar = ''
            if action.nargs != 0:
                metavar = _metavar(action)
                if action.nargs in ('+', '*'):
                    metavar += '...'
                elif action.nargs == '?':
                    metavar = f'[{metavar}]'
            return short, ', '.join(longs), metavar

        short_col = max((len(split_flags(a)[0]) for a in all_options), default=0)

        def flag_cell(action) -> tuple[str, str]:
            short, long, metavar = split_flags(action)
            plain = short.rjust(short_col) + long + (f" {metavar}" if metavar else '')
            colored = (' ' * (short_col - len(short)) + paint(short, 'flag')
                       + paint(long, 'flag')
                       + (f" {paint(metavar, 'value')}" if metavar else ''))
            return plain, colored

        flag_width = min(max((len(flag_cell(a)[0]) for a in all_options), default=0),
                         _HELP_FLAG_MAX_WIDTH)
        help_col = 2 + flag_width + 3
        # Too narrow for two columns: put each description under its flags.
        stacked = width - help_col < 24
        text_col = short_col + 4 if stacked else help_col
        text_width = max(width - text_col, 20)

        def row(plain: str, colored: str, text: str) -> list[str]:
            match = _HELP_DEFAULT_RE.search(text)
            body = text[:match.start()] if match else text
            lines = textwrap.wrap(body, text_width, break_on_hyphens=False) or ['']
            if match:
                default = match.group(1)
                if len(lines[-1]) + 1 + len(default) <= text_width:
                    lines[-1] = f"{lines[-1]} {paint(default, 'dim')}".lstrip()
                else:
                    lines.append(paint(default, 'dim'))
            indent = ' ' * text_col
            if stacked or len(plain) > flag_width:
                return [f"  {colored}"] + [indent + line for line in lines]
            first = f"  {colored}{' ' * (help_col - 2 - len(plain))}{lines[0]}"
            return [first] + [indent + line for line in lines[1:]]

        def heading(title: str) -> list[str]:
            return ['', paint(title.upper(), 'heading')]

        out = [paint(self.help_title, 'heading')
               + (paint(f" v{self.help_version}", 'dim') if self.help_version else '')]
        if self.description:
            out += textwrap.wrap(self.description, width, break_on_hyphens=False)

        out += heading("Usage")
        out.append(' '.join([f"  {paint(self.prog, 'bold')}", paint('[OPTIONS]', 'flag'),
                             *(paint(p, 'value') for p in self._positional_usage())]))
        for action in self._actions:
            if not action.option_strings and action.help != argparse.SUPPRESS:
                name = _metavar(action)
                out.append('')
                out += row(name, paint(name, 'value'), help_text(action))

        for title, actions in sections:
            out += heading(title)
            for action in actions:
                out += row(*flag_cell(action), help_text(action))

        if self.help_examples:
            out += heading("Examples")
            for what, cmd_args in self.help_examples:
                out.append(f"  {paint('# ' + what, 'dim')}")
                out.append(f"  {paint('$', 'dim')} {paint(self.prog, 'bold')} {cmd_args}".rstrip())
        out.append('')
        return '\n'.join(out)


def upstream_ref(value: str) -> str:
    """argparse type for --ref-tag: a tag name or a full commit SHA."""
    ref = value.strip().removeprefix("refs/tags/")
    if re.fullmatch(r"[0-9a-fA-F]{40}", ref):
        return ref.lower()
    # Upstream tags are b<NUM>, at most six characters for years to come.
    if re.fullmatch(r"[0-9a-fA-F]{7,39}", ref):
        raise argparse.ArgumentTypeError(
            f"{value!r} looks like an abbreviated commit SHA; GitHub only serves "
            "full 40-character SHAs, which 'git rev-parse <sha>' prints"
        )
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", ref) or ".." in ref:
        raise argparse.ArgumentTypeError(f"{value!r} is not a valid tag name")
    return ref


def cmake_arg(value: str) -> str:
    """argparse type for --cmake-arg: KEY=VALUE becomes -DKEY=VALUE, '-...' passes as is."""
    if value.startswith("-"):
        return value
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(?::[A-Za-z]+)?=.*", value, flags=re.DOTALL):
        return f"-D{value}"
    raise argparse.ArgumentTypeError(
        f"expected KEY=VALUE or a CMake flag starting with '-', got {value!r}"
    )


def install_dir_path(value: str) -> str:
    """argparse type for --install-dir: an absolute path, taken from the current directory."""
    if not value.strip():
        raise argparse.ArgumentTypeError("the folder name is empty")
    # expanduser covers --install-dir=~/x, which the shell leaves unexpanded.
    return os.path.abspath(os.path.expanduser(value))


# (what it does, arguments after the program name)
HELP_EXAMPLES = [
    ("Build and install the newest llama.cpp", ""),
    ("Keep the source and build tree for a faster rebuild next time", "-k"),
    ("Rebuild from the kept tree, skipping apt", "-k --skip-apt"),
    ("Roll back to a known-good upstream release", "-r b11399"),
    ("Try a pull request without replacing the installed binaries", "--beta 12345 -i ~/llama-pr"),
    (
        "Compile every flash-attention K/V cache type pair (much slower build)",
        "--cmake-arg GGML_CUDA_FA_QUANTS=all",
    ),
    ("Use 8 compile jobs to keep the machine responsive", "-j 8"),
    ("Include llama-server's built-in web UI", "--web-ui"),
    ("Compile with the newest clang on PATH instead of GCC", "--clang"),
    ("Delete the llama.cpp and llama-swap folders, then exit", "--clean"),
]


def parse_args() -> argparse.Namespace:
    names = list(BUILD_TARGETS.values())
    parser = HelpParser(
        title="llama.cpp CUDA Installer",
        description=(
            f"Build llama.cpp with CUDA support and install {', '.join(names[:-1])} "
            f"and {names[-1]}, plus the latest llama-swap release, to {INSTALL_DIR} "
            "or the --install-dir folder. The newest upstream commit is built unless "
            f"--ref-tag or --beta picks another. The {REPO_DIR} and {LLAMA_SWAP_DIR} "
            "working folders are made in the current directory and deleted after a "
            "successful install unless --keep-source is given. Run as a normal "
            "user; sudo is asked for only when apt runs or you cannot write to the "
            "install folder. After successful GPU verification, older APT-managed "
            "CUDA toolkits and replaced NVIDIA driver packages are purged with sudo."
        ),
        examples=HELP_EXAMPLES,
    )

    source = parser.add_argument_group("Source").add_mutually_exclusive_group()
    source.add_argument(
        "-r",
        "--ref-tag",
        type=upstream_ref,
        metavar="REF",
        help=(
            "Build upstream release tag REF (such as b11399) or a full 40-character "
            "commit SHA instead of the newest commit, to pin or roll back to a "
            f"known-good build. Tags are listed at {REPO_URL}/tags. Cannot be "
            "combined with --beta"
        ),
    )
    source.add_argument(
        "--beta",
        type=int,
        metavar="PR",
        help=(
            "Build GitHub pull request number PR instead of the newest upstream "
            "commit; its binaries report build number 1. Add --install-dir to try "
            "it without replacing your installed binaries. Cannot be combined with "
            "--ref-tag"
        ),
    )

    build = parser.add_argument_group("Build")
    build.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=os.cpu_count() or 4,
        metavar="N",
        help=(
            "Parallel compile jobs, one per CPU thread by default. Lower it to keep "
            "the machine responsive or if the compile runs out of memory "
            "(default: %(default)s)"
        ),
    )
    build.add_argument(
        "--clang",
        action="store_true",
        help=(
            "Compile with the newest clang on PATH, versioned (clang-N) or the "
            "OS default (clang), instead of the newest GCC nvcc accepts. It is "
            "also nvcc's host compiler, with nvcc's version check overridden if "
            "it is newer than the CUDA toolkit supports. If the binaries link "
            "clang's own OpenMP runtime, a private copy goes to "
            f"{PRIVATE_LIB_SUBDIR} next to the install folder "
            f"({os.path.normpath(os.path.join(INSTALL_DIR, PRIVATE_LIB_SUBDIR))} "
            "by default), found through their RUNPATH; the system loader "
            "configuration is not changed"
        ),
    )
    build.add_argument(
        "--web-ui",
        action="store_true",
        help=(
            "Embed llama-server's built-in web UI. Off by default: its files download "
            "at build time, and a bad download fails the whole build"
        ),
    )
    build.add_argument(
        "--cmake-arg",
        type=cmake_arg,
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help=(
            "Add a CMake configure setting; repeat for more. KEY=VALUE is passed "
            "as -DKEY=VALUE after this script's own settings, so it overrides "
            "them. Other CMake flags pass through as given but must be joined "
            "with '=', as in --cmake-arg=-Wno-dev. A kept build tree is "
            "reconfigured from scratch when these change"
        ),
    )
    build.add_argument(
        "--skip-apt",
        action="store_true",
        help=(
            f"Skip apt update and apt install of the build packages "
            f"({', '.join(SYSTEM_PACKAGES)}). Saves time on rebuilds; stops before "
            "building if any of them is not installed"
        ),
    )

    install = parser.add_argument_group("Install and clean up")
    install.add_argument(
        "-i",
        "--install-dir",
        type=install_dir_path,
        default=INSTALL_DIR,
        metavar="DIR",
        help=(
            "Folder to install the llama.cpp binaries and llama-swap to, created "
            "if missing; a relative path is taken from the current directory. sudo "
            "is used only if you cannot write to it. A folder outside your PATH "
            "suits a side-by-side test build: run its binaries by full path "
            "(default: %(default)s)"
        ),
    )
    install.add_argument(
        "-k",
        "--keep-source",
        action="store_true",
        help=(
            f"Keep the {REPO_DIR} and {LLAMA_SWAP_DIR} folders after a successful "
            "install, so the next run updates the checkout in place and rebuilds "
            "only what changed"
        ),
    )
    install.add_argument(
        "--clean",
        action="store_true",
        help=(
            f"Delete the {REPO_DIR} and {LLAMA_SWAP_DIR} folders if they exist, "
            "then exit. Installed binaries are left alone"
        ),
    )

    general = parser.add_argument_group("General")
    general.add_argument("-h", "--help", action="help", help="Show this help and exit")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if os.geteuid() == 0:
        raise RuntimeError("Run this script as a normal user, not with sudo or as root.")
    if args.jobs < 1:
        raise RuntimeError(f"--jobs must be at least 1, got {args.jobs}")

    if args.clean:
        removed = [path for path in (REPO_DIR, LLAMA_SWAP_DIR) if remove_path(path)]
        for path in removed:
            log.ok(f"removed {os.path.abspath(path)}")
        log.result_banner(
            True,
            [f"removed {', '.join(removed)}" if removed else "nothing to remove"],
            verdict="CLEAN SUCCEEDED",
        )
        return

    # Build environment only. The installed binaries are verified under the
    # caller's own environment, which is what they will run under.
    env = os.environ.copy()
    env["PATH"] = os.pathsep.join(
        entry for entry in (f"{CUDA_HOME}/bin", env.get("PATH", "")) if entry
    )

    # ---------------------------------------------------------------- step 1
    log.step("Preflight: host, CUDA toolkit and GPU inventory")

    free_gib = free_disk_gib(os.getcwd())
    log.table(list(host_inventory(free_gib=free_gib).items()))

    if free_gib is not None and free_gib < LOW_DISK_WARN_GIB:
        log.warning(
            f"Only {free_gib:.1f} GiB free here; a CUDA build plus ccache growth "
            "can need several GiB."
        )

    nvcc = require_executable(f"{CUDA_HOME}/bin/nvcc", env=env)
    cuda_version, nvcc_line = cuda_release(nvcc, env=env)
    gpus = gpu_inventory(env=env)

    hardware_rows = [
        ("nvcc", nvcc),
        ("CUDA toolkit", f"{cuda_version[0]}.{cuda_version[1]} ({nvcc_line})"),
    ]
    hardware_rows += [
        (
            f"GPU {gpu.index}",
            (
                f"{gpu.name}, compute {gpu.compute_cap}, "
                f"{gpu.memory_mib / 1024:.1f} GiB VRAM, driver {gpu.driver}"
            ),
        )
        for gpu in gpus
    ]
    log.table(hardware_rows)
    if not gpus:
        log.warning("No GPU inventory available; the build will fall back to -arch=native.")

    install_dir = args.install_dir
    check_install_dir(install_dir)
    private_lib_dir = os.path.normpath(os.path.join(install_dir, PRIVATE_LIB_SUBDIR))
    install_sudo = needs_sudo(install_dir)
    # Only known to be needed after the link, so ask up front when it might be.
    lib_sudo = args.clang and needs_sudo(private_lib_dir)
    log.table(
        [
            ("install folder", f"{install_dir} ({'sudo' if install_sudo else 'writable'})"),
            *(
                [("OpenMP copy", f"{private_lib_dir}, if the binaries link clang's libomp")]
                if args.clang
                else []
            ),
        ]
    )

    sudo_uses = [] if args.skip_apt else ["apt"]
    if install_sudo or lib_sudo:
        sudo_uses.append(f"installing to {install_dir}")
    if sudo_uses:
        ensure_sudo(reason=" and ".join(sudo_uses))
    else:
        log.info("sudo is not needed for this run")

    # ---------------------------------------------------------------- step 2
    log.step("System packages")

    if args.skip_apt:
        missing = missing_packages(SYSTEM_PACKAGES)
        if missing:
            raise RuntimeError(
                f"--skip-apt was given but {plural(len(missing), 'build package')} "
                f"{'is' if len(missing) == 1 else 'are'} not installed: "
                f"{' '.join(missing)}. Run once without --skip-apt."
            )
        log.ok(
            f"apt skipped; all {plural(len(SYSTEM_PACKAGES), 'package')} installed: "
            f"{' '.join(SYSTEM_PACKAGES)}"
        )
    else:
        # Retries and per-connection timeouts so a syncing mirror cannot hang the
        # run. `update` is non-fatal because apt falls back to cached indexes; the
        # `install` below is the real gate and errors if a package is missing.
        apt_opts = [
            "-o", "Acquire::Retries=3",
            "-o", "Acquire::http::Timeout=30",
            "-o", "Acquire::https::Timeout=30",
        ]
        try:
            update = run(["sudo", "apt", *apt_opts, "update"], check=False, timeout=600)
            if update.returncode != 0:
                log.warning("apt update returned non-zero; using cached package indexes.")
        except subprocess.TimeoutExpired:
            log.warning("apt update exceeded its 10 minute timeout; using cached indexes.")

        log.info(
            f"ensuring {plural(len(SYSTEM_PACKAGES), 'package')}: "
            f"{' '.join(SYSTEM_PACKAGES)}"
        )
        run(["sudo", "apt", *apt_opts, "install", "-y", *SYSTEM_PACKAGES])

    # ---------------------------------------------------------------- step 3
    omp_runtime: str | None = None
    if args.clang:
        log.step("Clang toolchain selection for C/C++ and nvcc")
        host = select_clang_toolchain(nvcc, env=env)
        omp_runtime = clang_openmp_runtime(host.toolchain, env=env)
        if omp_runtime is None:
            log.info("this clang ships no libomp; ggml will build without OpenMP")
        else:
            log.info(
                f"OpenMP runtime {omp_runtime}; binaries get RUNPATH "
                f"{private_lib_dir} for a private copy"
            )
    else:
        log.step("GCC toolchain selection for nvcc")
        host = select_gcc_toolchain(nvcc, env=env)
    toolchain = host.toolchain

    # ---------------------------------------------------------------- step 4
    log.step("Build tools and target architecture")

    cmake_bin, cmake_version = require_build_tool("cmake", env=env)
    ninja_bin, ninja_version = require_build_tool("ninja", env=env)
    tool_rows = [
        ("cmake", f"{cmake_bin} ({version_text(cmake_version)})"),
        ("ninja", f"{ninja_bin} ({version_text(ninja_version)})"),
    ]

    cuda_archs, arch_source = cuda_architectures(gpus)
    rejected_archs = nvcc_rejects_architectures(nvcc, cuda_archs, env=env)
    if rejected_archs:
        log.warning(
            f"nvcc {cuda_version[0]}.{cuda_version[1]} rejected "
            f"sm_{', sm_'.join(rejected_archs)} in a probe compile. The CUDA "
            "toolkit may be too old for this GPU, in which case the build will "
            "fail once it reaches a CUDA source."
        )
    elif cuda_archs != "native":
        log.info(f"nvcc accepts sm_{cuda_archs.replace(';', ', sm_')}")

    log.table(
        tool_rows
        + [
            ("CUDA architectures", f"{cuda_archs} ({arch_source})"),
            ("compile jobs", str(args.jobs)),
            ("web UI", "embedded" if args.web_ui else "disabled"),
        ]
    )

    # ---------------------------------------------------------------- step 5
    log.step("Source checkout")

    if args.beta is not None:
        log.info(f"beta mode: building from PR #{args.beta}")
        branch = f"pr-{args.beta}"
        sync_repo(REPO_DIR, REPO_URL, f"refs/pull/{args.beta}/head", branch, env=env)
    elif args.ref_tag is not None and re.fullmatch(r"[0-9a-f]{40}", args.ref_tag):
        log.info(f"pinned mode: building commit {args.ref_tag}")
        branch = f"commit-{args.ref_tag[:12]}"
        sync_repo(REPO_DIR, REPO_URL, args.ref_tag, branch, env=env)
    elif args.ref_tag is not None:
        log.info(f"pinned mode: building tag {args.ref_tag}")
        branch = f"tag-{args.ref_tag}"
        sync_repo(REPO_DIR, REPO_URL, f"refs/tags/{args.ref_tag}", branch, env=env)
    else:
        branch = "master"
        sync_repo(REPO_DIR, REPO_URL, "HEAD", branch, env=env)

    head = describe_head(REPO_DIR, env=env)
    log.table(
        [
            ("branch", branch),
            ("commit", f"{head['short_sha']} ({head['sha']})"),
            ("subject", head["subject"]),
            ("authored", f"{head['authored']} by {head['author']}"),
        ]
    )

    build_number: int | None = None
    newest_tag: int | None = None
    if args.beta is None:
        build_number, newest_tag = upstream_build_number(REPO_DIR, REPO_URL, env=env)
    if build_number is not None:
        log.ok(f"upstream build number for this commit: b{build_number}")
    elif args.beta is not None:
        log.info("PR branches carry no b tag; the build number will report as 1")
    else:
        # Routine when building master HEAD: upstream tags lag the push. Why a
        # tag is absent is not observable from here (not yet created, release
        # skipped, CI outcome), so state only the effect and stay at info so
        # the warning count keeps meaning something.
        newest = f"b{newest_tag}" if newest_tag is not None else "none found"
        log.info(
            f"commit is not covered by an upstream b tag (newest is {newest}), "
            "so the build number reports as 1"
        )

    # ---------------------------------------------------------------- step 6
    log.step("llama-swap release")
    swap_binary, swap_tag = fetch_llama_swap(LLAMA_SWAP_DIR)
    log.ok(f"llama-swap {swap_tag} ready at {swap_binary}")

    # ---------------------------------------------------------------- step 7
    log.step("CMake configure")

    # GGML_NATIVE=ON supplies -march=native for the CPU backend, which covers
    # everything Zen 4 offers here (AVX-512 with VNNI and BF16). It is passed
    # even though it is usually the default because upstream turns the default
    # OFF whenever SOURCE_DATE_EPOCH is set in the environment.
    #
    # BUILD_SHARED_LIBS=OFF links libllama and libggml into each binary, so
    # copying the binaries alone into the install folder is a complete install.
    #
    # Both UI variables must be set together: scripts/ui-assets.cmake gates
    # provisioning on BUILD_UI and HF_ENABLED independently, and HF_ENABLED
    # comes from LLAMA_USE_PREBUILT_UI, which defaults ON. Passing only
    # LLAMA_BUILD_UI=OFF still runs the Hugging Face download.
    #
    # Left at upstream defaults on purpose, so they follow upstream changes:
    #   GGML_CUDA_FA, GGML_CUDA_GRAPHS, GGML_OPENMP, GGML_CCACHE,
    #   GGML_CPU_REPACK .......... all ON.
    #   GGML_CUDA_FA_QUANTS ...... f16, bf16, q8_0 and q4_0 K/V pairs. "all"
    #       compiles every combination and takes far longer.
    #   GGML_LTO ................. OFF. It adds substantial link time and
    #       nearly all compute runs in CUDA kernels.
    #   GGML_CUDA_COMPRESSION_MODE "size".
    #
    # LLAMA_ALL_WARNINGS=OFF drops upstream's developer lint set (-Wall -Wextra
    # -Wpedantic -Wmissing-noreturn ...; it also drives GGML_ALL_WARNINGS),
    # which buries real diagnostics under thousands of style hints such as
    # noreturn suggestions on nvcc's host stubs for device-only functions.
    # Compiler-default warnings and every error still print.
    #
    # CMAKE_CUDA_FLAGS and CMAKE_BUILD_RPATH are cached, so they are passed on
    # every run, empty when unused, or a kept build tree would carry a previous
    # --clang run's nvcc override and RUNPATH into a GCC build.
    #
    # Hardening flags reach C and C++ through CMAKE_<LANG>_FLAGS, which ggml's
    # own add_compile_options() flags add to rather than replace, and nvcc's
    # host compiler through -Xcompiler. Linker flags go only to executables,
    # since every library is static; nvcc splits -Xcompiler values on commas,
    # so -Wl,... could not go through it anyway.
    #
    # --cmake-arg values go last: CMake keeps the last -D for a variable, so
    # they override any setting above.
    ui_enabled = "ON" if args.web_ui else "OFF"
    # nvcc flags beyond hardening, shown in the summary.
    cuda_extra_flags = [
        *host.nvcc_flags,
        *(
            f"-Xcompiler={flag}"
            for flag in CUDA_HOST_WARNING_OPT_OUTS.get(toolchain.family, ())
        ),
    ]
    cuda_flags = [
        *cuda_extra_flags,
        *(f"-Xcompiler={flag}" for flag in HARDENING_COMPILE_FLAGS),
    ]
    hardening = " ".join(HARDENING_COMPILE_FLAGS)
    configure_args = [
        f"-DLLAMA_BUILD_UI={ui_enabled}",
        f"-DLLAMA_USE_PREBUILT_UI={ui_enabled}",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DLLAMA_ALL_WARNINGS=OFF",
        f"-DCMAKE_C_COMPILER={toolchain.cc}",
        f"-DCMAKE_CXX_COMPILER={toolchain.cxx}",
        f"-DCMAKE_CUDA_COMPILER={nvcc}",
        f"-DCMAKE_CUDA_HOST_COMPILER={toolchain.cxx}",
        f"-DCMAKE_C_FLAGS={hardening}",
        f"-DCMAKE_CXX_FLAGS={hardening}",
        f"-DCMAKE_CUDA_FLAGS={' '.join(cuda_flags)}",
        f"-DCMAKE_EXE_LINKER_FLAGS={' '.join(HARDENING_LINK_FLAGS)}",
        f"-DCMAKE_BUILD_RPATH={private_lib_dir if omp_runtime else ''}",
        f"-DCMAKE_MAKE_PROGRAM={ninja_bin}",
        f"-DCUDAToolkit_ROOT={CUDA_HOME}",
        f"-DCMAKE_CUDA_ARCHITECTURES={cuda_archs}",
        "-DGGML_CUDA=ON",
        # Single GPU here, so the NVIDIA collectives library is dead weight.
        "-DGGML_CUDA_NCCL=OFF",
        "-DGGML_NATIVE=ON",
    ]
    if build_number is not None:
        # llama.cpp only derives this itself when the caller has not set it.
        configure_args.append(f"-DLLAMA_BUILD_NUMBER={build_number}")
    if args.cmake_arg:
        log.table([("extra CMake args", shlex.join(args.cmake_arg))])
    configure_args += args.cmake_arg

    build_dir = f"{REPO_DIR}/build"
    reset_stale_cmake_cache(
        build_dir,
        {
            "CMAKE_C_COMPILER": toolchain.cc,
            "CMAKE_CXX_COMPILER": toolchain.cxx,
            "CMAKE_CUDA_HOST_COMPILER": toolchain.cxx,
        },
        args.cmake_arg,
    )
    run(
        [cmake_bin, REPO_DIR, "-B", build_dir, *configure_args, "-G", "Ninja"],
        env=env,
        report_duration=False,
    )
    record_cmake_args(build_dir, args.cmake_arg)

    # ---------------------------------------------------------------- step 8
    log.step(f"Compile: {', '.join(BUILD_TARGETS)}")

    ccache_before = ccache_counters(env=env)
    compile_started = time.monotonic()
    run_ninja(
        [ninja_bin, "-C", build_dir, f"-j{args.jobs}", *BUILD_TARGETS],
        env=env,
        hide_ui_warning=not args.web_ui,
    )
    compile_seconds = time.monotonic() - compile_started

    log.table(report_ccache_delta(ccache_before, ccache_counters(env=env)))
    if not args.web_ui:
        log.info(
            "web UI not embedded (--web-ui adds it); upstream's expected "
            f"'{UI_NO_ASSETS_WARNING}' build warning was hidden"
        )

    # ---------------------------------------------------------------- step 9
    log.step(f"Install to {install_dir} and verify")

    bin_dir = os.path.join(build_dir, "bin")
    built = {name: os.path.join(bin_dir, name) for name in BUILD_TARGETS.values()}
    missing = [path for path in built.values() if not os.path.isfile(path)]
    if missing:
        listing = "\n".join(f"  - {path}" for path in missing)
        raise RuntimeError(f"Cannot install missing build outputs:\n{listing}")

    log.info(f"build outputs in {bin_dir}")
    log.table(
        [
            (name, f"{os.path.getsize(path) / (1024 ** 2):.1f} MiB")
            for name, path in built.items()
        ]
    )

    # Ship the OpenMP runtime only if the link actually used it: CMake builds
    # without OpenMP when it cannot find a working one.
    # (source, destination) of the private OpenMP runtime copy.
    runtime_copy: tuple[str, str] | None = None
    if omp_runtime is not None:
        readelf = require_executable("readelf", env=env)
        sonames = elf_dynamic(readelf, omp_runtime, "SONAME", env=env)
        # The loader looks the runtime up by soname, so the copy is named by it.
        soname = sonames[0] if sonames else os.path.basename(omp_runtime)
        users = [
            name
            for name, path in built.items()
            if soname in elf_dynamic(readelf, path, "NEEDED", env=env)
        ]
        if not users:
            log.info(f"no binary links {soname}; OpenMP was not used")
        else:
            for name in users:
                runpath = elf_dynamic(readelf, built[name], "RUNPATH", env=env)
                if private_lib_dir not in ":".join(runpath).split(":"):
                    raise RuntimeError(
                        f"{name} links {soname} but its RUNPATH {runpath} lacks "
                        f"{private_lib_dir}; it could not load the runtime"
                    )
            runtime_copy = (omp_runtime, os.path.join(private_lib_dir, soname))

    if install_sudo or (runtime_copy is not None and lib_sudo):
        ensure_sudo(reason="installing binaries")
    installed: list[str] = []
    # Before the binaries, so none is ever installed without its runtime.
    if runtime_copy is not None:
        ensure_dir(private_lib_dir, sudo=lib_sudo)
        install_atomically(*runtime_copy, sudo=lib_sudo)
        log.ok(f"OpenMP runtime installed to {runtime_copy[1]}")
    ensure_dir(install_dir, sudo=install_sudo)
    for name, source_path in [*built.items(), (LLAMA_SWAP_BINARY, swap_binary)]:
        destination = os.path.join(install_dir, name)
        install_atomically(source_path, destination, sudo=install_sudo)
        installed.append(destination)

    # Run every installed binary under the caller's environment (env=None), not
    # the build env, so a runtime library the loader cannot find fails here
    # rather than on first use.
    versions: dict[str, str] = {}
    for path in installed:
        returncode, output = capture_all([path, "--version"])
        if returncode != 0:
            last = output.splitlines()[-1] if output else "no output"
            raise RuntimeError(f"{path} --version exited {returncode}: {last}")
        name = os.path.basename(path)
        versions[name] = re.sub(r"^version:\s*", "", output.splitlines()[0].strip())
        log.ok(f"{name}: {versions[name]}")
    log.ok(f"installed {len(installed)} binaries")

    # Shadowing check: a copy earlier in the interactive PATH would win over the
    # one just installed, which is easy to miss and confusing to debug. A
    # custom folder off PATH is the usual side-by-side test install, so that
    # case is a note rather than a warning per binary.
    interactive_path = os.environ.get("PATH", "")
    path_dirs = {os.path.realpath(entry) for entry in interactive_path.split(os.pathsep) if entry}
    if os.path.realpath(install_dir) in path_dirs:
        for name in [*BUILD_TARGETS.values(), LLAMA_SWAP_BINARY]:
            resolved = shutil.which(name, path=interactive_path)
            expected = os.path.join(install_dir, name)
            if resolved is not None and os.path.realpath(resolved) != os.path.realpath(expected):
                log.warning(f"{name} resolves to {resolved}, shadowing {expected}.")
    elif install_dir == INSTALL_DIR:
        log.warning(f"{install_dir} is not on your interactive PATH.")
    else:
        log.info(
            f"{install_dir} is not on your PATH; run the binaries by full path, "
            f"such as {os.path.join(install_dir, 'llama')}"
        )

    device_status, device_output = capture_all(
        [os.path.join(install_dir, "llama-cli"), "--list-devices"]
    )
    devices = parse_devices(device_output)
    cuda_devices = [device for device in devices if device.startswith("CUDA")]
    log.table([("device", device) for device in devices])
    if device_status == 0 and cuda_devices:
        log.ok(
            f"{plural(len(cuda_devices), 'CUDA device')} visible to the installed binary"
        )
    else:
        raise RuntimeError(
            "Installed llama-cli failed CUDA device verification; old CUDA/driver packages retained"
        )

    cuda_cleanup = cleanup_old_cuda(cuda_version, nvcc, env=env)
    # Verify the installed applications again without build-only environment
    # overrides, before discarding the source/build tree.
    if cuda_cleanup != "nothing obsolete":
        for path in installed:
            run([path, "--version"], capture=True, output_limit=2)
        status, output = capture_all([os.path.join(install_dir, "llama-cli"), "--list-devices"])
        if status != 0 or not any(device.startswith("CUDA") for device in parse_devices(output)):
            raise RuntimeError("Installed CUDA build failed verification after package cleanup")

    if args.keep_source:
        sources = f"kept in {REPO_DIR}, {LLAMA_SWAP_DIR}"
        log.info(
            f"sources kept in {os.path.abspath(REPO_DIR)} and "
            f"{os.path.abspath(LLAMA_SWAP_DIR)}; --clean removes them"
        )
    else:
        remaining = remove_work_dirs((REPO_DIR, LLAMA_SWAP_DIR))
        sources = f"could not remove {', '.join(remaining)}" if remaining else "removed"

    log.finish_step()

    # ------------------------------------------------------------------ recap
    log.heading("Build summary")
    summary = {
        "commit": f"{head['short_sha']} on {branch}",
        "build number": (
            f"b{build_number}" if build_number is not None else "1 (untagged commit)"
        ),
        "version": versions[BUILD_TARGETS["llama-app"]],
        "llama-swap": versions[LLAMA_SWAP_BINARY],
        "compiler": f"{toolchain.version} + CUDA {cuda_version[0]}.{cuda_version[1]}",
        "nvcc flags": " ".join(cuda_extra_flags) or "none",
        "hardening": " ".join((*HARDENING_COMPILE_FLAGS, *HARDENING_LINK_FLAGS)),
        "OpenMP runtime": (
            f"{runtime_copy[1]} (private copy of {runtime_copy[0]})"
            if runtime_copy is not None
            else "not linked" if args.clang
            else "system"
        ),
        "cmake / ninja": f"{version_text(cmake_version)} / {version_text(ninja_version)}",
        "CUDA arch": cuda_archs,
        "web UI": "embedded" if args.web_ui else "disabled",
        "extra CMake args": shlex.join(args.cmake_arg) or "none",
        "installed": ", ".join(installed),
        "sources": sources,
        "CUDA/driver cleanup": cuda_cleanup,
        "compile time": log.format_duration(compile_seconds),
        "total time": log.format_duration(log.elapsed),
    }
    log.table(list(summary.items()))

    if log.warnings:
        log.heading(f"{plural(len(log.warnings), 'warning')} raised")
        for index, warning in enumerate(log.warnings, start=1):
            log.bullet(f"{index}. {warning}")

    log.result_banner(
        True,
        [
            f"{plural(len(installed), 'binary', 'binaries')} in {install_dir}",
            head["short_sha"],
            log.format_duration(log.elapsed),
            plural(len(log.warnings), "warning") if log.warnings else "no warnings",
        ],
    )


def fail(message: str) -> None:
    """Log a fatal error, point at the leftovers, and stamp the verdict."""
    log.error(message)
    if os.path.isdir(REPO_DIR):
        log.info(f"source and build tree left in place at {os.path.abspath(REPO_DIR)}")
    # Multi-line reasons stay in the ERROR entry above; the banner takes the
    # first line so the verdict stays scannable.
    headline = message.strip().splitlines()[0] if message.strip() else "unknown error"
    log.result_banner(
        False, [headline, f"failed after {log.format_duration(log.elapsed)}"]
    )


def _verdict_excepthook(
    exc_type: type[BaseException],
    exc: BaseException,
    tb: TracebackType | None,
) -> None:
    """Stamp the verdict on an exception no handler below anticipated.

    Nothing is caught here, so no handler is broadened to satisfy the guarantee
    that the banner is the final output. Python's own hook prints the traceback
    to stderr first, then the banner goes to stdout and the interpreter still
    exits non-zero on its own.
    """
    sys.__excepthook__(exc_type, exc, tb)
    fail(f"unhandled {exc_type.__name__}: {exc}")


if __name__ == "__main__":
    # Anything the handlers below do not name propagates normally and is
    # reported by the hook. SystemExit and the handled types never reach it.
    sys.excepthook = _verdict_excepthook
    try:
        main()
    except KeyboardInterrupt:
        fail("interrupted by user")
        sys.exit(130)
    except subprocess.CalledProcessError as failure:
        command = (
            failure.cmd if isinstance(failure.cmd, str) else shlex.join(failure.cmd)
        )
        fail(f"exit code {failure.returncode} from: {command}")
        sys.exit(failure.returncode or 1)
    except (RuntimeError, OSError, subprocess.SubprocessError) as failure:
        fail(str(failure) or failure.__class__.__name__)
        sys.exit(1)
