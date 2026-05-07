#!/usr/bin/env python3
"""
TurboQuant llama.cpp Automated Builder
=======================================
Automates the full installation and build of TurboQuant KV cache compression
for llama.cpp from TheTom's fork.

Target system:
  - Arch Linux (also supports Debian/Ubuntu)
  - AMD Ryzen 7900X (24 threads)
  - NVIDIA RTX 4090 (sm_89, CUDA)

Prerequisites:
  - Miniconda3 installed at ~/miniconda3/
  - Conda env 'turboquant' with Python 3.12 (script checks & gives instructions)
  - PyTorch cu128 wheels (script installs into conda env)

Source: https://github.com/TheTom/llama-cpp-turboquant
Branch: feature/turboquant-kv-cache
Paper:  TurboQuant (ICLR 2026) — Google Research + NYU

First-time setup (if conda env does not exist yet):
  conda create -n turboquant python=3.12 -y
  conda activate turboquant
  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
  python3 build_turboquant.py

Usage:
  python3 build_turboquant.py              # Full install + build
  python3 build_turboquant.py --deps-only  # Install dependencies only
  python3 build_turboquant.py --build-only # Build only (skip deps + pip)
  python3 build_turboquant.py --clean      # Nuke build dir and rebuild
  python3 build_turboquant.py --run        # Build + launch server
  python3 build_turboquant.py --run --model /path/to/model.gguf
  python3 build_turboquant.py --uninstall  # Remove from /usr/local/bin
"""

import argparse
import json
import logging
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from enum import Enum, auto
from pathlib import Path
from typing import Optional

# ─── Constants ───────────────────────────────────────────────────────────────

REPO_URL = "https://github.com/TheTom/llama-cpp-turboquant.git"
BRANCH = "feature/turboquant-kv-cache"
CUDA_ARCH_RTX4090 = "89"  # sm_89 Ada Lovelace
BUILD_THREADS = os.cpu_count() or 24
DEFAULT_INSTALL_DIR = Path.home() / "turboquant-llama"
BUILD_DIR_NAME = "build"
INSTALL_BIN_DIR = Path("/usr/local/bin")

# Only these binaries get installed to /usr/local/bin — everything else stays in build/
ESSENTIAL_BINARIES = [
    "llama-server",     # OpenAI-compatible API server (primary)
    "llama-cli",        # Interactive CLI inference
]

# ─── Conda + PyTorch cu128 ───────────────────────────────────────────────────

CONDA_BASE = Path.home() / "miniconda3"
CONDA_ENV_NAME = "turboquant"
CONDA_PYTHON_VERSION = "3.12"
PYTORCH_INDEX_URL = "https://download.pytorch.org/whl/cu128"

# Python packages installed into the conda env
PYTHON_PACKAGES = [
    # PyTorch cu128 — installed separately via --index-url
]
PYTHON_PACKAGES_EXTRA = [
    # TurboQuant ecosystem (pip, normal index)
    "turboquant",            # HuggingFace drop-in KV cache compression
    "turboquant-torch",      # Reference PyTorch implementation
    "huggingface-hub",       # huggingface-cli for model downloads
    "transformers",          # HuggingFace transformers
    "numpy",
    "scipy",
]

# CUDA versions known to cause problems
CUDA_BLACKLIST = ["13.1"]  # MMQ kernel segfaults

# Minimum CUDA version for reliable FA + turbo kernels
CUDA_MIN_VERSION = "12.2"

LOG_FMT = "%(asctime)s [%(levelname)s] %(message)s"
LOG_DATE = "%H:%M:%S"


class Distro(Enum):
    ARCH = auto()
    DEBIAN = auto()
    UNKNOWN = auto()


@dataclass
class SystemInfo:
    distro: Distro = Distro.UNKNOWN
    distro_name: str = ""
    kernel: str = ""
    cpu_model: str = ""
    cpu_threads: int = 0
    gpu_name: str = ""
    gpu_arch: str = ""
    cuda_version: str = ""
    cuda_path: str = ""
    cmake_version: str = ""
    git_version: str = ""
    has_nvidia_smi: bool = False
    warnings: list = field(default_factory=list)
    errors: list = field(default_factory=list)


# ─── Logging ─────────────────────────────────────────────────────────────────

def setup_logging(verbose: bool = False):
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format=LOG_FMT, datefmt=LOG_DATE)
    return logging.getLogger("turboquant-builder")


# ─── Shell helpers ───────────────────────────────────────────────────────────

def run(cmd, cwd: Optional[Path] = None, check: bool = True,
        capture: bool = False, env: Optional[dict] = None) -> subprocess.CompletedProcess:
    """Run a shell command with logging."""
    log = logging.getLogger("turboquant-builder")

    if isinstance(cmd, str):
        display_cmd = cmd
        shell = True
    else:
        display_cmd = " ".join(str(c) for c in cmd)
        shell = False

    log.debug(f"$ {display_cmd}")

    merged_env = None
    if env:
        merged_env = {**os.environ, **env}

    try:
        result = subprocess.run(
            cmd, shell=shell, cwd=cwd, check=check,
            capture_output=capture, text=True, env=merged_env,
        )
        return result
    except subprocess.CalledProcessError as e:
        log.error(f"Command failed (exit {e.returncode}): {display_cmd}")
        if e.stdout:
            log.error(f"stdout: {e.stdout[-500:]}")
        if e.stderr:
            log.error(f"stderr: {e.stderr[-500:]}")
        raise


def cmd_exists(name: str) -> bool:
    return shutil.which(name) is not None


def get_cmd_output(cmd: str) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
        return r.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


# ─── System Detection ───────────────────────────────────────────────────────

