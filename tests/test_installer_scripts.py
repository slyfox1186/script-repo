"""Regression tests for the Miniconda, 7-Zip and Docker Compose installers.

Every package manager, privileged command and network download is replaced by a
stub, HOME points into the test's temporary directory, and destructive commands
are intercepted wherever a refusal is being tested.
"""

import os
import shutil
import stat
import subprocess
import textwrap

import pytest

from conftest import REPO_ROOT

CONDA_SCRIPT = REPO_ROOT / "Bash/Misc/Conda/install_conda.sh"
SEVENZIP_SCRIPT = REPO_ROOT / "Bash/Installer-Scripts/SlyFox1186-Scripts/7zip_installer.sh"
COMPOSE_SCRIPT = REPO_ROOT / "Bash/Misc/docker_compose_multi_arch_installer.sh"
BASH = shutil.which("bash") or "/bin/bash"


def run_bash(script, *, env=None, stdin="", cwd=None, timeout=30):
    # Relative paths typed at a prompt resolve against the test's scratch area.
    if cwd is None and env is not None:
        cwd = env.get("TMPDIR")
    return subprocess.run(
        [BASH, "-c", script],
        input=stdin,
        capture_output=True,
        text=True,
        env=env,
        cwd=cwd,
        timeout=timeout,
    )


def make_stub(directory, name, body):
    path = directory / name
    path.write_text("#!/bin/bash\n" + textwrap.dedent(body))
    path.chmod(0o755)
    return path


@pytest.fixture
def home(tmp_path):
    home_dir = tmp_path / "home" / "user"
    home_dir.mkdir(parents=True)
    (home_dir / "keep.txt").write_text("user data")
    return home_dir


def minimal_path(directory):
    """Create a PATH directory with only the utilities the logging helpers need."""
    directory.mkdir()
    for tool in ("tee", "cat"):
        (directory / tool).symlink_to(shutil.which(tool))
    return directory


@pytest.fixture
def conda_env(tmp_path, home):
    env = dict(os.environ)
    env["HOME"] = str(home)
    env["TMPDIR"] = str(tmp_path)
    return env


def conda_session(body, marker):
    """Source the conda installer with rm and rmdir recorded instead of run."""
    return textwrap.dedent(
        f"""
        source "{CONDA_SCRIPT}"
        rm() {{ echo "rm $*" >> "{marker}"; }}
        rmdir() {{ echo "rmdir $*" >> "{marker}"; }}
        """
    ) + textwrap.dedent(body)


# --- install_conda.sh: choosing and replacing the installation directory ---


@pytest.mark.parametrize(
    "typed",
    [
        "~",
        "$HOME",
        "{home}",
        "{home}/",
        "{home}//../user",
        "{home}/..",
        "/",
        "{link}",
    ],
)
def test_conda_refuses_home_root_ancestors_and_symlinks(tmp_path, home, conda_env, typed):
    link = tmp_path / "link-to-home"
    link.symlink_to(home)
    marker = tmp_path / "removals.log"
    typed = typed.format(home=home, link=link)

    result = run_bash(
        conda_session('get_install_directory; echo "rc=$?"', marker),
        env=conda_env,
        stdin=typed + "\n",
    )

    assert result.returncode != 0
    assert "rc=0" not in result.stdout
    assert not marker.exists()
    assert (home / "keep.txt").read_text() == "user data"


def test_conda_refuses_nonempty_non_conda_directory(tmp_path, conda_env):
    project = tmp_path / "project"
    project.mkdir()
    (project / "work.txt").write_text("important")
    marker = tmp_path / "removals.log"

    result = run_bash(
        conda_session("get_install_directory", marker),
        env=conda_env,
        stdin=f"{project}\n",
    )

    assert result.returncode != 0
    assert "is not empty and is not a conda installation" in result.stderr
    assert not marker.exists()
    assert (project / "work.txt").read_text() == "important"


