# Arch Mirror Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the Arch mirror refresh script, unify the `rr` shortcut around it, install a verified current mirrorlist, and complete the interrupted system upgrade.

**Architecture:** Keep mirror discovery, validation, endpoint probing, and atomic installation in the existing standalone Bash script. Exercise the script through a shell regression harness that supplies controlled command doubles through `PATH`, then run the same production path against current Arch infrastructure.

**Tech Stack:** Bash, Reflector, curl, pacman, coreutils, ShellCheck

---

### Task 1: Regression Harness and Safe Defaults

**Files:**
- Create: `Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh`
- Modify: `Bash/Arch-Linux-Scripts/update_mirrorlist.sh`

- [ ] **Step 1: Write failing tests for help, defaults, and invalid arguments**

Create a self-contained Bash harness that supplies `reflector`, `curl`, `pacman`, `sudo`, and `install` command doubles through `PATH`, and asserts that `--non-interactive --dry-run` invokes Reflector with age 12, country United States, HTTPS, IPv4, 100% completion, a 20-mirror score pool, local rate sorting, and 10 ranked candidates from which 5 will be retained. Assert rejection of missing option values, nonnumeric counts, fewer than five retained mirrors, non-HTTPS protocols, and non-absolute save paths.

- [ ] **Step 2: Run the focused harness and verify RED**

Run: `bash Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh`

Expected: FAIL because the script lacks non-interactive/dry-run modes and safe validation.

- [ ] **Step 3: Implement strict parsing and defaults**

Add `set -Eeuo pipefail`, usage/error helpers, defaults of age 12, country `United States`, five retained mirrors, timeout 5, score pool 20, HTTPS, IPv4, 100% completion, and support for `--non-interactive` and `--dry-run`. Validate each argument before network or privileged operations. Only install Reflector when `command -v reflector` fails, using a full `pacman -Syu --needed --noconfirm reflector` transaction.

- [ ] **Step 4: Run the harness and syntax checks**

Run: `bash Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh && bash -n Bash/Arch-Linux-Scripts/update_mirrorlist.sh`

Expected: all default and argument tests pass; syntax check exits 0.

### Task 2: Candidate Validation and Atomic Installation

**Files:**
- Modify: `Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh`
- Modify: `Bash/Arch-Linux-Scripts/update_mirrorlist.sh`

- [ ] **Step 1: Write failing validation and installation tests**

Add cases where Reflector fails, emits fewer than five servers, emits an HTTP server, repository probes fail, or a pending package/signature is missing; assert nonzero exit and no destination mutation. Add a success case with ten HTTPS candidates and five completely successful mirrors; assert backup creation, root-mode installation request, destination content, and temporary-file cleanup.

- [ ] **Step 2: Run the focused harness and verify RED**

Run: `bash Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh`

Expected: new cases fail because candidate validation and atomic installation are absent.

- [ ] **Step 3: Implement fail-closed replacement**

Generate into temporary files, install a cleanup trap, parse active `Server =` lines, require at least five unique HTTPS URLs, reject active HTTP URLs, probe all enabled repository databases and every pending package/signature with bounded curl requests until five candidates pass, and leave dry runs uninstalled. For live runs, create a timestamped archive backup, stage the candidate with root ownership and mode 0644, then atomically rename it over the destination.

- [ ] **Step 4: Run regression and static checks**

Run: `bash Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh && bash -n Bash/Arch-Linux-Scripts/update_mirrorlist.sh && command -v shellcheck >/dev/null && shellcheck Bash/Arch-Linux-Scripts/update_mirrorlist.sh Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh || true`

Expected: harness passes, syntax exits 0, and ShellCheck reports no findings when installed.

### Task 3: Unify the Shell Shortcut

**Files:**
- Modify: `Bash/Arch-Linux-Scripts/.bash_aliases`
- Modify: `/home/jman/.bash_aliases`
- Test: `Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh`

- [ ] **Step 1: Add a failing alias-contract assertion**

Assert that the repository `rr` alias invokes `update_mirrorlist.sh --non-interactive` and contains no inline `reflector` command.

- [ ] **Step 2: Run the assertion and verify RED**

Run: `bash Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh`

Expected: FAIL against the current duplicated Reflector alias.

