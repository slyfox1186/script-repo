"""Regression tests for the compress-then-offer-delete shell helpers.

Every function that archives a directory and then offers to delete it must keep
the directory unless 7-Zip succeeded, the new archive passes `7z t`, the archive
lies outside the directory, and the directory did not change while it was read.

The function files are not sourced whole: some define aliases or run commands at
load time, and one has an unrelated syntax error.  Each test extracts only the
functions it exercises and runs them with stubbed `clear`/`sudo` in a scratch
directory.
"""

import os
import re
import shutil
import stat
import subprocess
import textwrap

import pytest

from conftest import REPO_ROOT

REAL_7Z = shutil.which("7z")
HELPERS = ("_7z_dir_snapshot", "_7z_archive_then_offer_delete")

# (file, entry function, arguments before the source directory, archive suffix)
SITES = [
    ("Bash/Arch-Linux-Scripts/.bash_functions", "7z_1", (), ".7z"),
    ("Bash/Arch-Linux-Scripts/.bash_functions", "7z_5", (), ".7z"),
    ("Bash/Arch-Linux-Scripts/.bash_functions", "7z_9", (), ".7z"),
    ("Bash/Arch-Linux-Scripts/.bash_functions.d/04_compression.sh", "7z_compress", ("5",), ".7z"),
    ("Bash/Arch-Linux-Scripts/.bash_functions.d/04_compression.sh", "zip_compress", ("5",), ".zip"),
    ("Bash/Ubuntu-Scripts/jammy/user-scripts/.bash_functions.d/04_compression.sh", "7z_compress", ("5",), ".7z"),
    ("Bash/Debian-Scripts/bookworm/user-scripts/.bash_functions", "7z_1", (), ".7z"),
    ("Bash/Debian-Scripts/bookworm/user-scripts/.bash_functions", "7z_5", (), ".7z"),
    ("Bash/Debian-Scripts/bookworm/user-scripts/.bash_functions", "7z_9", (), ".7z"),
    ("Bash/Debian-Scripts/bookworm/user-scripts/plain-scripts/.bash_functions", "7z_1", (), ".7z"),
    ("Bash/Debian-Scripts/bookworm/user-scripts/plain-scripts/.bash_functions", "7z_5", (), ".7z"),
    ("Bash/Debian-Scripts/bookworm/user-scripts/plain-scripts/.bash_functions", "7z_9", (), ".7z"),
    ("Bash/Raspbian-OS/user-scripts/.bash_functions", "7z_1", (), ".7z"),
    ("Bash/Raspbian-OS/user-scripts/.bash_functions", "7z_5", (), ".7z"),
    ("Bash/Raspbian-OS/user-scripts/.bash_functions", "7z_9", (), ".7z"),
    ("Bash/Ubuntu-Scripts/jammy-bak/user-scripts/.bash_functions", "7z_1", (), ".7z"),
    ("Bash/Ubuntu-Scripts/jammy-bak/user-scripts/.bash_functions", "7z_5", (), ".7z"),
    ("Bash/Ubuntu-Scripts/jammy-bak/user-scripts/.bash_functions", "7z_9", (), ".7z"),
]
SITE_IDS = ["{}:{}".format(path.split("Bash/", 1)[1], name) for path, name, _, _ in SITES]

needs_7z = pytest.mark.skipif(REAL_7Z is None, reason="7z is not installed")


def extract_functions(relative_path, names):
    text = (REPO_ROOT / relative_path).read_text()
    chunks = []
    for name in names:
        match = re.search(
            r"^" + re.escape(name) + r"\(\) \{\n.*?^\}\n", text, re.M | re.S
        )
        assert match, "{} not found in {}".format(name, relative_path)
        chunks.append(match.group(0))
    return "\n".join(chunks)


def write_stub(directory, name, body):
    path = directory / name
    path.write_text("#!/usr/bin/env bash\n" + textwrap.dedent(body))
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def make_stubs(tmp_path, fake_7z=None):
    stubs = tmp_path / "stubs"
    stubs.mkdir(exist_ok=True)
    write_stub(stubs, "clear", ":\n")
    write_stub(stubs, "sudo", 'exec "$@"\n')
    if fake_7z is not None:
        write_stub(stubs, "7z", fake_7z)
    return stubs


def run_site(tmp_path, site, source_arg, cwd, answer="1\n", fake_7z=None):
    relative_path, name, pre_args, _ = site
    stubs = make_stubs(tmp_path, fake_7z)
    path_entries = [str(stubs)]
    if REAL_7Z:
        path_entries.append(os.path.dirname(REAL_7Z))
    path_entries += ["/usr/bin", "/bin"]
    script = "{defs}\n{call} \"$@\"\n".format(
        defs=extract_functions(relative_path, HELPERS + (name,)), call=name
    )
    env = {
        "PATH": os.pathsep.join(path_entries),
        "HOME": str(tmp_path),
        "TERM": "dumb",
        "LC_ALL": "C",
    }
    return subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", script, "bash", *pre_args, source_arg],
        cwd=str(cwd),
        env=env,
        input=answer,
        capture_output=True,
        text=True,
        timeout=120,
    )


def make_source(parent, name="src"):
    source = parent / name
    (source / "sub").mkdir(parents=True)
    (source / "a.txt").write_text("alpha\n")
    (source / ".hidden").write_text("secret\n")
    (source / "sub" / ".nested").write_text("nested\n")
    return source


