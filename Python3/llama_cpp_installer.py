#!/usr/bin/env python3

import argparse
import os
import shutil
import subprocess
import sys

REPO_URL = "https://github.com/ggml-org/llama.cpp"
REPO_DIR = "llama.cpp"

# DiffusionGemma support lives only in this still-open PR (block-diffusion arch +
# the dedicated `llama-diffusion-cli` runner); mainline llama-cli/llama-server
# cannot generate from those GGUFs. `--diffusion` builds from it. See:
# https://github.com/ggml-org/llama.cpp/pull/24423
DIFFUSION_PR = 24423


def run(cmd: str | list[str], *, check: bool = True, shell: bool = False, **kwargs) -> subprocess.CompletedProcess:
    """Run a command, printing it first."""
    display = cmd if isinstance(cmd, str) else " ".join(cmd)
    print(f"\n>>> {display}")
    return subprocess.run(cmd, check=check, shell=shell, **kwargs)


def capture(cmd: list[str], *, env: dict[str, str] | None = None) -> str:
    """Run a command and return stripped stdout."""
    result = run(cmd, env=env, capture_output=True, text=True)
    return result.stdout.strip()


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


def sync_repo_to_latest(repo_dir: str, repo_url: str, *, env: dict[str, str] | None = None) -> str:
    """Clone a fresh copy of the latest upstream default branch."""
    remove_existing_repo(repo_dir)
    branch = remote_default_branch(repo_url, env=env)

    print(f"\nCloning llama.cpp repository from {branch}...\n")
    run(
        ["git", "clone", "--depth", "1", "--branch", branch, repo_url, repo_dir],
        env=env,
    )

    return branch


def sync_repo_to_pr(repo_dir: str, repo_url: str, pr_number: int, *, env: dict[str, str] | None = None) -> str:
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
    parser = argparse.ArgumentParser(description="Build and install llama.cpp with CUDA support")
    parser.add_argument("-k", "--keep", action="store_true", help="Keep the llama.cpp source directory after install (default: delete it)")
    parser.add_argument("--beta", type=int, metavar="PR", nargs="?", const=20075,
                        help="Build from a GitHub PR branch instead of latest release (default PR: 20075 — speculative decoding for hybrid models)")
    parser.add_argument("--diffusion", action="store_true",
                        help=f"Build the DiffusionGemma runners (llama-diffusion-cli + llama-diffusion-gemma-visual-server) "
                             f"from PR #{DIFFUSION_PR}. Required to run diffusion-gemma GGUFs, which mainline "
                             "llama-cli/llama-server cannot generate from. Installs just those static binaries alongside "
                             "your existing llama-server (does not overwrite it).")
    return parser.parse_args()