def test_conda_accepts_new_and_empty_directories_without_recursive_removal(tmp_path, conda_env):
    empty = tmp_path / "empty"
    empty.mkdir()
    marker = tmp_path / "removals.log"

    result = run_bash(
        conda_session("get_install_directory", marker),
        env=conda_env,
        stdin=f"{empty}\n",
    )
    assert result.returncode == 0
    assert result.stdout.strip() == str(empty)

    result = run_bash(
        conda_session("get_install_directory", marker),
        env=conda_env,
        stdin=f"{tmp_path}/new/../fresh\n",
    )
    assert result.returncode == 0
    assert result.stdout.strip() == str(tmp_path / "fresh")
    assert not marker.exists()


def test_conda_prepare_removes_empty_directory_with_rmdir_only(tmp_path, conda_env):
    empty = tmp_path / "empty"
    empty.mkdir()
    result = run_bash(
        f'source "{CONDA_SCRIPT}"; prepare_install_directory "{empty}"',
        env=conda_env,
    )
    assert result.returncode == 0
    assert not empty.exists()


def make_fake_conda(path):
    (path / "conda-meta").mkdir(parents=True)
    (path / "bin").mkdir()
    conda = path / "bin" / "conda"
    conda.write_text("#!/bin/sh\n")
    conda.chmod(0o755)
    (path / "envs" / "work").mkdir(parents=True)


def test_conda_replaces_existing_conda_install_only_after_yes(tmp_path, conda_env):
    install = tmp_path / "miniconda3"
    make_fake_conda(install)

    declined = run_bash(
        f'source "{CONDA_SCRIPT}"; get_install_directory',
        env=conda_env,
        stdin=f"{install}\nn\n",
    )
    assert declined.returncode != 0
    assert install.is_dir()

    accepted = run_bash(
        f'source "{CONDA_SCRIPT}"; dir=$(get_install_directory) && prepare_install_directory "$dir"',
        env=conda_env,
        stdin=f"{install}\ny\n",
    )
    assert accepted.returncode == 0, accepted.stderr
    assert not install.exists()


def test_conda_prepare_refuses_home_even_when_called_directly(tmp_path, home, conda_env):
    marker = tmp_path / "removals.log"
    result = run_bash(
        conda_session(f'prepare_install_directory "{home}"', marker),
        env=conda_env,
    )
    assert result.returncode != 0
    assert not marker.exists()
    assert (home / "keep.txt").exists()


def test_conda_directory_prompt_stops_at_end_of_input(conda_env):
    result = run_bash(
        f'source "{CONDA_SCRIPT}"; get_install_directory',
        env=conda_env,
        stdin="",
        timeout=10,
    )
    assert result.returncode != 0
    assert "No installation directory was entered" in result.stderr


def test_conda_canonicalize_path_resolves_existing_part_and_normalizes_rest(tmp_path, conda_env):
    real = tmp_path / "real"
    real.mkdir()
    (tmp_path / "alias").symlink_to(real)
    result = run_bash(
        f"""
        source "{CONDA_SCRIPT}"
        canonicalize_path "{tmp_path}//alias/./missing/../conda/"
        canonicalize_path "/"
        """,
        env=conda_env,
    )
    assert result.stdout.splitlines() == [str(real / "conda"), "/"]


# --- install_conda.sh: dependencies, disk space and workspace ---


@pytest.mark.parametrize(
    ("distro", "like", "family"),
    [
        ("ubuntu", "debian", "apt"),
        ("linuxmint", "ubuntu debian", "apt"),
        ("pop", "ubuntu debian", "apt"),
        ("rocky", "rhel centos fedora", "rpm"),
        ("endeavouros", "arch", "pacman"),
        ("opensuse-tumbleweed", "opensuse suse", "zypper"),
    ],
)
def test_conda_package_family_uses_id_then_id_like(conda_env, distro, like, family):
    result = run_bash(
        f'source "{CONDA_SCRIPT}"; DISTRO={distro}; DISTRO_LIKE="{like}"; linux_package_family',
        env=conda_env,
    )
    assert result.returncode == 0
    assert result.stdout.strip() == family


def test_conda_unknown_distro_with_tools_present_skips_package_manager(tmp_path, conda_env):
    calls = tmp_path / "sudo.log"
    result = run_bash(
        f"""
        source "{CONDA_SCRIPT}"
        sudo() {{ echo "$*" >> "{calls}"; }}
        OS=linux DISTRO=gentoo DISTRO_LIKE=""
        ensure_dependencies
        """,
        env=conda_env,
    )
    assert result.returncode == 0, result.stderr
    assert not calls.exists()


