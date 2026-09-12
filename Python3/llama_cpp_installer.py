#!/usr/bin/env python3
"""Build and install CUDA-enabled llama.cpp binaries.

Tuned for this host: AMD Ryzen 9 7900X (Zen 4), NVIDIA RTX 4090 (compute
capability 8.9), Ubuntu 24.04, system CUDA under /usr/local/cuda.

Run without sudo. The script escalates only for apt and for installing the
finished binaries, and it primes the sudo timestamp up front so a long compile
cannot strand the install behind a password prompt.
"""

from __future__ import annotations

import argparse
import os
import glob
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
from dataclasses import dataclass
from types import TracebackType
from typing import Any, Sequence

REPO_URL = "https://github.com/ggml-org/llama.cpp"
REPO_DIR = "llama.cpp"
INSTALL_DIR = "/usr/local/bin"

SYSTEM_PACKAGES = (
    "build-essential",
    "ccache",  # upstream: "for faster repeated compilation, install ccache"
    "cmake",
    "git",
    "libssl-dev",  # upstream: HTTPS/TLS support (LLAMA_OPENSSL is ON by default)
    "ninja-build",
)

BUILD_TARGETS = ("llama-cli", "llama-server")

# Directories checked for build tools before falling back to a PATH search.
# Copies inside a conda or venv prefix are skipped so the build does not depend
# on which environment was active. See require_build_tool for why cmake also
# picks the newest candidate rather than the first one found.
SYSTEM_TOOL_DIRS = ("/usr/local/bin", "/usr/bin")

# K/V type combinations to compile FlashAttention kernels for. Upstream replaced
# the old GGML_CUDA_FA_ALL_QUANTS boolean with this list; ALL_QUANTS is now just
# a deprecated alias for "all", which compiles every combination and takes far
# longer. This list covers the configurations usable on a 24 GB card.
# Combinations not compiled fall back to f16-f16 with a runtime warning.
CUDA_FA_QUANTS = "f16-f16;bf16-bf16;q8_0-q8_0;q4_0-q4_0"

TOTAL_STEPS = 8

# Heuristic, not a measured requirement: a single-architecture CUDA build plus
# its ccache growth runs to several GiB, so anything under this is worth a look
# before spending twenty minutes on a compile.
LOW_DISK_WARN_GIB = 10


class Log:
    """Timestamped, labelled console output with step banners."""

    LABEL_WIDTH = 5
    INDENT = " " * 14  # len("[mm:ss] ") + LABEL_WIDTH + 1
    RULE_WIDTH = 78
    COLORS = {
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
        minutes, secs = divmod(int(round(seconds)), 60)
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

    def warn(self, message: str) -> None:
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
        rows = [row for row in rows if row is not None]
        if not rows:
            return
        width = min(max(len(key) for key, _ in rows), 26)
        for key, value in rows:
            print(f"{self.INDENT}{key.ljust(width)}  {value}", flush=True)

    def bullet(self, text: str) -> None:
        print(f"{self.INDENT}{self._paint(text, 'DIM')}", flush=True)

    def result_banner(self, succeeded: bool, segments: Sequence[str]) -> None:
        """Final, unmissable verdict. Always the last output of the run.

        Segments are packed onto lines at the " | " separators, so a fact is
        never split across a line break the way "1" / "warning(s)" was.
        """
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
class GccToolchain:
    """A version-matched GCC compiler pair accepted for CUDA host compilation."""

    major: int
    cc: str
    cxx: str
    version: str


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
    cmd: Sequence[str], *, env: dict[str, str] | None = None, quiet: bool = False
) -> str:
    """Run a command and return stdout and stderr together.

    Some llama.cpp binaries print version and device banners on stderr, so a
    stdout-only read would come back empty. Output is not echoed here; callers
    format it, which avoids printing the same block twice.
    """
    result = run(
        cmd, env=env, capture=True, check=False, quiet=quiet, show_output=False
    )
    return ((result.stdout or "") + (result.stderr or "")).strip()


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
        log.warn("nvidia-smi not found; cannot inventory GPUs or query compute capability.")
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
        log.warn("nvidia-smi failed; GPU details unavailable.")
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
            log.warn(f"Could not parse nvidia-smi row: {line!r}")
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
    command: str, *, env: dict[str, str], prefer_newest: bool = False
) -> tuple[str, tuple[int, ...]]:
    """Resolve a build tool, skipping conda/venv copies.

    With prefer_newest, the highest-versioned candidate wins rather than the
    first on PATH. That matters for cmake here: CUDA 13 relocated the cuda/,
    cub/ and thrust/ headers into the CCCL 3.0 layout, and only a CMake new
    enough to add the toolkit's include/cccl directory to FindCUDAToolkit hands
    that path to host-compiled translation units. nvcc finds those headers on
    its own, so an older CMake builds fine today while silently dropping an
    include path any host-only translation unit would need.
    """
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

    if not usable:
        log.warn(
            f"Only environment-managed copies of {command} found; using {candidates[0]}."
        )
        chosen = candidates[0]
        return chosen, tool_version(chosen, env=env)

    if not prefer_newest or len(usable) == 1:
        chosen = usable[0]
        return chosen, tool_version(chosen, env=env)

    versions = {item: tool_version(item, env=env) for item in usable}
    log.info(
        f"{command} candidates (newest wins): "
        + ", ".join(
            f"{item} ({version_text(version)})" for item, version in versions.items()
        )
    )
    chosen = max(usable, key=lambda item: versions[item])
    if versions[chosen] == ():
        log.warn(f"Could not determine a version for any {command}; using {chosen}.")
    return chosen, versions[chosen]