def detect_distro() -> tuple:
    """Detect whether we're on Arch or Debian-based."""
    os_release = Path("/etc/os-release")
    if not os_release.exists():
        return Distro.UNKNOWN, "unknown"

    content = os_release.read_text()
    id_line = ""
    name_line = ""
    id_like = ""
    for line in content.splitlines():
        if line.startswith("ID="):
            id_line = line.split("=", 1)[1].strip().strip('"').lower()
        if line.startswith("PRETTY_NAME="):
            name_line = line.split("=", 1)[1].strip().strip('"')
        if line.startswith("ID_LIKE="):
            id_like = line.split("=", 1)[1].strip().strip('"').lower()

    arch_ids = {"arch", "archlinux", "endeavouros", "manjaro", "garuda", "cachyos"}
    debian_ids = {"debian", "ubuntu", "linuxmint", "pop", "zorin", "elementary", "neon"}

    if id_line in arch_ids:
        return Distro.ARCH, name_line or id_line

    likes = id_like.split()
    if any(x in arch_ids for x in likes):
        return Distro.ARCH, name_line or id_line
    if any(x in debian_ids for x in likes):
        return Distro.DEBIAN, name_line or id_line

    if id_line in debian_ids:
        return Distro.DEBIAN, name_line or id_line

    return Distro.UNKNOWN, name_line or id_line


def detect_cuda() -> tuple:
    """Return (cuda_version, cuda_path)."""
    nvcc_out = get_cmd_output("nvcc --version 2>/dev/null")
    version = ""
    if nvcc_out:
        match = re.search(r"release (\d+\.\d+)", nvcc_out)
        if match:
            version = match.group(1)

    cuda_path = ""
    for candidate in [
        os.environ.get("CUDA_HOME", ""),
        os.environ.get("CUDA_PATH", ""),
        "/opt/cuda",
        "/usr/local/cuda",
        "/usr",
    ]:
        if candidate and Path(candidate).is_dir():
            nvcc_bin = Path(candidate) / "bin" / "nvcc"
            if nvcc_bin.exists():
                cuda_path = candidate
                break

    if not version:
        smi_out = get_cmd_output("nvidia-smi 2>/dev/null | head -3")
        match = re.search(r"CUDA Version:\s*(\d+\.\d+)", smi_out)
        if match:
            version = match.group(1)

    return version, cuda_path


def detect_gpu() -> tuple:
    """Return (gpu_name, compute_arch)."""
    name = get_cmd_output(
        "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1"
    )
    arch = ""

    # Known Ada Lovelace GPUs
    ada_gpus = ["4090", "4080", "4070", "4060", "L40", "L4"]
    ampere_gpus = ["3090", "3080", "3070", "3060", "A100", "A40", "A30", "A10"]
    hopper_gpus = ["H100", "H200"]
    blackwell_gpus = ["B200", "B100", "GB200"]

    for g in ada_gpus:
        if g in name:
            arch = "89"
            break
    if not arch:
        for g in ampere_gpus:
            if g in name:
                arch = "86"
                break
    if not arch:
        for g in hopper_gpus:
            if g in name:
                arch = "90"
                break
    if not arch:
        for g in blackwell_gpus:
            if g in name:
                arch = "120"
                break

    if not arch:
        caps = get_cmd_output(
            "nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1"
        )
        if caps:
            arch = caps.replace(".", "")

    return name, arch


def gather_system_info() -> SystemInfo:
    """Collect all relevant system information."""
    log = logging.getLogger("turboquant-builder")
    info = SystemInfo()

    log.info("Detecting system configuration...")

    info.distro, info.distro_name = detect_distro()
    log.info(f"  Distro:  {info.distro_name} ({info.distro.name})")

    info.kernel = platform.release()

    try:
        cpuinfo = Path("/proc/cpuinfo").read_text()
        for line in cpuinfo.splitlines():
            if line.startswith("model name"):
                info.cpu_model = line.split(":", 1)[1].strip()
                break
    except Exception:
        info.cpu_model = platform.processor()
    info.cpu_threads = os.cpu_count() or 24
    log.info(f"  CPU:     {info.cpu_model} ({info.cpu_threads} threads)")

    info.has_nvidia_smi = cmd_exists("nvidia-smi")
    if info.has_nvidia_smi:
        info.gpu_name, info.gpu_arch = detect_gpu()
        log.info(f"  GPU:     {info.gpu_name} (sm_{info.gpu_arch})")
    else:
        info.warnings.append("nvidia-smi not found — NVIDIA driver may not be installed")
        log.warning("  GPU:     nvidia-smi not found!")

    info.cuda_version, info.cuda_path = detect_cuda()
    if info.cuda_version:
        log.info(f"  CUDA:    {info.cuda_version} ({info.cuda_path})")
        if info.cuda_version in CUDA_BLACKLIST:
            info.errors.append(
                f"CUDA {info.cuda_version} is blacklisted — MMQ kernel segfaults. "
                f"Use CUDA 12.4-12.8."
            )
        try:
            cur = tuple(int(x) for x in info.cuda_version.split("."))
            req = tuple(int(x) for x in CUDA_MIN_VERSION.split("."))
            if cur < req:
                info.warnings.append(
                    f"CUDA {info.cuda_version} is below recommended {CUDA_MIN_VERSION}. "
                    f"Flash Attention kernels may not work correctly."
                )
        except ValueError:
            pass
    else:
        info.warnings.append("CUDA toolkit not detected — will attempt to install")

    cmake_v = get_cmd_output("cmake --version 2>/dev/null | head -1")
    info.cmake_version = cmake_v
    log.info(f"  cmake:   {cmake_v or 'NOT FOUND'}")

    git_v = get_cmd_output("git --version 2>/dev/null")
    info.git_version = git_v
    log.info(f"  git:     {git_v or 'NOT FOUND'}")

    return info


# ─── Dependency Installation ─────────────────────────────────────────────────

