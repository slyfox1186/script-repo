# Script repository status

Updated: 2026-10-09

Current work covers all 40 installers in
`/home/jman/tmp/script-repo/Bash/installer-scripts/gnu-software/`, the GitHub
version helper, and its bulk lookup caller. Jeff authorized committing and
pushing all pending changes, including his manual directory moves and deletions.
The release branch is `main`; use `git log -1` for the release commit.

No action is required from Jeff.

The installers remain standalone. The legacy builders now use private temporary
workspaces, checked downloads, bounded network waits and retries, validated
options, configurable `JOBS`, and cleanup prompts that retain files at EOF.
Version parsing, compiler selection, build paths, package checks, and publication
of binaries, headers, and pkg-config files were corrected. Meson projects use
Ninja, and release archives use their shipped configure scripts.

GCC now rejects missing or invalid GNU signatures and failed prerequisite checks,
retains dependency-check results, and reports versioned compiler installations
correctly. Saved static binaries survive build cleanup. glibc remains isolated
in its versioned prefix, requires passing tests, and no longer modifies global
library links or the timezone. Existing pinned releases were retained.

`/home/jman/tmp/script-repo/Bash/misc/source-git-repo-version.sh` has a new
`-h`/`--help` menu. It follows GitHub's latest-release designation, uses tag
fallback only when a latest release is absent, validates input, rejects preview
versions, and reports errors with nonzero status. Successful output is one
numeric version line. The bulk caller uses the corrected lowercase URL and
downloads the helper once, completely, before execution.

Read `/home/jman/tmp/script-repo/Bash/installer-scripts/gnu-software/README.md`
for resource controls, cleanup behavior, install locations, and validation limits.
Do not run multiple installers into the same prefix concurrently. Actual GNU
compilation and real installed programs still need validation on a disposable
machine. No installer, full test suite, or production build ran in this session.

Focused validation: 206 GNU installer checks and 163 GitHub helper/caller checks
passed. Filesystem checks used real temporary links and copies; build and package
commands were mocked. A real GNU Autoconf signature was accepted, and the same
archive was rejected after modification. Live GitHub release and tag lookups
also passed. Bash syntax, the repository's ShellCheck error baseline, Ruff
0.16.6 lint, Python compile checks, and diff integrity passed across tracked files.

Repeat the focused checks:

```bash
bash /home/jman/tmp/script-repo/tests/gnu_installers_test.sh
bash /home/jman/tmp/script-repo/tests/source_git_repo_version_test.sh
```

Python validation uses the verified interpreter
`/home/jman/miniconda3/envs/agent-duet/bin/python` (Python 3.13.15). Ruff 0.16.6
was installed in that compatible environment for the repository's lint gate.
GitHub's `Python package` workflow is manually disabled; CodeQL is active.

Previous project facts retained for continuity:

- Architecture detection is at
  `/home/jman/tmp/script-repo/Bash/misc/check-gcc-architecture.sh`. It queries
  GCC's native selection instead of maintaining a CPU list. It prints an
  architecture name, accepts a compiler argument or `GCC`, and fails when native
  detection is unsupported. That work was included in commit `8720da4b`.
- Networking tools and their usage/recovery guide are at
  `/home/jman/tmp/script-repo/Bash/networking/`. The prior networking release was
  `88bb4da9`. Real Netplan/ifupdown activation remains unverified on this machine.
- Personal dotfiles in `/home/jman/tmp/script-repo/Bash/arch-linux-scripts/`
  target Ubuntu/APT. The retained `.bashrc` loads `.bash_aliases`; modular alias
  files remain omitted by the installer.
- QNAP scripts were removed at Jeff's request. Earlier permission snapshots
  predate repository pulls and are not rollback records for this work.