def _gcc_major(executable: str, *, env: dict[str, str]) -> int:
    output = capture(
        [executable, "-dumpfullversion", "-dumpversion"], env=env, quiet=True
    )
    match = re.match(r"(\d+)", output)
    if match is None:
        raise RuntimeError(f"Could not determine the GCC version from {executable}")
    return int(match.group(1))


def _gcc_version_string(executable: str, *, env: dict[str, str]) -> str:
    output = capture([executable, "--version"], env=env, quiet=True)
    return output.splitlines()[0].strip() if output else "unknown"


def _make_toolchain(
    cc: str, cxx: str, *, expected_major: int | None, env: dict[str, str], label: str
) -> GccToolchain | None:
    """Validate a compiler pair and return a toolchain, or None with a reason."""
    if _is_ccache_shim(cc) or _is_ccache_shim(cxx):
        log.info(f"skipping {label}: resolves to a ccache shim")
        return None

    try:
        cc_major = _gcc_major(cc, env=env)
        cxx_major = _gcc_major(cxx, env=env)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        log.info(f"skipping {label}: could not query version ({error})")
        return None

    if cc_major != cxx_major:
        log.info(
            f"skipping {label}: gcc reports {cc_major} but g++ reports {cxx_major}"
        )
        return None
    if expected_major is not None and cc_major != expected_major:
        log.info(f"skipping {label}: mislabeled, reports {cc_major}")
        return None

    return GccToolchain(
        major=cc_major, cc=cc, cxx=cxx, version=_gcc_version_string(cc, env=env)
    )


def installed_gcc_toolchains(*, env: dict[str, str]) -> list[GccToolchain]:
    """Find usable GCC toolchains, newest major version first."""
    search_path = env.get("PATH", os.defpath)
    version_pattern = re.compile(r"^gcc-(\d+)$")
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
        "versioned GCC candidates on PATH: "
        + (", ".join(f"gcc-{major}" for major in sorted(installed_majors, reverse=True)) or "none")
    )

    toolchains: list[GccToolchain] = []
    for major in sorted(installed_majors, reverse=True):
        cc = shutil.which(f"gcc-{major}", path=search_path)
        cxx = shutil.which(f"g++-{major}", path=search_path)
        if cc is None or cxx is None:
            log.info(f"skipping gcc-{major}: no matching g++-{major}")
            continue
        toolchain = _make_toolchain(
            cc, cxx, expected_major=major, env=env, label=f"gcc-{major} ({cc})"
        )
        if toolchain is not None:
            toolchains.append(toolchain)

    # Some installs expose only unversioned executables, which is how a
    # hand-built GCC under /usr/local shows up.
    cc = shutil.which("gcc", path=search_path)
    cxx = shutil.which("g++", path=search_path)
    if cc is not None and cxx is not None:
        toolchain = _make_toolchain(
            cc, cxx, expected_major=None, env=env, label=f"unversioned gcc ({cc})"
        )
        if toolchain is not None and all(
            existing.major != toolchain.major for existing in toolchains
        ):
            toolchains.append(toolchain)

    return sorted(toolchains, key=lambda item: item.major, reverse=True)