- [ ] **Step 3: Replace both aliases**

Set `rr` to invoke `/home/jman/tmp/script-repo/Bash/Arch-Linux-Scripts/update_mirrorlist.sh --non-interactive`, preserving the existing leading `clear` behavior.

- [ ] **Step 4: Run focused verification**

Run: `bash Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh && bash -n Bash/Arch-Linux-Scripts/.bash_aliases /home/jman/.bash_aliases`

Expected: all tests and syntax checks pass.

### Task 4: Live Refresh and Upgrade Verification

**Files:**
- Modify: `/etc/pacman.d/mirrorlist`
- Create: `/etc/pacman.d/mirrorlist.backup-<UTC timestamp>`

- [ ] **Step 1: Generate and inspect without installing**

Run: `Bash/Arch-Linux-Scripts/update_mirrorlist.sh --non-interactive --dry-run`

Expected: Reflector ranks current candidates, five complete endpoint and pending-artifact validations succeed, and the installed mirrorlist remains unchanged.

- [ ] **Step 2: Install the validated mirrorlist**

Run: `Bash/Arch-Linux-Scripts/update_mirrorlist.sh --non-interactive`

Expected: a timestamped backup is created and the validated HTTPS list is installed atomically.

- [ ] **Step 3: Inspect production output**

Run: `stat /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup-* && sed -n '1,80p' /etc/pacman.d/mirrorlist`

Expected: root ownership, mode 0644, current generation timestamp, and five distinct HTTPS servers.

- [ ] **Step 4: Reproduce the original package path**

Run: `sudo pacman -Syyu --noconfirm`

Expected: repository refresh and package transaction exit 0 without the reported 404 failures.

- [ ] **Step 5: Confirm package and repository state**

Run: `pacman -Q audit gnome-control-center gnome-keybindings gvfs libphonenumber && pacman -Qu`

Expected: the requested package versions (or newer) are installed and no official repository upgrade remains.

### Task 5: Validated Weekly Automation

**Files:**
- Create: `Bash/Arch-Linux-Scripts/systemd/update-arch-mirrors.service`
- Create: `Bash/Arch-Linux-Scripts/systemd/update-arch-mirrors.timer`
- Install: `/usr/local/sbin/update-arch-mirrors`
- Install: `/etc/systemd/system/update-arch-mirrors.service`
- Install: `/etc/systemd/system/update-arch-mirrors.timer`

- [ ] **Step 1: Add and statically verify hardened units**

Create a root oneshot service with network ordering, a private temporary directory, strict system protection, `/etc/pacman.d` as its only system write path, bounded address families, and a syscall allowlist that includes ownership operations required by atomic installation. Create a persistent weekly timer with up to 12 hours of randomized delay. Run `systemd-analyze verify` on both files and require exit 0 with no warnings.

- [ ] **Step 2: Install the production command and timer**

Install the script as root-owned mode 0755 at `/usr/local/sbin/update-arch-mirrors`, install both units as root-owned mode 0644, reload systemd, and enable the timer immediately.

- [ ] **Step 3: Exercise the real automated path**

Run `sudo systemctl start update-arch-mirrors.service`, require a successful terminal state, inspect its journal, confirm the installed list excludes every provider that failed real artifacts during investigation, and confirm the timer is enabled and waiting.

### Task 6: Final Audit and Commit

**Files:**
- Review all files above.

- [ ] **Step 1: Re-run the complete validation set**

Run the regression harness, Bash syntax checks, ShellCheck when available, `git diff --check`, `git status --short`, and inspect `git diff -- Bash/Arch-Linux-Scripts/update_mirrorlist.sh Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh Bash/Arch-Linux-Scripts/.bash_aliases`.

Expected: zero failures, no whitespace errors, and only intended changes.

- [ ] **Step 2: Commit repository changes**

Run: `git add Bash/Arch-Linux-Scripts/update_mirrorlist.sh Bash/Arch-Linux-Scripts/tests/update_mirrorlist_test.sh Bash/Arch-Linux-Scripts/.bash_aliases Bash/Arch-Linux-Scripts/systemd docs/superpowers && git commit -m "fix: validate Arch mirrors before replacement"`

Expected: commit succeeds without staging unrelated files.
