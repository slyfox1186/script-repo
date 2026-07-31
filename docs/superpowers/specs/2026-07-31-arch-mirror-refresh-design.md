# Arch Mirror Refresh Design

## Objective

Make `Bash/Arch-Linux-Scripts/update_mirrorlist.sh` reliably select fast, current Arch Linux mirrors without replacing a working pacman mirrorlist with stale, insecure, empty, or unverified output. Use the hardened script to repair the current package-download failure and update the `rr` shell shortcut to call the maintained implementation.

## Current Failure and Root Cause

The active `/etc/pacman.d/mirrorlist` was generated on 2026-06-22 and lists `us.mirrors.cicku.me` first. On 2026-07-31, pacman refreshed repository metadata but received HTTP 404 responses from that mirror for packages named by the new metadata. Pacman aborted the transaction without upgrading packages.

The current script contributes avoidable risk:

- it permits plain HTTP by default;
- it uses a one-second download timeout;
- it writes Reflector output directly to the live mirrorlist;
- it does not validate the generated file or current repository availability;
- it runs `pacman -Sy reflector`, which can create an unsupported partial-upgrade state;
- its mirror-selection behavior is also duplicated in the `rr` alias with different settings.

## Proposed Behavior

The script will:

1. Refuse to run as root, preserving the existing user-facing invocation contract.
2. Require `sudo` and install Reflector only when it is absent, using `pacman -Syu --needed reflector` rather than a database-only refresh.
3. Default to HTTPS mirrors in the United States and Canada that synchronized within the last 12 hours.
4. Consider up to 100 recently synchronized candidates and retain the 10 fastest successful mirrors, providing redundancy without an unnecessarily long list.
5. Ask Reflector to write to a temporary file on the destination filesystem rather than directly to the active mirrorlist.
6. Validate that the candidate file contains at least three distinct HTTPS `Server` entries and no active non-HTTPS entries.
7. Probe the current `core.db` endpoint through the highest-ranked candidates. At least three candidates must return a successful HTTP response before installation.
8. Create or refresh a timestamped backup of the current mirrorlist and install the validated candidate atomically with root ownership and mode `0644`.
9. Preserve the existing command-line customization options, validate option values, and add a non-interactive mode suitable for the `rr` alias and automation.
10. Leave the current mirrorlist untouched and return a nonzero status if discovery, ranking, validation, probing, backup, or installation fails.

The `rr` alias in both the deployed shell configuration and repository copy will call this script in non-interactive mode. It will no longer contain a second Reflector policy.

## Boundaries

The change will not enable the stock `reflector.timer`, alter `/etc/pacman.conf`, remove cached packages, update AUR packages, or change unrelated Arch maintenance scripts. The existing system upgrade will be retried only after the installed mirrorlist passes validation and package databases can be refreshed from it.

## Error Handling and Safety

- Temporary files will be removed on every exit path using a trap.
- Argument parsing will reject missing values, unsupported protocols, nonnumeric counts, unsafe destination paths, and values that cannot satisfy the minimum validated mirror count.
- Candidate validation occurs before any privileged replacement.
- The backup and replacement steps will use explicit paths and fail closed.
- Network failures will identify the failed phase and retain the old list.
- The script will not delete pacman's lock file or bypass signature checking.

## Verification

Shell-level regression tests will exercise argument validation, Reflector invocation, failed discovery, insufficient servers, HTTP rejection, failed endpoint probes, successful atomic installation, backup creation, and cleanup. External commands will be supplied through a controlled test `PATH` so tests exercise the real script flow without modifying `/etc`.

Verification will include:

- a red-green run of the focused regression tests;
- ShellCheck, if installed, and `bash -n` for syntax;
- a dry run that generates and validates a candidate without installing it;
- a live non-interactive refresh of `/etc/pacman.d/mirrorlist`;
- inspection of the installed list and direct checks of its top endpoints;
- `sudo pacman -Syyu --noconfirm` to reproduce the original production path;
- confirmation that the named pending packages are upgraded and `pacman -Qu` reports no remaining official repository upgrades;
- repository diff and whitespace checks confirming only intended files changed.

## Success Criteria

The task is complete when the script and aliases implement one consistent validated policy, the live mirrorlist contains multiple current HTTPS mirrors, the original 404 transaction completes through pacman, and all available scripted and live verification passes. Any unavailable or unsafe check will be reported explicitly rather than inferred.