def nvcc_accepts_host_compiler(
    nvcc: str, toolchain: GccToolchain, *, env: dict[str, str]
) -> tuple[bool, str]:
    """Compile a minimal CUDA source to verify nvcc accepts a GCC toolchain."""
    with tempfile.TemporaryDirectory(prefix="llama-cpp-nvcc-probe-") as temp_dir:
        source_path = os.path.join(temp_dir, "compiler_probe.cu")
        object_path = os.path.join(temp_dir, "compiler_probe.o")
        with open(source_path, "w", encoding="utf-8") as source_file:
            source_file.write('extern "C" __global__ void compiler_probe() {}\n')

        result = run(
            [nvcc, "-ccbin", toolchain.cxx, "-x", "cu", "-c", source_path, "-o", object_path],
            check=False,
            capture=True,
            env=env,
            quiet=True,
        )

    if result.returncode == 0:
        return True, ""
    output = ((result.stderr or "") + (result.stdout or "")).strip()
    reason = output.splitlines()[-1] if output else "nvcc exited without diagnostics"
    return False, reason


def nvcc_rejects_architectures(
    nvcc: str, architectures: str, *, env: dict[str, str]
) -> list[str]:
    """Return the architectures in the list that this nvcc will not compile for.

    The host-compiler probe above uses nvcc's default architecture, so a toolkit
    too old for the installed GPU passes it and only fails once the real compile
    reaches a CUDA source. One probe per architecture catches that in about a
    second. Reported as a warning rather than a hard stop: the probe uses a
    plain sm_<n> name and newer parts also accept suffixed variants, so a
    rejection here is a strong signal but not proof.
    """
    if architectures == "native":
        return []

    rejected: list[str] = []
    with tempfile.TemporaryDirectory(prefix="llama-cpp-arch-probe-") as temp_dir:
        source_path = os.path.join(temp_dir, "arch_probe.cu")
        with open(source_path, "w", encoding="utf-8") as source_file:
            source_file.write('extern "C" __global__ void arch_probe() {}\n')

        for arch in architectures.split(";"):
            if not arch:
                continue
            result = run(
                [
                    nvcc,
                    f"-arch=sm_{arch}",
                    "-c",
                    source_path,
                    "-o",
                    os.path.join(temp_dir, f"arch_probe_{arch}.o"),
                ],
                check=False,
                capture=True,
                env=env,
                quiet=True,
            )
            if result.returncode != 0:
                rejected.append(arch)
    return rejected


def select_gcc_toolchain(nvcc: str, *, env: dict[str, str]) -> GccToolchain:
    """Select the newest installed GCC toolchain accepted by nvcc."""
    toolchains = installed_gcc_toolchains(env=env)
    if not toolchains:
        raise RuntimeError(
            "No usable GCC toolchain was found. Install matching gcc and g++ packages."
        )

    log.info(f"probing {plural(len(toolchains), 'toolchain')} against nvcc")
    rejected: list[str] = []
    for toolchain in toolchains:
        accepted, reason = nvcc_accepts_host_compiler(nvcc, toolchain, env=env)
        if accepted:
            log.ok(f"selected {toolchain.version} ({toolchain.cc})")
            return toolchain
        log.info(f"GCC {toolchain.major} rejected by nvcc: {reason}")
        rejected.append(f"GCC {toolchain.major}: {reason}")

    details = "\n".join(f"  - {failure}" for failure in rejected)
    raise RuntimeError(
        f"nvcc rejected every installed GCC toolchain:\n{details}\n"
        "Install a host compiler supported by this CUDA toolkit."
    )


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


def cccl_include_dirs(cuda_home: str) -> list[str]:
    """CCCL header directories shipped by the toolkit, if it has the new layout.

    CUDA 13 moved cuda/, cub/ and thrust/ into a separate cccl include tree.
    """
    patterns = (
        os.path.join(cuda_home, "include", "cccl"),
        os.path.join(cuda_home, "targets", "*", "include", "cccl"),
    )
    found: list[str] = []
    for pattern in patterns:
        found.extend(path for path in glob.glob(pattern) if os.path.isdir(path))
    return found


