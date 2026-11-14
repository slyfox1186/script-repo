# Script repository status

Updated: 2026-11-14

Latest change: `Bash/installer-scripts/github-projects/build-tools.sh` now builds each Meson venv
beside the live one (`lib/build-tools/meson-VERSION.XXXXXX`) and removes the old one only after the
new one passes its version check, so a failed upgrade keeps Meson working. Manifest cleanup stops at
the install prefix instead of climbing past it with `rmdir -p`. The legacy report also lists Meson
files that pre-5.0 versions put in `/usr/local/local` and `/usr/local/lib/python3*/dist-packages`
with `sudo pip install`; those leftovers were removed from JSERVERPC. The script can be sourced, and
`tests/build_tools_test.sh` (44 checks) covers the cleanup and report. GitHub Actions is disabled
for the repository; the three built-in workflows still show `active` because GitHub cannot disable
them one at a time.

Earlier today: `build-tar.sh` and `build-all-gnu.sh` backport GNU tar maintainer commit
`8632df398b2f548465ebe68b8f494c0d6f8d913d` for tar 1.35, adding `$(LIBINTL) $(LIBICONV)` to
`tar_LDADD` in `Makefile.am` and the release's pregenerated `Makefile.in`. Pristine release files
patch cleanly and the focused standalone configure/link check runs GNU tar 1.35 with libiconv
resolved. `build-texinfo.sh` now uses Texinfo 7.3; its previously failing `makedoc.c`,
`echo-area.c`, and `m-x.c` compile with the script's flags. The complete `info/` and `tta/`
subdirectories also built, including the Perl XS modules. All 59 browser user-agent lines across 39
installers use Firefox 160 on X11/Linux exactly as requested. The mocked installer suite passed all
227 checks; Bash syntax and ShellCheck error-level checks passed across all 40 installers. No full
build or installation was run.

Earlier today: `build-all-gnu.sh` now uses valid Wget and Make configure options, current
development dependencies, and the required download user agent. Live release/archive discovery
passed for all 16 programs. Configure-only checks passed for Wget 1.25.0, Make 4.4.1, and Nano
9.3; no package installation or installation was run.

Earlier change (2026-11-08): new `Bash/ubuntu-scripts/resolute-raccoon/` holds JSERVERPC's Ubuntu 26.04 Bash
configuration (`.bashrc`, `.bash_aliases`, `.bash_functions` and `.bash_functions.d/`, login files,
`.inputrc`, `.nanorc`), copied unchanged, with a README. Dotfiles only: the jammy setup, package and
mirror scripts were not ported. See `CHANGELOG.md`.

Earlier change (2026-11-07): every dotfile set uses JSERVERPC's two-line prompt and colors.

Current work covers all 40 installers in
`/home/jman/tmp/github_projects/script-repo/Bash/installer-scripts/gnu-software/`, the GitHub
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

`/home/jman/tmp/github_projects/script-repo/Bash/misc/source-git-repo-version.sh` has a new
`-h`/`--help` menu with cyan headings, green commands, and clearer spacing.
Help fits an 80-column terminal and honors `NO_COLOR`; redirected output stays
plain. Tag links accept GitHub's canonical repository casing, including
`FFmpeg/FFmpeg` when the requested URL uses `ffmpeg/ffmpeg`. The copy at
`/home/jman/tmp/source-git-repo-version.sh` includes this fix and returned `9.0.2`
for Jeff's exact FFmpeg command. It follows GitHub's latest-release designation, uses tag
fallback only when a latest release is absent, validates input, rejects preview
versions, and reports errors with nonzero status. Successful output is one
numeric version line. The bulk caller uses the corrected lowercase URL and
downloads the helper once, completely, before execution.

Read `/home/jman/tmp/github_projects/script-repo/Bash/installer-scripts/gnu-software/README.md`
for resource controls, cleanup behavior, install locations, and validation limits.
Do not run multiple installers into the same prefix concurrently. Actual GNU
compilation and real installed programs still need validation on a disposable
machine. No installer, full test suite, or production build ran in this session.

Focused validation: 213 GNU installer checks and 176 GitHub helper/caller checks
passed. Filesystem checks used real temporary links and copies; build and package
commands were mocked. A real GNU Autoconf signature was accepted, and the same
archive was rejected after modification. Live GitHub release and tag lookups
also passed. Bash syntax, the repository's ShellCheck error baseline, Ruff
0.16.6 lint, Python compile checks, and diff integrity passed across tracked files.

Repeat the focused checks:

```bash
bash /home/jman/tmp/github_projects/script-repo/tests/gnu_installers_test.sh
bash /home/jman/tmp/github_projects/script-repo/tests/source_git_repo_version_test.sh
```

The `agent-duet` environment used for earlier Python validation no longer exists. For Python
checks, set `REPO_PYTHON` to a compatible Miniconda interpreter as `CLAUDE.md` describes, with
Ruff 0.16.6 for the lint gate.
GitHub's `Python package` workflow is manually disabled; CodeQL is active.

Previous project facts retained for continuity:

- Architecture detection is at
  `/home/jman/tmp/github_projects/script-repo/Bash/misc/check-gcc-architecture.sh`. It queries
  GCC's native selection instead of maintaining a CPU list. It prints an
  architecture name, accepts a compiler argument or `GCC`, and fails when native
  detection is unsupported. That work was included in commit `8720da4b`.
- Networking tools and their usage/recovery guide are at
  `/home/jman/tmp/github_projects/script-repo/Bash/networking/`. The prior networking release was
  `88bb4da9`. Real Netplan/ifupdown activation remains unverified on this machine.
- Personal dotfiles in `/home/jman/tmp/github_projects/script-repo/Bash/arch-linux/`
  target Ubuntu/APT. The retained `.bashrc` loads `.bash_aliases`; modular alias
  files remain omitted by the installer.
- QNAP scripts were removed at Jeff's request. Earlier permission snapshots
  predate repository pulls and are not rollback records for this work.
