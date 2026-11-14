# Repository Guidelines

## Project Structure & Module Organization

Place utilities in their language directory (`Bash/`, `Python3/`, `PowerShell/`, `Batch/`, `AHK/`, `AHK-v2/`, `Perl/`, `VBScript/` or `Tampermonkey/`). Bash groups scripts by distribution or purpose; Python uses topic subdirectories.

## Build, Test, and Development Commands

Run from the root unless specified. For local Python work, inspect dependencies, run `/home/jman/miniconda3/bin/conda env list`, and set `REPO_PYTHON` to a compatible Miniconda environment's absolute interpreter. Verify required imports; no shared Python environment manifest is tracked.

These checks mirror `.github/workflows/python-package.yml` (Python 3.9/3.13, Ruff 0.16.6). GitHub Actions is disabled for this repository, so run them locally:

- `bash -n path/to/script.sh`: syntax check; also check changed `.bashrc`, `.bash_functions`, and `.bash_aliases` files.
- `shellcheck -S error path/to/script.sh`: check shell errors.
- `"$REPO_PYTHON" -m ruff check Python3 --no-cache --select F,E9,B904,B007,S113,S324`: Python lint.
- `"$REPO_PYTHON" -W error::SyntaxWarning -m py_compile path/to/script.py`: compile-check; the workflow checks every tracked Python file.
- In `Rust/`, use `cargo build -j 1`, `cargo fmt --check`, and `cargo clippy -j 1 --all-targets --all-features -- -D warnings`. Formatting/linting require rustfmt/Clippy components.

## Coding Style & Naming Conventions

Use four spaces for new Python code (Rust follows `Rust/rustfmt.toml`); preserve surrounding shell style. Python filenames commonly use underscores; shell filenames commonly use hyphens. Preserve public command names.

## Testing Guidelines

Tests are standalone Bash scripts named `tests/*_test.sh`; run one with `bash tests/<name>_test.sh`. `pytest.ini` selects `tests/`, which currently holds no Python tests; new pytest files go there as `test_*.py` with `test_*` functions. Isolate filesystem changes and mock privileged and network commands.

Rust unit tests are inline under `Rust/src/`; run `cargo test -j 1` from `Rust/` once Jeff approves the suite.

## Commit & Pull Request Guidelines

Commit subjects are imperative (`Update 05_filesystem.sh`) or carry a `fix:`/`docs:` prefix. PR descriptions state behavior changes, affected platforms, dependencies and validation results.

## Security & Configuration

Follow `SECURITY.md` for private vulnerability reports. The personal dotfiles in `Bash/arch-linux/` target Ubuntu/APT despite the directory name (see its `README.md`).