def verify_cccl_visible(build_dir: str, cuda_home: str) -> None:
    """Check that cmake handed the toolkit's CCCL headers to the build.

    nvcc finds those headers itself, so a cmake that omits them still builds
    today while leaving any host-compiled translation unit that includes cuda/,
    cub/ or thrust/ without an include path. Rather than guess which cmake
    version added the directory, read what this cmake actually detected.
    """
    expected = cccl_include_dirs(cuda_home)
    if not expected:
        return  # pre-CUDA 13 layout: nothing to check

    detected = glob.glob(
        os.path.join(build_dir, "CMakeFiles", "*", "CMakeCUDACompiler.cmake")
    )
    if not detected:
        log.info("no CMakeCUDACompiler.cmake found; skipping the CCCL include check")
        return

    try:
        with open(detected[0], encoding="utf-8", errors="replace") as handle:
            text = handle.read()
    except OSError as error:
        log.info(f"could not read {detected[0]}: {error}")
        return

    if any(os.path.basename(path) in text or path in text for path in expected):
        log.info("toolkit CCCL headers are present in cmake's CUDA include dirs")
    else:
        log.warn(
            f"The toolkit ships CCCL headers ({expected[0]}) but cmake did not add "
            "them to the CUDA include directories. Host-compiled sources that "
            "include cuda/, cub/ or thrust/ headers would not find them."
        )


def remote_default_branch(repo_url: str, *, env: dict[str, str]) -> str:
    """Resolve the remote default branch name from HEAD."""
    output = capture(
        ["git", "ls-remote", "--symref", repo_url, "HEAD"], env=env, quiet=True
    )
    for line in output.splitlines():
        if not line.startswith("ref: "):
            continue
        ref = line.split("\t", 1)[0].replace("ref: ", "", 1).strip()
        if ref.startswith("refs/heads/"):
            branch = ref.removeprefix("refs/heads/")
            log.info(f"remote default branch: {branch}")
            return branch
    raise RuntimeError(f"Could not determine default branch for {repo_url}")


def remove_existing_repo(repo_dir: str) -> None:
    """Remove an existing repository path before cloning."""
    if not os.path.lexists(repo_dir):
        return
    log.info(f"removing existing {repo_dir}")
    if os.path.islink(repo_dir) or not os.path.isdir(repo_dir):
        os.remove(repo_dir)
    else:
        shutil.rmtree(repo_dir)


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


def sync_repo_to_latest(repo_dir: str, repo_url: str, *, env: dict[str, str]) -> str:
    """Clone a fresh shallow copy of the latest upstream default branch."""
    remove_existing_repo(repo_dir)
    branch = remote_default_branch(repo_url, env=env)
    run(["git", "clone", "--depth", "1", "--branch", branch, repo_url, repo_dir], env=env)
    return branch


