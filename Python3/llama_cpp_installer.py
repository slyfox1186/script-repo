#!/usr/bin/env python3
"""Build and install CUDA-enabled llama.cpp binaries."""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Any

REPO_URL = "https://github.com/ggml-org/llama.cpp"
REPO_DIR = "llama.cpp"

# DiffusionGemma support lives only in this still-open PR (block-diffusion arch +
# the dedicated `llama-diffusion-cli` runner); mainline llama-cli/llama-server
# cannot generate from those GGUFs. `--diffusion` builds from it. See:
# https://github.com/ggml-org/llama.cpp/pull/24423
DIFFUSION_PR = 24423

SYSTEM_PACKAGES = (
    "build-essential",
    "cmake",
    "git",
    "ninja-build",
)
MAINLINE_BUILD_TARGETS = ("llama-cli", "llama-server")
DIFFUSION_BUILD_TARGETS = (
    "llama-diffusion-cli",
    "llama-diffusion-gemma-visual-server",
)


@dataclass(frozen=True)
class GccToolchain:
    """Paths for one complete, version-matched GCC toolchain."""

    major: int
    cc: str
    cxx: str
    ar: str
    ranlib: str


def run(
    cmd: str | list[str],
    *,
    check: bool = True,
    shell: bool = False,
    **kwargs: Any,
) -> subprocess.CompletedProcess[Any]:
    """Run a command, printing it first."""
    display = cmd if isinstance(cmd, str) else " ".join(cmd)
    print(f"\n>>> {display}")
    return subprocess.run(cmd, check=check, shell=shell, **kwargs)


def capture(cmd: list[str], *, env: dict[str, str] | None = None) -> str:
    """Run a command and return stripped stdout."""
    result = run(cmd, env=env, capture_output=True, text=True)
    return str(result.stdout).strip()


def require_executable(command: str, *, env: dict[str, str] | None = None) -> str:
    """Resolve an executable or raise a clear preflight error."""
    search_path = env.get("PATH") if env is not None else None
    executable = shutil.which(command, path=search_path)
    if executable is None:
        raise RuntimeError(f"Required executable not found: {command}")
    return executable


def cuda_release(nvcc: str, *, env: dict[str, str] | None = None) -> tuple[int, int]:
    """Return the CUDA toolkit major/minor version reported by nvcc."""
    output = capture([nvcc, "--version"], env=env)
    match = re.search(r"\brelease\s+(\d+)\.(\d+)\b", output)
    if match is None:
        raise RuntimeError(
            f"Could not determine the CUDA version from {nvcc} --version"
        )
    return int(match.group(1)), int(match.group(2))


def _gcc_major(executable: str, *, env: dict[str, str]) -> int:
    """Return the major version reported by a GCC-family executable."""
    output = capture([executable, "-dumpfullversion", "-dumpversion"], env=env)
    match = re.match(r"(\d+)", output)
    if match is None:
        raise RuntimeError(f"Could not determine the GCC version from {executable}")
    return int(match.group(1))


def _toolchain_for_major(
    major: int, *, search_path: str, env: dict[str, str]
) -> GccToolchain | None:
    """Resolve and validate every tool required for a GCC major version."""
    cc = shutil.which(f"gcc-{major}", path=search_path)
    cxx = shutil.which(f"g++-{major}", path=search_path)
    ar = shutil.which(f"gcc-ar-{major}", path=search_path)
    ranlib = shutil.which(f"gcc-ranlib-{major}", path=search_path)
    if cc is None or cxx is None or ar is None or ranlib is None:
        return None

    try:
        cc_major = _gcc_major(cc, env=env)
        cxx_major = _gcc_major(cxx, env=env)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"[WARN] Skipping GCC {major} toolchain that could not be queried: {error}")
        return None
    if cc_major != major or cxx_major != major:
        print(
            f"[WARN] Skipping mislabeled GCC {major} toolchain: "
            f"gcc reports {cc_major} and g++ reports {cxx_major}."
        )
        return None

    return GccToolchain(major=major, cc=cc, cxx=cxx, ar=ar, ranlib=ranlib)


