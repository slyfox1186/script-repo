# Repository Guidelines

## Project Structure & Module Organization

Place utilities in their language directory: `Bash/`, `Python3/`, `PowerShell/`, `Batch/`, `AHK/`, `AHK-v2/`, `Perl/`, `VBScript/`, or `Tampermonkey/`. Bash groups scripts by distribution/purpose; Python uses topic subdirectories. `Registry/`, `XML/`, and `YAML/` contain registry edits, an editor theme, and Compose configurations. The `build-gcc` crate lives directly in `Rust/`, with modules in `Rust/src/`. Tests are Bash scripts in `tests/`.

## Build, Test, and Development Commands

Run from the root unless specified. For local Python work, inspect dependencies, run `/home/jman/miniconda3/bin/conda env list`, and set `REPO_PYTHON` to a compatible Miniconda environment's absolute interpreter. Verify required imports; no shared Python environment manifest is tracked.

These checks mirror `.github/workflows/python-package.yml` (Python 3.9/3.13, Ruff 0.16.6). GitHub Actions is disabled for this repository, so run them locally:

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

Tests are standalone Bash scripts named `tests/*_test.sh`; run one with `bash tests/<name>_test.sh`. `pytest.ini` selects `tests/`, which currently holds no Python tests; new pytest files go there as `test_*.py` with `test_*` functions. Isolate filesystem changes and mock privileged and network commands.

Rust unit tests are inline under `Rust/src/`; run `cargo test -j 1` from `Rust/` after approval for the suite.

## Commit & Pull Request Guidelines

History mixes imperative subjects (`Update 05_filesystem.sh`) with `fix:`/`docs:` prefixes. Keep commits focused. Describe behavior changes, affected platforms, dependencies, and validation results in PRs; link relevant issues.

## Security & Configuration

Review installers before execution; keep credentials out of source/logs. Follow `SECURITY.md` for private vulnerability reports. Read `Bash/arch-linux/README.md`: its personal dotfiles target Ubuntu/APT despite the directory name.
