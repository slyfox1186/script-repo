"""Regression tests for Python3/llama_cpp_installer.py.

Git fixtures are local repositories under tmp_path; nothing is cloned from the
network, compiled, installed, or run with sudo.
"""

import os
import shutil
import stat
import subprocess

import pytest

from conftest import load_script_module

installer = load_script_module("Python3/llama_cpp_installer.py", "llama_cpp_installer")

requires_git = pytest.mark.skipif(shutil.which("git") is None, reason="git is not installed")


def git(*args, cwd):
    subprocess.run(
        ["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
    )


@pytest.fixture
def git_env(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    monkeypatch.delenv("GIT_DIR", raising=False)
    return dict(os.environ)


@pytest.fixture
def workdir(tmp_path, monkeypatch, git_env):
    """An upstream repository and an empty working directory to run from."""
    upstream = tmp_path / "upstream"
    upstream.mkdir()
    git("init", "-q", cwd=upstream)
    (upstream / "README.md").write_text("upstream\n")
    (upstream / ".gitignore").write_text("/build*\n/models/*\n")
    (upstream / "models").mkdir()
    (upstream / "models" / ".keep").write_text("")
    git("add", "-A", cwd=upstream)
    git("add", "-f", "models/.keep", cwd=upstream)
    git("commit", "-q", "-m", "initial", cwd=upstream)

    run_dir = tmp_path / "run"
    run_dir.mkdir()
    monkeypatch.chdir(run_dir)
    return upstream, run_dir


def clone_as_installer(upstream, env):
    """Produce the checkout the installer itself would leave behind."""
    git("clone", "-q", str(upstream), installer.REPO_DIR, cwd=os.getcwd())
    installer.record_checkout(installer.REPO_DIR, ["HEAD"], env=env)
    build = os.path.join(installer.REPO_DIR, installer.BUILD_SUBDIR, "bin")
    os.makedirs(build)
    with open(os.path.join(build, "llama-server"), "w") as handle:
        handle.write("binary")


@requires_git
def test_pristine_installer_checkout_is_removed(workdir, git_env):
    upstream, _ = workdir
    clone_as_installer(upstream, git_env)
    assert installer.checkout_removal_blockers(installer.REPO_DIR, env=git_env) == []
    installer.remove_existing_repo(installer.REPO_DIR, env=git_env)
    assert not os.path.lexists(installer.REPO_DIR)


@requires_git
def test_unmarked_checkout_is_refused(workdir, git_env):
    upstream, _ = workdir
    git("clone", "-q", str(upstream), installer.REPO_DIR, cwd=os.getcwd())
    with pytest.raises(RuntimeError, match="not created by this installer"):
        installer.remove_existing_repo(installer.REPO_DIR, env=git_env)
    assert os.path.isfile(os.path.join(installer.REPO_DIR, "README.md"))


@requires_git
@pytest.mark.parametrize(
    "user_file",
    ["notes.txt", os.path.join("models", "model.gguf"), os.path.join("docs", "draft.md")],
)
def test_user_files_block_removal(workdir, git_env, user_file):
    upstream, _ = workdir
    clone_as_installer(upstream, git_env)
    path = os.path.join(installer.REPO_DIR, user_file)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write("mine")
    with pytest.raises(RuntimeError, match="changes or files of your own"):
        installer.remove_existing_repo(installer.REPO_DIR, env=git_env)
    assert os.path.isfile(path)


@requires_git
def test_modified_tracked_file_blocks_removal(workdir, git_env):
    upstream, _ = workdir
    clone_as_installer(upstream, git_env)
    with open(os.path.join(installer.REPO_DIR, "README.md"), "a") as handle:
        handle.write("local edit\n")
    assert installer.checkout_removal_blockers(installer.REPO_DIR, env=git_env)


@requires_git
def test_local_commit_blocks_removal(workdir, git_env):
    upstream, _ = workdir
    clone_as_installer(upstream, git_env)
    repo = os.path.abspath(installer.REPO_DIR)
    with open(os.path.join(repo, "README.md"), "a") as handle:
        handle.write("committed locally\n")
    git("commit", "-q", "-am", "local work", cwd=repo)
    blockers = installer.checkout_removal_blockers(installer.REPO_DIR, env=git_env)
    assert any("not on the upstream remote" in reason for reason in blockers)


@requires_git
def test_stash_blocks_removal(workdir, git_env):
    upstream, _ = workdir
    clone_as_installer(upstream, git_env)
    repo = os.path.abspath(installer.REPO_DIR)
    with open(os.path.join(repo, "README.md"), "a") as handle:
        handle.write("stashed\n")
    git("stash", "-q", cwd=repo)
    blockers = installer.checkout_removal_blockers(installer.REPO_DIR, env=git_env)
    assert any("not on the upstream remote" in reason for reason in blockers)


@requires_git
def test_symlink_to_checkout_is_refused(workdir, git_env, tmp_path):
    upstream, _ = workdir
    clone_as_installer(upstream, git_env)
    real = tmp_path / "elsewhere"
    os.rename(installer.REPO_DIR, real)
    os.symlink(real, installer.REPO_DIR)
    with pytest.raises(RuntimeError, match="not a plain directory"):
        installer.remove_existing_repo(installer.REPO_DIR, env=git_env)
    assert (real / "README.md").is_file()


def test_plain_file_is_refused(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    with open(installer.REPO_DIR, "w") as handle:
        handle.write("not a checkout")
    with pytest.raises(RuntimeError, match="not a plain directory"):
        installer.remove_existing_repo(installer.REPO_DIR, env=dict(os.environ))
    assert os.path.isfile(installer.REPO_DIR)


@requires_git
def test_offline_run_keeps_previous_checkout(workdir, git_env, monkeypatch):
    upstream, _ = workdir
    clone_as_installer(upstream, git_env)

    def offline(*_args, **_kwargs):
        raise RuntimeError("could not resolve host")

    monkeypatch.setattr(installer, "remote_default_branch", offline)
    with pytest.raises(RuntimeError, match="could not resolve host"):
        installer.sync_repo_to_latest(installer.REPO_DIR, str(upstream), env=git_env)
    assert os.path.isfile(os.path.join(installer.REPO_DIR, "README.md"))


@requires_git
def test_sync_replaces_checkout_and_marks_new_clone(workdir, git_env, monkeypatch):
    upstream, _ = workdir
    clone_as_installer(upstream, git_env)
    branch = subprocess.run(
        ["git", "-C", str(upstream), "symbolic-ref", "--short", "HEAD"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    monkeypatch.setattr(installer, "remote_default_branch", lambda *_a, **_k: branch)
    upstream_url = "file://" + str(upstream)  # --depth is ignored for plain paths
    installer.sync_repo_to_latest(installer.REPO_DIR, upstream_url, env=git_env)
    assert not os.path.exists(os.path.join(installer.REPO_DIR, installer.BUILD_SUBDIR))
    assert installer.checkout_removal_blockers(installer.REPO_DIR, env=git_env) == []


def make_executable(path, body="#!/bin/sh\nexit 0\n"):
    path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def test_which_non_shim_skips_ccache_shims(tmp_path):
    ccache = tmp_path / "ccache-bin"
    ccache.mkdir()
    make_executable(ccache / "ccache")
    shim_dir = tmp_path / "lib" / "ccache"
    shim_dir.mkdir(parents=True)
    os.symlink(ccache / "ccache", shim_dir / "gcc-14")
    real_dir = tmp_path / "usr-bin"
    real_dir.mkdir()
    make_executable(real_dir / "gcc-14")

    shim_first = os.pathsep.join(["", str(shim_dir), str(real_dir)])
    assert installer._which_non_shim("gcc-14", shim_first) == str(real_dir / "gcc-14")
    assert installer._which_non_shim("gcc-14", str(shim_dir)) is None


def test_which_non_shim_ignores_directories_and_cwd(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    make_executable(tmp_path / "gcc")  # only reachable through an empty entry
    odd = tmp_path / "odd"
    (odd / "gcc").mkdir(parents=True)
    assert installer._which_non_shim("gcc", os.pathsep.join(["", str(odd), ""])) is None


def test_which_non_shim_accepts_symlinked_real_compiler(tmp_path):
    target = tmp_path / "x86_64-linux-gnu-gcc-13"
    make_executable(target)
    bindir = tmp_path / "bin"
    bindir.mkdir()
    os.symlink(target, bindir / "gcc-13")
    assert installer._which_non_shim("gcc-13", str(bindir)) == str(bindir / "gcc-13")


@pytest.mark.parametrize(
    "inherited, expected",
    [
        ("", "/cuda/bin"),
        ("/a::/b", "/cuda/bin:/a:/b"),
        (":/a", "/cuda/bin:/a"),
        ("/a:", "/cuda/bin:/a"),
        ("/cuda/bin:/a", "/cuda/bin:/a"),
    ],
)
def test_join_search_path_drops_empty_and_repeated(inherited, expected):
    assert installer.join_search_path("/cuda/bin", inherited) == expected


def test_build_environment_has_no_current_directory_entries():
    for base in ({}, {"PATH": "", "LD_LIBRARY_PATH": ""}, {"PATH": "/usr/bin:", "LD_LIBRARY_PATH": "/x::/y"}):
        env = installer.build_environment("/usr/local/cuda", base)
        for key in ("PATH", "LD_LIBRARY_PATH"):
            assert "" not in env[key].split(os.pathsep), (base, env[key])
        assert "lib" not in env["PATH"].split(os.pathsep)[0]
        assert env["PATH"].split(os.pathsep)[0] == "/usr/local/cuda/bin"
        assert env["LD_LIBRARY_PATH"].split(os.pathsep)[0] == "/usr/local/cuda/lib64"


def test_describe_head_parses_and_pads(monkeypatch):
    fields = "\x1f".join(["abc123def", "abc123d", "Subject", "Author", "2026-01-01T00:00:00Z"])
    monkeypatch.setattr(installer, "capture", lambda *_a, **_k: fields)
    head = installer.describe_head("repo", env={})
    assert head == {
        "sha": "abc123def",
        "short_sha": "abc123d",
        "subject": "Subject",
        "author": "Author",
        "authored": "2026-01-01T00:00:00Z",
    }
    monkeypatch.setattr(installer, "capture", lambda *_a, **_k: "abc123def")
    assert installer.describe_head("repo", env={})["author"] == "unknown"


@pytest.mark.parametrize("returncode, expected", [(-9, 137), (-15, 143), (2, 2), (0, 1)])
def test_exit_status(returncode, expected):
    assert installer.exit_status(returncode) == expected


def write_fake_binaries(bin_dir, server_body, cli_body):
    bin_dir.mkdir(parents=True, exist_ok=True)
    make_executable(bin_dir / "llama-server", server_body)
    make_executable(bin_dir / "llama-cli", cli_body)


def test_verify_binaries_reports_version_and_devices(tmp_path):
    write_fake_binaries(
        tmp_path,
        "#!/bin/sh\necho 'version: 1234 (abc)' >&2\n",
        "#!/bin/sh\necho 'Available devices:'\necho '  CUDA0: NVIDIA RTX (24000 MiB)'\n",
    )
    version, devices = installer.verify_binaries(str(tmp_path), env=dict(os.environ))
    assert version == "1234 (abc)"
    assert devices == ["CUDA0: NVIDIA RTX (24000 MiB)"]


def test_verify_binaries_allows_no_gpu_listing(tmp_path):
    write_fake_binaries(tmp_path, "#!/bin/sh\necho 'version: 1'\n", "#!/bin/sh\necho 'Available devices:'\n")
    _, devices = installer.verify_binaries(str(tmp_path), env=dict(os.environ))
    assert devices == []


@pytest.mark.parametrize(
    "server_body, cli_body",
    [
        ("#!/bin/sh\necho 'error while loading shared libraries' >&2\nexit 127\n", "#!/bin/sh\nexit 0\n"),
        ("#!/bin/sh\necho 'version: 1'\n", "#!/bin/sh\necho 'ggml_cuda_init: failed' >&2\nexit 1\n"),
    ],
)
def test_verify_binaries_fails_on_nonzero_exit(tmp_path, server_body, cli_body):
    write_fake_binaries(tmp_path, server_body, cli_body)
    with pytest.raises(RuntimeError, match="exited with status"):
        installer.verify_binaries(str(tmp_path), env=dict(os.environ))