def install_deps_arch(info: SystemInfo):
    """Install all needed packages on Arch Linux."""
    log = logging.getLogger("turboquant-builder")
    log.info("Installing dependencies (Arch Linux / pacman)...")

    core_pkgs = [
        "base-devel", "cmake", "git", "ninja", "curl", "wget",
        "openssl", "python",
    ]
    nvidia_pkgs = ["cuda", "cudnn"]
    all_pkgs = core_pkgs + nvidia_pkgs

    log.info(f"  Packages: {' '.join(all_pkgs)}")
    run(f"sudo pacman -Syu --needed --noconfirm {' '.join(all_pkgs)}")

    # Ensure CUDA env vars are set for this session
    cuda_env_file = Path("/etc/profile.d/cuda.sh")
    if not cuda_env_file.exists():
        log.info("  Writing CUDA environment to /etc/profile.d/cuda.sh ...")
        cuda_env = (
            'export PATH="/opt/cuda/bin:$PATH"\n'
            'export LD_LIBRARY_PATH="/opt/cuda/lib64:$LD_LIBRARY_PATH"\n'
            'export CUDA_HOME="/opt/cuda"\n'
        )
        run(f"echo '{cuda_env}' | sudo tee /etc/profile.d/cuda.sh", check=False)

    # Apply to current process
    os.environ["PATH"] = f"/opt/cuda/bin:{os.environ.get('PATH', '')}"
    os.environ["LD_LIBRARY_PATH"] = f"/opt/cuda/lib64:{os.environ.get('LD_LIBRARY_PATH', '')}"
    os.environ["CUDA_HOME"] = "/opt/cuda"

    new_ver, new_path = detect_cuda()
    if new_ver:
        log.info(f"  CUDA installed: {new_ver} at {new_path}")
    else:
        log.warning("  CUDA still not detected after install — check pacman output above")
        log.warning("  You may need to: source /etc/profile.d/cuda.sh")


def install_deps_debian(info: SystemInfo):
    """Install all needed packages on Debian/Ubuntu."""
    log = logging.getLogger("turboquant-builder")
    log.info("Installing dependencies (Debian/Ubuntu / apt)...")

    core_pkgs = [
        "build-essential", "cmake", "git", "ninja-build", "curl", "wget",
        "libssl-dev", "libgomp1", "libcurl4-openssl-dev", "python3",
    ]

    log.info(f"  Core packages: {' '.join(core_pkgs)}")
    run("sudo apt-get update -qq")
    run(f"sudo apt-get install -y {' '.join(core_pkgs)}")

    if info.cuda_version:
        log.info(f"  CUDA {info.cuda_version} already present, skipping CUDA install")
    else:
        log.info("  Installing nvidia-cuda-toolkit from apt...")
        log.info("  NOTE: For best results, install CUDA from:")
        log.info("        https://developer.nvidia.com/cuda-downloads")
        run("sudo apt-get install -y nvidia-cuda-toolkit")

    new_ver, _ = detect_cuda()
    if new_ver:
        log.info(f"  CUDA ready: {new_ver}")


def install_deps(info: SystemInfo):
    if info.distro == Distro.ARCH:
        install_deps_arch(info)
    elif info.distro == Distro.DEBIAN:
        install_deps_debian(info)
    else:
        log = logging.getLogger("turboquant-builder")
        log.error(
            f"Unsupported distro: {info.distro_name}. "
            "Install manually: cmake, git, build tools, CUDA toolkit."
        )
        sys.exit(1)


# ─── Conda Environment ───────────────────────────────────────────────────────

def get_conda_bin() -> Optional[Path]:
    """Find the conda binary."""
    conda = CONDA_BASE / "bin" / "conda"
    if conda.exists():
        return conda
    # Fallback: check PATH
    which = shutil.which("conda")
    if which:
        return Path(which)
    return None


def conda_env_exists() -> bool:
    """Check if the turboquant conda environment already exists."""
    conda = get_conda_bin()
    if not conda:
        return False
    result = get_cmd_output(f"{conda} env list 2>/dev/null")
    for line in result.splitlines():
        parts = line.split()
        if parts and parts[0] == CONDA_ENV_NAME:
            return True
    return False


def get_conda_env_python() -> Optional[Path]:
    """Return the Python binary inside the turboquant conda env."""
    py = CONDA_BASE / "envs" / CONDA_ENV_NAME / "bin" / "python"
    if py.exists():
        return py
    return None


def get_conda_env_pip() -> Optional[Path]:
    """Return the pip binary inside the turboquant conda env."""
    pip = CONDA_BASE / "envs" / CONDA_ENV_NAME / "bin" / "pip"
    if pip.exists():
        return pip
    return None


