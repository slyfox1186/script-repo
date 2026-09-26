"""Regression tests for Python3/pip_updater.py.

Every test works on throwaway data under pytest's tmp_path: disposable
virtual environments, locally built wheels, and a private cache directory.
Nothing contacts a package index or touches a real conda environment; pip is
pointed at a local wheel directory through PIP_NO_INDEX/PIP_FIND_LINKS.
"""

import base64
import csv
import hashlib
import io
import json
import os
import signal
import subprocess
import sys
import textwrap
import time
import zipfile
from pathlib import Path

import pytest

from conftest import REPO_ROOT, load_script_module

pu = load_script_module("Python3/pip_updater.py", "pip_updater_under_test")

PY_TAG = f"cpython-{sys.version_info[0]}{sys.version_info[1]}"


@pytest.fixture(autouse=True)
def private_cache(tmp_path, monkeypatch):
    """Keep every cache, lock, and journal write inside tmp_path."""
    root = tmp_path / "cache" / "pip-updater"
    monkeypatch.setattr(pu, "CACHE_ROOT", root)
    monkeypatch.setattr(pu, "CACHE_FILE", str(root / "cache-v2.json"))
    for name in list(os.environ):
        if name.startswith("PIP_"):
            monkeypatch.delenv(name)
    monkeypatch.setenv("PIP_CONFIG_FILE", os.devnull)
    monkeypatch.setenv("PIP_DISABLE_PIP_VERSION_CHECK", "1")
    monkeypatch.setenv("PIP_NO_CACHE_DIR", "1")
    return root


def _record_hash(data):
    digest = hashlib.sha256(data).digest()
    return "sha256=" + base64.urlsafe_b64encode(digest).rstrip(b"=").decode()


def build_wheel(directory, name, version, *, files=None, requires=(), record_extra=()):
    """Write a minimal pure-Python wheel and return its path."""
    dist = f"{name}-{version}"
    dist_info = f"{dist}.dist-info"
    members = dict(files if files is not None else {f"{name}/__init__.py": b""})
    metadata = f"Metadata-Version: 2.1\nName: {name}\nVersion: {version}\n"
    metadata += "".join(f"Requires-Dist: {req}\n" for req in requires)
    members[f"{dist_info}/METADATA"] = metadata.encode()
    members[f"{dist_info}/WHEEL"] = (
        b"Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
    )
    record = io.StringIO()
    writer = csv.writer(record, lineterminator="\n")
    for path, data in members.items():
        writer.writerow([path, _record_hash(data), len(data)])
    for row in record_extra:
        writer.writerow(row)
    writer.writerow([f"{dist_info}/RECORD", "", ""])
    members[f"{dist_info}/RECORD"] = record.getvalue().encode()
    path = Path(directory) / f"{dist}-py3-none-any.whl"
    with zipfile.ZipFile(path, "w") as archive:
        for member, data in members.items():
            archive.writestr(member, data)
    return path


def fake_layout(prefix):
    site = Path(prefix) / "lib" / "python3.13" / "site-packages"
    return {
        "purelib": str(site),
        "platlib": str(site),
        "scripts": str(Path(prefix) / "bin"),
        "data": str(prefix),
        "include": str(Path(prefix) / "include" / "python3.13"),
        "headers_base": str(Path(prefix) / "include" / "python3.13"),
        "cache_tag": "cpython-313",
    }


def install_fake_dist(prefix, name, version, paths):
    """Create installed metadata whose RECORD claims the given site paths."""
    site = Path(prefix) / "lib" / "python3.13" / "site-packages"
    dist_info = site / f"{name}-{version}.dist-info"
    dist_info.mkdir(parents=True)
    rows = list(paths) + [f"{dist_info.name}/RECORD"]
    for relative in paths:
        target = site / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(f"{name}\n")
    (dist_info / "RECORD").write_text("".join(f"{row},,\n" for row in rows))
    return {"name": name, "version": version, "metadata_path": str(dist_info)}


def site_target(relative):
    return f"lib/python3.13/site-packages/{relative}"