def main():
    args = parse_args()

    if os.geteuid() == 0:
        print("You must run this script without sudo or as root.")
        sys.exit(1)

    # Set compilers to GCC 14 for best optimization support
    cc = "/usr/bin/gcc-14"
    cxx = "/usr/bin/g++-14"
    ar = "/usr/bin/gcc-ar-14"
    ranlib = "/usr/bin/gcc-ranlib-14"

    # Set CUDA environment variables — use system CUDA, not conda's
    cuda_home = "/usr/local/cuda"

    env = os.environ.copy()
    env.update({
        "CC": cc,
        "CXX": cxx,
        "AR": ar,
        "RANLIB": ranlib,
        "CUDA_HOME": cuda_home,
        "PATH": f"{cuda_home}/bin:{env.get('PATH', '')}:/usr/lib/x86_64-linux-gnu",
        "LD_LIBRARY_PATH": f"{cuda_home}/lib64:{env.get('LD_LIBRARY_PATH', '')}:/usr/lib/x86_64-linux-gnu",
    })

    # Install system dependencies.
    # Retries + per-connection timeouts so a syncing mirror can't hang us indefinitely.
    # `update` is non-fatal: apt falls back to cached indexes on partial failure,
    # and the `install` below is the real gate — it will error if a package is actually missing.
    apt_opts = [
        "-o", "Acquire::Retries=3",
        "-o", "Acquire::http::Timeout=30",
        "-o", "Acquire::https::Timeout=30",
    ]
    try:
        update = run(["sudo", "apt-get", "update", *apt_opts], check=False, timeout=600)
        update_ok = update.returncode == 0
    except subprocess.TimeoutExpired:
        print("\n[WARN] 'apt-get update' exceeded 10-minute wall timeout; using cached indexes.")
        update_ok = False
    if not update_ok:
        print("[WARN] apt-get update incomplete; proceeding with cached package indexes.")
    run([
        "sudo", "apt-get", "install", "-y", *apt_opts,
        "build-essential", "cmake", "curl", "g++-14", "gcc-14",
        "libcurl4-openssl-dev", "ninja-build", "pciutils",
    ])

    # Debug environment
    print("\n=== Build Environment ===")
    for label, cmd in [
        ("CC", [cc, "--version"]),
        ("CXX", [cxx, "--version"]),
        ("NVCC", ["nvcc", "--version"]),
    ]:
        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        lines = result.stdout.strip().splitlines()
        if label == "NVCC":
            line = next((output_line for output_line in lines if "release" in output_line), lines[0] if lines else "N/A")
        else:
            line = lines[0] if lines else "N/A"
        print(f"{label:16s} {line}")
    print(f"{'CUDA_HOME':16s} {cuda_home}")
    print(f"{'LD_LIBRARY_PATH':16s} {env['LD_LIBRARY_PATH']}")
    print("=========================")

    # Clone or update llama.cpp repository.
    if args.diffusion:
        print(f"\n=== DIFFUSION MODE: building llama-diffusion-cli from DiffusionGemma PR #{DIFFUSION_PR} ===")
        branch = sync_repo_to_pr(REPO_DIR, REPO_URL, DIFFUSION_PR, env=env)
    elif args.beta is not None:
        print(f"\n=== BETA MODE: Building from PR #{args.beta} ===")
        branch = sync_repo_to_pr(REPO_DIR, REPO_URL, args.beta, env=env)
    else:
        branch = sync_repo_to_latest(REPO_DIR, REPO_URL, env=env)
    print(f"Using llama.cpp branch: {branch}")

    print("\nBuilding llama.cpp with GCC 14 + CUDA support...\n")

    # Remove stale CMake cache to pick up compiler changes
    for path in [f"{REPO_DIR}/build/CMakeCache.txt", f"{REPO_DIR}/build/CMakeFiles"]:
        if os.path.isfile(path):
            os.remove(path)
        elif os.path.isdir(path):
            shutil.rmtree(path)

    # Get CPU count
    nproc = os.cpu_count() or 4

    # Configure CMake with CUDA support and GCC 14 optimizations
    cmake_bin = "/usr/local/bin/cmake"
    run([
        cmake_bin, REPO_DIR,
        "-B", f"{REPO_DIR}/build",
        "-G", "Ninja",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DCMAKE_BUILD_TYPE=Release",
        f"-DCMAKE_C_COMPILER={cc}",
        f"-DCMAKE_CXX_COMPILER={cxx}",
        f"-DCMAKE_AR={ar}",
        f"-DCMAKE_RANLIB={ranlib}",
        f"-DCMAKE_CUDA_COMPILER={cuda_home}/bin/nvcc",
        f"-DCMAKE_CUDA_HOST_COMPILER={cxx}",
        "-DCMAKE_CUDA_FLAGS=--diag-suppress=177",
        "-DCMAKE_MAKE_PROGRAM=/usr/local/bin/ninja",
        f"-DCUDAToolkit_ROOT={cuda_home}",
        "-DCMAKE_CUDA_ARCHITECTURES=89",
        "-DGGML_CUDA=ON",
        "-DGGML_CUDA_FA=ON",
        "-DGGML_CUDA_FA_ALL_QUANTS=ON",
        "-DGGML_CUDA_GRAPHS=ON",
        "-DGGML_CUDA_COMPRESSION_MODE=size",
        "-DGGML_NATIVE=ON",
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
        "-DGGML_LTO=ON",
        "-DGGML_OPENMP=ON",
        "-DGGML_CCACHE=ON",
        "-DGGML_CPU_REPACK=ON",
    ], env=env)

    # Clean previous build artifacts
    ninja_bin = "/usr/local/bin/ninja"
    run([ninja_bin, "-C", f"{REPO_DIR}/build", "-t", "clean"], env=env, check=False)

    # Build specific targets with ninja.
    # Diffusion mode builds ONLY the DiffusionGemma runners. Because the build is
    # static (-DBUILD_SHARED_LIBS=OFF, CUDA compiled in), the resulting binaries
    # are self-contained and install cleanly next to the mainline llama-server
    # instead of overwriting it with a PR-branch build.
    #   - llama-diffusion-cli ................. interactive terminal runner
    #   - llama-diffusion-gemma-visual-server . persistent stdin/stdout server that
    #       takes OpenAI-format messages and streams the denoised answer back; this
    #       is what the chat web app's diffusion_shim.py drives.
    if args.diffusion:
        build_targets = ["llama-diffusion-cli", "llama-diffusion-gemma-visual-server"]
    else:
        build_targets = [
            "llama-cli", "llama-mtmd-cli", "llama-server",
            "llama-gguf-split", "llama-bench",
            "llama-perplexity", "llama-quantize", "llama-imatrix",
        ]
    run([ninja_bin, "-C", f"{REPO_DIR}/build", f"-j{nproc}", *build_targets], env=env)

    print(f"\nllama.cpp built successfully in {REPO_DIR}/build/bin")

    # Install every requested static binary before removing the source tree.
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
        path for path in installed_binaries
        if not os.path.isfile(path) or not os.access(path, os.X_OK)
    ]
    if invalid_installs:
        invalid_list = "\n".join(f"  - {path}" for path in invalid_installs)
        raise RuntimeError(f"Installed binaries could not be verified:\n{invalid_list}")
    print(f"Installed {len(installed_binaries)} static binaries successfully.")

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