def installed_gcc_toolchains(*, env: dict[str, str]) -> list[GccToolchain]:
    """Find complete installed GCC toolchains, newest major version first."""
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

    toolchains = [
        toolchain
        for major in sorted(installed_majors, reverse=True)
        if (
            toolchain := _toolchain_for_major(
                major, search_path=search_path, env=env
            )
        )
        is not None
    ]

    # Some distributions expose only unversioned GCC executables. Include that
    # complete toolchain as a fallback without duplicating an already discovered
    # versioned toolchain.
    cc = shutil.which("gcc", path=search_path)
    cxx = shutil.which("g++", path=search_path)
    ar = shutil.which("gcc-ar", path=search_path)
    ranlib = shutil.which("gcc-ranlib", path=search_path)
    if cc is not None and cxx is not None and ar is not None and ranlib is not None:
        cc_major = _gcc_major(cc, env=env)
        cxx_major = _gcc_major(cxx, env=env)
        if cc_major != cxx_major:
            print(
                "[WARN] Skipping mismatched default compiler toolchain: "
                f"gcc reports {cc_major} and g++ reports {cxx_major}."
            )
        elif all(toolchain.major != cc_major for toolchain in toolchains):
            toolchains.append(
                GccToolchain(
                    major=cc_major,
                    cc=cc,
                    cxx=cxx,
                    ar=ar,
                    ranlib=ranlib,
                )
            )

    return sorted(toolchains, key=lambda toolchain: toolchain.major, reverse=True)


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
            [
                nvcc,
                "-ccbin",
                toolchain.cxx,
                "-x",
                "cu",
                "-c",
                source_path,
                "-o",
                object_path,
            ],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

    if result.returncode == 0:
        return True, ""

    output = (result.stderr or result.stdout).strip()
    reason = output.splitlines()[-1] if output else "nvcc exited without diagnostics"
    return False, reason


def select_gcc_toolchain(nvcc: str, *, env: dict[str, str]) -> GccToolchain:
    """Select the newest installed complete GCC toolchain accepted by nvcc."""
    toolchains = installed_gcc_toolchains(env=env)
    if not toolchains:
        raise RuntimeError(
            "No complete GCC toolchain was found. Install matching gcc, g++, "
            "gcc-ar, and gcc-ranlib packages."
        )

    rejected: list[str] = []
    for toolchain in toolchains:
        print(f"\nChecking whether nvcc accepts GCC {toolchain.major}...")
        accepted, reason = nvcc_accepts_host_compiler(nvcc, toolchain, env=env)
        if accepted:
            print(f"Selected GCC {toolchain.major}, the newest compatible toolchain.")
            return toolchain
        rejected.append(f"GCC {toolchain.major}: {reason}")
        print(f"[WARN] Skipping GCC {toolchain.major}: {reason}")

    details = "\n".join(f"  - {failure}" for failure in rejected)
    raise RuntimeError(
        "nvcc rejected every installed complete GCC toolchain:\n"
        f"{details}\nInstall a host compiler supported by this CUDA toolkit."
    )


def remote_default_branch(repo_url: str, *, env: dict[str, str] | None = None) -> str:
    """Resolve the remote default branch name from HEAD."""
    output = capture(["git", "ls-remote", "--symref", repo_url, "HEAD"], env=env)
    for line in output.splitlines():
        if not line.startswith("ref: "):
            continue
        ref = line.split("\t", 1)[0].replace("ref: ", "", 1).strip()
        if ref.startswith("refs/heads/"):
            return ref.removeprefix("refs/heads/")
    raise RuntimeError(f"Could not determine default branch for {repo_url}")


def remove_existing_repo(repo_dir: str) -> None:
    """Remove an existing repository path before cloning."""
    if not os.path.lexists(repo_dir):
        return

    print(f"\nRemoving existing {repo_dir} repository...\n")
    if os.path.islink(repo_dir) or not os.path.isdir(repo_dir):
        os.remove(repo_dir)
    else:
        shutil.rmtree(repo_dir)