def new_wheel(name, targets, generated=()):
    return {
        "name": name,
        "version": "2.0",
        "sha256": "0" * 64,
        "targets": {site_target(t) for t in targets} | {site_target(g) for g in generated},
        "generated": {site_target(g) for g in generated},
    }


def plan_item(name, version="2.0", current="1.0"):
    return {"name": name, "version": version, "sha256": "0" * 64, "current_version": current}


NO_CONDA = {"paths": set(), "distributions": set()}


# F12 -- decoded wheel filenames must not reach aria2 option syntax.

@pytest.mark.parametrize(
    "url",
    [
        "https://x/pkg-1.0-py3-none-any.whl%0A%20%20dir=..%0A%20%20out=escape.whl",
        "https://x/pkg-1.0-py3-none-any%0Acheck-certificate=false%0Ax.whl",
        "https://x/pkg-1.0-py3-none-any.whl%0D",
        "https://x/pkg%091.0-py3-none-any.whl",
        "https://x/pkg-1.0-py3-none-any%2F..%2Fx.whl",
        "https://x/pkg-1.0-py3-none-any%5Cx.whl",
        "https://x/pkg-1.0-py3-none-any%00.whl",
        "https://x/-pkg-1.0-py3-none-any.whl",
        "https://x/pkg-1.0-py3-none-any.whl\tmirror",
        "https://x/pkg.whl",
    ],
)
def test_wheel_filename_rejects_unsafe_names(url):
    with pytest.raises(pu.UpdaterError):
        pu.wheel_filename_from_url(url)


