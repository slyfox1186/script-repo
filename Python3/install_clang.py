#!/usr/bin/env python3
"""Build the newest LLVM/Clang release from source, tuned for this host, and install it.

Follows LLVM's documented recipe for the fastest compiler
(llvm.org/docs/HowToBuildWithPGO.html, AdvancedBuilds.html,
BuildingADistribution.html and bolt/docs/OptimizingClang.md):

  1. stage1        The newest apt clang and lld build clang, lld and
                   compiler-rt's profile runtime from the release sources.
  2. instrumented  stage1 builds an IR-instrumented clang and lld with the
                   same ThinLTO and -march flags as the final build.
  3. training      The instrumented toolchain builds LLVM, Clang and lld (the
                   documented "all" workload); its profiles are merged.
  4. final         stage1 builds the toolchain with that profile, ThinLTO,
                   -march=<this CPU>, static linking, and BOLT applied to
                   clang. With an NVIDIA GPU it adds the NVPTX backend and the
                   OpenMP offload runtimes for it.
  5. install       A DESTDIR install is smoke-tested, promoted to
                   /opt/llvm/<version>, linked into /usr/local/bin as
                   clang-<major> and friends, and registered with the host's
                   clang update-alternatives group.

Run without sudo. It escalates only for apt, the promotion into /opt, links in
/usr/local/bin and update-alternatives, and keeps the sudo timestamp fresh so a
multi-hour build does not stall at the install step on a password prompt.
Completed stages are stamped, so a rerun after a failure resumes.
"""

from __future__ import annotations

import argparse
import collections
import contextlib
import fcntl
import hashlib
import json
import os
import platform
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
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, ClassVar, TextIO

GITHUB_RELEASES_API = "https://api.github.com/repos/llvm/llvm-project/releases"
RELEASE_TAG_RE = re.compile(r"^llvmorg-(\d+)\.(\d+)\.(\d+)$")
SHA256_DIGEST_RE = re.compile(r"^sha256:([0-9a-f]{64})$")
NINJA_PROGRESS_RE = re.compile(r"^\[(\d+)/(\d+)\] ")
MIN_CMAKE = (3, 20, 0)  # cmake_minimum_required in llvm/CMakeLists.txt

DEFAULT_PREFIX_ROOT = Path("/opt/llvm")
DEFAULT_LINK_DIR = Path("/usr/local/bin")
DEFAULT_CACHE_ROOT = (
    Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "install-clang"
)

# Build tools come only from these directories, newest version first, so a
# Conda or pyenv copy that happens to be on PATH never ends up in the build.
SYSTEM_TOOL_DIRS = (Path("/usr/local/bin"), Path("/usr/bin"))
SYSTEM_PYTHON = Path("/usr/bin/python3")
CLEAN_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# Build subprocesses inherit only these variables, so Conda's CC, CFLAGS,
# LDFLAGS, PKG_CONFIG_PATH and similar cannot leak into the compiler build.
ENV_PASSTHROUGH = ("HOME", "USER", "LOGNAME", "TERM", "TMPDIR")
CUDA_ROOT = Path("/usr/local/cuda")

LLVM_HOST_TARGETS = {"x86_64": "X86", "aarch64": "AArch64"}

# LLVM's CMake docs size LLVM_PARALLEL_LINK_JOBS at one link job per 15 GB of
# RAM. ThinLTO stages keep LLVM's own limit of 2 instead, because each ThinLTO
# link already runs its backends in parallel.
RAM_GIB_PER_LINK_JOB = 15

# LLDB's documented Ubuntu dependencies, plus zstd for LLVM_ENABLE_ZSTD and the
# generic build tools. The host clang/lld pair is added once it is known.
APT_PACKAGES = (
    "build-essential",
    "cmake",
    "ninja-build",
    "python3-dev",
    "swig",
    "libedit-dev",
    "libncurses-dev",
    "libxml2-dev",
    "liblzma-dev",
    "zlib1g-dev",
    "ccache",
    "libzstd-dev",
)

FINAL_PROJECTS = "clang;clang-tools-extra;lld;lldb;bolt"
# Host and NVPTX runtime sets follow offload/cmake/caches/Offload.cmake. AMDGPU
# offload is left out: it needs ROCm's HSA runtime, which this setup does not install.
HOST_RUNTIMES = "compiler-rt;libunwind;libcxx;libcxxabi;openmp;offload"
NVPTX_TRIPLE = "nvptx64-nvidia-cuda"
NVPTX_RUNTIMES = "compiler-rt;libc;openmp;libcxx;libcxxabi"
# From clang/cmake/caches/BOLT.cmake: BOLT rewrites the binary from its relocations.
BOLT_LINKER_FLAGS = "-Wl,--emit-relocs,-znow"

# Bump when a stage definition changes in a way its CMake arguments do not show.
PIPELINE_REVISION = 1
STAMP_CONFIG = ".install-clang-config"
STAMP_DONE = ".install-clang-done"
INSTALL_MARKER = ".install-clang.json"


class Log:
    """Classic shell-style console output: [INFO] tags and $ command echoes."""

    COLORS: ClassVar[dict[str, str]] = {
        "INFO": "36",
        "OK": "32",
        "WARNING": "33",
        "ERROR": "31",
        "HEAD": "1;36",
        "CMD": "1",
    }

    def __init__(self) -> None:
        self.color = (
            sys.stdout.isatty()
            and not os.environ.get("NO_COLOR")
            and os.environ.get("TERM") != "dumb"
        )
        self.warnings: list[str] = []
        self._progress_open = False

    def paint(self, text: str, key: str) -> str:
        return f"\033[{self.COLORS[key]}m{text}\033[0m" if self.color else text

    def _emit(self, tag: str, message: str, *, stream: TextIO | None = None) -> None:
        self.end_progress()
        print(
            f"{self.paint(f'[{tag}]', tag)} {message}",
            file=stream or sys.stdout,
            flush=True,
        )

    def info(self, message: str) -> None:
        self._emit("INFO", message)

    def ok(self, message: str) -> None:
        self._emit("OK", message)

    def warning(self, message: str) -> None:
        self.warnings.append(message)
        self._emit("WARNING", message)

    def error(self, message: str) -> None:
        self._emit("ERROR", message, stream=sys.stderr)

    def command(self, argv: Sequence[str | Path], *, env_prefix: str = "") -> None:
        self.end_progress()
        print(
            self.paint(f"$ {env_prefix}{shlex.join(str(a) for a in argv)}", "CMD"),
            flush=True,
        )

    def heading(self, title: str) -> None:
        self.end_progress()
        print()
        print(self.paint(title, "HEAD"))
        print(self.paint("-" * len(title), "HEAD"), flush=True)

    def rows(self, rows: Sequence[tuple[str, str]]) -> None:
        width = max((len(key) for key, _ in rows), default=0)
        for key, value in rows:
            print(f"    {key.ljust(width)}  {value}", flush=True)

    def progress(self, text: str) -> None:
        """Rewrite one status line on a terminal; print plain lines otherwise."""
        if sys.stdout.isatty():
            columns = shutil.get_terminal_size((100, 24)).columns
            print(f"\r\033[K{text[: columns - 1]}", end="", flush=True)
            self._progress_open = True
        else:
            print(text, flush=True)

    def end_progress(self) -> None:
        if self._progress_open:
            print(flush=True)
            self._progress_open = False


log = Log()


class InstallError(RuntimeError):
    """A failure the user can act on; reported without a traceback."""


@dataclass(frozen=True)
class SourceAsset:
    name: str
    url: str
    size: int
    sha256: str


@dataclass(frozen=True)
class Release:
    tag: str
    version: tuple[int, int, int]
    asset: SourceAsset

    @property
    def version_str(self) -> str:
        return ".".join(map(str, self.version))

    @property
    def major(self) -> int:
        return self.version[0]


@dataclass(frozen=True)
class Gpu:
    name: str
    arch: str  # e.g. "sm_89"


@dataclass(frozen=True)
class HostCompiler:
    major: int
    cc: Path
    cxx: Path


@dataclass(frozen=True)
class Host:
    cpus: int
    mem_total_gib: float
    mem_avail_gib: float
    machine: str
    llvm_target: str
    gpu: Gpu | None
    cuda_root: Path | None


@dataclass(frozen=True)
class Tools:
    cmake: Path
    ninja: Path
    python: Path


@dataclass
class Stage:
    name: str
    title: str
    source: Path
    build: Path
    cmake_args: list[str]
    targets: list[str] = field(default_factory=list)
    fingerprint: str = ""


# ─── Small helpers ───────────────────────────────────────────────────────────


def format_duration(seconds: float) -> str:
    seconds = round(seconds)
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return f"{hours}h{minutes:02d}m{secs:02d}s"
    if minutes:
        return f"{minutes}m{secs:02d}s"
    return f"{secs}s"


def gib(num_bytes: float) -> str:
    if num_bytes < 2**30:
        return f"{num_bytes / 2**20:.0f} MiB"
    return f"{num_bytes / 2**30:.1f} GiB"