def check_conda_or_exit():
    """
    Verify miniconda3 is installed and the 'turboquant' env exists.
    If not, print clear instructions and exit.
    """
    log = logging.getLogger("turboquant-builder")

    conda = get_conda_bin()
    if not conda:
        log.error("")
        log.error("=" * 60)
        log.error("  Miniconda3 NOT FOUND at ~/miniconda3/")
        log.error("=" * 60)
        log.error("")
        log.error("  Install Miniconda3 first:")
        log.error("")
        log.error("    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh")
        log.error("    bash Miniconda3-latest-Linux-x86_64.sh -b -p ~/miniconda3")
        log.error("    ~/miniconda3/bin/conda init bash")
        log.error("    source ~/.bashrc")
        log.error("")
        log.error("  Then re-run this script.")
        log.error("=" * 60)
        sys.exit(1)

    log.info(f"  Conda:   {conda}")

    if not conda_env_exists():
        log.error("")
        log.error("=" * 60)
        log.error(f"  Conda environment '{CONDA_ENV_NAME}' NOT FOUND")
        log.error("=" * 60)
        log.error("")
        log.error("  Create it with Python 3.12 and PyTorch cu128:")
        log.error("")
        log.error(f"    conda create -n {CONDA_ENV_NAME} python={CONDA_PYTHON_VERSION} -y")
        log.error(f"    conda activate {CONDA_ENV_NAME}")
        log.error(f"    pip install torch torchvision torchaudio --index-url {PYTORCH_INDEX_URL}")
        log.error(f"    pip install {' '.join(PYTHON_PACKAGES_EXTRA)}")
        log.error("")
        log.error("  Then re-run this script.")
        log.error("=" * 60)
        sys.exit(1)

    # Env exists — verify Python version
    env_py = get_conda_env_python()
    if env_py:
        py_ver = get_cmd_output(f"{env_py} --version 2>&1")
        log.info(f"  Env:     {CONDA_ENV_NAME} ({py_ver})")
        if CONDA_PYTHON_VERSION not in py_ver:
            log.warning(
                f"  Expected Python {CONDA_PYTHON_VERSION} but got {py_ver}. "
                f"Recreate with: conda create -n {CONDA_ENV_NAME} python={CONDA_PYTHON_VERSION} -y"
            )
    else:
        log.warning(f"  Conda env '{CONDA_ENV_NAME}' exists but Python not found in it")


def install_python_packages():
    """Install PyTorch cu128 + TurboQuant packages into the conda env."""
    log = logging.getLogger("turboquant-builder")
    pip = get_conda_env_pip()
    if not pip:
        log.warning("pip not found in conda env — skipping Python package install")
        return

    log.info(f"Installing PyTorch cu128 into '{CONDA_ENV_NAME}' env...")
    run(f"{pip} install torch torchvision torchaudio --index-url {PYTORCH_INDEX_URL}")

    if PYTHON_PACKAGES_EXTRA:
        log.info(f"Installing TurboQuant ecosystem packages...")
        run(f"{pip} install {' '.join(PYTHON_PACKAGES_EXTRA)}")

    # Verify PyTorch CUDA
    env_py = get_conda_env_python()
    if env_py:
        verify = get_cmd_output(
            f'{env_py} -c "import torch; print(f\'PyTorch {{torch.__version__}} '
            f'CUDA {{torch.version.cuda}} avail={{torch.cuda.is_available()}}\')" 2>&1'
        )
        if verify:
            log.info(f"  {verify}")
        else:
            log.warning("  Could not verify PyTorch CUDA — check manually after activating env")


# ─── Clone / Update Repo ────────────────────────────────────────────────────

def clone_or_update(install_dir: Path) -> Path:
    """Clone the TurboQuant fork or pull latest if already cloned."""
    log = logging.getLogger("turboquant-builder")
    repo_dir = install_dir / "llama-cpp-turboquant"

    if (repo_dir / ".git").is_dir():
        log.info(f"Repo exists at {repo_dir}, updating...")
        run("git fetch origin", cwd=repo_dir)

        current = get_cmd_output(f"git -C {repo_dir} branch --show-current")
        target_branch = BRANCH.split("/")[-1] if "/" in BRANCH else BRANCH
        if current != BRANCH:
            log.info(f"  Switching to branch {BRANCH}...")
            run(f"git checkout {BRANCH}", cwd=repo_dir)

        run(f"git pull origin {BRANCH} --ff-only", cwd=repo_dir, check=False)
    else:
        log.info(f"Cloning {REPO_URL} (branch: {BRANCH})...")
        install_dir.mkdir(parents=True, exist_ok=True)
        run(f"git clone --depth 1 -b {BRANCH} {REPO_URL} {repo_dir}")

    commit = get_cmd_output(f"git -C {repo_dir} log -1 --oneline")
    log.info(f"  HEAD: {commit}")

    # Fix upstream bug: GGML_API expands to 'extern', causing double-extern errors
    patch_turbo_extern_bug(repo_dir)

    return repo_dir


