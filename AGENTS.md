# Repository Guidelines

## Project Structure & Module Organization

Place utilities in their language directory: `Bash/`, `Python3/`, `PowerShell/`, `Batch/`, `AHK/`, `AHK-v2/`, `Perl/`, `VBScript/`, or `Tampermonkey/`. Bash groups scripts by distribution/purpose; Python uses topic subdirectories. `Registry/`, `XML/`, and `YAML/` contain registry edits, an editor theme, and Compose configurations. The `build-gcc` crate lives directly in `Rust/`, with modules in `Rust/src/`. Tests live in `tests/` and `Bash/Arch-Linux-Scripts/tests/`.

## Build, Test, and Development Commands

Run from the root unless specified. For local Python work, inspect dependencies, run `/home/jman/miniconda3/bin/conda env list`, and set `REPO_PYTHON` to a compatible Miniconda environment's absolute interpreter. Verify required imports; no shared Python environment manifest is tracked.

The baseline is defined in `.github/workflows/python-package.yml`, which specifies Python 3.9/3.13 and Ruff 0.16.6:

- `bash -n path/to/script.sh`: syntax check; also check changed `.bashrc`, `.bash_functions`, and `.bash_aliases` files.
- `shellcheck -S error path/to/script.sh`: check shell errors.
- `"$REPO_PYTHON" -m ruff check Python3 --no-cache --select F,E9,B904,B007,S113,S324`: Python lint.
- `"$REPO_PYTHON" -W error::SyntaxWarning -m py_compile path/to/script.py`: compile-check; the workflow checks every tracked Python file.
- `"$REPO_PYTHON" Python3/file_renamer.py /path/to/sample prefix --dry-run`: preview renaming.
- In `Rust/`, use `cargo build -j 1`, `cargo fmt --check`, and `cargo clippy -j 1 --all-targets --all-features -- -D warnings`. Formatting/linting require rustfmt/Clippy components.

Ask Jeff before full suites, production builds, or CPU-intensive jobs.

## Coding Style & Naming Conventions

Use four spaces for new Python/Rust code; preserve surrounding shell style. Python filenames commonly use underscores; shell filenames commonly use hyphens. Preserve public command names. `Rust/rustfmt.toml` specifies four spaces and 100 columns. Avoid unrelated reformatting.

## Testing Guidelines

Use pytest `test_*.py` files and `test_*` functions. `pytest.ini` selects `tests/`; no coverage threshold is configured. Run focused installer tests with `"$REPO_PYTHON" -m pytest tests/test_bash_dotfile_snapshot.py`. Isolate filesystem changes and mock privileged commands. Archive round-trips require `7z`.

Run mirror tests separately: `bash Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh`. Known failure: its `rr` assertion expects an absent alias.

Rust unit tests are inline under `Rust/src/`; run `cargo test -j 1` from `Rust/` after approval for the suite.

## Commit & Pull Request Guidelines

History mixes imperative subjects (`Update 05_filesystem.sh`) with `fix:`/`docs:` prefixes. Keep commits focused. Describe behavior changes, affected platforms, dependencies, and validation results in PRs; link relevant issues.

## Security & Configuration

Review installers before execution; keep credentials out of source/logs. Follow `SECURITY.md` for private vulnerability reports. Read `Bash/Arch-Linux-Scripts/README.md`: its personal dotfiles target Ubuntu/APT despite the directory name.