@pytest.mark.parametrize(
    ("distro", "like", "expected"),
    [
        ("linuxmint", "ubuntu debian", "apt-get install -y curl"),
        ("manjaro", "arch", "pacman -S --needed --noconfirm curl"),
    ],
)
def test_conda_missing_tools_installs_packages_without_full_upgrade(
    tmp_path, conda_env, distro, like, expected
):
    stubs = minimal_path(tmp_path / "stubs")
    calls = tmp_path / "sudo.log"
    env = dict(conda_env, PATH=str(stubs))
    result = run_bash(
        f"""
        source "{CONDA_SCRIPT}"
        sudo() {{
            echo "$*" >> "{calls}"
            printf '#!/bin/sh\\n' > "{stubs}/curl"
            printf '#!/bin/sh\\n' > "{stubs}/tar"
            /bin/chmod 755 "{stubs}/curl" "{stubs}/tar"
        }}
        OS=linux DISTRO={distro} DISTRO_LIKE="{like}"
        ensure_dependencies
        """,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    recorded = calls.read_text()
    assert expected in recorded
    assert "-Syu" not in recorded
    assert "upgrade" not in recorded


def test_conda_unsupported_distro_with_missing_tools_fails_clearly(tmp_path, conda_env):
    stubs = minimal_path(tmp_path / "stubs")
    env = dict(conda_env, PATH=str(stubs))
    result = run_bash(
        f'source "{CONDA_SCRIPT}"; OS=linux DISTRO=gentoo DISTRO_LIKE=""; ensure_dependencies',
        env=env,
    )
    assert result.returncode == 1
    assert "Unsupported Linux distribution: gentoo" in result.stderr


def test_conda_package_manager_failure_is_reported(tmp_path, conda_env):
    stubs = minimal_path(tmp_path / "stubs")
    env = dict(conda_env, PATH=str(stubs))
    result = run_bash(
        f'source "{CONDA_SCRIPT}"; sudo() {{ return 100; }}; OS=linux DISTRO=debian; install_dependencies',
        env=env,
    )
    assert result.returncode == 1
    assert "Failed to install dependencies with apt-get" in result.stderr


@pytest.mark.parametrize(
    ("available", "ok"),
    [("2000000", True), ("1000", False), ("-", False)],
)
def test_conda_disk_space_uses_posix_df_for_install_location(tmp_path, conda_env, available, ok):
    calls = tmp_path / "df.log"
    target = tmp_path / "not" / "created" / "miniconda3"
    result = run_bash(
        f"""
        source "{CONDA_SCRIPT}"
        df() {{
            echo "$*" >> "{calls}"
            echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
            echo "/dev/sda1 9999999 1 {available} 1% /"
        }}
        check_disk_space "{target}"
        """,
        env=conda_env,
    )
    assert (result.returncode == 0) is ok, result.stderr
    assert calls.read_text().strip() == f"-Pk {tmp_path}"


def test_conda_workspace_is_private_and_removed_on_success(tmp_path, conda_env):
    result = run_bash(
        f"""
        source "{CONDA_SCRIPT}"
        set -euo pipefail
        init_workspace
        stat -c '%a' "$TEMP_DIR"
        echo "$TEMP_DIR"
        log "working"
        """,
        env=conda_env,
    )
    assert result.returncode == 0, result.stderr
    mode, workspace = result.stdout.split()
    assert mode == "700"
    assert workspace.startswith(str(tmp_path / "conda_installer."))
    assert not os.path.exists(workspace)
    assert not list((tmp_path / "home" / "user").glob("miniconda_install_log.*"))


def test_conda_workspace_keeps_log_after_failure(tmp_path, home, conda_env):
    result = run_bash(
        f"""
        source "{CONDA_SCRIPT}"
        set -euo pipefail
        init_workspace
        echo "$TEMP_DIR"
        fail "download broke"
        """,
        env=conda_env,
    )
    assert result.returncode == 1
    workspace = result.stdout.strip()
    assert not os.path.exists(workspace)
    kept = list(home.glob("miniconda_install_log.*"))
    assert len(kept) == 1
    assert "download broke" in kept[0].read_text()
    assert stat.S_IMODE(kept[0].stat().st_mode) == 0o600


def test_conda_kept_installer_never_replaces_existing_file(tmp_path, home, conda_env):
    workspace = tmp_path / "ws"
    workspace.mkdir()
    (workspace / "Miniconda3-test.sh").write_text("new installer")
    (home / "Miniconda3-test.sh").write_text("older copy")
    result = run_bash(
        f"""
        source "{CONDA_SCRIPT}"
        TEMP_DIR="{workspace}" INSTALLER=Miniconda3-test.sh
        cleanup_installer
        """,
        env=conda_env,
        stdin="n\n",
    )
    assert result.returncode == 0, result.stderr
    assert (home / "Miniconda3-test.sh").read_text() == "older copy"
    kept = list(home.glob("Miniconda3-test.sh.*"))
    assert len(kept) == 1
    assert kept[0].read_text() == "new installer"
    assert f"Installer kept at: {kept[0]}" in result.stderr


def test_conda_script_is_side_effect_free_when_sourced(tmp_path, conda_env):
    result = run_bash(
        f'source "{CONDA_SCRIPT}"; echo "[$TEMP_DIR]"; [[ $- != *e* ]] && echo no-errexit',
        env=conda_env,
    )
    assert result.stdout.split() == ["[]", "no-errexit"]
    assert not list(tmp_path.glob("conda_installer*"))


# --- 7zip_installer.sh: working directory ---


@pytest.fixture
def sevenzip_stubs(tmp_path):
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    calls = tmp_path / "calls.log"
    make_stub(
        stubs,
        "wget",
        f"""
        echo "wget $*" >> "{calls}"
        out=""
        while (($#)); do
            case "$1" in
                -qO-) echo '<a>Download 7-Zip 99.01 (2099-01-01) for Windows</a>'; exit 0 ;;
                -cqO) out="$2"; shift ;;
            esac
            shift
        done
        echo archive > "$out"
        """,
    )
    make_stub(
        stubs,
        "tar",
        f"""
        echo "tar $*" >> "{calls}"
        while (($#)); do
            [[ "$1" == -C ]] && touch "$2/7zzs"
            shift
        done
        """,
    )
    make_stub(stubs, "sudo", f'echo "sudo $*" >> "{calls}"\n')
    make_stub(
        stubs,
        "uname",
        """
        case "$1" in
            -s) echo Linux ;;
            -m) echo x86_64 ;;
        esac
        """,
    )
    return stubs, calls


def run_sevenzip(tmp_path, stubs, *args):
    workdir = tmp_path / "cwd"
    workdir.mkdir(exist_ok=True)
    scratch = tmp_path / "tmp"
    scratch.mkdir(exist_ok=True)
    env = dict(os.environ, PATH=f"{stubs}:/usr/bin:/bin", TMPDIR=str(scratch), TERM="dumb")
    result = subprocess.run(
        [BASH, str(SEVENZIP_SCRIPT), *args],
        input="y\n",
        capture_output=True,
        text=True,
        env=env,
        cwd=workdir,
        timeout=30,
    )
    return result, workdir, scratch


def test_sevenzip_keeps_existing_directory_and_cleans_only_its_own(tmp_path, sevenzip_stubs):
    stubs, calls = sevenzip_stubs
    existing = tmp_path / "cwd" / "7zip-install-script"
    existing.mkdir(parents=True)
    (existing / "sentinel.txt").write_text("mine")

    result, _, scratch = run_sevenzip(tmp_path, stubs)

    assert result.returncode == 0, result.stdout + result.stderr
    assert (existing / "sentinel.txt").read_text() == "mine"
    assert list(scratch.iterdir()) == []
    recorded = calls.read_text()
    assert "7zip-install-script" not in recorded
    assert "sudo rm" not in recorded
    assert "sudo cp -f" in recorded


def test_sevenzip_no_cleanup_prints_retained_directory(tmp_path, sevenzip_stubs):
    stubs, _ = sevenzip_stubs
    result, _, scratch = run_sevenzip(tmp_path, stubs, "--no-cleanup")

    assert result.returncode == 0, result.stdout + result.stderr
    kept = list(scratch.iterdir())
    assert len(kept) == 1
    assert f"Installation files kept in: {kept[0]}" in result.stdout
    assert (kept[0] / "7zip-99.01" / "7zzs").exists()


def test_sevenzip_package_family_and_failure_propagation(tmp_path):
    body = textwrap.dedent(
        f"""
        eval "$(sed -n '/^log()/,/^}}/p; /^fail()/,/^}}/p; /^linux_package_family()/,/^}}/p; /^install_dependencies()/,/^}}/p' "{SEVENZIP_SCRIPT}")"
        OS=linux DISTRO=endeavouros DISTRO_LIKE=arch
        linux_package_family
        sudo() {{ echo "sudo $*"; return 1; }}
        install_dependencies
        """
    )
    result = run_bash(body)
    assert result.returncode == 1
    lines = result.stdout.splitlines()
    assert lines[0] == "pacman"
    sudo_calls = [line for line in lines if line.startswith("sudo ")]
    assert sudo_calls == ["sudo pacman -S --needed --noconfirm tar wget xz"]
    assert "Failed to install dependencies with pacman" in result.stdout


# --- docker_compose_multi_arch_installer.sh: missing curl ---


def unshare_available():
    unshare = shutil.which("unshare")
    if not unshare:
        return None
    probe = subprocess.run(
        [unshare, "-r", BASH, "-c", "exit 0"], capture_output=True, timeout=10
    )
    return unshare if probe.returncode == 0 else None


UNSHARE = unshare_available()


def run_compose_main(tmp_path, *, with_curl, with_apt_get, apt_get_succeeds=True):
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    calls = tmp_path / "calls.log"
    if with_curl:
        make_stub(stubs, "curl", "exit 0\n")
    if with_apt_get:
        install_curl = (
            f'[[ "$1" == install ]] && printf "#!/bin/sh\\n" > "{stubs}/curl" && /bin/chmod 755 "{stubs}/curl"\n'
            if apt_get_succeeds
            else '[[ "$1" == install ]] && exit 100\n'
        )
        make_stub(stubs, "apt-get", f'echo "apt-get $*" >> "{calls}"\n' + install_curl + "exit 0\n")
    script = textwrap.dedent(
        f"""
        source "{COMPOSE_SCRIPT}"
        fetch_and_install_docker_compose() {{ echo "fetch $*" >> "{calls}"; }}
        PATH="{stubs}"
        main
        """
    )
    result = subprocess.run(
        [UNSHARE, "-r", BASH, "-c", script],
        capture_output=True,
        text=True,
        timeout=30,
    )
    recorded = calls.read_text() if calls.exists() else ""
    return result, recorded


@pytest.mark.skipif(UNSHARE is None, reason="unprivileged user namespaces are unavailable")
def test_compose_installs_only_curl_then_continues(tmp_path):
    result, recorded = run_compose_main(tmp_path, with_curl=False, with_apt_get=True)
    assert result.returncode == 0, result.stderr
    assert recorded.splitlines() == [
        "apt-get update",
        "apt-get install -y curl",
        "fetch false",
    ]


@pytest.mark.skipif(UNSHARE is None, reason="unprivileged user namespaces are unavailable")
def test_compose_fails_when_curl_cannot_be_installed(tmp_path):
    result, recorded = run_compose_main(
        tmp_path, with_curl=False, with_apt_get=True, apt_get_succeeds=False
    )
    assert result.returncode == 1
    assert "fetch" not in recorded
    assert "Failed to install curl" in result.stderr


@pytest.mark.skipif(UNSHARE is None, reason="unprivileged user namespaces are unavailable")
def test_compose_without_curl_or_apt_get_fails_clearly(tmp_path):
    result, recorded = run_compose_main(tmp_path, with_curl=False, with_apt_get=False)
    assert result.returncode == 1
    assert "curl is required" in result.stderr
    assert recorded == ""


@pytest.mark.skipif(UNSHARE is None, reason="unprivileged user namespaces are unavailable")
def test_compose_with_curl_goes_straight_to_fetch(tmp_path):
    result, recorded = run_compose_main(tmp_path, with_curl=True, with_apt_get=True)
    assert result.returncode == 0, result.stderr
    assert recorded.splitlines() == ["fetch false"]