def patch_turbo_extern_bug(repo_dir: Path):
    """Fix compile warnings/errors in the TurboQuant fork."""
    log = logging.getLogger("turboquant-builder")
    patched = []

    # ── ops.cpp fixes ──
    ops_cpp = repo_dir / "ggml" / "src" / "ggml-cpu" / "ops.cpp"
    if ops_cpp.exists():
        text = ops_cpp.read_text()
        changed = False

        # Fix: extern "C" GGML_API -> extern "C" (double-extern error)
        if 'extern "C" GGML_API int turbo3_cpu_wht_group_size' in text:
            text = text.replace(
                'extern "C" GGML_API int turbo3_cpu_wht_group_size',
                'extern "C" int turbo3_cpu_wht_group_size',
            )
            patched.append("ops.cpp: removed double-extern")
            changed = True

        # Fix: missing TURBO enum cases in ggml_compute_forward_clamp switch
        if ("GGML_TYPE_Q8_K:\n        case GGML_TYPE_I8:" in text
                and "GGML_TYPE_TURBO3_0" not in text.split("ggml_compute_forward_clamp")[-1]
                    .split("GGML_ABORT")[0]):
            text = text.replace(
                "case GGML_TYPE_Q8_K:\n        case GGML_TYPE_I8:",
                "case GGML_TYPE_Q8_K:\n"
                "        case GGML_TYPE_TURBO2_0:\n"
                "        case GGML_TYPE_TURBO3_0:\n"
                "        case GGML_TYPE_TURBO4_0:\n"
                "        case GGML_TYPE_I8:",
            )
            patched.append("ops.cpp: added TURBO enum cases to clamp switch")
            changed = True

        if changed:
            ops_cpp.write_text(text)

    # ── ggml-turbo-quant.c fix ──
    turbo_c = repo_dir / "ggml" / "src" / "ggml-turbo-quant.c"
    if turbo_c.exists():
        text = turbo_c.read_text()
        if "GGML_API int turbo3_cpu_wht_group_size = 0" in text:
            text = text.replace(
                "GGML_API int turbo3_cpu_wht_group_size = 0",
                "int turbo3_cpu_wht_group_size = 0",
            )
            turbo_c.write_text(text)
            patched.append("ggml-turbo-quant.c: removed extern on definition")

    # ── set-rows.cu fix: unused warp_id in turbo3/turbo2 kernels ──
    set_rows = repo_dir / "ggml" / "src" / "ggml-cuda" / "set-rows.cu"
    if set_rows.exists():
        text = set_rows.read_text()
        changed = False

        for block_type, qk_name in [("turbo3_0", "QK_TURBO3"), ("turbo2_0", "QK_TURBO2")]:
            # Remove unused warp_id lines preceding lane/elem_in_block for turboN blocks
            old = (f"const int warp_id = j / WARP_SIZE;\n"
                   f"    const int lane    = j % WARP_SIZE;\n"
                   f"    const int elem_in_block = j % {qk_name};\n"
                   f"    block_{block_type} * blk = blk_base + (j / {qk_name});")
            new = (f"const int lane    = j % WARP_SIZE;\n"
                   f"    const int elem_in_block = j % {qk_name};\n"
                   f"    block_{block_type} * blk = blk_base + (j / {qk_name});")
            if old in text:
                text = text.replace(old, new)
                patched.append(f"set-rows.cu: removed unused warp_id in {block_type} kernel")
                changed = True

        if changed:
            set_rows.write_text(text)

    # ── llama-kv-cache.cpp fix: unused 'il' variables in state_write_data ──
    kv_cache = repo_dir / "src" / "llama-kv-cache.cpp"
    if kv_cache.exists():
        text = kv_cache.read_text()
        changed = False

        for context in [
            ("const uint32_t il = layer.il;\n\n"
             "        auto * k = layer.k_stream[cr.strm];",
             "auto * k = layer.k_stream[cr.strm];"),
            ("const uint32_t il = layer.il;\n\n"
             "            auto * v = layer.v_stream[cr.strm];",
             "auto * v = layer.v_stream[cr.strm];"),
        ]:
            if context[0] in text:
                text = text.replace(context[0], context[1])
                changed = True

        if changed:
            kv_cache.write_text(text)
            patched.append("llama-kv-cache.cpp: removed unused 'il' variables")

    if patched:
        for msg in patched:
            log.info(f"  Patched {msg}")
    else:
        log.debug("  No turbo patches needed (already fixed or not present)")


# ─── CMake Configure + Build ────────────────────────────────────────────────

def configure_and_build(repo_dir: Path, info: SystemInfo, clean: bool = False):
    """Run cmake configure and build."""
    log = logging.getLogger("turboquant-builder")
    build_dir = repo_dir / BUILD_DIR_NAME

    if clean and build_dir.exists():
        log.info(f"Cleaning build directory: {build_dir}")
        shutil.rmtree(build_dir)

    cuda_arch = info.gpu_arch or CUDA_ARCH_RTX4090
    log.info(f"Target CUDA architecture: sm_{cuda_arch}")

    # ── Determine generator ──
    generator = "Ninja" if cmd_exists("ninja") else "Unix Makefiles"
    log.info(f"CMake generator: {generator}")

    # ── CMake configure ──
    cmake_args = [
        "cmake",
        "-B", str(build_dir),
        "-S", str(repo_dir),
        "-G", generator,
        "-DBUILD_SHARED_LIBS=OFF",
        "-DCMAKE_BUILD_TYPE=Release",
        # ─ CUDA core ─
        "-DGGML_CUDA=ON",
        "-DGGML_CUDA_GRAPHS=ON",
        "-DGGML_CUDA_COMPRESSION_MODE=size",
        "-DGGML_NATIVE=ON",                        # AVX2/AVX512 for Ryzen 7900X
        # ─ Flash Attention — REQUIRED for turbo3 V path ─
        "-DGGML_CUDA_FA=ON",
        "-DGGML_CUDA_FA_ALL_QUANTS=ON",
        # ─ Target architecture ─
        f"-DCMAKE_CUDA_ARCHITECTURES={cuda_arch}",  # sm_89 for RTX 4090
        # ─ Let turbo kernels handle dispatch ─
        "-DGGML_CUDA_FORCE_CUBLAS=OFF",
        # ─ x86 SIMD — explicit for Ryzen 7900X (Zen 4) ─
        "-DGGML_SSE42=ON",
        "-DGGML_AVX=ON",
        "-DGGML_AVX2=ON",
        "-DGGML_BMI2=ON",
        "-DGGML_FMA=ON",
        "-DGGML_F16C=ON",
        "-DGGML_AVX512=ON",
        "-DGGML_AVX512_BF16=ON",
        "-DGGML_AVX512_VNNI=ON",
        "-DGGML_AVX512_VBMI=ON",
        # ─ Build optimizations ─
        "-DGGML_LTO=ON",
        "-DGGML_OPENMP=ON",
        "-DGGML_CCACHE=ON",
        "-DGGML_CPU_REPACK=ON",
        # ─ For IDE / tooling ─
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
    ]

    # Point to CUDA if non-standard path (common on Arch: /opt/cuda)
    if info.cuda_path and info.cuda_path not in ("/usr",):
        nvcc = Path(info.cuda_path) / "bin" / "nvcc"
        if nvcc.exists():
            cmake_args.append(f"-DCMAKE_CUDA_COMPILER={nvcc}")

    log.info("Configuring with CMake...")
    for arg in cmake_args:
        log.debug(f"  {arg}")
    run(cmake_args, cwd=repo_dir)

    # ── Build ──
    jobs = info.cpu_threads
    log.info(f"Building with {jobs} parallel jobs...")
    build_start = time.time()

    build_cmd = [
        "cmake", "--build", str(build_dir),
        "--config", "Release",
        f"-j{jobs}",
        "--target", "llama-server", "llama-cli",
    ]
    run(build_cmd, cwd=repo_dir)

    elapsed = time.time() - build_start
    log.info(f"Build completed in {elapsed:.1f}s")

    # ── Verify key binaries ──
    binaries = ["llama-server", "llama-cli"]
    bin_dir = build_dir / "bin"
    found = []
    missing = []

    for b in binaries:
        if (bin_dir / b).exists():
            found.append(b)
        else:
            missing.append(b)

    if found:
        log.info(f"  Built: {', '.join(found)}")
    if missing:
        log.warning(f"  Not found (may be optional): {', '.join(missing)}")

    return build_dir