@pytest.mark.parametrize(
    "url,expected",
    [
        (
            "https://f/torch-2.4.0%2Bcu121-cp313-cp313-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
            "torch-2.4.0+cu121-cp313-cp313-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        ),
        ("https://f/six-1.16.0-py2.py3-none-any.whl", "six-1.16.0-py2.py3-none-any.whl"),
        ("https://f/pkg-1.0-1-py3-none-any.whl#sha256=ab", "pkg-1.0-1-py3-none-any.whl"),
        ("https://f/zope.interface-5.4.0-cp39-cp39-win_amd64.whl", "zope.interface-5.4.0-cp39-cp39-win_amd64.whl"),
        ("https://f/pkg-1!2.0-py3-none-any.whl", "pkg-1!2.0-py3-none-any.whl"),
    ],
)
def test_wheel_filename_accepts_real_names(url, expected):
    assert pu.wheel_filename_from_url(url) == expected


def test_aria2_input_boundary_revalidates(monkeypatch, tmp_path):
    monkeypatch.setattr(pu.shutil, "which", lambda _name: "/nonexistent/aria2c")
    unsafe = {
        "name": "pkg",
        "url": "https://x/pkg-1.0-py3-none-any.whl",
        "filename": "pkg-1.0-py3-none-any.whl\n  dir=..",
        "sha256": "a" * 64,
    }
    with pytest.raises(pu.UpdaterError, match="unsafe download entry"):
        pu.download_with_aria2([unsafe], tmp_path, progress=None)


# F05 -- RECORD rows are uninstall authority and must match archive members.

@pytest.mark.parametrize(
    "extra_row",
    [
        ["../../../bin/python", "", ""],
        ["/etc/passwd", "", ""],
        ["pkg/not_in_archive.py", "", ""],
        ["pkg/__init__.py", "", ""],
    ],
)
def test_inspect_wheel_rejects_unsafe_record_rows(tmp_path, extra_row):
    wheel = build_wheel(tmp_path, "pkg", "1.0", record_extra=[extra_row])
    with pytest.raises(pu.UpdaterError, match="RECORD"):
        pu.inspect_wheel(wheel, tmp_path, fake_layout(tmp_path))


def test_inspect_wheel_requires_record(tmp_path):
    path = tmp_path / "pkg-1.0-py3-none-any.whl"
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("pkg-1.0.dist-info/METADATA", "Name: pkg\nVersion: 1.0\n")
        archive.writestr("pkg-1.0.dist-info/WHEEL", "Root-Is-Purelib: true\n")
    with pytest.raises(pu.UpdaterError, match="lacks RECORD"):
        pu.inspect_wheel(path, tmp_path, fake_layout(tmp_path))


def test_inspect_wheel_models_bytecode_and_named_headers(tmp_path):
    wheel = build_wheel(
        tmp_path,
        "My_Pkg",
        "1.0",
        files={
            "my_pkg/__init__.py": b"",
            "My_Pkg-1.0.data/headers/demo.h": b"int x;\n",
        },
    )
    info = pu.inspect_wheel(wheel, tmp_path, fake_layout(tmp_path), "My_Pkg")
    assert "include/python3.13/My_Pkg/demo.h" in info["targets"]
    pyc = site_target("my_pkg/__pycache__/__init__.cpython-313.pyc")
    assert pyc in info["targets"] and info["generated"] == {pyc}


# F06 / F13 -- shared paths and pip's per-package uninstall/install order.

def _shared_prefix(tmp_path):
    prefix = tmp_path / "prefix"
    shared = ["ns/shared.py", "ns/__pycache__/shared.cpython-313.pyc"]
    inventory = {
        "a": install_fake_dist(prefix, "a", "1.0", shared + ["a.py"]),
        "b": install_fake_dist(prefix, "b", "1.0", shared + ["b.py"]),
    }
    return prefix, inventory


def test_order_dependent_shared_file_is_refused(tmp_path):
    prefix, inventory = _shared_prefix(tmp_path)
    plan = [plan_item("a"), plan_item("b")]
    wheels = {
        "a": new_wheel("a", ["ns/shared.py", "a.py"], ["ns/__pycache__/shared.cpython-313.pyc"]),
        "b": new_wheel("b", ["b.py"]),
    }
    with pytest.raises(pu.UpdaterError, match="one at a time"):
        pu.validate_new_wheels(prefix, plan, wheels, inventory, NO_CONDA)


def test_shared_file_written_by_every_replaced_claimant_is_accepted(tmp_path):
    prefix, inventory = _shared_prefix(tmp_path)
    plan = [plan_item("a"), plan_item("b")]
    pyc = ["ns/__pycache__/shared.cpython-313.pyc"]
    wheels = {
        "a": new_wheel("a", ["ns/shared.py", "a.py"], pyc),
        "b": new_wheel("b", ["ns/shared.py", "b.py"], pyc),
    }
    shared = pu.validate_new_wheels(prefix, plan, wheels, inventory, NO_CONDA)
    assert site_target("ns/shared.py") in shared


def test_shared_bytecode_is_not_a_false_refusal(tmp_path):
    prefix, inventory = _shared_prefix(tmp_path)
    plan = [plan_item("a")]
    wheels = {
        "a": new_wheel(
            "a", ["ns/shared.py", "a.py"], ["ns/__pycache__/shared.cpython-313.pyc"]
        )
    }
    pu.validate_new_wheels(prefix, plan, wheels, inventory, NO_CONDA)


def test_moved_file_between_replaced_and_new_package_is_refused(tmp_path):
    prefix = tmp_path / "prefix"
    inventory = {"a": install_fake_dist(prefix, "a", "1.0", ["a/sub.py", "a/__init__.py"])}
    plan = [plan_item("a"), plan_item("a-core", current=None)]
    wheels = {
        "a": new_wheel("a", ["a/__init__.py"]),
        "a-core": new_wheel("a-core", ["a/sub.py"]),
    }
    with pytest.raises(pu.UpdaterError, match="one at a time"):
        pu.validate_new_wheels(prefix, plan, wheels, inventory, NO_CONDA)


def test_shared_backup_restores_exact_bytes(tmp_path):
    prefix, _inventory = _shared_prefix(tmp_path)
    txn = tmp_path / "txn"
    txn.mkdir()
    shared = site_target("ns/shared.py")
    claims = {shared: {"a", "b"}}
    path = prefix / shared
    path.write_bytes(b"winner\n")
    backups = pu.backup_shared_files(prefix, claims, {"a"}, txn / "shared")
    path.write_bytes(b"other\n")
    pu.restore_shared_files(prefix, txn, backups)
    assert path.read_bytes() == b"winner\n"
    (txn / backups[0]["backup"]).write_bytes(b"tampered")
    with pytest.raises(pu.UpdaterError, match="has changed"):
        pu.restore_shared_files(prefix, txn, backups)


# F07 -- rollback artifacts are verified like update artifacts.

def test_rollback_wheel_hash_and_ownership_are_enforced(tmp_path):
    prefix = tmp_path / "prefix"
    inventory = {"a": install_fake_dist(prefix, "a", "1.0", ["a/__init__.py"])}
    wheel = {
        "name": "a",
        "version": "1.0",
        "sha256": "1" * 64,
        "targets": {site_target("a/__init__.py"), site_target("a-1.0.dist-info/RECORD")},
        "generated": set(),
    }
    artifacts = [{"name": "a", "sha256": "1" * 64}]
    pu.validate_rollback_wheels(prefix, {"a": "1.0"}, {"a": wheel}, artifacts, inventory, NO_CONDA)

    with pytest.raises(pu.UpdaterError, match="checksum"):
        pu.validate_rollback_wheels(
            prefix, {"a": "1.0"}, {"a": wheel}, [{"name": "a", "sha256": "0" * 64}],
            inventory, NO_CONDA,
        )
    stray = dict(wheel, targets=wheel["targets"] | {"bin/python"})
    with pytest.raises(pu.UpdaterError, match="does not own"):
        pu.validate_rollback_wheels(prefix, {"a": "1.0"}, {"a": stray}, artifacts, inventory, NO_CONDA)
    conda = {"paths": {site_target("a/__init__.py")}, "distributions": set()}
    with pytest.raises(pu.UpdaterError, match="Conda-owned"):
        pu.validate_rollback_wheels(prefix, {"a": "1.0"}, {"a": wheel}, artifacts, inventory, conda)


def test_rollback_artifacts_are_reverified(tmp_path):
    old = tmp_path / "old"
    old.mkdir()
    wheel = old / "a-1.0-py3-none-any.whl"
    wheel.write_bytes(b"wheel")
    manifest = {
        "old_artifacts": {
            "a": {"filename": wheel.name, "sha256": hashlib.sha256(b"wheel").hexdigest()}
        }
    }
    pu.verify_rollback_artifacts(tmp_path, manifest)
    wheel.write_bytes(b"changed")
    with pytest.raises(pu.UpdaterError, match="has changed"):
        pu.verify_rollback_artifacts(tmp_path, manifest)
    wheel.unlink()
    with pytest.raises(pu.UpdaterError, match="missing or unexpected"):
        pu.verify_rollback_artifacts(tmp_path, manifest)


def test_yanked_rollback_copy_is_allowed_with_warning(monkeypatch, capsys):
    report = {
        "install": [
            {
                "is_yanked": True,
                "metadata": {"name": "a", "version": "1.0"},
                "download_info": {
                    "url": "https://x/a-1.0-py3-none-any.whl",
                    "archive_info": {"hashes": {"sha256": "A" * 64}},
                },
            }
        ]
    }

    def fake_stream(args, **_kwargs):
        Path(args[args.index("--report") + 1]).write_text(json.dumps(report))
        return subprocess.CompletedProcess(args, 0, "", "")

    monkeypatch.setattr(pu, "stream_command", fake_stream)
    monkeypatch.setattr(pu, "pip_command", lambda _prefix: ["pip"])
    found = pu.resolve_exact_download_artifacts("/p", ["a==1.0"])
    assert found[0]["yanked"] and found[0]["sha256"] == "a" * 64
    assert "yanked" in capsys.readouterr().out


# F04 -- preview never recovers, rolls back, or deletes journals.

def _journal(root, name, prefix, status):
    directory = root / "transactions" / name
    directory.mkdir(parents=True)
    (directory / "manifest.json").write_text(json.dumps({"prefix": str(prefix), "status": status}))
    return directory


def test_dry_run_recovery_is_read_only(private_cache, tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(pu, "rollback_transaction", lambda *args: calls.append(args))
    prefix = tmp_path / "env"
    prefix.mkdir()
    applying = _journal(private_cache, "txn-applying", prefix, "applying")
    prepared = _journal(private_cache, "txn-prepared", prefix, "prepared")
    other = _journal(private_cache, "txn-other", tmp_path, "applying")
    before = (applying / "manifest.json").read_text()

    with pytest.raises(pu.UpdaterError, match="without --dry-run"):
        pu.recover_incomplete_transactions(prefix, dry_run=True)
    assert calls == []
    assert (applying / "manifest.json").read_text() == before
    assert prepared.is_dir() and other.is_dir()

    pu.recover_incomplete_transactions(prefix)
    assert len(calls) == 1
    assert not applying.exists() and not prepared.exists() and other.is_dir()


def test_unknown_journal_status_is_refused(private_cache, tmp_path):
    prefix = tmp_path / "env"
    prefix.mkdir()
    journal = _journal(private_cache, "txn-x", prefix, "half-written")
    for dry_run in (True, False):
        with pytest.raises(pu.UpdaterError, match="unrecognized status"):
            pu.recover_incomplete_transactions(prefix, dry_run=dry_run)
    assert journal.is_dir()


def test_main_dry_run_refuses_before_any_rollback(private_cache, tmp_path, monkeypatch):
    prefix = tmp_path / "env"
    prefix.mkdir()
    _journal(private_cache, "txn-applying", prefix, "applying")
    calls = []
    monkeypatch.setattr(pu, "rollback_transaction", lambda *args: calls.append("rollback"))
    monkeypatch.setattr(pu, "prune_stale_locks", lambda: calls.append("prune"))
    monkeypatch.setattr(pu, "install_termination_handlers", lambda: None)
    monkeypatch.setattr(
        pu, "get_known_environments", lambda: ({"base": "/root", "env": str(prefix)}, "/root")
    )
    monkeypatch.setattr(pu, "activate_environment", lambda *_args: None)
    monkeypatch.setattr(pu, "preflight_health", lambda _p: calls.append("preflight"))
    monkeypatch.setattr(sys, "argv", ["pip_updater.py", "env", "--all", "--dry-run"])
    with pytest.raises(pu.UpdaterError, match="without --dry-run"):
        pu.main()
    assert calls == []


# F09 / F22 -- postflight compares broken edges, not version-bearing text.

def test_postflight_tolerates_same_broken_edge_only():
    before = ["pkga 1.0 has requirement pkgb<2, but you have pkgb 2.0."]
    same_edge = "pkga 1.0 has requirement pkgb<2, but you have pkgb 2.1."
    new_edge = "pkga 1.0 has requirement pkgc<3, but you have pkgc 3.0."
    missing = "pkgd 1.0 requires pkge, which is not installed."
    assert pu.new_pip_conflicts({same_edge}, before) == set()
    assert pu.new_pip_conflicts({same_edge, new_edge, missing}, before) == {new_edge, missing}
    assert pu.pip_conflict_key(missing) == ("pkgd", "pkge")
    assert pu.new_pip_conflicts({missing}, [missing.replace("1.0", "0.9")]) == set()


# F14 -- holds are context-dependent.

def test_hold_lifts_when_capper_is_offered(monkeypatch, tmp_path):
    prefix = tmp_path / "env"
    site = prefix / "lib" / "site-packages"
    inventory = []
    for name, version in (("a", "1.0"), ("b", "1.9")):
        inventory.append(
            {
                "name": name,
                "version": version,
                "installer": "pip",
                "direct_url": "",
                "metadata_path": str(site / f"{name}-{version}.dist-info"),
            }
        )
    holds = {"b": {"name": "b", "installed": "1.9", "latest": "2.0", "cappers": {"a": "1.0"}}}
    monkeypatch.setattr(pu, "get_cached_holds", lambda _prefix: holds)
    b = {"name": "b", "version": "1.9", "latest_version": "2.0"}
    a = {"name": "a", "version": "1.0", "latest_version": "2.0"}

    eligible, excluded = pu.filter_outdated_packages([b], inventory, NO_CONDA, prefix)
    assert eligible == [] and excluded == [("b", "held back by a")]

    eligible, excluded = pu.filter_outdated_packages([a, b], inventory, NO_CONDA, prefix)
    assert [row["name"] for row in eligible] == ["a", "b"] and excluded == []

    holds["b"]["installed"] = "1.8"
    eligible, _excluded = pu.filter_outdated_packages([b], inventory, NO_CONDA, prefix)
    assert [row["name"] for row in eligible] == ["b"]


# F15 -- child lifetime and stdin backpressure.

def test_stream_command_waits_for_child_after_eof():
    child = "import os,sys,time; os.close(1); os.close(2); time.sleep(0.5); sys.exit(3)"
    start = time.monotonic()
    result = pu.stream_command([sys.executable, "-c", child], timeout=10, tick=0.05)
    assert result.returncode == 3
    assert time.monotonic() - start >= 0.45


def test_stream_command_deadline_bounds_unread_stdin():
    start = time.monotonic()
    with pytest.raises(pu.UpdaterError, match="timed out"):
        pu.stream_command(
            [sys.executable, "-c", "import time; time.sleep(30)"],
            input_data=b"x" * 2_000_000,
            timeout=0.5,
            tick=0.05,
        )
    assert time.monotonic() - start < 5


def test_stream_command_interleaves_large_input_and_output():
    echo = "import sys\nfor line in sys.stdin: sys.stdout.write(line)\n"
    payload = "".join(f"line {index:07d}\n" for index in range(200_000))
    result = pu.stream_command(
        [sys.executable, "-c", echo], input_data=payload, timeout=60, tick=0.1
    )
    assert result.returncode == 0
    assert result.stdout.splitlines()[-1] == "line 0199999"


# F23 -- exit status follows the signal number.

def test_termination_signal_exit_status(tmp_path):
    fake_conda = tmp_path / "conda"
    fake_conda.write_text("#!/bin/sh\nkill -HUP $PPID\nsleep 5\n")
    fake_conda.chmod(0o755)
    env = {key: value for key, value in os.environ.items() if not key.startswith("PIP_")}
    env.update(CONDA_EXE=str(fake_conda), XDG_CACHE_HOME=str(tmp_path / "cache"))
    result = subprocess.run(
        [sys.executable, str(REPO_ROOT / "Python3" / "pip_updater.py"), "env", "--all"],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 128 + signal.SIGHUP, result.stderr
    assert "signal 1" in result.stderr


# Target-interpreter checks run against disposable virtual environments.

@pytest.fixture(scope="module")
def wheelhouse(tmp_path_factory):
    directory = tmp_path_factory.mktemp("wheels")
    build_wheel(directory, "pkga", "1.0", requires=["pkgb<2"])
    for version in ("1.9", "2.0", "2.1"):
        build_wheel(directory, "pkgb", version)
    for version in ("1.0", "2.0"):
        build_wheel(directory, "pkgc", version)
    build_wheel(directory, "pkgd", "1.0", requires=["pkge<2"])
    for version in ("1.0", "2.0"):
        build_wheel(directory, "pkge", version)
    return directory


def make_venv(path, wheelhouse, installs):
    subprocess.run([sys.executable, "-m", "venv", str(path)], check=True)
    (path / "conda-meta").mkdir()
    python = str(path / "bin" / "python")
    subprocess.run(
        [python, "-m", "pip", "install", "-q", "--no-deps", "--no-index",
         "--find-links", str(wheelhouse)] + list(installs),
        check=True,
    )
    return path


@pytest.fixture
def conflicted_env(tmp_path, wheelhouse, monkeypatch):
    """pkga 1.0 needs pkgb<2 while pkgb 2.0 is installed: an existing conflict."""
    monkeypatch.setenv("PIP_NO_INDEX", "1")
    monkeypatch.setenv("PIP_FIND_LINKS", str(wheelhouse))
    return make_venv(
        tmp_path / "venv",
        wheelhouse,
        ["pkga==1.0", "pkgb==2.0", "pkgc==1.0", "pkgd==1.0", "pkge==1.0"],
    )


@pytest.fixture
def resolving_env(conflicted_env, tmp_path):
    """The conflicted venv, when its pip reports hashes for local wheels.

    Real indexes publish SHA-256 digests, which the updater requires.  For
    ``--find-links`` files only newer pips compute one in ``--report`` (the pip
    bundled with Python 3.9 does not), so resolver tests need such a pip.
    """
    report = tmp_path / "hash-probe.json"
    subprocess.run(
        [str(conflicted_env / "bin" / "python"), "-m", "pip", "install", "--dry-run",
         "--ignore-installed", "--no-deps", "--report", str(report), "pkgc==1.0"],
        check=True,
        capture_output=True,
    )
    item = json.loads(report.read_text())["install"][0]
    if not item["download_info"].get("archive_info", {}).get("hashes"):
        pytest.skip("this pip omits local-wheel hashes from --report")
    return conflicted_env


def test_pip_install_location_overrides_are_refused(conflicted_env, tmp_path, monkeypatch):
    pu.check_pip_install_location(conflicted_env)
    for variable, value in (
        ("PIP_PREFIX", str(tmp_path / "elsewhere")),
        ("PIP_TARGET", str(tmp_path / "elsewhere")),
        ("PIP_ROOT", str(tmp_path / "elsewhere")),
        ("PIP_USER", "1"),
    ):
        monkeypatch.setenv(variable, value)
        with pytest.raises(pu.UpdaterError, match="install somewhere other"):
            pu.check_pip_install_location(conflicted_env)
        monkeypatch.delenv(variable)
    config = tmp_path / "pip.conf"
    config.write_text(f"[install]\nprefix = {tmp_path / 'elsewhere'}\n")
    monkeypatch.setenv("PIP_CONFIG_FILE", str(config))
    with pytest.raises(pu.UpdaterError, match="prefix="):
        pu.check_pip_install_location(conflicted_env)


def test_existing_conflict_no_longer_blocks_unrelated_update(resolving_env):
    plan = pu.resolve_update_plan(str(resolving_env), ["pkgc"])
    assert [(item["name"], item["version"]) for item in plan] == [("pkgc", "2.0")]


def test_broken_holder_is_constrained_not_rooted(conflicted_env):
    analysis = pu.analyze_requirements(conflicted_env)
    assert analysis["broken_holders"] == {"pkga": []}
    inventory = pu.index_inventory(pu.get_environment_inventory(conflicted_env))
    roots, constraints, unpinnable = pu.retained_environment_pins(
        inventory, {"pkgc": ("pkgc", "2.0")}, analysis
    )
    assert "pkga==1.0" in constraints and "pkga==1.0" not in roots
    assert "pkgb==2.0" in roots and unpinnable == []


def test_downgrade_and_newly_broken_plans_are_refused(conflicted_env):
    inventory = pu.index_inventory(pu.get_environment_inventory(conflicted_env))
    downgrade = [dict(plan_item("pkgb", "1.9", "2.0"), requires=[])]
    analysis = pu.analyze_requirements(conflicted_env, downgrade)
    assert analysis["downgrades"] == [{"name": "pkgb", "current": "2.0", "proposed": "1.9"}]
    with pytest.raises(pu.UpdaterError, match="--allow-downgrade"):
        pu.enforce_plan_policy(downgrade, inventory, {"pkgb"}, analysis, allow_downgrade=False)
    pu.enforce_plan_policy(downgrade, inventory, {"pkgb"}, analysis, allow_downgrade=True)
    assert downgrade[0]["downgrade"] is True

    breaks_cap = [dict(plan_item("pkge", "2.0", "1.0"), requires=[])]
    analysis = pu.analyze_requirements(conflicted_env, breaks_cap)
    assert [edge["requirement"] for edge in analysis["newly_broken"]] == ["pkge<2"]
    with pytest.raises(pu.UpdaterError, match="unmet"):
        pu.enforce_plan_policy(breaks_cap, inventory, {"pkge"}, analysis, allow_downgrade=False)

    unselected = [dict(plan_item("pkgc", "2.0", "1.0"), requires=[])]
    with pytest.raises(pu.UpdaterError, match="did not select"):
        pu.enforce_plan_policy(
            unselected, inventory, {"pkge"}, pu.analyze_requirements(conflicted_env, unselected),
            allow_downgrade=False,
        )


def test_invalid_installed_version_is_not_pinned(resolving_env):
    site = next((resolving_env / "lib").glob("python*/site-packages"))
    dist_info = site / "legacy-1.0_custom.dist-info"
    dist_info.mkdir()
    (dist_info / "METADATA").write_text("Metadata-Version: 2.1\nName: legacy\nVersion: 1.0-custom\n")
    (dist_info / "INSTALLER").write_text("pip\n")
    (dist_info / "RECORD").write_text(f"{dist_info.name}/METADATA,,\n")
    analysis = pu.analyze_requirements(resolving_env)
    assert analysis["invalid_versions"] == ["legacy"]
    inventory = pu.index_inventory(pu.get_environment_inventory(resolving_env))
    roots, constraints, unpinnable = pu.retained_environment_pins(inventory, {}, analysis)
    assert unpinnable == ["legacy 1.0-custom"]
    assert not any(spec.startswith("legacy") for spec in roots + constraints)
    plan = pu.resolve_update_plan(str(resolving_env), ["pkgc"])
    assert [item["name"] for item in plan] == ["pkgc"]


def _fake_health(monkeypatch):
    def preflight(prefix):
        return {
            "doctor": "healthy",
            "conda_records_digest": pu.load_conda_ownership(prefix)["records_digest"],
            "conda_issues": {},
            "pip_broken": sorted(pu.pip_check_report(prefix)),
        }

    monkeypatch.setattr(pu, "preflight_health", preflight)
    monkeypatch.setattr(pu, "doctor_snapshot", lambda _prefix: "healthy")


def test_transaction_applies_and_forced_failure_rolls_back(resolving_env, tmp_path, monkeypatch):
    """A real install into a disposable venv, then a forced post-install failure."""
    _fake_health(monkeypatch)
    sentinel = tmp_path / "outside" / "sentinel.txt"
    sentinel.parent.mkdir()
    sentinel.write_text("untouched\n")
    prefix = str(resolving_env)

    plan = pu.resolve_update_plan(prefix, ["pkgc"])
    pu.update_packages(prefix, "venv", ["pkgc"], plan)
    versions = {row["name"]: row["version"] for row in pu.get_environment_inventory(prefix)}
    assert versions["pkgc"] == "2.0" and versions["pkgb"] == "2.0"

    original = pu.verify_targets_present

    def fail_after_install(prefix_arg, target_list):
        if Path(target_list).name == "new-targets.json":
            raise pu.UpdaterError("forced post-install failure")
        return original(prefix_arg, target_list)

    monkeypatch.setattr(pu, "verify_targets_present", fail_after_install)
    plan = pu.resolve_update_plan(prefix, ["pkgb"])
    assert [(item["name"], item["version"]) for item in plan] == [("pkgb", "2.1")]
    with pytest.raises(pu.UpdaterError, match="rolled back successfully"):
        pu.update_packages(prefix, "venv", ["pkgb"], plan)
    versions = {row["name"]: row["version"] for row in pu.get_environment_inventory(prefix)}
    assert versions["pkgb"] == "2.0"
    assert sentinel.read_text() == "untouched\n"
    assert not list((pu.CACHE_ROOT / "transactions").glob("txn-*"))


def test_help_mentions_allow_downgrade():
    result = subprocess.run(
        [sys.executable, str(REPO_ROOT / "Python3" / "pip_updater.py"), "--help"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0
    assert "--allow-downgrade" in textwrap.dedent(result.stdout)
