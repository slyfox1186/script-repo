"""Exercise dotfile installation with local downloads and a disposable home."""

import os
from pathlib import Path
import subprocess
import sys
import textwrap

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT = REPO_ROOT / "Bash/Arch-Linux-Scripts"


def run_installer(tmp_path, failure=None):
    home = tmp_path / "home"
    home.mkdir()
    for name in (".bashrc", ".bash_aliases", ".bash_functions"):
        (home / name).write_text("# existing user configuration\n")
    for name in (".bash_functions.d", ".bash_aliases.d"):
        (home / name).mkdir()
        (home / name / "old.sh").write_text("printf 'existing user helper\\n'\n")

    stubs = tmp_path / "stubs"
    stubs.mkdir()
    wget = stubs / "wget"
    wget.write_text(
        "#!{}\n".format(sys.executable)
        + textwrap.dedent(
            """
            import os
            from pathlib import Path
            import shutil
            import sys

            output = next(arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('--output-document='))
            relative = sys.argv[-1].split('/Bash/Arch-Linux-Scripts/', 1)[1]
            failure = os.environ.get('DOWNLOAD_FAILURE')
            if failure == 'download' and relative.endswith('04_compression.sh'):
                sys.exit(23)
            if failure == 'syntax' and relative.endswith('04_compression.sh'):
                Path(output).write_text('broken() {\\n')
            else:
                shutil.copyfile(Path(os.environ['SNAPSHOT_SOURCE']) / relative, output)
            """
        )
    )
    wget.chmod(0o700)
    if failure == "copy":
        cp = stubs / "cp"
        cp.write_text(
            "#!/usr/bin/env bash\n"
            'if [[ "${!#}" == "$HOME/.bash_aliases" && ! -e "$COPY_FAIL_MARKER" ]]; then\n'
            '    printf failed > "$COPY_FAIL_MARKER"\n'
            "    exit 42\n"
            "fi\n"
            'exec /usr/bin/cp "$@"\n'
        )
        cp.chmod(0o700)
    env = dict(os.environ)
    env.update(
        HOME=str(home),
        PATH="{}:/usr/bin:/bin".format(stubs),
        SNAPSHOT_SOURCE=str(SNAPSHOT),
        DOWNLOAD_FAILURE=failure or "",
        COPY_FAIL_MARKER=str(tmp_path / "copy-failure"),
    )
    result = subprocess.run(
        ["bash", str(SNAPSHOT / "arch-scripts.sh")],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    return home, result


def assert_originals(home):
    for name in (".bashrc", ".bash_aliases", ".bash_functions"):
        assert (home / name).read_text() == "# existing user configuration\n"
    for name in (".bash_functions.d", ".bash_aliases.d"):
        assert (home / name / "old.sh").read_text() == "printf 'existing user helper\\n'\n"
        assert sorted(p.name for p in (home / name).iterdir()) == ["old.sh"]


def test_snapshot_installs_complete_set_and_preserves_backup(tmp_path):
    home, result = run_installer(tmp_path)
    assert result.returncode == 0, result.stderr
    for name in (".bashrc", ".bash_aliases", ".bash_functions"):
        assert (home / name).read_bytes() == (SNAPSHOT / name).read_bytes()
        assert (home / name).stat().st_mode & 0o777 == 0o600
    source_files = sorted(p.relative_to(SNAPSHOT / ".bash_functions.d") for p in (SNAPSHOT / ".bash_functions.d").rglob("*") if p.is_file())
    installed_files = sorted(p.relative_to(home / ".bash_functions.d") for p in (home / ".bash_functions.d").rglob("*") if p.is_file())
    assert installed_files == source_files
    for name in source_files:
        assert (home / ".bash_functions.d" / name).read_bytes() == (SNAPSHOT / ".bash_functions.d" / name).read_bytes()
    assert not (home / ".bash_aliases.d").exists()
    backups = list((home / ".local/state/bash-dotfiles-backups").iterdir())
    assert len(backups) == 1
    assert_originals(backups[0])
    assert backups[0].stat().st_mode & 0o777 == 0o700


@pytest.mark.parametrize("failure", ["download", "syntax", "copy"])
def test_snapshot_failure_preserves_existing_dotfiles(tmp_path, failure):
    home, result = run_installer(tmp_path, failure)
    assert result.returncode != 0
    assert_originals(home)
    if failure == "copy":
        assert "restoration attempted" in result.stderr
    else:
        assert not (home / ".local/state/bash-dotfiles-backups").exists()