# ─── Verification ────────────────────────────────────────────────────────────

def verify_build(build_dir: Path):
    """Verify the build supports TurboQuant cache types."""
    log = logging.getLogger("turboquant-builder")
    log.info("Verifying TurboQuant support in build...")

    for name in ["llama-cli", "llama-server"]:
        binary = build_dir / "bin" / name
        if not binary.exists():
            continue
        help_out = get_cmd_output(f"{binary} --help 2>&1 | head -200")
        if "cache-type" in help_out.lower() or "ctk" in help_out:
            log.info(f"  {name}: --cache-type flags present")
        else:
            log.warning(f"  {name}: could not confirm --cache-type in --help")

        if "turbo" in help_out.lower():
            log.info(f"  {name}: turbo3/turbo4 types confirmed")
        else:
            log.info(f"  {name}: turbo types register at runtime (normal)")


# ─── Install to /usr/local/bin ───────────────────────────────────────────────

def install_binaries(build_dir: Path):
    """Copy only essential binaries to /usr/local/bin via sudo."""
    log = logging.getLogger("turboquant-builder")
    log.info(f"Installing essential binaries to {INSTALL_BIN_DIR}/")

    bin_dir = build_dir / "bin"
    installed = []
    skipped = []

    for name in ESSENTIAL_BINARIES:
        src = bin_dir / name
        dst = INSTALL_BIN_DIR / name
        if not src.exists():
            skipped.append(name)
            continue

        log.info(f"  {name} -> {dst}")
        run(f"sudo install -m 755 {src} {dst}")
        installed.append(name)

    if installed:
        log.info(f"  Installed: {', '.join(installed)}")
    if skipped:
        log.warning(f"  Skipped (not built): {', '.join(skipped)}")

    # Verify they're on PATH
    for name in installed:
        which = shutil.which(name)
        if which:
            log.info(f"  {name} accessible at: {which}")
        else:
            log.warning(f"  {name} installed but not found on PATH")

    return installed


def uninstall_binaries():
    """Remove TurboQuant binaries from /usr/local/bin."""
    log = logging.getLogger("turboquant-builder")
    log.info(f"Removing TurboQuant binaries from {INSTALL_BIN_DIR}/")

    for name in ESSENTIAL_BINARIES:
        dst = INSTALL_BIN_DIR / name
        if dst.exists():
            log.info(f"  Removing {dst}")
            run(f"sudo rm -f {dst}")
        else:
            log.info(f"  {name} not found, skipping")


# ─── Write convenience scripts ──────────────────────────────────────────────