def build_env(**extra: str) -> dict[str, str]:
    env = {key: os.environ[key] for key in ENV_PASSTHROUGH if key in os.environ}
    env.update(PATH=CLEAN_PATH, LANG="C.UTF-8", LC_ALL="C.UTF-8")
    env.update(extra)
    return env


def run(
    cmd: Sequence[str | Path],
    *,
    env: dict[str, str] | None = None,
    check: bool = True,
    capture: bool = False,
    quiet: bool = False,
    cwd: Path | None = None,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    argv = [str(a) for a in cmd]
    if not quiet:
        log.command(argv)
    result = subprocess.run(
        argv,
        env=env,
        cwd=cwd,
        check=False,
        text=True,
        capture_output=capture,
        timeout=timeout,
    )
    if check and result.returncode != 0:
        detail = ""
        if capture:
            lines = (result.stderr or result.stdout or "").strip().splitlines()
            detail = f": {lines[-1]}" if lines else ""
        raise InstallError(
            f"command failed with exit {result.returncode}{detail}: {shlex.join(argv)}"
        )
    return result


def output_of(
    cmd: Sequence[str | Path], *, env: dict[str, str] | None = None
) -> str | None:
    """Combined stdout/stderr of a probe, or None if it cannot run or fails."""
    try:
        result = subprocess.run(
            [str(a) for a in cmd],
            env=env or build_env(),
            check=False,
            text=True,
            capture_output=True,
            timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return (result.stdout + result.stderr).strip()


def as_root(cmd: Sequence[str | Path]) -> list[str]:
    argv = [str(a) for a in cmd]
    return argv if os.geteuid() == 0 else ["sudo", *argv]


def writable(path: Path) -> bool:
    """Whether the current user can create or replace entries at path."""
    probe = path
    while not probe.exists():
        probe = probe.parent
    return os.access(probe, os.W_OK | os.X_OK)


def remove_tree(path: Path, *, inside: Path, privileged: bool = False) -> None:
    """Delete a directory tree only when it sits strictly inside another directory."""
    resolved = path.resolve()
    root = inside.resolve()
    if path.is_symlink() or resolved == root or root not in resolved.parents:
        raise InstallError(f"refusing to delete {path}: not strictly inside {inside}")
    if not path.exists():
        return
    if privileged:
        run(as_root(["rm", "-rf", "--one-file-system", "--", resolved]))
    else:
        shutil.rmtree(resolved)


def version_tuple(text: str) -> tuple[int, ...]:
    match = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", text)
    if not match:
        return ()
    return tuple(int(part) for part in match.groups(default="0"))


def free_bytes(path: Path) -> int:
    probe = path
    while not probe.exists():
        probe = probe.parent
    return shutil.disk_usage(probe).free


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ─── GitHub release lookup and source download ───────────────────────────────


class _HttpsOnlyRedirect(urllib.request.HTTPRedirectHandler):
    """Follow redirects only to HTTPS and keep the API token on api.github.com."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        if urllib.parse.urlsplit(newurl).scheme != "https":
            raise urllib.error.HTTPError(
                newurl, code, f"refusing non-HTTPS redirect to {newurl}", headers, fp
            )
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if (
            new is not None
            and urllib.parse.urlsplit(newurl).hostname != "api.github.com"
        ):
            new.remove_header("Authorization")
        return new


_OPENER = urllib.request.build_opener(_HttpsOnlyRedirect)
_USER_AGENT = "install_clang.py"


def github_json(url: str) -> object:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": _USER_AGENT,
    }
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            with _OPENER.open(
                urllib.request.Request(url, headers=headers), timeout=30
            ) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            if exc.code in (403, 429):
                raise InstallError(
                    f"GitHub API refused {url} ({exc.code}); unauthenticated requests are "
                    "limited to 60 per hour. Set GH_TOKEN or GITHUB_TOKEN and retry."
                ) from exc
            if exc.code == 404:
                raise InstallError(f"GitHub API has no such release: {url}") from exc
            last_error = exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = exc
        time.sleep(2 * (attempt + 1))
    raise InstallError(f"could not reach the GitHub API ({url}): {last_error}")


def release_from_json(data: dict[str, Any]) -> Release | None:
    """A stable release with a source tarball, or None; a missing digest is fatal."""
    match = RELEASE_TAG_RE.match(data.get("tag_name", ""))
    if not match or data.get("draft") or data.get("prerelease"):
        return None
    version = (int(match[1]), int(match[2]), int(match[3]))
    name = f"llvm-project-{'.'.join(map(str, version))}.src.tar.xz"
    for asset in data.get("assets", []):
        if asset.get("name") != name:
            continue
        digest = SHA256_DIGEST_RE.match(asset.get("digest") or "")
        if not digest:
            raise InstallError(
                f"{data['tag_name']}: GitHub publishes no SHA-256 digest for {name}, "
                "so the download cannot be verified"
            )
        return Release(
            data["tag_name"],
            version,
            SourceAsset(
                name, asset["browser_download_url"], int(asset["size"]), digest[1]
            ),
        )
    return None


def fetch_release(pin: str | None) -> Release:
    if pin:
        tag = pin if pin.startswith("llvmorg-") else f"llvmorg-{pin}"
        if not RELEASE_TAG_RE.match(tag):
            raise InstallError(f"--release expects a stable X.Y.Z version, got {pin!r}")
        data = github_json(f"{GITHUB_RELEASES_API}/tags/{tag}")
        release = release_from_json(data) if isinstance(data, dict) else None
        if release is None:
            raise InstallError(
                f"{tag} is not a published stable release with a source tarball"
            )
        return release
    data = github_json(f"{GITHUB_RELEASES_API}?per_page=100")
    items = (
        [item for item in data if isinstance(item, dict)]
        if isinstance(data, list)
        else []
    )
    stable = []
    for item in items:
        match = RELEASE_TAG_RE.match(item.get("tag_name", ""))
        if match and not item.get("draft") and not item.get("prerelease"):
            stable.append(((int(match[1]), int(match[2]), int(match[3])), item))
    # GitHub's "latest" flag follows publication date, and LLVM ships backport
    # releases of older branches, so take the highest version. Only that one's
    # digest matters; older releases predate GitHub's asset digests.
    for _, item in sorted(stable, key=lambda pair: pair[0], reverse=True):
        release = release_from_json(item)
        if release is not None:
            return release
    raise InstallError(
        "no stable llvmorg-X.Y.Z release with a source tarball was found"
    )


def download(asset: SourceAsset, directory: Path) -> Path:
    """Fetch an asset over HTTPS with resume, verifying GitHub's SHA-256 digest."""
    directory.mkdir(parents=True, exist_ok=True)
    final = directory / asset.name
    if final.is_file() and sha256_file(final) == asset.sha256:
        log.info(f"Reusing verified download {final}")
        return final
    partial = final.with_name(final.name + ".part")
    for attempt in range(1, 4):
        offset = partial.stat().st_size if partial.exists() else 0
        if offset > asset.size:
            partial.unlink()
            offset = 0
        headers = {"User-Agent": _USER_AGENT}
        if offset:
            headers["Range"] = f"bytes={offset}-"
        try:
            with _OPENER.open(
                urllib.request.Request(asset.url, headers=headers), timeout=60
            ) as response:
                if offset and response.status != 206:
                    offset = 0
                digest = hashlib.sha256()
                if offset:
                    with partial.open("rb") as existing:
                        for chunk in iter(lambda: existing.read(1 << 20), b""):
                            digest.update(chunk)
                received = offset
                last_report = 0.0
                with partial.open("ab" if offset else "wb") as handle:
                    for chunk in iter(lambda: response.read(1 << 20), b""):
                        handle.write(chunk)
                        digest.update(chunk)
                        received += len(chunk)
                        now = time.monotonic()
                        interval = 1 if sys.stdout.isatty() else 15
                        if now - last_report >= interval or received == asset.size:
                            last_report = now
                            log.progress(
                                f"[INFO] Downloading {asset.name}: "
                                f"{gib(received)} of {gib(asset.size)} "
                                f"({100 * received // max(asset.size, 1)}%)"
                            )
                log.end_progress()
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            log.end_progress()
            log.warning(f"Download attempt {attempt} failed: {exc}")
            time.sleep(3 * attempt)
            continue
        if received != asset.size:
            log.warning(
                f"Download attempt {attempt} ended at {received} of {asset.size} bytes"
            )
            continue
        if digest.hexdigest() != asset.sha256:
            partial.unlink()
            raise InstallError(
                f"{asset.name} failed SHA-256 verification; the partial file was removed"
            )
        partial.replace(final)
        log.ok(f"Verified {asset.name} (sha256 {asset.sha256[:16]}...)")
        return final
    raise InstallError(f"could not download {asset.url} after 3 attempts")


def extract_source(archive: Path, release: Release, work: Path) -> Path:
    """Unpack the source tarball once; a marker records which archive it came from."""
    root_name = f"llvm-project-{release.version_str}.src"
    source_parent = work / "src"
    source = source_parent / root_name
    marker = source / ".install-clang-extracted"
    if marker.is_file() and marker.read_text() == release.asset.sha256:
        log.info(f"Reusing extracted sources in {source}")
        return source
    staging = work / "src.partial"
    for stale in (staging, source_parent):
        remove_tree(stale, inside=work)
    staging.mkdir(parents=True)
    log.info(f"Extracting {archive.name}")
    with tarfile.open(archive, "r:xz") as tar:
        tar.extractall(staging, filter="data")
    entries = sorted(p.name for p in staging.iterdir())
    if entries != [root_name]:
        raise InstallError(
            f"{archive.name} should contain only {root_name}/, found {entries}"
        )
    staging.rename(source_parent)
    marker.write_text(release.asset.sha256)
    log.ok(f"Sources ready in {source}")
    return source


# ─── Host inspection ─────────────────────────────────────────────────────────


def read_meminfo() -> tuple[float, float]:
    values: dict[str, int] = {}
    with open("/proc/meminfo") as handle:
        for line in handle:
            key, _, rest = line.partition(":")
            values[key] = int(rest.split()[0])  # kB
    return values["MemTotal"] / 2**20, values["MemAvailable"] / 2**20


def detect_gpu() -> Gpu | None:
    text = output_of(
        ["nvidia-smi", "--query-gpu=name,compute_cap", "--format=csv,noheader"]
    )
    if not text:
        return None
    name, _, cap = text.splitlines()[0].rpartition(",")
    cap = cap.strip()
    if not re.fullmatch(r"\d+\.\d+", cap):
        return None
    return Gpu(name.strip(), "sm_" + cap.replace(".", ""))


def detect_host() -> Host:
    machine = platform.machine()
    if machine not in LLVM_HOST_TARGETS:
        raise InstallError(f"unsupported host architecture {machine}")
    total, available = read_meminfo()
    gpu = detect_gpu()
    cuda_root = CUDA_ROOT if (CUDA_ROOT / "bin" / "ptxas").is_file() else None
    return Host(
        len(os.sched_getaffinity(0)),
        total,
        available,
        machine,
        LLVM_HOST_TARGETS[machine],
        gpu,
        cuda_root,
    )


def detect_host_compiler() -> HostCompiler | None:
    """The newest versioned apt clang with its matching clang++."""
    found = []
    for path in Path("/usr/bin").glob("clang-[0-9]*"):
        match = re.fullmatch(r"clang-(\d+)", path.name)
        if match and (path.parent / f"clang++-{match[1]}").exists():
            found.append(
                HostCompiler(int(match[1]), path, path.parent / f"clang++-{match[1]}")
            )
    return max(found, key=lambda compiler: compiler.major, default=None)


def detect_native_cpu(compiler: HostCompiler) -> str:
    """Resolve -march=native to a named CPU so the build is reproducible and logged."""
    text = output_of(
        [
            compiler.cc,
            "-march=native",
            "-###",
            "-x",
            "c",
            "-c",
            "/dev/null",
            "-o",
            "/dev/null",
        ]
    )
    match = re.search(r'"-target-cpu" "([^"]+)"', text or "")
    if not match:
        raise InstallError(f"{compiler.cc} could not resolve -march=native")
    return match[1]


def pick_tool(name: str, minimum: tuple[int, ...] = ()) -> Path:
    best: tuple[tuple[int, ...], Path] | None = None
    for directory in SYSTEM_TOOL_DIRS:
        candidate = directory / name
        if not (candidate.is_file() and os.access(candidate, os.X_OK)):
            continue
        version = version_tuple(output_of([candidate, "--version"]) or "")
        if version and version >= minimum and (best is None or version > best[0]):
            best = (version, candidate)
    if best is None:
        wanted = f" {'.'.join(map(str, minimum))}+" if minimum else ""
        raise InstallError(
            f"no usable {name}{wanted} in {', '.join(map(str, SYSTEM_TOOL_DIRS))}"
        )
    return best[1]


def pick_tools() -> Tools:
    if not (
        SYSTEM_PYTHON.is_file()
        and version_tuple(output_of([SYSTEM_PYTHON, "--version"]) or "") >= (3, 8)
    ):
        raise InstallError(f"LLVM's build needs Python 3.8+ at {SYSTEM_PYTHON}")
    return Tools(pick_tool("cmake", MIN_CMAKE), pick_tool("ninja"), SYSTEM_PYTHON)


def missing_packages(packages: Sequence[str]) -> list[str]:
    missing = []
    for package in packages:
        status = output_of(["dpkg-query", "-W", "-f=${Status}", package])
        if status != "install ok installed":
            missing.append(package)
    return missing


def install_packages(packages: Sequence[str]) -> None:
    missing = missing_packages(packages)
    if not missing:
        log.ok(f"All {len(packages)} build packages are installed")
        return
    apt_opts = [
        "-o",
        "Acquire::Retries=3",
        "-o",
        "Acquire::http::Timeout=30",
        "-o",
        "Acquire::https::Timeout=30",
    ]
    env = build_env(DEBIAN_FRONTEND="noninteractive")
    try:
        update = run(
            as_root(["apt", *apt_opts, "update"]), env=env, check=False, timeout=600
        )
        if update.returncode != 0:
            log.warning("apt update failed; installing from the cached package indexes")
    except subprocess.TimeoutExpired:
        log.warning(
            "apt update exceeded 10 minutes; installing from the cached package indexes"
        )
    run(as_root(["apt", *apt_opts, "install", "-y", *missing]), env=env)


class SudoKeepalive:
    """Refresh the sudo timestamp in the background during the long build."""

    def __init__(self) -> None:
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self, *, needed: bool) -> None:
        if os.geteuid() == 0 or not needed:
            return
        cached = (
            subprocess.run(
                ["sudo", "-n", "true"], capture_output=True, check=False
            ).returncode
            == 0
        )
        if not cached:
            log.info(
                "sudo is needed for apt and the install; asking now so the build is not interrupted later"
            )
            run(["sudo", "-v"])
        self._thread = threading.Thread(target=self._refresh, daemon=True)
        self._thread.start()

    def _refresh(self) -> None:
        while not self._stop.wait(60):
            subprocess.run(["sudo", "-n", "-v"], capture_output=True, check=False)

    def stop(self) -> None:
        self._stop.set()


# ─── Build plan ──────────────────────────────────────────────────────────────


def common_args(tools: Tools, *, tests: bool = False) -> list[str]:
    return [
        "-DCMAKE_BUILD_TYPE=Release",
        f"-DPython3_EXECUTABLE={tools.python}",
        "-DLLVM_ENABLE_ASSERTIONS=OFF",
        f"-DLLVM_INCLUDE_TESTS={'ON' if tests else 'OFF'}",
        "-DLLVM_INCLUDE_EXAMPLES=OFF",
        "-DLLVM_INCLUDE_BENCHMARKS=OFF",
        "-DLLVM_INCLUDE_DOCS=OFF",
        "-DLLVM_ENABLE_ZLIB=FORCE_ON",
        "-DLLVM_ENABLE_ZSTD=FORCE_ON",
    ]


def compiler_args(cc: Path, cxx: Path) -> list[str]:
    return [f"-DCMAKE_C_COMPILER={cc}", f"-DCMAKE_CXX_COMPILER={cxx}"]


def bitcode_tool_args(stage1_bin: Path) -> list[str]:
    """ThinLTO stages archive bitcode, which only LLVM's own binutils index."""
    return [
        f"-DCMAKE_AR={stage1_bin / 'llvm-ar'}",
        f"-DCMAKE_RANLIB={stage1_bin / 'llvm-ranlib'}",
        f"-DCMAKE_NM={stage1_bin / 'llvm-nm'}",
    ]


def build_plan(
    *,
    source: Path,
    work: Path,
    tools: Tools,
    host: Host,
    compiler: HostCompiler,
    cpu: str,
    dest: Path,
    ccache: bool,
) -> tuple[list[Stage], Path]:
    llvm_src = source / "llvm"
    stage1 = work / "stage1"
    instrumented = work / "instrumented"
    training = work / "training"
    final = work / "final"
    profdata = work / "clang.profdata"
    stage1_bin = stage1 / "bin"
    instrumented_bin = instrumented / "bin"
    link_jobs = max(1, int(host.mem_avail_gib // RAM_GIB_PER_LINK_JOB))
    march = f"-march={cpu}"
    # ccache hashes -fprofile-generate paths and -fprofile-instr-use file
    # contents, so it is safe for every stage except training, whose purpose
    # is to run the instrumented compiler; cache hits there would skip the
    # very compilations that record the profile.
    cached = [f"-DLLVM_CCACHE_BUILD={'ON' if ccache else 'OFF'}"]

    stages = [
        Stage(
            "stage1",
            "stage1 compiler (host clang builds clang, lld and the profile runtime)",
            llvm_src,
            stage1,
            compiler_args(compiler.cc, compiler.cxx)
            + common_args(tools)
            + cached
            + [
                "-DLLVM_ENABLE_PROJECTS=clang;lld",
                "-DLLVM_ENABLE_RUNTIMES=compiler-rt",
                f"-DLLVM_TARGETS_TO_BUILD={host.llvm_target}",
                "-DLLVM_USE_LINKER=lld",
                f"-DLLVM_PARALLEL_LINK_JOBS={link_jobs}",
                # Only the profile runtime and builtins are needed from stage1.
                "-DCOMPILER_RT_BUILD_SANITIZERS=OFF",
                "-DCOMPILER_RT_BUILD_XRAY=OFF",
                "-DCOMPILER_RT_BUILD_LIBFUZZER=OFF",
                "-DCOMPILER_RT_BUILD_MEMPROF=OFF",
                "-DCOMPILER_RT_BUILD_ORC=OFF",
                "-DCOMPILER_RT_BUILD_GWP_ASAN=OFF",
                "-DCOMPILER_RT_BUILD_CTX_PROFILE=OFF",
            ],
            [
                "clang",
                "lld",
                "llvm-profdata",
                "llvm-ar",
                "llvm-ranlib",
                "llvm-nm",
                "builtins",
                "runtimes",
            ],
        ),
        Stage(
            "instrumented",
            "instrumented compiler (IR PGO instrumentation, ThinLTO, host CPU flags)",
            llvm_src,
            instrumented,
            compiler_args(stage1_bin / "clang", stage1_bin / "clang++")
            + common_args(tools)
            + cached
            + bitcode_tool_args(stage1_bin)
            + [
                "-DLLVM_ENABLE_PROJECTS=clang;lld",
                f"-DLLVM_TARGETS_TO_BUILD={host.llvm_target}",
                "-DLLVM_BUILD_INSTRUMENTED=IR",
                "-DLLVM_BUILD_RUNTIME=No",
                "-DLLVM_ENABLE_LTO=Thin",
                "-DLLVM_USE_LINKER=lld",
                f"-DCMAKE_C_FLAGS={march}",
                f"-DCMAKE_CXX_FLAGS={march}",
            ],
            ["clang", "lld"],
        ),
        Stage(
            "training",
            "profile training (instrumented toolchain builds LLVM, Clang and lld)",
            llvm_src,
            training,
            compiler_args(instrumented_bin / "clang", instrumented_bin / "clang++")
            + common_args(tools)
            + ["-DLLVM_CCACHE_BUILD=OFF"]
            + [
                "-DLLVM_ENABLE_PROJECTS=clang;lld",
                f"-DLLVM_TARGETS_TO_BUILD={host.llvm_target}",
                "-DLLVM_USE_LINKER=lld",
                f"-DLLVM_PARALLEL_LINK_JOBS={link_jobs}",
            ],
        ),
    ]

    targets = [host.llvm_target]
    final_args = (
        compiler_args(stage1_bin / "clang", stage1_bin / "clang++")
        # Tests are configured so --run-tests never forces a rebuild; ninja
        # builds them only for the check-* targets.
        + common_args(tools, tests=True)
        + cached
        + bitcode_tool_args(stage1_bin)
        + [
            f"-DCMAKE_INSTALL_PREFIX={dest}",
            f"-DLLVM_ENABLE_PROJECTS={FINAL_PROJECTS}",
            f"-DLLVM_ENABLE_RUNTIMES={HOST_RUNTIMES}",
            "-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON",
            "-DLLVM_ENABLE_LTO=Thin",
            "-DLLVM_USE_LINKER=lld",
            f"-DLLVM_PROFDATA_FILE={profdata}",
            f"-DCMAKE_C_FLAGS={march}",
            f"-DCMAKE_CXX_FLAGS={march}",
            f"-DCMAKE_EXE_LINKER_FLAGS={BOLT_LINKER_FLAGS}",
            f"-DCMAKE_SHARED_LINKER_FLAGS={BOLT_LINKER_FLAGS}",
            "-DCLANG_BOLT=INSTRUMENT",
            # With LTO the LLVM and Clang static archives would hold bitcode, so
            # install only the toolchain (BuildingADistribution.html).
            "-DLLVM_INSTALL_TOOLCHAIN_ONLY=ON",
            "-DLLVM_ENABLE_LIBXML2=FORCE_ON",
            "-DLLDB_ENABLE_PYTHON=ON",
            "-DLLDB_ENABLE_SWIG=ON",
            "-DLLDB_ENABLE_LIBEDIT=ON",
            "-DLLDB_ENABLE_CURSES=ON",
            "-DLLDB_ENABLE_LZMA=ON",
            "-DLLDB_ENABLE_LIBXML2=ON",
        ]
    )
    if host.gpu:
        targets.append("NVPTX")
        final_args += [
            f"-DLLVM_RUNTIME_TARGETS=default;{NVPTX_TRIPLE}",
            f"-DRUNTIMES_{NVPTX_TRIPLE}_LLVM_ENABLE_RUNTIMES={NVPTX_RUNTIMES}",
            (
                f"-DRUNTIMES_{NVPTX_TRIPLE}_CACHE_FILES="
                f"{source / 'compiler-rt/cmake/caches/NVPTX.cmake'};{source / 'libcxx/cmake/caches/NVPTX.cmake'}"
            ),
            "-DLIBOMPTARGET_PLUGINS_TO_BUILD=cuda;host",
            # Keep LLVM's default of dlopening libcuda (openmp/docs/Building.md).
            # Linking it directly compiles the plugin against the SDK's cuda.h,
            # and CUDA 13 changed cuMemPrefetchAsync to a 5-argument form that
            # LLVM 23's plugin does not call; the dlopen path uses LLVM's own
            # header. Set explicitly so an older cached value cannot linger.
            "-DLIBOMPTARGET_DLOPEN_PLUGINS=cuda",
        ]
    else:
        final_args.append("-DLIBOMPTARGET_PLUGINS_TO_BUILD=host")
    final_args.append(f"-DLLVM_TARGETS_TO_BUILD={';'.join(targets)}")
    stages.append(
        Stage(
            "final",
            "final toolchain (PGO + ThinLTO + host CPU flags, then BOLT on clang)",
            llvm_src,
            final,
            final_args,
        )
    )

    previous = f"revision={PIPELINE_REVISION}"
    for stage in stages:
        # The install prefix only affects `ninja install`, and ccache produces
        # the same objects as the compiler, so neither may discard a finished build.
        relevant = [
            arg
            for arg in stage.cmake_args
            if not arg.startswith(("-DCMAKE_INSTALL_PREFIX=", "-DLLVM_CCACHE_BUILD="))
        ]
        payload = json.dumps([previous, str(stage.source), relevant, stage.targets])
        stage.fingerprint = hashlib.sha256(payload.encode()).hexdigest()
        previous = stage.fingerprint
    return stages, profdata


# ─── Build execution ─────────────────────────────────────────────────────────


def stream_build(
    cmd: Sequence[str | Path], *, env: dict[str, str], log_path: Path, label: str
) -> None:
    """Run a build step with output in the log file and a progress line on screen."""
    argv = [str(a) for a in cmd]
    log.command(argv)
    tail: collections.deque[str] = collections.deque(maxlen=60)
    started = time.monotonic()
    last_update = 0.0
    with log_path.open("a") as log_file:
        log_file.write(f"\n$ {shlex.join(argv)}\n")
        log_file.flush()
        process = subprocess.Popen(
            argv,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            bufsize=1,
        )
        assert process.stdout is not None
        try:
            for line in process.stdout:
                log_file.write(line)
                tail.append(line.rstrip("\n"))
                match = NINJA_PROGRESS_RE.match(line)
                now = time.monotonic()
                if match and now - last_update >= (1 if sys.stdout.isatty() else 60):
                    last_update = now
                    done, total = int(match[1]), int(match[2])
                    log.progress(
                        f"[INFO] {label}: {done}/{total} ({100 * done // max(total, 1)}%) "
                        f"after {format_duration(now - started)}"
                    )
        except BaseException:
            process.kill()
            process.wait()
            raise
        returncode = process.wait()
    log.end_progress()
    if returncode != 0:
        print("\n".join(tail), file=sys.stderr)
        raise InstallError(
            f"{label} failed with exit {returncode}; full log: {log_path}"
        )
    log.ok(f"{label} finished in {format_duration(time.monotonic() - started)}")


def run_stage(
    stage: Stage,
    *,
    tools: Tools,
    work: Path,
    jobs: int,
    log_path: Path,
    on_fresh_configure: Callable[[], None] | None = None,
) -> float:
    """Configure and build one stage unless its stamp shows it is already done."""
    done = stage.build / STAMP_DONE
    if done.is_file() and done.read_text() == stage.fingerprint:
        log.info(f"{stage.name}: already built with this configuration, skipping")
        return 0.0
    started = time.monotonic()
    configured = stage.build / STAMP_CONFIG
    if stage.build.exists() and not (
        configured.is_file() and configured.read_text() == stage.fingerprint
    ):
        log.info(f"{stage.name}: configuration changed, discarding the old build tree")
        remove_tree(stage.build, inside=work)
    fresh = not stage.build.exists()
    stage.build.mkdir(parents=True, exist_ok=True)
    if fresh and on_fresh_configure is not None:
        on_fresh_configure()
    env = build_env()
    stream_build(
        [
            tools.cmake,
            "-G",
            "Ninja",
            "-S",
            stage.source,
            "-B",
            stage.build,
            f"-DCMAKE_MAKE_PROGRAM={tools.ninja}",
            *stage.cmake_args,
        ],
        env=env,
        log_path=log_path,
        label=f"{stage.name} configure",
    )
    configured.write_text(stage.fingerprint)
    stream_build(
        [tools.ninja, "-C", stage.build, "-j", str(jobs), *stage.targets],
        env=env,
        log_path=log_path,
        label=f"{stage.name} build",
    )
    done.write_text(stage.fingerprint)
    return time.monotonic() - started


def merge_profiles(
    stage1: Path, instrumented: Path, profdata: Path, fingerprint: str
) -> None:
    stamp = profdata.with_suffix(".fingerprint")
    if profdata.is_file() and stamp.is_file() and stamp.read_text() == fingerprint:
        log.info("Merged profile is current, skipping")
        return
    raw = sorted((instrumented / "profiles").glob("*.profraw"))
    if not raw:
        raise InstallError(
            f"training produced no .profraw files in {instrumented / 'profiles'}"
        )
    llvm_profdata = stage1 / "bin" / "llvm-profdata"
    run([llvm_profdata, "merge", f"-output={profdata}", *raw], env=build_env())
    summary = output_of([llvm_profdata, "show", profdata]) or ""
    functions = re.search(r"Total functions: (\d+)", summary)
    log.ok(
        f"Merged {len(raw)} raw profile(s)"
        + (f" covering {int(functions[1]):,} functions" if functions else "")
    )
    stamp.write_text(fingerprint)


def check_runtime_flags(final: Path, march: str) -> None:
    """The host-CPU flag must stay out of runtimes that user programs link."""
    caches = sorted((final / "runtimes").glob("*-bins/CMakeCache.txt"))
    if not caches:
        raise InstallError(f"no runtimes build caches found under {final / 'runtimes'}")
    for cache in caches:
        for line in cache.read_text(errors="replace").splitlines():
            if re.match(r"CMAKE_(C|CXX|ASM)_FLAGS(_RELEASE)?:", line) and march in line:
                raise InstallError(f"{march} leaked into {cache}: {line}")
    log.ok(
        f"{march} is absent from all {len(caches)} runtimes build caches, so the runtimes stay portable"
    )


# ─── Smoke tests ─────────────────────────────────────────────────────────────

C_HELLO = '#include <stdio.h>\nint main(void) { puts("smoke-c-ok"); return 0; }\n'
CXX_HELLO = textwrap.dedent("""\
    #include <iostream>
    #include <string>
    #include <vector>
    int main() {
      std::vector<std::string> parts{"smoke", "cxx", "ok"};
      std::string joined;
      for (const auto &part : parts) joined += (joined.empty() ? "" : "-") + part;
      std::cout << joined << "\\n";
    }
    """)
OPENMP_HOST = textwrap.dedent("""\
    #include <omp.h>
    #include <stdio.h>
    int main(void) {
      long sum = 0;
    #pragma omp parallel for reduction(+ : sum)
      for (long i = 1; i <= 1000000; ++i) sum += i;
      printf("smoke-openmp-ok threads=%d\\n", omp_get_max_threads());
      return sum == 500000500000L ? 0 : 1;
    }
    """)
ASAN_OVERFLOW = textwrap.dedent("""\
    #include <stdlib.h>
    int main(void) {
      volatile char *p = malloc(8);
      p[8] = 1;
      free((void *)p);
      return 0;
    }
    """)
OPENMP_OFFLOAD = textwrap.dedent("""\
    #include <omp.h>
    #include <stdio.h>
    int main(void) {
      int on_host = 1;
      long sum = 0;
    #pragma omp target map(from : on_host)
      { on_host = omp_is_initial_device(); }
    #pragma omp target teams distribute parallel for reduction(+ : sum) map(tofrom : sum)
      for (long i = 1; i <= 1000000; ++i) sum += i;
      printf("smoke-offload %s sum=%ld\\n", on_host ? "host" : "gpu", sum);
      return (!on_host && sum == 500000500000L) ? 0 : 1;
    }
    """)
CUDA_KERNEL = textwrap.dedent("""\
    #include <cstdio>
    __global__ void square(int *v, int n) {
      int i = blockIdx.x * blockDim.x + threadIdx.x;
      if (i < n) v[i] *= v[i];
    }
    int main() {
      const int n = 256;
      int host[n];
      for (int i = 0; i < n; ++i) host[i] = i;
      int *dev = nullptr;
      if (cudaMalloc(&dev, sizeof host) != cudaSuccess) return 2;
      cudaMemcpy(dev, host, sizeof host, cudaMemcpyHostToDevice);
      square<<<(n + 127) / 128, 128>>>(dev, n);
      cudaMemcpy(host, dev, sizeof host, cudaMemcpyDeviceToHost);
      cudaFree(dev);
      for (int i = 0; i < n; ++i)
        if (host[i] != i * i) return 1;
      std::puts("smoke-cuda-ok");
      return 0;
    }
    """)


def smoke_test(root: Path, release: Release, host: Host, scratch_parent: Path) -> None:
    """Exercise the staged toolchain end to end before anything is promoted."""
    bin_dir = root / "bin"
    env = build_env()
    clang, clangxx = bin_dir / "clang", bin_dir / "clang++"
    version_text = output_of([clang, "--version"], env=env) or ""
    if f"clang version {release.version_str}" not in version_text:
        raise InstallError(
            f"staged clang reports {version_text.splitlines()[:1]}, "
            f"expected {release.version_str}"
        )
    log.ok(version_text.splitlines()[0])
    triple = output_of([clang, "-print-target-triple"], env=env) or ""
    runtime_dir = root / "lib" / triple
    rpath = f"-Wl,-rpath,{runtime_dir}"

    passed: list[str] = []
    with tempfile.TemporaryDirectory(dir=scratch_parent, prefix="smoke-") as tmp_name:
        tmp = Path(tmp_name)
        (tmp / "hello.c").write_text(C_HELLO)
        (tmp / "hello.cpp").write_text(CXX_HELLO)
        (tmp / "omp.c").write_text(OPENMP_HOST)
        (tmp / "overflow.c").write_text(ASAN_OVERFLOW)

        def build_and_run(
            label: str,
            compile_cmd: list[str | Path],
            expect: str,
            run_env: dict[str, str] | None = None,
        ) -> None:
            run(compile_cmd, env=env, capture=True, cwd=tmp)
            result = subprocess.run(
                [str(tmp / "a.out")],
                env=run_env or env,
                cwd=tmp,
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
            )
            if result.returncode != 0 or expect not in result.stdout:
                raise InstallError(
                    f"smoke test '{label}' failed (exit {result.returncode}): "
                    f"{(result.stdout + result.stderr).strip()[:500]}"
                )
            passed.append(label)

        build_and_run(
            "C, default linker", [clang, "-O2", "hello.c", "-o", "a.out"], "smoke-c-ok"
        )
        build_and_run(
            "C++ with libstdc++",
            [clangxx, "-O2", "hello.cpp", "-o", "a.out"],
            "smoke-cxx-ok",
        )
        build_and_run(
            "C++ with libc++",
            [clangxx, "-O2", "-stdlib=libc++", rpath, "hello.cpp", "-o", "a.out"],
            "smoke-cxx-ok",
        )
        build_and_run(
            "ThinLTO with lld",
            [clangxx, "-O2", "-flto=thin", "-fuse-ld=lld", "hello.cpp", "-o", "a.out"],
            "smoke-cxx-ok",
        )
        build_and_run(
            "OpenMP on the host",
            [clang, "-O2", "-fopenmp", rpath, "omp.c", "-o", "a.out"],
            "smoke-openmp-ok",
            {**env, "OMP_NUM_THREADS": "4"},
        )

        run(
            [clang, "-g", "-fsanitize=address,undefined", "overflow.c", "-o", "a.out"],
            env=env,
            capture=True,
            cwd=tmp,
        )
        asan = subprocess.run(
            [str(tmp / "a.out")],
            env=env,
            cwd=tmp,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        if asan.returncode == 0 or "heap-buffer-overflow" not in asan.stderr:
            raise InstallError(
                "smoke test 'AddressSanitizer' did not report the planted overflow"
            )
        passed.append("AddressSanitizer catches a heap overflow")

        for tool in (
            "clangd",
            "clang-tidy",
            "clang-format",
            "ld.lld",
            "lldb",
            "llvm-bolt",
            "llvm-ar",
            "llvm-profdata",
            "llvm-symbolizer",
        ):
            if output_of([bin_dir / tool, "--version"], env=env) is None:
                raise InstallError(f"smoke test: {tool} --version failed")
        passed.append("tool --version checks")
        lldb_python = output_of(
            [bin_dir / "lldb", "--batch", "-o", "script print(6 * 7)"], env=env
        )
        if not lldb_python or "42" not in lldb_python:
            raise InstallError(
                f"smoke test: LLDB's Python scripting failed: {lldb_python}"
            )
        passed.append("LLDB Python scripting")

        readelf = (
            output_of(
                [bin_dir / "llvm-readelf", "-S", (bin_dir / "clang").resolve()], env=env
            )
            or ""
        )
        if ".note.bolt_info" not in readelf:
            raise InstallError(
                "clang carries no .note.bolt_info section, so BOLT was not applied"
            )
        passed.append("clang is BOLT-optimized")

        if host.gpu:
            gpu_env = {**env, "OMP_TARGET_OFFLOAD": "MANDATORY"}
            cuda_flags = [f"--cuda-path={host.cuda_root}"] if host.cuda_root else []
            (tmp / "offload.c").write_text(OPENMP_OFFLOAD)
            try:
                build_and_run(
                    f"OpenMP offload to {host.gpu.arch}",
                    [
                        clang,
                        "-O2",
                        "-fopenmp",
                        f"--offload-arch={host.gpu.arch}",
                        "-Wno-unknown-cuda-version",
                        *cuda_flags,
                        rpath,
                        "offload.c",
                        "-o",
                        "a.out",
                    ],
                    "smoke-offload gpu",
                    gpu_env,
                )
            except InstallError as exc:
                log.warning(f"GPU offload is not working: {exc}")
            if host.cuda_root:
                (tmp / "square.cu").write_text(CUDA_KERNEL)
                cudart = host.cuda_root / "lib64"
                try:
                    build_and_run(
                        f"CUDA kernel on {host.gpu.arch}",
                        [
                            clangxx,
                            "-O2",
                            "-x",
                            "cuda",
                            f"--offload-arch={host.gpu.arch}",
                            "-Wno-unknown-cuda-version",
                            *cuda_flags,
                            "square.cu",
                            f"-L{cudart}",
                            "-lcudart",
                            f"-Wl,-rpath,{cudart}",
                            "-o",
                            "a.out",
                        ],
                        "smoke-cuda-ok",
                    )
                except InstallError as exc:
                    log.warning(f"CUDA compilation is not working: {exc}")
    for label in passed:
        log.ok(f"smoke test passed: {label}")


# ─── Install, links and alternatives ─────────────────────────────────────────


def read_marker(dest: Path) -> dict[str, Any] | None:
    try:
        data = json.loads((dest / INSTALL_MARKER).read_text())
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) and data.get("path") == str(dest) else None


def promote(staged: Path, dest: Path, release: Release, cpu: str) -> None:
    """Move the tested tree into place, keeping the old one until the new one works."""
    parent = dest.parent
    privileged = not writable(parent)
    wrap = as_root if privileged else (lambda cmd: [str(a) for a in cmd])
    (staged / INSTALL_MARKER).write_text(
        json.dumps(
            {
                "path": str(dest),
                "tag": release.tag,
                "version": release.version_str,
                "march": cpu,
                "installed": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            },
            indent=2,
        )
        + "\n"
    )
    run(wrap(["mkdir", "-p", parent]))
    incoming = parent / f".{dest.name}.incoming"
    previous = parent / f".{dest.name}.previous"
    for leftover in (incoming, previous):
        remove_tree(leftover, inside=parent, privileged=privileged)
    run(wrap(["mv", "-T", staged, incoming]))
    if privileged:
        run(as_root(["chown", "-R", "root:root", incoming]))
    if dest.exists():
        if read_marker(dest) is None:
            raise InstallError(
                f"{dest} exists but was not installed by this script; not replacing it"
            )
        run(wrap(["mv", "-T", dest, previous]))
    run(wrap(["mv", "-T", incoming, dest]))
    installed = output_of([dest / "bin" / "clang", "--version"])
    if not installed or f"clang version {release.version_str}" not in installed:
        run(wrap(["mv", "-T", dest, incoming]))
        restored = previous.exists()
        if restored:
            run(wrap(["mv", "-T", previous, dest]))
        raise InstallError(
            f"installed clang at {dest} does not run; the new tree was moved to {incoming} "
            + ("and the previous install was restored" if restored else "")
        )
    remove_tree(previous, inside=parent, privileged=privileged)
    log.ok(f"Installed LLVM {release.version_str} to {dest}")


def points_into(link: Path, root: Path) -> bool:
    try:
        target = os.readlink(link)
    except OSError:
        return False
    return target.startswith(str(root) + "/")


def link_tools(dest: Path, link_dir: Path, prefix_root: Path, major: int) -> int:
    """Create versioned links (clang-23, clang++-23, ld.lld-23, ...) in link_dir."""
    suffix = f"-{major}"
    wanted: dict[str, Path] = {}
    for tool in sorted((dest / "bin").iterdir()):
        if tool.is_file() and os.access(tool, os.X_OK):
            wanted.setdefault(
                tool.name if tool.name.endswith(suffix) else tool.name + suffix, tool
            )
    script = ["set -e"]
    if link_dir.is_dir():
        for existing in sorted(link_dir.iterdir()):
            if (
                existing.name.endswith(suffix)
                and existing.is_symlink()
                and points_into(existing, prefix_root)
                and existing.name not in wanted
            ):
                script.append(shlex.join(["rm", "-f", "--", str(existing)]))
    skipped = []
    for name, target in wanted.items():
        link = link_dir / name
        if (link.exists() or link.is_symlink()) and not points_into(link, prefix_root):
            skipped.append(name)
            continue
        script.append(shlex.join(["ln", "-sfn", str(target), str(link)]))
    if skipped:
        log.warning(
            f"Left {len(skipped)} existing file(s) in {link_dir} alone: {', '.join(skipped)}"
        )
    cmd = [
        "sh",
        "-c",
        "mkdir -p " + shlex.quote(str(link_dir)) + "\n" + "\n".join(script),
    ]
    log.info(f"Linking {len(wanted)} tools into {link_dir} with the {suffix} suffix")
    subprocess.run(as_root(cmd) if not writable(link_dir) else cmd, check=True)
    return len(wanted)


@dataclass
class AlternativesGroup:
    link: str | None = None
    slaves: dict[str, str] = field(default_factory=dict)
    alternatives: list[str] = field(default_factory=list)


def query_alternatives(name: str) -> AlternativesGroup | None:
    text = output_of(["update-alternatives", "--query", name])
    if text is None:
        return None
    info = AlternativesGroup()
    section = None
    for line in text.splitlines():
        if line.startswith("Link: "):
            info.link = line[6:].strip()
        elif line.startswith("Slaves:"):
            section = "slaves"
        elif line.startswith("Alternative: "):
            info.alternatives.append(line[13:].strip())
            section = None
        elif section == "slaves" and line.startswith(" "):
            slave_name, _, slave_link = line.strip().partition(" ")
            info.slaves[slave_name] = slave_link.strip()
        elif not line.startswith(" "):
            section = None
    return info


def register_alternatives(dest: Path, major: int, select: bool) -> str:
    """Add this install to the clang alternatives group, reusing the group's link layout."""
    group = query_alternatives("clang")
    master_link = Path("/usr/bin/clang")
    if group is None and (master_link.exists() or master_link.is_symlink()):
        log.warning(
            f"{master_link} is not managed by update-alternatives; leaving the default clang alone"
        )
        return "not registered"
    link = group.link if group and group.link else str(master_link)
    slaves = group.slaves if group and group.slaves else {"clang++": "/usr/bin/clang++"}
    master = dest / "bin" / "clang"
    cmd = [
        "update-alternatives",
        "--install",
        link,
        "clang",
        str(master),
        str(major * 10),
    ]
    for slave_name, slave_link in slaves.items():
        if (dest / "bin" / slave_name).exists():
            cmd += ["--slave", slave_link, slave_name, str(dest / "bin" / slave_name)]
    run(as_root(cmd))
    if not select:
        return "registered, not selected"
    run(as_root(["update-alternatives", "--set", "clang", str(master)]))
    return f"selected as the default clang ({link})"


# ─── Commands ────────────────────────────────────────────────────────────────


def uninstall(version: str, prefix_root: Path, link_dir: Path) -> int:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise InstallError(f"--uninstall expects X.Y.Z, got {version!r}")
    dest = prefix_root / version
    if read_marker(dest) is None:
        raise InstallError(f"{dest} is not an install made by this script")
    group = query_alternatives("clang")
    if group and str(dest / "bin" / "clang") in group.alternatives:
        run(
            as_root(
                [
                    "update-alternatives",
                    "--remove",
                    "clang",
                    str(dest / "bin" / "clang"),
                ]
            )
        )
    links = (
        [p for p in link_dir.iterdir() if p.is_symlink() and points_into(p, dest)]
        if link_dir.is_dir()
        else []
    )
    if links:
        script = "\n".join(shlex.join(["rm", "-f", "--", str(p)]) for p in links)
        cmd = ["sh", "-c", script]
        subprocess.run(as_root(cmd) if not writable(link_dir) else cmd, check=True)
    remove_tree(dest, inside=prefix_root, privileged=not writable(prefix_root))
    log.ok(f"Removed LLVM {version}, {len(links)} link(s) and its alternatives entry")
    return 0


def lock_holders(lock_path: Path) -> list[int]:
    """PIDs holding an flock on lock_path, read from /proc/locks."""
    st = lock_path.stat()
    holders = []
    with open("/proc/locks") as handle:
        for line in handle:
            fields = line.split()
            # Waiting requests are marked "->"; only granted locks matter.
            if len(fields) < 6 or fields[1] == "->" or fields[1] != "FLOCK":
                continue
            major, minor, inode = fields[5].split(":")
            if (int(major, 16), int(minor, 16), int(inode)) == (
                os.major(st.st_dev),
                os.minor(st.st_dev),
                st.st_ino,
            ):
                holders.append(int(fields[4]))
    return holders


def process_alive(pid: int) -> bool:
    """True while pid exists and is not a zombie."""
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
    except OSError:
        return False
    return stat.rpartition(")")[2].split()[0] != "Z"


def process_tree(pid: int) -> list[int]:
    """pid followed by all of its descendants."""
    tree = [pid]
    for member in tree:
        for task in Path(f"/proc/{member}/task").glob("*"):
            try:
                tree += [
                    int(child) for child in (task / "children").read_text().split()
                ]
            except OSError:
                continue
    return list(dict.fromkeys(tree))


def stop_previous_run(pid: int) -> None:
    """Stop an earlier install_clang.py run and everything it started.

    Its finished stages are stamped and ninja only records completed outputs,
    so the new run resumes where the old one stopped.
    """
    try:
        cmdline = (
            Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode()
        )
    except OSError:
        return  # already gone
    if "install_clang" not in cmdline:
        raise InstallError(
            f"the work directory lock is held by pid {pid} ({cmdline.strip()}), "
            "which is not an install_clang.py run; stop it or use --work-dir"
        )
    tree = process_tree(pid)
    log.warning(
        f"An earlier install_clang.py run (pid {pid}, {len(tree)} processes) still holds "
        "the work directory; stopping it and resuming its finished stages"
    )
    for signal_number, grace in ((signal.SIGTERM, 30.0), (signal.SIGKILL, 10.0)):
        for member in tree:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.kill(member, signal_number)
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            tree = [member for member in tree if process_alive(member)]
            if not tree:
                return
            time.sleep(0.5)
    raise InstallError(f"could not stop the earlier run; still alive: {tree}")


def acquire_lock(cache_root: Path) -> int:
    """Take the work directory lock, stopping a leftover earlier run if needed."""
    cache_root.mkdir(parents=True, exist_ok=True)
    lock_path = cache_root / ".lock"
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o644)
    for _ in range(3):
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except BlockingIOError:
            holders = [pid for pid in lock_holders(lock_path) if pid != os.getpid()]
            if not holders:
                time.sleep(1)  # the holder exited between the two checks
            for pid in holders:
                stop_previous_run(pid)
    os.close(fd)
    raise InstallError(f"could not take the work directory lock {lock_path}")


def finish_existing(dest: Path, release: Release, args: argparse.Namespace) -> int:
    log.ok(
        f"LLVM {release.version_str} is already installed in {dest}; use --force to rebuild it"
    )
    if args.dry_run or args.no_install:
        return 0
    link_tools(dest, args.link_dir, args.prefix_root, release.major)
    if not args.no_alternatives:
        log.info(
            f"clang alternatives: {register_alternatives(dest, release.major, not args.keep_default)}"
        )
    return 0


def offer_cleanup(
    work: Path, args: argparse.Namespace, log_dir: Path, *, default_remove: bool
) -> None:
    """Ask, as the last step of a successful build, whether to delete its build files.

    Only this version's work directory goes: logs stay, and so does the ccache
    cache, which keeps later rebuilds fast.
    """
    if not work.exists():
        return
    usage = output_of(["du", "-s", "--block-size=1", "--one-file-system", work])
    what = f"{work} ({gib(int(usage.split()[0]))})" if usage else str(work)
    if args.keep_work:
        remove = False
    elif args.remove_work:
        remove = True
    elif not sys.stdin.isatty():
        log.info(
            f"Keeping the build files in {what}: there is no terminal to ask "
            "(pass --remove-work to delete them unattended)"
        )
        return
    else:
        log.heading("Cleanup")
        if not default_remove:
            log.info(
                "These files hold the finished build; without them, installing "
                "later means rebuilding from scratch."
            )
        choices = "[Y/n]" if default_remove else "[y/N]"
        while True:
            try:
                answer = input(f"Remove the build files in {what}? {choices} ")
            except EOFError:
                answer = ""
            answer = answer.strip().lower()
            if answer in ("", "y", "yes", "n", "no"):
                break
            print("Please answer y or n.")
        remove = default_remove if not answer else answer.startswith("y")
    if remove:
        remove_tree(work, inside=args.work_dir)
        log.ok(
            f"Removed {what}; the logs stay in {log_dir} and ccache keeps the "
            "compiled objects for faster rebuilds"
        )
    else:
        log.info(f"Kept the build files in {what}")


def install(args: argparse.Namespace) -> int:
    started = time.monotonic()
    log.heading("Finding the newest LLVM release")
    release = fetch_release(args.release)
    log.info(
        f"Selected {release.tag} ({release.asset.name}, {gib(release.asset.size)})"
    )
    dest = args.prefix_root / release.version_str
    if read_marker(dest) and not args.force:
        return finish_existing(dest, release, args)

    log.heading("Inspecting this machine")
    host = detect_host()
    compiler = detect_host_compiler()
    packages = list(APT_PACKAGES)
    packages += (
        [f"clang-{compiler.major}", f"lld-{compiler.major}"]
        if compiler
        else ["clang", "lld"]
    )
    jobs = args.jobs or host.cpus
    log.rows(
        [
            ("CPU threads", str(host.cpus)),
            (
                "memory",
                f"{host.mem_total_gib:.1f} GiB total, {host.mem_avail_gib:.1f} GiB available",
            ),
            (
                "GPU",
                f"{host.gpu.name} ({host.gpu.arch})"
                if host.gpu
                else "none detected (no NVPTX/offload)",
            ),
            ("CUDA SDK", str(host.cuda_root) if host.cuda_root else "not found"),
            (
                "host compiler",
                str(compiler.cc)
                if compiler
                else "none yet (apt clang will be installed)",
            ),
            ("build jobs", str(jobs)),
        ]
    )

    work = args.work_dir / release.version_str
    if args.dry_run:
        missing = missing_packages(packages)
        log.info(f"apt packages to install: {' '.join(missing) if missing else 'none'}")
        if compiler is None:
            log.info(
                "The host compiler and CPU name are resolved after apt installs clang"
            )
            return 0
        tools = pick_tools()
        cpu = args.march or detect_native_cpu(compiler)
        stages, _ = build_plan(
            source=work / "src" / f"llvm-project-{release.version_str}.src",
            work=work,
            tools=tools,
            host=host,
            compiler=compiler,
            cpu=cpu,
            dest=dest,
            ccache=not args.no_ccache,
        )
        for stage in stages:
            log.heading(f"Stage {stage.name}: {stage.title}")
            print(
                shlex.join(
                    [
                        str(tools.cmake),
                        "-G",
                        "Ninja",
                        "-S",
                        str(stage.source),
                        "-B",
                        str(stage.build),
                        *stage.cmake_args,
                    ]
                )
            )
            print(
                shlex.join(
                    [
                        str(tools.ninja),
                        "-C",
                        str(stage.build),
                        "-j",
                        str(jobs),
                        *stage.targets,
                    ]
                )
            )
        return 0

    lock_fd = acquire_lock(args.work_dir)
    keepalive = SudoKeepalive()
    try:
        will_install = not args.no_install and (
            not args.no_alternatives
            or not writable(args.prefix_root)
            or not writable(args.link_dir)
        )
        keepalive.start(needed=will_install or bool(missing_packages(packages)))
        log.heading("Installing build dependencies with apt")
        install_packages(packages)
        compiler = compiler or detect_host_compiler()
        if compiler is None:
            raise InstallError("apt installed clang, but no /usr/bin/clang-N was found")
        tools = pick_tools()
        cpu = args.march or detect_native_cpu(compiler)
        log.rows(
            [
                ("cmake", str(tools.cmake)),
                ("ninja", str(tools.ninja)),
                ("python", str(tools.python)),
                ("host clang", f"{compiler.cc} / {compiler.cxx}"),
                ("tuned for", f"-march={cpu}"),
            ]
        )

        work.mkdir(parents=True, exist_ok=True)
        free = free_bytes(work)
        if free < args.min_free_gib * 2**30:
            raise InstallError(
                f"{work} has {gib(free)} free; the build needs about "
                f"{args.min_free_gib} GiB (override with --min-free-gib)"
            )
        log_dir = args.work_dir / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = (
            log_dir / f"llvm-{release.version_str}-{time.strftime('%Y%m%d-%H%M%S')}.log"
        )
        log.info(f"Full build output goes to {log_path}")

        log.heading(f"Fetching llvm-project {release.version_str}")
        archive = download(release.asset, work)
        source = extract_source(archive, release, work)

        stages, profdata = build_plan(
            source=source,
            work=work,
            tools=tools,
            host=host,
            compiler=compiler,
            cpu=cpu,
            dest=dest,
            ccache=not args.no_ccache,
        )
        durations: list[tuple[str, str]] = []
        by_name = {stage.name: stage for stage in stages}

        def clear_profiles() -> None:
            profiles = by_name["instrumented"].build / "profiles"
            for raw in profiles.glob("*.profraw"):
                raw.unlink()

        for stage in stages:
            log.heading(f"Building {stage.name} - LLVM {release.version_str}")
            log.info(stage.title)
            if stage.name == "final":
                merge_profiles(
                    by_name["stage1"].build,
                    by_name["instrumented"].build,
                    profdata,
                    by_name["training"].fingerprint,
                )
            elapsed = run_stage(
                stage,
                tools=tools,
                work=work,
                jobs=jobs,
                log_path=log_path,
                on_fresh_configure=clear_profiles if stage.name == "training" else None,
            )
            durations.append(
                (stage.name, format_duration(elapsed) if elapsed else "reused")
            )

        final = by_name["final"].build
        check_runtime_flags(final, f"-march={cpu}")
        if args.run_tests:
            log.heading(f"Testing LLVM {release.version_str} (check-clang, check-lld)")
            stream_build(
                [tools.ninja, "-C", final, "-j", str(jobs), "check-clang", "check-lld"],
                env=build_env(),
                log_path=log_path,
                label="check-clang and check-lld",
            )

        log.heading(f"Staging and testing LLVM {release.version_str}")
        destdir = work / "destdir"
        remove_tree(destdir, inside=work)
        stream_build(
            [tools.ninja, "-C", final, "install"],
            env=build_env(DESTDIR=str(destdir)),
            log_path=log_path,
            label="staged install",
        )
        staged = destdir / dest.relative_to("/")
        smoke_test(staged, release, host, work)

        if args.no_install:
            log.ok(
                f"Built and tested; the staged toolchain is in {staged} (--no-install)"
            )
            offer_cleanup(work, args, log_dir, default_remove=False)
            return 0

        log.heading(f"Installing LLVM {release.version_str}")
        promote(staged, dest, release, cpu)
        linked = link_tools(dest, args.link_dir, args.prefix_root, release.major)
        alternatives = "skipped (--no-alternatives)"
        if not args.no_alternatives:
            alternatives = register_alternatives(
                dest, release.major, not args.keep_default
            )

        log.heading("Summary")
        log.rows(
            [
                (
                    "version",
                    f"{release.tag} built with PGO, ThinLTO, BOLT and -march={cpu}",
                ),
                ("installed to", str(dest)),
                (
                    "links",
                    f"{linked} tools in {args.link_dir} (clang-{release.major}, clang++-{release.major}, ...)",
                ),
                ("alternatives", alternatives),
                *[(f"stage {name}", took) for name, took in durations],
                ("total time", format_duration(time.monotonic() - started)),
                ("build log", str(log_path)),
            ]
        )
        for warning in log.warnings:
            log.warning(f"(repeated) {warning}")
        offer_cleanup(work, args, log_dir, default_remove=True)
        return 0
    finally:
        keepalive.stop()
        os.close(lock_fd)


# fmt: off
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

    def __init__(self, *args, title: str, version: str = '', examples=(), **kwargs):
        super().__init__(*args, add_help=False, **kwargs)
        self.help_title = title
        self.help_version = version
        self.help_examples = examples

    def _positional_usage(self) -> list[str]:
        parts = []
        for action in self._actions:
            if action.option_strings or action.help == argparse.SUPPRESS:
                continue
            name = action.metavar or action.dest.upper()
            parts.append({'?': f'[{name}]', '*': f'[{name} ...]', '+': f'{name} ...'}.get(action.nargs, name))
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
            (group.title, [a for a in group._group_actions
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
                metavar = action.metavar or action.dest.upper()
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
            lines = textwrap.wrap(body, text_width) or ['']
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
            out += textwrap.wrap(self.description, width)

        out += heading("Usage")
        out.append(' '.join([f"  {paint(self.prog, 'bold')}", paint('[OPTIONS]', 'flag'),
                             *(paint(p, 'value') for p in self._positional_usage())]))
        for action in self._actions:
            if not action.option_strings and action.help != argparse.SUPPRESS:
                name = action.metavar or action.dest.upper()
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
# fmt: on


# (what it does, arguments after the program name)
HELP_EXAMPLES = [
    ("Build and install the newest release, tuned for this machine", ""),
    (
        "Show the detected hardware and every stage's CMake command, then exit",
        "--dry-run",
    ),
    ("Build and smoke-test only; install later with a plain rerun", "--no-install"),
    (
        "Build a specific release and run clang and lld's test suites",
        "--release 23.1.2 --run-tests",
    ),
    ("Install without making it the default clang", "--keep-default"),
    ("Remove an install made by this script", "--uninstall 23.1.2"),
]


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = HelpParser(
        prog=Path(sys.argv[0]).name,
        title="LLVM/Clang source installer",
        description=(
            "Build the newest LLVM release from source with LLVM's documented PGO, ThinLTO and "
            "BOLT recipe, tuned for this CPU and GPU, then install it under /opt/llvm/<version> "
            "with versioned links and a clang alternatives entry. Run without sudo; the script "
            "asks for it once and uses it only for apt and the install."
        ),
        examples=HELP_EXAMPLES,
    )
    build = parser.add_argument_group("Build")
    build.add_argument(
        "--release",
        metavar="X.Y.Z",
        help="Build this release instead of the newest stable one",
    )
    build.add_argument(
        "--jobs",
        type=int,
        metavar="N",
        help="Parallel build jobs (default: all CPU threads)",
    )
    build.add_argument(
        "--march",
        metavar="CPU",
        help="CPU to tune the compiler binaries for (default: what -march=native resolves to)",
    )
    build.add_argument(
        "--no-ccache",
        action="store_true",
        help="Compile without ccache (it is used for every stage except profile training)",
    )
    build.add_argument(
        "--run-tests",
        action="store_true",
        help="Build and run check-clang and check-lld before installing",
    )
    build.add_argument(
        "--work-dir",
        type=Path,
        default=DEFAULT_CACHE_ROOT,
        metavar="DIR",
        help="Where sources, build trees and logs go (default: %(default)s)",
    )
    build.add_argument(
        "--min-free-gib",
        type=int,
        default=80,
        metavar="GIB",
        help="Free space the work directory must have (default: %(default)s)",
    )
    build.add_argument(
        "--keep-work",
        action="store_true",
        help="Keep the build files after a successful build without asking",
    )
    build.add_argument(
        "--remove-work",
        action="store_true",
        help="Delete the build files after a successful build without asking",
    )
    build.add_argument(
        "--force",
        action="store_true",
        help="Rebuild and reinstall even if this version is already installed",
    )
    install_group = parser.add_argument_group("Install")
    install_group.add_argument(
        "--prefix-root",
        type=Path,
        default=DEFAULT_PREFIX_ROOT,
        metavar="DIR",
        help="Install to DIR/<version> (default: %(default)s)",
    )
    install_group.add_argument(
        "--link-dir",
        type=Path,
        default=DEFAULT_LINK_DIR,
        metavar="DIR",
        help="Where the versioned tool links go (default: %(default)s)",
    )
    install_group.add_argument(
        "--keep-default",
        action="store_true",
        help="Register with update-alternatives but leave the current default clang selected",
    )
    install_group.add_argument(
        "--no-alternatives",
        action="store_true",
        help="Do not touch the clang update-alternatives group",
    )
    install_group.add_argument(
        "--no-install",
        action="store_true",
        help="Build and smoke-test only; keep the staged tree in the work directory",
    )
    install_group.add_argument(
        "--uninstall",
        metavar="X.Y.Z",
        help="Remove an install made by this script, its links and alternatives entry",
    )
    general = parser.add_argument_group("General")
    general.add_argument(
        "--dry-run",
        action="store_true",
        help="Show the hardware, apt packages and every stage's CMake command, then exit",
    )
    general.add_argument("--no-color", action="store_true", help="Disable colored help")
    general.add_argument("-h", "--help", action="help", help="Show this help and exit")
    args = parser.parse_args(argv)
    if args.jobs is not None and args.jobs < 1:
        parser.error("--jobs must be at least 1")
    if args.keep_work and args.remove_work:
        parser.error("--keep-work and --remove-work cannot be combined")
    args.prefix_root = args.prefix_root.absolute()
    args.link_dir = args.link_dir.absolute()
    args.work_dir = args.work_dir.expanduser().absolute()
    return args


def main() -> int:
    if sys.version_info < (3, 12):
        print(
            "install_clang.py needs Python 3.12+ (tarfile extraction filters).",
            file=sys.stderr,
        )
        return 2
    args = parse_args()
    if sys.platform != "linux" or shutil.which("dpkg-query") is None:
        log.error("This script supports Debian/Ubuntu Linux only.")
        return 2
    try:
        if args.uninstall:
            return uninstall(args.uninstall, args.prefix_root, args.link_dir)
        return install(args)
    except InstallError as exc:
        log.error(str(exc))
        return 1
    except KeyboardInterrupt:
        log.end_progress()
        log.error("Interrupted. Finished stages are stamped; rerun to resume.")
        return 130


if __name__ == "__main__":
    sys.exit(main())