def sync_repo_to_pr(
    repo_dir: str, repo_url: str, pr_number: int, *, env: dict[str, str]
) -> str:
    """Clone shallowly and check out a specific PR branch for beta testing."""
    remove_existing_repo(repo_dir)
    ref = f"refs/pull/{pr_number}/head"
    local_branch = f"pr-{pr_number}"
    run(["git", "clone", "--depth", "1", repo_url, repo_dir], env=env)
    run(
        ["git", "-C", repo_dir, "fetch", "--depth", "1", "origin", f"{ref}:{local_branch}"],
        env=env,
    )
    run(["git", "-C", repo_dir, "checkout", local_branch], env=env)
    return local_branch


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

    # This lists every tag in the repository, which is thousands of refs, so it
    # is summarised rather than echoed.
    log.info("querying upstream tags for a build number (this lists all refs)")
    output = capture(
        ["git", "ls-remote", "--tags", repo_url], env=env, quiet=True
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


def install_atomically(source: str, target: str) -> None:
    """Install a binary via staged file plus rename.

    A plain `install` opens the destination for writing, which fails with
    ETXTBSY if that binary is currently running (llama-server as a service, for
    instance). Staging next to the target and renaming over it swaps the
    directory entry instead, leaving any running process on the old inode.
    """
    directory, name = os.path.split(target)
    staged = os.path.join(directory, f".{name}.new")
    run(["sudo", "install", "-m", "0755", source, staged])
    try:
        run(["sudo", "mv", "-f", staged, target])
    except subprocess.CalledProcessError:
        # Do not leave a half-installed dotfile sitting in the install dir.
        run(["sudo", "rm", "-f", staged], check=False, quiet=True)
        raise


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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build and install llama.cpp with CUDA support",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-k",
        "--keep",
        action="store_true",
        help="Keep the llama.cpp source directory after install (default: delete it)",
    )
    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=os.cpu_count() or 4,
        metavar="N",
        help="Parallel compile jobs (default: %(default)s, one per logical CPU)",
    )
    parser.add_argument(
        "--web-ui",
        action="store_true",
        help=(
            "Embed llama-server's built-in web UI (sets LLAMA_BUILD_UI and "
            "LLAMA_USE_PREBUILT_UI). Off by default: the assets are fetched from "
            "a Hugging Face bucket at build time, the commit-matched bucket is "
            "often unpopulated so the build falls back to 'latest', and a bucket "
            "archive missing a required asset fails the embed step and the whole "
            "build."
        ),
    )
    parser.add_argument(
        "--beta",
        type=int,
        metavar="PR",
        nargs="?",
        const=20075,
        help=(
            "Build from a GitHub PR branch instead of the latest upstream branch "
            "(default PR: 20075, speculative decoding for hybrid models)"
        ),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if os.geteuid() == 0:
        raise RuntimeError("Run this script as a normal user, not with sudo or as root.")
    if args.jobs < 1:
        raise RuntimeError(f"--jobs must be at least 1, got {args.jobs}")

    cuda_home = "/usr/local/cuda"
    env = os.environ.copy()
    env.update(
        {
            "CUDA_HOME": cuda_home,
            "PATH": f"{cuda_home}/bin:{env.get('PATH', '')}:/usr/lib/x86_64-linux-gnu",
            "LD_LIBRARY_PATH": (
                f"{cuda_home}/lib64:{env.get('LD_LIBRARY_PATH', '')}"
                ":/usr/lib/x86_64-linux-gnu"
            ),
        }
    )

    # ---------------------------------------------------------------- step 1
    log.step("Preflight: host, CUDA toolkit and GPU inventory")

    free_gib = free_disk_gib(os.getcwd())
    log.table(list(host_inventory(free_gib=free_gib).items()))

    if free_gib is not None and free_gib < LOW_DISK_WARN_GIB:
        log.warn(
            f"Only {free_gib:.1f} GiB free here; a CUDA build plus ccache growth "
            "can need several GiB."
        )

    nvcc = require_executable(f"{cuda_home}/bin/nvcc", env=env)
    cuda_version, nvcc_line = cuda_release(nvcc, env=env)
    gpus = gpu_inventory(env=env)

    hardware_rows = [
        ("nvcc", nvcc),
        ("CUDA toolkit", f"{cuda_version[0]}.{cuda_version[1]} ({nvcc_line})"),
    ]
    hardware_rows += [
        (
            f"GPU {gpu.index}",
            f"{gpu.name}, compute {gpu.compute_cap}, "
            f"{gpu.memory_mib / 1024:.1f} GiB VRAM, driver {gpu.driver}",
        )
        for gpu in gpus
    ]
    log.table(hardware_rows)
    if not gpus:
        log.warn("No GPU inventory available; the build will fall back to -arch=native.")

    ensure_sudo(reason="apt and installing binaries later")

    # ---------------------------------------------------------------- step 2
    log.step("System packages")

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
            log.warn("apt update returned non-zero; using cached package indexes.")
    except subprocess.TimeoutExpired:
        log.warn("apt update exceeded its 10 minute timeout; using cached indexes.")

    log.info(
        f"ensuring {plural(len(SYSTEM_PACKAGES), 'package')}: "
        f"{' '.join(SYSTEM_PACKAGES)}"
    )
    run(["sudo", "apt", *apt_opts, "install", "-y", *SYSTEM_PACKAGES])

    # ---------------------------------------------------------------- step 3
    log.step("GCC toolchain selection for nvcc")
    toolchain = select_gcc_toolchain(nvcc, env=env)
    env.update({"CC": toolchain.cc, "CXX": toolchain.cxx})

    # ---------------------------------------------------------------- step 4
    log.step("Build tools and target architecture")

    cmake_bin, cmake_version = require_build_tool("cmake", env=env, prefer_newest=True)
    ninja_bin, ninja_version = require_build_tool("ninja", env=env)
    tool_rows = [
        ("cmake", f"{cmake_bin} ({version_text(cmake_version)})"),
        ("ninja", f"{ninja_bin} ({version_text(ninja_version)})"),
    ]

    cuda_archs, arch_source = cuda_architectures(gpus)
    rejected_archs = nvcc_rejects_architectures(nvcc, cuda_archs, env=env)
    if rejected_archs:
        log.warn(
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
            ("FlashAttention K/V", CUDA_FA_QUANTS),
            ("web UI", "embedded" if args.web_ui else "disabled"),
        ]
    )

    # ---------------------------------------------------------------- step 5
    log.step("Source checkout")

    if args.beta is not None:
        log.info(f"beta mode: building from PR #{args.beta}")
        branch = sync_repo_to_pr(REPO_DIR, REPO_URL, args.beta, env=env)
    else:
        branch = sync_repo_to_latest(REPO_DIR, REPO_URL, env=env)

    head = describe_head(REPO_DIR, env=env)
    log.table(
        [
            ("branch", branch),
            ("commit", f"{head['short_sha']} ({head['sha']})"),
            ("subject", head["subject"]),
            ("authored", f"{head['authored']} by {head['author']}"),
        ]
    )

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
    log.step("CMake configure")

    # GGML_NATIVE=ON supplies -march=native for the CPU backend, which covers
    # everything Zen 4 offers here (AVX-512 with VNNI and BF16). Setting
    # GGML_NATIVE also forces ggml's individual ISA switches off by design, so
    # listing them separately would be redundant.
    #
    # Both UI variables must be set together: scripts/ui-assets.cmake gates
    # provisioning on BUILD_UI and HF_ENABLED independently, and HF_ENABLED
    # comes from LLAMA_USE_PREBUILT_UI, which defaults ON. Passing only
    # LLAMA_BUILD_UI=OFF still runs the Hugging Face download.
    #
    # Deliberately NOT set:
    #   GGML_LTO ................. upstream default is OFF. It adds substantial
    #       link time and nearly all compute runs in CUDA kernels.
    #   GGML_CUDA_COMPRESSION_MODE  upstream already defaults to "size" and the
    #       single-architecture binary here is small either way.
    #   GGML_CUDA_FA_ALL_QUANTS .. deprecated. See CUDA_FA_QUANTS above.
    ui_enabled = "ON" if args.web_ui else "OFF"
    configure_args = [
        f"-DLLAMA_BUILD_UI={ui_enabled}",
        f"-DLLAMA_USE_PREBUILT_UI={ui_enabled}",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DCMAKE_BUILD_TYPE=Release",
        f"-DCMAKE_C_COMPILER={toolchain.cc}",
        f"-DCMAKE_CXX_COMPILER={toolchain.cxx}",
        f"-DCMAKE_CUDA_COMPILER={nvcc}",
        f"-DCMAKE_CUDA_HOST_COMPILER={toolchain.cxx}",
        f"-DCMAKE_MAKE_PROGRAM={ninja_bin}",
        f"-DCUDAToolkit_ROOT={cuda_home}",
        f"-DCMAKE_CUDA_ARCHITECTURES={cuda_archs}",
        "-DGGML_CUDA=ON",
        "-DGGML_CUDA_FA=ON",
        f"-DGGML_CUDA_FA_QUANTS={CUDA_FA_QUANTS}",
        "-DGGML_CUDA_GRAPHS=ON",
        # Single GPU here, so the NVIDIA collectives library is dead weight.
        "-DGGML_CUDA_NCCL=OFF",
        "-DGGML_NATIVE=ON",
        "-DGGML_OPENMP=ON",
        "-DGGML_CCACHE=ON",
        "-DGGML_CPU_REPACK=ON",
    ]
    if build_number is not None:
        # llama.cpp only derives this itself when the caller has not set it.
        configure_args.append(f"-DLLAMA_BUILD_NUMBER={build_number}")

    build_dir = f"{REPO_DIR}/build"
    run(
        [cmake_bin, REPO_DIR, "-B", build_dir, *configure_args, "-G", "Ninja"],
        env=env,
        report_duration=False,
    )
    verify_cccl_visible(build_dir, cuda_home)

    # ---------------------------------------------------------------- step 7
    log.step(f"Compile: {', '.join(BUILD_TARGETS)}")

    ccache_before = ccache_counters(env=env)
    compile_started = time.monotonic()
    run(
        [ninja_bin, "-C", build_dir, f"-j{args.jobs}", *BUILD_TARGETS],
        env=env,
        report_duration=False,
    )
    compile_seconds = time.monotonic() - compile_started

    log.table(report_ccache_delta(ccache_before, ccache_counters(env=env)))
    if not args.web_ui:
        log.info(
            "the 'UI: no assets available' warning above is expected: UI "
            "provisioning is off, so 0 assets were embedded"
        )

    # ---------------------------------------------------------------- step 8
    log.step(f"Install to {INSTALL_DIR} and verify")

    bin_dir = os.path.join(build_dir, "bin")
    built = {target: os.path.join(bin_dir, target) for target in BUILD_TARGETS}
    missing = [path for path in built.values() if not os.path.isfile(path)]
    if missing:
        listing = "\n".join(f"  - {path}" for path in missing)
        raise RuntimeError(f"Cannot install missing build outputs:\n{listing}")

    log.info(f"build outputs in {bin_dir}")
    log.table(
        [
            (target, f"{os.path.getsize(path) / (1024 ** 2):.1f} MiB")
            for target, path in built.items()
        ]
    )

    ensure_sudo(reason="installing binaries")
    installed: list[str] = []
    for target, source_path in built.items():
        destination = os.path.join(INSTALL_DIR, target)
        install_atomically(source_path, destination)
        installed.append(destination)

    invalid = [
        path
        for path in installed
        if not os.path.isfile(path) or not os.access(path, os.X_OK)
    ]
    if invalid:
        listing = "\n".join(f"  - {path}" for path in invalid)
        raise RuntimeError(f"Installed binaries could not be verified:\n{listing}")
    log.ok(f"installed {len(installed)} binaries")

    # Shadowing check: a copy earlier in the interactive PATH would win over the
    # one just installed, which is easy to miss and confusing to debug.
    for target in BUILD_TARGETS:
        resolved = shutil.which(target, path=os.environ.get("PATH"))
        expected = os.path.join(INSTALL_DIR, target)
        if resolved is None:
            log.warn(f"{target} is not on your interactive PATH ({expected} installed).")
        elif os.path.realpath(resolved) != os.path.realpath(expected):
            log.warn(f"{target} resolves to {resolved}, shadowing {expected}.")

    version_line = "unknown"
    version_output = capture_all([os.path.join(INSTALL_DIR, "llama-server"), "--version"], env=env)
    if version_output:
        log.output(version_output, limit=6)
        version_line = re.sub(r"^version:\s*", "", version_output.splitlines()[0].strip())

    devices = parse_devices(
        capture_all([os.path.join(INSTALL_DIR, "llama-cli"), "--list-devices"], env=env)
    )
    cuda_devices = [device for device in devices if device.startswith("CUDA")]
    log.table([("device", device) for device in devices])
    if cuda_devices:
        log.ok(
            f"{plural(len(cuda_devices), 'CUDA device')} visible to the installed binary"
        )
    else:
        log.warn("No CUDA device was enumerated; check the driver and CUDA runtime.")

    if os.path.isdir(REPO_DIR):
        if args.keep:
            log.info(f"source kept at {os.path.abspath(REPO_DIR)}")
        else:
            shutil.rmtree(REPO_DIR)
            log.info("source directory removed")

    log.finish_step()

    # ------------------------------------------------------------------ recap
    log.heading("Build summary")
    summary = {
        "commit": f"{head['short_sha']} on {branch}",
        "build number": (
            f"b{build_number}" if build_number is not None else "1 (untagged commit)"
        ),
        "version": version_line,
        "compiler": f"{toolchain.version} + CUDA {cuda_version[0]}.{cuda_version[1]}",
        "cmake / ninja": f"{version_text(cmake_version)} / {version_text(ninja_version)}",
        "CUDA arch": cuda_archs,
        "FA K/V combos": CUDA_FA_QUANTS,
        "web UI": "embedded" if args.web_ui else "disabled",
        "installed": ", ".join(installed),
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
            f"{plural(len(installed), 'binary', 'binaries')} in {INSTALL_DIR}",
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