def write_launcher_scripts(build_dir: Path, install_dir: Path):
    """Write helper shell scripts for common operations."""
    log = logging.getLogger("turboquant-builder")
    scripts_dir = install_dir / "scripts"
    scripts_dir.mkdir(exist_ok=True)

    # All scripts reference /usr/local/bin (installed binaries)
    ibd = INSTALL_BIN_DIR

    # ── Server launcher (symmetric turbo3) ──
    server_script = scripts_dir / "start-server.sh"
    server_script.write_text(f"""\
#!/usr/bin/env bash
# TurboQuant llama-server launcher — symmetric turbo3/turbo3
# Usage: ./start-server.sh <model.gguf> [context_size] [port]
set -euo pipefail

# ── Activate conda env ──
source {CONDA_BASE}/etc/profile.d/conda.sh
conda activate {CONDA_ENV_NAME}

MODEL="${{1:?Usage: $0 <model.gguf> [context_size] [port]}}"
CTX="${{2:-131072}}"
PORT="${{3:-8080}}"

# Layer-adaptive mode 1: first4+last4 layers at q8_0 for best quality
export TURBO_LAYER_ADAPTIVE=1

echo "=== TurboQuant llama-server ==="
echo "  Model:   $MODEL"
echo "  Context: $CTX tokens"
echo "  KV:      turbo3/turbo3 (symmetric)"
echo "  FA:      ON (required for turbo3)"
echo "  Port:    $PORT"
echo "  API:     http://localhost:$PORT/v1/chat/completions"
echo ""

exec {ibd}/llama-server \\
    -m "$MODEL" \\
    --cache-type-k turbo3 \\
    --cache-type-v turbo3 \\
    -ngl 99 \\
    -c "$CTX" \\
    -fa on \\
    --host 0.0.0.0 \\
    --port "$PORT"
""")
    server_script.chmod(0o755)

    # ── Asymmetric K/V launcher (for Q4_K_M models) ──
    asym_script = scripts_dir / "start-server-asymmetric.sh"
    asym_script.write_text(f"""\
#!/usr/bin/env bash
# TurboQuant llama-server — asymmetric K/V mode
# Keeps K at q8_0 (high precision for softmax routing), compresses V with turbo4.
# Use this for Q4_K_M weight-quantized models where symmetric turbo degrades.
set -euo pipefail

# ── Activate conda env ──
source {CONDA_BASE}/etc/profile.d/conda.sh
conda activate {CONDA_ENV_NAME}

MODEL="${{1:?Usage: $0 <model.gguf> [context_size] [port]}}"
CTX="${{2:-131072}}"
PORT="${{3:-8080}}"

export TURBO_LAYER_ADAPTIVE=1

echo "=== TurboQuant (asymmetric K/V) ==="
echo "  Model:   $MODEL"
echo "  Context: $CTX tokens"
echo "  K cache: q8_0  (high precision)"
echo "  V cache: turbo4 (compressed)"
echo "  Port:    $PORT"
echo ""

exec {ibd}/llama-server \\
    -m "$MODEL" \\
    --cache-type-k q8_0 \\
    --cache-type-v turbo4 \\
    -ngl 99 \\
    -c "$CTX" \\
    -fa on \\
    --host 0.0.0.0 \\
    --port "$PORT"
""")
    asym_script.chmod(0o755)

    # ── Rebuild helper ──
    rebuild_script = scripts_dir / "rebuild.sh"
    rebuild_script.write_text(f"""\
#!/usr/bin/env bash
# Pull latest changes, rebuild, and re-install binaries to /usr/local/bin
set -euo pipefail

source {CONDA_BASE}/etc/profile.d/conda.sh
conda activate {CONDA_ENV_NAME}

REPO_DIR="{build_dir.parent}"
BUILD_DIR="{build_dir}"

echo "=== Pulling latest changes ==="
cd "$REPO_DIR"
git pull origin {BRANCH} --ff-only
git log -1 --oneline

echo ""
echo "=== Rebuilding ==="
cmake --build "$BUILD_DIR" --config Release -j$(nproc) --target llama-server llama-cli

echo ""
echo "=== Installing essential binaries to {ibd}/ ==="
for BIN in {' '.join(ESSENTIAL_BINARIES)}; do
    if [ -f "$BUILD_DIR/bin/$BIN" ]; then
        sudo install -m 755 "$BUILD_DIR/bin/$BIN" {ibd}/$BIN
        echo "  $BIN -> {ibd}/$BIN"
    fi
done

echo ""
echo "=== Done ==="
llama-server --version 2>&1 | head -1 || true
""")
    rebuild_script.chmod(0o755)

    log.info(f"Launcher scripts written to {scripts_dir}/")
    log.info(f"  start-server.sh            — symmetric turbo3 (recommended for Q8_0+ models)")
    log.info(f"  start-server-asymmetric.sh — q8_0 K + turbo4 V (for Q4_K_M models)")
    log.info(f"  rebuild.sh                 — pull latest + rebuild")


# ─── Optional: launch server ────────────────────────────────────────────────

def launch_server(build_dir: Path, model_path: Optional[str], context: int = 131072):
    """Optionally launch llama-server with turbo3."""
    log = logging.getLogger("turboquant-builder")

    server = INSTALL_BIN_DIR / "llama-server"
    if not server.exists():
        # Fallback to build dir if not installed yet
        server = build_dir / "bin" / "llama-server"
    if not server.exists():
        log.error(f"llama-server not found at {INSTALL_BIN_DIR}/ or {build_dir / 'bin'}/")
        return

    if not model_path:
        log.info("")
        log.info("No --model specified. To launch the server, run:")
        log.info(f"  llama-server -m <model.gguf> \\")
        log.info(f"    -ctk turbo3 -ctv turbo3 -ngl 99 -c {context} -fa on")
        return

    model = Path(model_path)
    if not model.exists():
        log.error(f"Model file not found: {model}")
        return

    log.info(f"Launching llama-server with TurboQuant...")
    log.info(f"  Model:   {model}")
    log.info(f"  Context: {context}")
    log.info(f"  KV:      turbo3/turbo3")
    log.info(f"  URL:     http://localhost:8080")
    log.info(f"  Press Ctrl+C to stop\n")

    env = {"TURBO_LAYER_ADAPTIVE": "1"}
    cmd = [
        str(server),
        "-m", str(model),
        "--cache-type-k", "turbo3",
        "--cache-type-v", "turbo3",
        "-ngl", "99",
        "-c", str(context),
        "-fa", "on",
        "--host", "0.0.0.0",
        "--port", "8080",
    ]

    try:
        run(cmd, env=env)
    except KeyboardInterrupt:
        log.info("\nServer stopped.")


# ─── Write build manifest ───────────────────────────────────────────────────