def sync_repo_to_latest(
    repo_dir: str, repo_url: str, *, env: dict[str, str] | None = None
) -> str:
    """Clone a fresh copy of the latest upstream default branch."""
    remove_existing_repo(repo_dir)
    branch = remote_default_branch(repo_url, env=env)

    print(f"\nCloning llama.cpp repository from {branch}...\n")
    run(
        ["git", "clone", "--depth", "1", "--branch", branch, repo_url, repo_dir],
        env=env,
    )

    return branch


def sync_repo_to_pr(
    repo_dir: str, repo_url: str, pr_number: int, *, env: dict[str, str] | None = None
) -> str:
    """Clone a fresh repo and check out a specific PR branch for beta testing."""
    remove_existing_repo(repo_dir)
    ref = f"refs/pull/{pr_number}/head"
    local_branch = f"pr-{pr_number}"

    print("\nCloning llama.cpp repository...\n")
    run(["git", "clone", repo_url, repo_dir], env=env)
    run(["git", "-C", repo_dir, "fetch", "origin", f"{ref}:{local_branch}"], env=env)
    run(["git", "-C", repo_dir, "checkout", local_branch], env=env)

    # Show what we checked out
    sha = capture(["git", "-C", repo_dir, "rev-parse", "--short", "HEAD"], env=env)
    print(f"\nChecked out PR #{pr_number} at commit {sha}")
    return local_branch


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build and install llama.cpp with CUDA support"
    )
    parser.add_argument(
        "-k",
        "--keep",
        action="store_true",
        help="Keep the llama.cpp source directory after install (default: delete it)",
    )
    parser.add_argument(
        "--beta",
        type=int,
        metavar="PR",
        nargs="?",
        const=20075,
        help="Build from a GitHub PR branch instead of the latest upstream branch (default PR: 20075 — speculative decoding for hybrid models)",
    )
    parser.add_argument(
        "--diffusion",
        action="store_true",
        help=f"Build the DiffusionGemma runners (llama-diffusion-cli + llama-diffusion-gemma-visual-server) "
        f"from PR #{DIFFUSION_PR}. Required to run diffusion-gemma GGUFs, which mainline "
        "llama-cli/llama-server cannot generate from. Installs just those binaries alongside "
        "your existing llama-server (does not overwrite it).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if os.geteuid() == 0:
        print("You must run this script without sudo or as root.")
        sys.exit(1)

    # Set CUDA environment variables — use system CUDA, not conda's
    cuda_home = "/usr/local/cuda"

    env = os.environ.copy()
    env.update(
        {
            "CUDA_HOME": cuda_home,
            "PATH": f"{cuda_home}/bin:{env.get('PATH', '')}:/usr/lib/x86_64-linux-gnu",
            "LD_LIBRARY_PATH": f"{cuda_home}/lib64:{env.get('LD_LIBRARY_PATH', '')}:/usr/lib/x86_64-linux-gnu",
        }
    )

    nvcc = require_executable(f"{cuda_home}/bin/nvcc", env=env)
    cuda_version = cuda_release(nvcc, env=env)
    print(f"\nDetected CUDA {cuda_version[0]}.{cuda_version[1]}.")

    # Install system dependencies.
    # Retries + per-connection timeouts so a syncing mirror can't hang us indefinitely.
    # `update` is non-fatal: apt falls back to cached indexes on partial failure,
    # and the `install` below is the real gate — it will error if a package is actually missing.
    apt_opts = [
        "-o",
        "Acquire::Retries=3",
        "-o",
        "Acquire::http::Timeout=30",
        "-o",
        "Acquire::https::Timeout=30",
    ]
    try:
        update = run(["sudo", "apt", *apt_opts, "update"], check=False, timeout=600)
        update_ok = update.returncode == 0
    except subprocess.TimeoutExpired:
        print(
            "\n[WARN] 'apt update' exceeded 10-minute wall timeout; using cached indexes."
        )
        update_ok = False
    if not update_ok:
        print("[WARN] apt update incomplete; proceeding with cached package indexes.")
    run(
        [
            "sudo",
            "apt",
            *apt_opts,
            "install",
            "-y",
            *SYSTEM_PACKAGES,
        ]
    )

    # Use the newest complete GCC toolchain that this nvcc can compile with.
    toolchain = select_gcc_toolchain(nvcc, env=env)
    cc = toolchain.cc
    cxx = toolchain.cxx
    ar = toolchain.ar
    ranlib = toolchain.ranlib
    env.update({"CC": cc, "CXX": cxx, "AR": ar, "RANLIB": ranlib})

    # Resolve the remaining tools that apt guarantees.
    cmake_bin = require_executable("cmake", env=env)
    ninja_bin = require_executable("ninja", env=env)

    # Debug environment
    print("\n=== Build Environment ===")
    for label, cmd in [
        ("CC", [cc, "--version"]),
        ("CXX", [cxx, "--version"]),
        ("NVCC", [nvcc, "--version"]),
    ]:
        result = subprocess.run(
            cmd, check=False, capture_output=True, text=True, env=env
        )
        lines = result.stdout.strip().splitlines()
        if label == "NVCC":
            line = next(
                (output_line for output_line in lines if "release" in output_line),
                lines[0] if lines else "N/A",
            )
        else:
            line = lines[0] if lines else "N/A"
        print(f"{label:16s} {line}")
    print(f"{'CUDA_HOME':16s} {cuda_home}")
    print(f"{'LD_LIBRARY_PATH':16s} {env['LD_LIBRARY_PATH']}")
    print("=========================")

    # Clone or update llama.cpp repository.
    if args.diffusion:
        print(
            f"\n=== DIFFUSION MODE: building llama-diffusion-cli from DiffusionGemma PR #{DIFFUSION_PR} ==="
        )
        branch = sync_repo_to_pr(REPO_DIR, REPO_URL, DIFFUSION_PR, env=env)
    elif args.beta is not None:
        print(f"\n=== BETA MODE: Building from PR #{args.beta} ===")
        branch = sync_repo_to_pr(REPO_DIR, REPO_URL, args.beta, env=env)
    else:
        branch = sync_repo_to_latest(REPO_DIR, REPO_URL, env=env)
    print(f"Using llama.cpp branch: {branch}")

    print(f"\nBuilding llama.cpp with GCC {toolchain.major} + CUDA support...\n")

    # Remove stale CMake cache to pick up compiler changes
    for path in [f"{REPO_DIR}/build/CMakeCache.txt", f"{REPO_DIR}/build/CMakeFiles"]:
        if os.path.isfile(path):
            os.remove(path)
        elif os.path.isdir(path):
            shutil.rmtree(path)

    # Get CPU count
    nproc = os.cpu_count() or 4

    # Configure CMake with CUDA support and native optimizations. GGML_NATIVE
    # supplies -march=native for x86 and targets the GPUs attached at build
    # time; individual ISA and CUDA architecture switches would duplicate it.
    run(
        [
            cmake_bin,
            REPO_DIR,
            "-B",
            f"{REPO_DIR}/build",
            "-G",
            "Ninja",
            "-DBUILD_SHARED_LIBS=OFF",
            "-DCMAKE_BUILD_TYPE=Release",
            f"-DCMAKE_C_COMPILER={cc}",
            f"-DCMAKE_CXX_COMPILER={cxx}",
            f"-DCMAKE_AR={ar}",
            f"-DCMAKE_RANLIB={ranlib}",
            f"-DCMAKE_CUDA_COMPILER={nvcc}",
            f"-DCMAKE_CUDA_HOST_COMPILER={cxx}",
            f"-DCMAKE_MAKE_PROGRAM={ninja_bin}",
            f"-DCUDAToolkit_ROOT={cuda_home}",
            "-DCMAKE_CUDA_ARCHITECTURES=native",
            "-DGGML_CUDA=ON",
            "-DGGML_CUDA_FA=ON",
            "-DGGML_CUDA_FA_ALL_QUANTS=ON",
            "-DGGML_CUDA_GRAPHS=ON",
            "-DGGML_CUDA_COMPRESSION_MODE=size",
            "-DGGML_NATIVE=ON",
            "-DGGML_LTO=ON",
            "-DGGML_OPENMP=ON",
            "-DGGML_CCACHE=ON",
            "-DGGML_CPU_REPACK=ON",
        ],
        env=env,
    )

    # Clean previous build artifacts
    run([ninja_bin, "-C", f"{REPO_DIR}/build", "-t", "clean"], env=env, check=False)

    # Build specific targets with ninja.
    # Diffusion mode builds ONLY the DiffusionGemma runners. llama.cpp's component
    # libraries are linked statically into each output (-DBUILD_SHARED_LIBS=OFF),
    # so the runners install cleanly next to the mainline llama-server instead of
    # overwriting it with a PR-branch build.
    #   - llama-diffusion-cli ................. interactive terminal runner
    #   - llama-diffusion-gemma-visual-server . persistent stdin/stdout server that
    #       takes OpenAI-format messages and streams the denoised answer back; this
    #       is what the chat web app's diffusion_shim.py drives.
    if args.diffusion:
        build_targets = list(DIFFUSION_BUILD_TARGETS)
    else:
        build_targets = list(MAINLINE_BUILD_TARGETS)
    run([ninja_bin, "-C", f"{REPO_DIR}/build", f"-j{nproc}", *build_targets], env=env)

    print(f"\nllama.cpp built successfully in {REPO_DIR}/build/bin")

    # Install every requested binary before removing the source tree.
    install_dir = "/usr/local/bin"
    print(f"\nInstalling binaries to {install_dir}...")

    bin_dir = f"{REPO_DIR}/build/bin"
    built_binaries = [os.path.join(bin_dir, target) for target in build_targets]
    missing_binaries = [path for path in built_binaries if not os.path.isfile(path)]
    if missing_binaries:
        missing_list = "\n".join(f"  - {path}" for path in missing_binaries)
        raise RuntimeError(f"Cannot install missing build outputs:\n{missing_list}")

    installed_binaries = []
    for source_path, target in zip(built_binaries, build_targets, strict=True):
        installed_path = os.path.join(install_dir, target)
        run(["sudo", "install", "-m", "0755", source_path, installed_path])
        installed_binaries.append(installed_path)

    invalid_installs = [
        path
        for path in installed_binaries
        if not os.path.isfile(path) or not os.access(path, os.X_OK)
    ]
    if invalid_installs:
        invalid_list = "\n".join(f"  - {path}" for path in invalid_installs)
        raise RuntimeError(f"Installed binaries could not be verified:\n{invalid_list}")
    print(f"Installed {len(installed_binaries)} binaries successfully.")

    # Clean up cloned repo unless --keep was passed
    if os.path.isdir(REPO_DIR):
        if args.keep:
            print(f"Source directory kept at {os.path.join(os.getcwd(), REPO_DIR)}")
        else:
            shutil.rmtree(REPO_DIR)
            print("Source directory removed.")

    print("\nInstallation and build complete.")
    if args.diffusion:
        print(
            "\nInstalled the DiffusionGemma runners — your mainline llama-server was left untouched.\n"
            "  llama-diffusion-cli ................... interactive terminal runner:\n"
            "      llama-diffusion-cli -m /path/to/diffusiongemma-*.gguf --jinja -cnv --diffusion-visual\n"
            "  llama-diffusion-gemma-visual-server ... stdin/stdout server the chat web app drives;\n"
            "      launched for you by run_diffusion.py (you do not run it by hand)."
        )


if __name__ == "__main__":
    main()