def archive_paths(archive):
    listing = subprocess.run(
        [REAL_7Z, "l", "-ba", "-slt", "--", str(archive)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return {line[len("Path = "):] for line in listing.splitlines() if line.startswith("Path = ")}


@pytest.mark.parametrize("site", SITES, ids=SITE_IDS)
@pytest.mark.parametrize(
    "fake_7z",
    [
        pytest.param('echo "disk full" >&2\nexit 2\n', id="fatal"),
        # 7-Zip exits 1 when it skipped unreadable input but still wrote a valid
        # archive, so only the exit status reveals the missing data.
        pytest.param(
            '"{}" "$@" >/dev/null || exit\n[[ "$1" == a ]] && exit 1\nexit 0\n'.format(REAL_7Z),
            id="warning",
            marks=needs_7z,
        ),
    ],
)
def test_failed_compression_keeps_source(tmp_path, site, fake_7z):
    work = tmp_path / "work"
    work.mkdir()
    source = make_source(work)
    result = run_site(tmp_path, site, "src", work, fake_7z=fake_7z)
    assert result.returncode != 0
    assert (source / "a.txt").is_file() and (source / ".hidden").is_file()
    assert not (work / ("src" + site[3])).exists()


@pytest.mark.parametrize("site", SITES, ids=SITE_IDS)
def test_archive_failing_integrity_test_keeps_source(tmp_path, site):
    work = tmp_path / "work"
    work.mkdir()
    source = make_source(work)
    fake = """
    if [[ "$1" == a ]]; then
        shift $(($# - 2))
        printf 'garbage' > "$1"
        exit 0
    fi
    exit 2
    """
    result = run_site(tmp_path, site, "src", work, fake_7z=fake)
    assert result.returncode != 0
    assert (source / "a.txt").is_file()
    assert not (work / ("src" + site[3])).exists()


@needs_7z
@pytest.mark.parametrize("site", SITES, ids=SITE_IDS)
def test_source_changed_during_compression_is_kept(tmp_path, site):
    work = tmp_path / "work"
    work.mkdir()
    source = make_source(work)
    fake = 'if [[ "$1" == a ]]; then echo late > "{}/late.txt"; fi\nexec "{}" "$@"\n'.format(
        source, REAL_7Z
    )
    result = run_site(tmp_path, site, "src", work, fake_7z=fake)
    assert result.returncode != 0
    assert (source / "late.txt").is_file() and (source / "a.txt").is_file()


@needs_7z
@pytest.mark.parametrize("site", SITES, ids=SITE_IDS)
@pytest.mark.parametrize("answer, deleted", [("1\n", True), ("2\n", False), ("\n", False)])
def test_successful_archive_includes_hidden_files(tmp_path, site, answer, deleted):
    work = tmp_path / "work"
    work.mkdir()
    source = make_source(work)
    result = run_site(tmp_path, site, "src/", work, answer=answer)
    assert result.returncode == 0, result.stderr
    archive = work / ("src" + site[3])
    assert archive.is_file()
    assert {"a.txt", ".hidden", "sub", "sub/.nested"} <= archive_paths(archive)
    subprocess.run([REAL_7Z, "t", "--", str(archive)], capture_output=True, check=True)
    assert source.exists() != deleted


@needs_7z
@pytest.mark.parametrize("site", SITES, ids=SITE_IDS)
def test_archive_inside_source_is_refused(tmp_path, site):
    source = make_source(tmp_path)
    before = sorted(p.name for p in source.rglob("*"))
    result = run_site(tmp_path, site, ".", source)
    assert result.returncode != 0
    assert sorted(p.name for p in source.rglob("*")) == before


@needs_7z
@pytest.mark.parametrize(
    "site",
    [site for site in SITES if "plain-scripts" not in site[0]],
    ids=[i for i in SITE_IDS if "plain-scripts" not in i],
)
def test_absolute_source_from_inside_is_refused(tmp_path, site):
    # The plain Bookworm variant writes <source>.7z beside the source, so an
    # absolute source never places its archive inside itself.
    source = make_source(tmp_path)
    before = sorted(p.name for p in source.rglob("*"))
    result = run_site(tmp_path, site, str(source), source / "sub")
    assert result.returncode != 0
    assert sorted(p.name for p in source.rglob("*")) == before


@needs_7z
@pytest.mark.parametrize("site", SITES, ids=SITE_IDS)
def test_existing_archive_is_refused_and_untouched(tmp_path, site):
    work = tmp_path / "work"
    work.mkdir()
    source = make_source(work)
    archive = work / ("src" + site[3])
    archive.write_bytes(b"previous archive")
    result = run_site(tmp_path, site, "src", work)
    assert result.returncode != 0
    assert archive.read_bytes() == b"previous archive"
    assert (source / "a.txt").is_file()


@needs_7z
@pytest.mark.parametrize("site", SITES, ids=SITE_IDS)
@pytest.mark.parametrize("name", ["with space", "-dash start"])
def test_awkward_names(tmp_path, site, name):
    work = tmp_path / "work"
    work.mkdir()
    source = make_source(work, name)
    result = run_site(tmp_path, site, name, work)
    assert result.returncode == 0, result.stderr
    archive = work / (name + site[3])
    assert ".hidden" in archive_paths(archive)
    assert not source.exists()


@needs_7z
@pytest.mark.parametrize("site", SITES, ids=SITE_IDS)
def test_absolute_source_elsewhere(tmp_path, site):
    source = make_source(tmp_path / "data")
    work = tmp_path / "work"
    work.mkdir()
    result = run_site(tmp_path, site, str(source), work)
    assert result.returncode == 0, result.stderr
    if "plain-scripts" in site[0]:
        archive = tmp_path / "data" / ("src" + site[3])
    else:
        archive = work / ("src" + site[3])
    assert {"a.txt", ".hidden"} <= archive_paths(archive)
    assert not source.exists()