def write_manifest(install_dir: Path, info: SystemInfo, build_dir: Path):
    """Write a JSON manifest of the build for future reference."""
    repo_dir = install_dir / "llama-cpp-turboquant"
    manifest = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "repo": REPO_URL,
        "branch": BRANCH,
        "commit": get_cmd_output(f"git -C {repo_dir} rev-parse HEAD"),
        "system": {
            "distro": info.distro_name,
            "kernel": info.kernel,
            "cpu": info.cpu_model,
            "cpu_threads": info.cpu_threads,
            "gpu": info.gpu_name,
            "gpu_arch": f"sm_{info.gpu_arch}",
            "cuda_version": info.cuda_version,
        },
        "cmake_flags": {
            "GGML_CUDA": "ON",
            "GGML_NATIVE": "ON",
            "GGML_CUDA_FA": "ON",
            "GGML_CUDA_FA_ALL_QUANTS": "ON",
            "CMAKE_CUDA_ARCHITECTURES": info.gpu_arch or CUDA_ARCH_RTX4090,
            "GGML_CUDA_FORCE_CUBLAS": "OFF",
        },
        "conda": {
            "base": str(CONDA_BASE),
            "env_name": CONDA_ENV_NAME,
            "python": CONDA_PYTHON_VERSION,
            "pytorch_index": PYTORCH_INDEX_URL,
        },
        "build_dir": str(build_dir),
        "installed_binaries": {
            name: str(INSTALL_BIN_DIR / name)
            for name in ESSENTIAL_BINARIES
            if (INSTALL_BIN_DIR / name).exists()
        },
        "build_binaries": {
            name: str(build_dir / "bin" / name)
            for name in ESSENTIAL_BINARIES
            if (build_dir / "bin" / name).exists()
        },
    }

    manifest_path = install_dir / "build-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))
    logging.getLogger("turboquant-builder").info(f"Build manifest: {manifest_path}")


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Automated TurboQuant llama.cpp builder for Arch Linux & Debian",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Examples:
  %(prog)s                                    # Full install + build
  %(prog)s --install-dir ~/llm/turboquant     # Custom source location
  %(prog)s --clean                            # Clean rebuild
  %(prog)s --run --model ~/models/qwen.gguf   # Build + launch server
  %(prog)s --deps-only                        # Just install system packages
  %(prog)s --build-only                       # Skip deps, just build
  %(prog)s --uninstall                        # Remove from /usr/local/bin
        """,
    )

    parser.add_argument("--install-dir", type=Path, default=DEFAULT_INSTALL_DIR,
                        help=f"Root directory (default: {DEFAULT_INSTALL_DIR})")
    parser.add_argument("--deps-only", action="store_true",
                        help="Only install system dependencies, then exit")
    parser.add_argument("--build-only", action="store_true",
                        help="Skip dependency install, just clone/build")
    parser.add_argument("--clean", action="store_true",
                        help="Remove build dir before building")
    parser.add_argument("--uninstall", action="store_true",
                        help="Remove TurboQuant binaries from /usr/local/bin")
    parser.add_argument("--run", action="store_true",
                        help="Launch llama-server after building")
    parser.add_argument("--model", type=str, default=None,
                        help="Path to .gguf model (used with --run)")
    parser.add_argument("--context", type=int, default=131072,
                        help="Context size for server (default: 131072)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Verbose debug output")

    args = parser.parse_args()
    log = setup_logging(args.verbose)

    log.info("=" * 60)
    log.info("  TurboQuant llama.cpp — Automated Builder")
    log.info(f"  Target: RTX 4090 (sm_89) + Ryzen 7900X")
    log.info(f"  Install to: {INSTALL_BIN_DIR}/")
    log.info("=" * 60)

    # ── Handle --uninstall early ──
    if args.uninstall:
        uninstall_binaries()
        log.info("Uninstall complete.")
        return

    # ── 1. System detection ──
    info = gather_system_info()

    if info.errors:
        for err in info.errors:
            log.error(f"FATAL: {err}")
        sys.exit(1)

    for warn in info.warnings:
        log.warning(f"  {warn}")

    # ── 2. Conda environment check ──
    check_conda_or_exit()

    # ── 3. System dependencies ──
    if not args.build_only:
        install_deps(info)
        info.cuda_version, info.cuda_path = detect_cuda()

    if args.deps_only:
        log.info("Dependencies installed. Exiting (--deps-only).")
        return

    if not info.cuda_version:
        log.error(
            "CUDA toolkit not detected. Please install CUDA manually and "
            "ensure 'nvcc' is on PATH, then re-run with --build-only."
        )
        sys.exit(1)

    # ── 4. PyTorch cu128 + TurboQuant packages ──
    if not args.build_only:
        install_python_packages()

    # ── 5. Clone / update repo ──
    repo_dir = clone_or_update(args.install_dir)

    # ── 6. Configure + build ──
    build_dir = configure_and_build(repo_dir, info, clean=args.clean)

    # ── 7. Verify ──
    verify_build(build_dir)

    # ── 8. Install essential binaries to /usr/local/bin ──
    install_binaries(build_dir)

    # ── 9. Write scripts + manifest ──
    write_launcher_scripts(build_dir, args.install_dir)
    write_manifest(args.install_dir, info, build_dir)

    # ── 10. Summary ──
    log.info("")
    log.info("=" * 60)
    log.info("  BUILD + INSTALL COMPLETE")
    log.info("=" * 60)
    log.info(f"  Conda env:     {CONDA_ENV_NAME} (Python {CONDA_PYTHON_VERSION} + PyTorch cu128)")
    log.info(f"  Installed to:  {INSTALL_BIN_DIR}/")
    for name in ESSENTIAL_BINARIES:
        marker = "OK" if (INSTALL_BIN_DIR / name).exists() else "MISSING"
        log.info(f"    [{marker}] {name}")
    log.info(f"  Source dir:    {args.install_dir}")
    log.info("")
    log.info("  Quick start:")
    log.info(f"    conda activate {CONDA_ENV_NAME}")
    log.info(f"    llama-server -m <model.gguf> \\")
    log.info(f"      -ctk turbo3 -ctv turbo3 -ngl 99 -c 131072 -fa on")
    log.info("")
    log.info("  Or use the launcher scripts (they activate conda for you):")
    log.info(f"    {args.install_dir / 'scripts' / 'start-server.sh'} <model.gguf>")
    log.info("")
    log.info("  Key reminders:")
    log.info("    • -fa on is REQUIRED (turbo3 V needs Flash Attention)")
    log.info("    • TURBO_LAYER_ADAPTIVE=1 for best quality (set in scripts)")
    log.info("    • For Q4_K_M models, try: -ctk q8_0 -ctv turbo4")
    log.info("    • Do NOT use CUDA 13.1 (MMQ segfaults)")
    log.info(f"    • To uninstall: python3 {sys.argv[0]} --uninstall")
    log.info(f"    • To update:    {args.install_dir / 'scripts' / 'rebuild.sh'}")
    log.info("=" * 60)

    # ── 11. Optional: launch ──
    if args.run:
        launch_server(build_dir, args.model, args.context)


if __name__ == "__main__":
    main()
