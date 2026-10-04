#!usr/bin/env python
"""Hands-off full system upgrade (official repos and AUR) with yay.

Runs a single `yay -Syu` with every prompt answered in advance, plus the
checks the Arch wiki recommends around an upgrade.

Before the upgrade:
  * refuses to run as root (yay calls sudo itself and will not build as root)
  * allows only one run at a time, and deletes a leftover pacman lock unless a
    running package manager still has it open
  * checks network, free disk space and AC power
  * prints unread Arch news and stops on any "manual intervention" post
  * lists pending repo and AUR updates and exits early when there are none
  * refreshes archlinux-keyring first when it is outdated
  * saves native and foreign package lists, and optionally takes a snapshot

During the upgrade:
  * sudo is asked for once, then kept alive with --sudoloop
  * PKGBUILD clean, diff and edit menus are disabled
  * makedepends are removed and build sources cleaned after install
  * -git and other VCS packages are checked (--devel)
  * git is never allowed to stop and ask for credentials

After the upgrade:
  * what changed (read from pacman.log), new and pending .pacnew/.pacsave files
  * whether a reboot is required or recommended
  * systemd units that failed during the run, orphans, AUR rebuild candidates
  * optional orphan removal, package cache trimming and desktop notification

Skipping the diff menu means AUR PKGBUILD changes are installed without
review. Keep that in mind for AUR packages from maintainers you do not trust.

pacman's --noconfirm takes the default answer of every prompt, and the default
for "remove conflicting package?" is No. A real conflict therefore stops the
upgrade safely instead of removing anything; --resolve-conflicts changes that.

Usage:
  update_yay_packages.py               upgrade everything
  update_yay_packages.py --dry-run     checks and pending updates only
  update_yay_packages.py --help        all options

Exit codes: 0 upgraded or nothing to do, 1 upgrade failed,
            2 stopped by a pre-flight check, 130 interrupted.
"""

from __future__ import annotations

import argparse
import datetime as dt
import email.utils
import fcntl
import json
import logging
import os
import re
import shlex
import shutil
import subprocess
import sys
import textwrap
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"
)
NEWS_FEED_URL = "https://archlinux.org/feeds/news/"
AUR_URL = "https://aur.archlinux.org/"
PACMAN_LOG = Path("/var/log/pacman.log")
PACMAN_DB_LOCK = Path("/var/lib/pacman/db.lck")
STATE_DIR = (
    Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    / "update_yay_packages"
)
KEEP_RUNS = 30
RETRY_DELAY_SECONDS = 30
HTTP_TIMEOUT = 15

EXIT_OK, EXIT_FAILED, EXIT_PREFLIGHT, EXIT_INTERRUPTED = 0, 1, 2, 130

PACKAGE_MANAGERS = ("pacman", "yay", "paru", "pikaur", "aura", "pamac", "pamac-daemon", "packagekitd")
# The running kernel is checked separately; these are user-space pieces that
# keep running old code (or mismatch a loaded module) until the next boot.
REBOOT_RECOMMENDED_RE = re.compile(
    r"^(systemd|glibc|dbus(-broker)?|linux-firmware.*|.*-ucode|nvidia.*|mesa|lib32-mesa)$"
)
MANUAL_INTERVENTION_RE = re.compile(r"manual\s+intervention|intervention\s+required", re.IGNORECASE)
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
LOG_ENTRY_RE = re.compile(r"\[ALPM\] (upgraded|downgraded|installed|reinstalled|removed) (\S+) \((.*)\)")
LOG_WARNING_RE = re.compile(r"\[ALPM\] warning: (.*)")

log = logging.getLogger("update_yay")
raw_log = logging.getLogger("update_yay.output")


class PreflightError(Exception):
    """A condition that makes upgrading unsafe right now."""


@dataclass
class Pending:
    repo: list[str] | None = None  # None means the check could not run
    aur: list[str] | None = None

    @property
    def nothing_to_do(self) -> bool:
        return self.repo == [] and self.aur == []

    def repo_names(self) -> set[str]:
        return {line.split()[0] for line in self.repo or []}


@dataclass
class Changes:
    upgraded: list[tuple[str, str]] = field(default_factory=list)
    installed: list[tuple[str, str]] = field(default_factory=list)
    removed: list[tuple[str, str]] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


# --------------------------------------------------------------------------- helpers


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    log.debug("$ %s", shlex.join(cmd))
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    try:
        return subprocess.run(cmd, **kwargs)
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]}: not found")


def output_lines(result: subprocess.CompletedProcess) -> list[str]:
    return [ANSI_RE.sub("", line).strip() for line in (result.stdout or "").splitlines() if line.strip()]


def run_live(cmd: list[str], env: dict[str, str] | None = None) -> int:
    """Run cmd with output shown as it happens.

    On a terminal the child inherits it directly: yay keeps its colours and
    progress bars, and sudo reuses the credentials cached for this terminal
    (a pty wrapper would count as a new terminal and ask for the password
    again). Without a terminal, output is copied into the run log as well.
    """
    log.debug("$ %s", shlex.join(cmd))
    interactive = sys.stdout.isatty()
    proc = subprocess.Popen(
        cmd,
        env=env,
        stdin=None if sys.stdin.isatty() else subprocess.DEVNULL,
        stdout=None if interactive else subprocess.PIPE,
        stderr=None if interactive else subprocess.STDOUT,
        text=True,
        errors="replace",
    )
    interrupted = False
    if proc.stdout is not None:
        try:
            for line in proc.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                raw_log.info(ANSI_RE.sub("", line.rstrip("\n")))
        except KeyboardInterrupt:
            interrupted = True
    while True:
        try:
            rc = proc.wait()
            break
        except KeyboardInterrupt:
            # The child got the same SIGINT; let pacman finish or roll back
            # instead of killing it mid-transaction.
            interrupted = True
            log.warning("Interrupt received, waiting for %s to stop cleanly...", cmd[0])
    if interrupted:
        raise KeyboardInterrupt
    return rc


def http_get(url: str, method: str = "GET") -> bytes:
    request = urllib.request.Request(url, method=method, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
        return response.read()


def human_bytes(n: float) -> str:
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if n < 1024 or unit == "TiB":
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TiB"


def setup_logging(log_file: Path, verbose: bool) -> None:
    console = logging.StreamHandler(sys.stderr)
    console.setLevel(logging.DEBUG if verbose else logging.INFO)
    console.setFormatter(logging.Formatter("==> %(message)s"))

    file_handler = logging.FileHandler(log_file, encoding="utf-8")
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)-7s %(message)s", "%Y-%m-%d %H:%M:%S"))

    log.setLevel(logging.DEBUG)
    log.addHandler(console)
    log.addHandler(file_handler)

    raw_handler = logging.FileHandler(log_file, encoding="utf-8")
    raw_handler.setFormatter(logging.Formatter("    | %(message)s"))
    raw_log.setLevel(logging.INFO)
    raw_log.addHandler(raw_handler)
    raw_log.propagate = False


def prune_old_files(directory: Path) -> None:
    for pattern, keep in (("*_yay_update.log", KEEP_RUNS), ("*_pkglist_*.txt", KEEP_RUNS * 2)):
        for old in sorted(directory.glob(pattern), reverse=True)[keep:]:
            old.unlink(missing_ok=True)


# --------------------------------------------------------------------------- pre-flight


def check_not_root() -> None:
    if os.geteuid() == 0:
        raise PreflightError(
            "Run this as your normal user, not root or sudo. yay asks for sudo itself and refuses to build packages as root."
        )


def check_tools() -> None:
    missing = [tool for tool in ("yay", "pacman", "sudo") if not shutil.which(tool)]
    if missing:
        raise PreflightError(f"Required command(s) not found: {', '.join(missing)}")
    if not all(shutil.which(tool) for tool in ("checkupdates", "pacdiff", "paccache")):
        log.warning("pacman-contrib is not installed; pending-update listing, .pacnew checks and cache trimming are limited.")


def acquire_instance_lock():
    runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR") or STATE_DIR)
    lock_path = runtime_dir / "update_yay_packages.lock"
    handle = open(lock_path, "w")  # noqa: SIM115  must stay open to hold the flock
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        raise PreflightError(f"Another run of this script is already in progress ({lock_path}).") from None
    return handle


def running_package_managers() -> list[str]:
    result = run(["pgrep", "-a", "-x", "|".join(PACKAGE_MANAGERS)])
    return output_lines(result) if result.returncode == 0 else []


def lock_holders() -> list[str] | None:
    """Processes that have db.lck open, or None when that cannot be checked.

    libalpm keeps the lock file open for as long as it holds the lock, so this
    catches any frontend, not only the names in PACKAGE_MANAGERS. The holder
    runs as root, so seeing its open files needs sudo.
    """
    if not shutil.which("fuser"):
        return None
    result = run(["sudo", "-n", "fuser", str(PACMAN_DB_LOCK)])
    if result.returncode == 1 and not (result.stderr or "").strip():
        return []
    if result.returncode != 0:
        return None
    holders = []
    for pid in result.stdout.split():
        try:
            holders.append(f"{pid} {Path('/proc', pid, 'comm').read_text().strip()}")
        except OSError:
            holders.append(pid)
    return holders


def check_pacman_lock(dry_run: bool) -> None:
    """Delete a leftover pacman lock; stop only while a running process still holds it."""
    if not PACMAN_DB_LOCK.exists():
        return
    busy = running_package_managers()
    if busy:
        raise PreflightError(
            "The pacman database is locked by a running package manager. Let it finish first:\n    " + "\n    ".join(busy)
        )
    if dry_run:
        log.warning("%s exists but no package manager is running. A real run deletes it.", PACMAN_DB_LOCK)
        return
    holders = lock_holders()
    if holders:
        raise PreflightError(
            "The pacman database is locked by a running process. Let it finish first:\n    " + "\n    ".join(holders)
        )
    if holders is None:
        log.debug("Could not list processes holding %s (needs fuser and sudo); going by process names.",
                  PACMAN_DB_LOCK)
    # A new pacman cannot take the lock while the stale file exists, so nothing can grab it before the rm.
    if run(["sudo", "-n", "rm", "-f", str(PACMAN_DB_LOCK)]).returncode != 0:
        raise PreflightError(f"Could not remove the stale lock. Remove it with: sudo rm {PACMAN_DB_LOCK}")
    log.warning("Deleted a leftover pacman lock (%s); no process was using it.", PACMAN_DB_LOCK)


def check_network() -> None:
    try:
        http_get(AUR_URL, method="HEAD")
    except urllib.error.HTTPError as exc:
        if exc.code >= 500:
            log.warning("The AUR answered HTTP %s; AUR packages may fail to update this run.", exc.code)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        reason = getattr(exc, "reason", exc)
        raise PreflightError(f"Cannot reach {AUR_URL} ({reason}). Check the network connection.") from None


def yay_current_config() -> dict:
    result = run(["yay", "-Pg"])
    try:
        return json.loads(result.stdout)
    except (json.JSONDecodeError, TypeError):
        return {}


def check_disk_space(min_free_gb: float, min_boot_mb: float, yay_config: dict) -> None:
    cache_dirs = output_lines(run(["pacman-conf", "CacheDir"])) or ["/var/cache/pacman/pkg"]
    build_dir = yay_config.get("buildDir") or str(Path.home() / ".cache/yay")
    targets = [(path, min_free_gb * 1024**3) for path in ["/", *cache_dirs, build_dir]]
    if os.path.ismount("/boot"):
        targets.append(("/boot", min_boot_mb * 1024**2))

    seen: set[int] = set()
    problems = []
    for raw_path, needed in targets:
        path = Path(raw_path)
        while not path.exists() and path != path.parent:
            path = path.parent
        device = os.stat(path).st_dev
        if device in seen:
            continue
        seen.add(device)
        stats = os.statvfs(path)
        free = stats.f_bavail * stats.f_frsize
        log.debug("Free space on %s: %s", path, human_bytes(free))
        if free < needed:
            problems.append(f"{path}: {human_bytes(free)} free, need {human_bytes(needed)}")
    if problems:
        raise PreflightError(
            "Not enough free disk space:\n    " + "\n    ".join(problems)
            + "\n    Free some space (for example: sudo paccache -rk2) or lower --min-free-gb / --min-boot-mb."
        )


def check_power(allow_battery: bool) -> None:
    supplies = Path("/sys/class/power_supply")
    if allow_battery or not supplies.is_dir():
        return
    for supply in supplies.iterdir():
        info = {}
        for name in ("type", "scope", "status", "capacity"):
            try:
                info[name] = (supply / name).read_text().strip()
            except OSError:
                info[name] = ""
        # Controllers, mice and headsets report scope "Device"; only system batteries matter.
        if info["type"] == "Battery" and info["scope"] != "Device" and info["status"] == "Discharging":
            capacity = info["capacity"] or "?"
            raise PreflightError(
                f"Running on battery ({capacity}%). A power loss mid-upgrade can leave the system unbootable. "
                "Plug in, or pass --allow-battery."
            )


def last_full_upgrade() -> dt.datetime | None:
    try:
        lines = PACMAN_LOG.read_text(errors="replace").splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        if "starting full system upgrade" in line and line.startswith("["):
            try:
                return dt.datetime.strptime(line[1 : line.index("]")], "%Y-%m-%dT%H:%M:%S%z")
            except ValueError:
                continue
    return None


def fetch_news() -> list[dict]:
    root = ET.fromstring(http_get(NEWS_FEED_URL))
    items = []
    for item in root.iter("item"):
        published = item.findtext("pubDate")
        date = email.utils.parsedate_to_datetime(published) if published else None
        if date and date.tzinfo is None:  # RFC 2822 "-0000" parses as naive
            date = date.replace(tzinfo=dt.timezone.utc)
        items.append({
            "title": (item.findtext("title") or "").strip(),
            "link": (item.findtext("link") or "").strip(),
            "date": date,
        })
    return items


def check_news(ignore_news: bool) -> None:
    since = last_full_upgrade()
    if since is None:
        since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=30)
    try:
        news = fetch_news()
    except Exception as exc:  # the feed is advisory; never block an upgrade on it
        log.warning("Could not read Arch news (%s). Check https://archlinux.org/news/ before upgrading.", exc)
        return

    unread = [item for item in news if item["date"] and item["date"] > since]
    if not unread:
        log.info("No Arch news since the last upgrade (%s).", since.strftime("%Y-%m-%d %H:%M"))
        return
    log.info("Arch news since the last upgrade:")
    for item in unread:
        log.info("  %s  %s\n      %s", item["date"].strftime("%Y-%m-%d"), item["title"], item["link"])

    blocking = [item for item in unread if MANUAL_INTERVENTION_RE.search(item["title"])]
    if blocking and not ignore_news:
        raise PreflightError(
            "Unread Arch news asks for manual intervention. Read it and do the steps it describes, "
            "then re-run with --ignore-news:\n    " + "\n    ".join(f"{i['title']}  {i['link']}" for i in blocking)
        )


def pending_updates(devel: bool) -> Pending:
    pending = Pending()
    if shutil.which("checkupdates"):
        # checkupdates syncs a private copy of the databases, so this never
        # causes a partial upgrade.
        result = run(["checkupdates", "--nocolor"])
        if result.returncode == 0:
            pending.repo = output_lines(result)
        elif result.returncode == 2:
            pending.repo = []
        else:
            log.warning("checkupdates failed: %s", (result.stderr or "").strip() or f"exit {result.returncode}")

    result = run(["yay", "-Qua", *(["--devel"] if devel else [])])
    lines = [line for line in output_lines(result) if "->" in line]
    if result.returncode == 0 or (not lines and not (result.stderr or "").strip()):
        pending.aur = lines
    else:
        log.warning("AUR update check failed: %s", (result.stderr or "").strip() or f"exit {result.returncode}")
        pending.aur = lines or None
    return pending


def show_pending(pending: Pending) -> None:
    for label, lines in (("Repository", pending.repo), ("AUR", pending.aur)):
        if lines is None:
            log.info("%s updates: unknown (check failed)", label)
        elif not lines:
            log.info("%s updates: none", label)
        else:
            log.info("%s updates (%d):\n    %s", label, len(lines), "\n    ".join(lines))


def authenticate_sudo() -> bool:
    """Make sure yay's sudo calls will not stop to ask for a password.

    Returns False when only pacman is allowed without a password. yay's
    --sudoloop retries `sudo -v` forever when it fails, so the caller must
    drop it in that case.
    """
    if sys.stdin.isatty():
        log.info("Asking for the sudo password once; --sudoloop keeps it valid for the whole run.")
        if run(["sudo", "-v"], capture_output=False).returncode != 0:
            raise PreflightError("sudo authentication failed.")
        return True
    if run(["sudo", "-n", "-v"]).returncode == 0:
        return True
    if run(["sudo", "-n", "pacman", "-V"]).returncode == 0:
        return False
    raise PreflightError(
        "No terminal to ask for the sudo password. Run this from a terminal, or allow pacman with NOPASSWD in sudoers."
    )


# --------------------------------------------------------------------------- upgrade steps


def refresh_keyring_if_outdated(pending: Pending) -> None:
    # Arch wiki: update the keyring before everything else so packages signed
    # by newly added packager keys pass signature checks.
    if "archlinux-keyring" not in pending.repo_names():
        return
    log.info("archlinux-keyring is outdated; updating it before the rest of the system.")
    rc = run_live(["sudo", "pacman", "-Sy", "--needed", "--noconfirm", "archlinux-keyring"])
    if rc != 0:
        raise RuntimeError(
            "Keyring update failed. The package databases are now synced but nothing else is upgraded: "
            "do not install single packages until a full upgrade succeeds."
        )


def take_snapshot(stamp: str) -> None:
    hooks = [pkg for pkg in ("snap-pac", "timeshift-autosnap") if run(["pacman", "-Q", pkg]).returncode == 0]
    if hooks:
        log.info("Skipping manual snapshot: %s already snapshots every pacman transaction.", ", ".join(hooks))
        return
    description = f"before yay update {stamp}"
    if shutil.which("snapper"):
        cmd = ["sudo", "snapper", "-c", "root", "create", "--description", description, "--cleanup-algorithm", "number"]
    elif shutil.which("timeshift"):
        cmd = ["sudo", "timeshift", "--create", "--comments", description, "--tags", "O"]
    else:
        raise PreflightError("--snapshot was given but neither snapper nor timeshift is installed.")
    log.info("Creating snapshot: %s", description)
    if run_live(cmd) != 0:
        raise PreflightError("Snapshot failed; not upgrading without the requested restore point.")


def save_package_lists(stamp: str) -> None:
    for kind, flags in (("native", "-Qqen"), ("foreign", "-Qqem")):
        result = run(["pacman", flags])
        target = STATE_DIR / f"{stamp}_pkglist_{kind}.txt"
        target.write_text(result.stdout)
        log.debug("Saved %s package list to %s", kind, target)


def build_yay_command(args: argparse.Namespace) -> list[str]:
    cmd = [
        "yay", "-Syu",
        "--noconfirm",
        "--sudoloop",
        "--cleanmenu=false", "--diffmenu=false", "--editmenu=false",
        "--answerclean", "None", "--answerdiff", "None", "--answeredit", "None",
        "--noremovemake" if args.keep_makedeps else "--removemake",
        "--cleanafter",
        "--devel=false" if args.no_devel else "--devel",
    ]
    if args.resolve_conflicts:
        cmd.append("--useask")
    if args.ignore:
        cmd += ["--ignore", ",".join(args.ignore)]
    return cmd + args.yay_arg


def upgrade(cmd: list[str], retries: int) -> int:
    env = os.environ | {"GIT_TERMINAL_PROMPT": "0"}
    rc = 0
    for attempt in range(retries + 1):
        if attempt:
            log.warning("yay failed (exit %d); retrying in %ds (attempt %d of %d).",
                        rc, RETRY_DELAY_SECONDS, attempt + 1, retries + 1)
            time.sleep(RETRY_DELAY_SECONDS)
        log.info("Running: %s", shlex.join(cmd))
        rc = run_live(cmd, env=env)
        if rc == 0:
            return 0
        if PACMAN_DB_LOCK.exists() and not running_package_managers():
            log.error("yay left %s behind; not retrying. Run this script again: it clears a stale lock first.",
                      PACMAN_DB_LOCK)
            return rc
    return rc


# --------------------------------------------------------------------------- reporting


def pacman_log_size() -> int:
    try:
        return PACMAN_LOG.stat().st_size
    except OSError:
        return 0


def read_changes(offset: int) -> Changes:
    changes = Changes()
    try:
        with PACMAN_LOG.open("rb") as handle:
            handle.seek(offset)
            text = handle.read().decode("utf-8", errors="replace")
    except OSError:
        return changes
    buckets = {"upgraded": changes.upgraded, "downgraded": changes.upgraded, "reinstalled": changes.upgraded,
               "installed": changes.installed, "removed": changes.removed}
    for line in text.splitlines():
        if match := LOG_ENTRY_RE.search(line):
            buckets[match.group(1)].append((match.group(2), match.group(3)))
        elif match := LOG_WARNING_RE.search(line):
            changes.warnings.append(match.group(1))
    return changes


def failed_units() -> set[str]:
    result = run(["systemctl", "--failed", "--no-legend", "--plain"])
    return {line.split()[0] for line in output_lines(result)}


def report(changes: Changes, failed_before: set[str], args: argparse.Namespace, cleanup: bool) -> list[str]:
    """Log the post-upgrade findings and return the lines worth a notification.

    cleanup=False skips orphan removal and cache trimming, which should only
    follow a completed upgrade.
    """
    notes = []
    log.info("Changes: %d upgraded, %d installed, %d removed.",
             len(changes.upgraded), len(changes.installed), len(changes.removed))
    for verb, entries in (("upgraded", changes.upgraded), ("installed", changes.installed), ("removed", changes.removed)):
        for name, detail in entries:
            log.debug("  %s %s (%s)", verb, name, detail)

    for warning in changes.warnings:
        log.warning("pacman: %s", warning)

    if shutil.which("pacdiff"):
        pending_merges = output_lines(run(["pacdiff", "-o"]))
        if pending_merges:
            log.warning("Config files waiting to be merged (run: sudo pacdiff):\n    %s",
                        "\n    ".join(pending_merges))
            notes.append(f"{len(pending_merges)} .pacnew/.pacsave file(s) to merge")

    kernel = os.uname().release
    if not Path("/usr/lib/modules", kernel).is_dir():
        log.warning("REBOOT REQUIRED: modules for the running kernel %s were replaced; "
                    "new hardware and modules will not load until you reboot.", kernel)
        notes.append("reboot required (kernel)")
    else:
        hinted = sorted({name for name, _ in changes.upgraded if REBOOT_RECOMMENDED_RE.match(name)})
        if hinted:
            log.info("Reboot recommended soon; core components were updated: %s", ", ".join(hinted))
            notes.append("reboot recommended")

    newly_failed = failed_units() - failed_before
    if newly_failed:
        log.warning("systemd units that failed during the upgrade: %s (see: systemctl status <unit>)",
                    ", ".join(sorted(newly_failed)))
        notes.append(f"{len(newly_failed)} failed unit(s)")

    orphans = output_lines(run(["pacman", "-Qdtq"]))
    if orphans and args.remove_orphans and cleanup:
        log.info("Removing %d orphan package(s): %s", len(orphans), " ".join(orphans))
        if run_live(["sudo", "pacman", "-Rns", "--noconfirm", *orphans]) != 0:
            log.warning("Orphan removal failed; nothing was removed.")
    elif orphans:
        log.info("%d orphan package(s), not removed (use --remove-orphans): %s", len(orphans), " ".join(orphans))

    if shutil.which("checkrebuild"):
        rebuild = output_lines(run(["checkrebuild"]))
        if rebuild:
            log.warning("Packages that may need a rebuild against the new libraries (yay -S --rebuild <pkg>):\n    %s",
                        "\n    ".join(rebuild))
            notes.append(f"{len(rebuild)} package(s) may need a rebuild")

    if args.clean_cache and cleanup:
        if shutil.which("paccache"):
            log.info("Trimming the package cache to the newest %d version(s) of each package.", args.cache_keep)
            run_live(["sudo", "paccache", "-r", "-k", str(args.cache_keep)])
            run_live(["sudo", "paccache", "-r", "-u", "-k", "0"])
        else:
            log.warning("--clean-cache needs paccache from pacman-contrib.")
    return notes


def notify(title: str, body: str) -> None:
    if shutil.which("notify-send") and (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        run(["notify-send", "--app-name=yay update", title, body])


# --------------------------------------------------------------------------- help screen

BOLD, ITALIC, RED, GREEN, YELLOW, CYAN = "1", "3", "31", "32", "33", "36"
HELP_MAX_WIDTH = 100
NBSP = " "  # textwrap only breaks on ASCII whitespace, so this glues "default: 3" together

HELP_INTRO = (
    "Runs one yay -Syu with every prompt answered in advance. It first checks the network, "
    "free disk space, AC power, unread Arch news and the pacman lock, and stops before "
    "changing anything if one of them fails."
)
# Options that trade a safety net for convenience; their flag is shown in red.
CAUTIONS = {
    "ignore_news": "only after doing the steps the news post describes.",
    "resolve_conflicts": "it can remove installed packages without asking.",
}
HELP_EXAMPLES = (
    ("Upgrade everything", ""),
    ("See what is pending without changing anything", "-n"),
    ("Take a restore point first and get a notification when done", "--snapshot --notify"),
    ("Hold back the kernel and GPU driver, then trim the package cache",
     "--ignore linux,nvidia-dkms --clean-cache"),
)
EXIT_CODE_HELP = (
    (EXIT_OK, "upgraded, or nothing to do"),
    (EXIT_FAILED, "the upgrade failed"),
    (EXIT_PREFLIGHT, "stopped by a pre-flight check or a bad option, nothing changed"),
    (EXIT_INTERRUPTED, "interrupted with Ctrl+C"),
)


def wants_color(stream) -> bool:
    # https://no-color.org and https://force-color.org
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR"):
        return True
    isatty = getattr(stream, "isatty", None)
    return bool(isatty and isatty()) and os.environ.get("TERM") != "dumb"


class Style:
    def __init__(self, enabled: bool):
        self.enabled = enabled

    def __call__(self, text: str, *codes: str) -> str:
        if not self.enabled or not codes or not text:
            return text
        return f"\x1b[{';'.join(codes)}m{text}\x1b[0m"


class HelpParser(argparse.ArgumentParser):
    """ArgumentParser with a grouped, coloured help screen and a short usage line."""

    def __init__(self, **kwargs):
        super().__init__(add_help=False, **kwargs)

    def format_usage(self, style: Style | None = None) -> str:
        style = style or Style(False)
        return f"{style('Usage:', BOLD, GREEN)} {style(self.prog, BOLD)} {style('[options]', ITALIC, YELLOW)}\n"

    def print_usage(self, file=None) -> None:
        file = file or sys.stdout
        self._print_message(self.format_usage(Style(wants_color(file))), file)

    def print_help(self, file=None) -> None:
        file = file or sys.stdout
        self._print_message(self.format_help(Style(wants_color(file))), file)

    def error(self, message: str):
        style = Style(wants_color(sys.stderr))
        self.print_usage(sys.stderr)
        self.exit(2, f"{style('error:', BOLD, RED)} {message}\n"
                     f"Run {style(self.prog + ' --help', BOLD, CYAN)} to see every option.\n")

    def format_help(self, style: Style | None = None) -> str:
        style = style or Style(False)
        width = min(shutil.get_terminal_size().columns, HELP_MAX_WIDTH) - 1
        groups = [(g.title, [a for a in g._group_actions if a.help != argparse.SUPPRESS])
                  for g in self._action_groups]
        groups = [(title, actions) for title, actions in groups if actions]
        flags = sorted((opt for _, actions in groups for a in actions for opt in a.option_strings),
                       key=len, reverse=True)
        flag_re = re.compile(r"(?<![\w-])(" + "|".join(map(re.escape, flags)) + r")(?![\w-])")

        def highlight(line: str) -> str:
            line = flag_re.sub(lambda m: style(m.group(1), BOLD, CYAN), line)
            return re.sub(r"\[default: [^\]]*\]", lambda m: style(m.group(0), "2"), line)

        def wrap(text: str, size: int) -> list[str]:
            return [line.replace(NBSP, " ")
                    for line in textwrap.wrap(text, max(size, 20), break_on_hyphens=False, break_long_words=False)]

        def heading(title: str) -> str:
            return style(f"{title}:", BOLD, GREEN)

        def invocation(action: argparse.Action) -> tuple[str, str]:
            flag_codes = (BOLD, RED) if action.dest in CAUTIONS else (BOLD, CYAN)
            plain = ", ".join(action.option_strings)
            coloured = ", ".join(style(opt, *flag_codes) for opt in action.option_strings)
            if action.nargs != 0:
                metavar = action.metavar or action.dest.upper()
                plain += f" {metavar}"
                coloured += " " + style(metavar, ITALIC, YELLOW)
            return plain, coloured

        def description(action: argparse.Action, size: int) -> list[str]:
            text = action.help
            if action.nargs != 0 and action.default not in (None, [], argparse.SUPPRESS):
                shown = f"{action.default:g}" if isinstance(action.default, float) else action.default
                text += f" [default:{NBSP}{shown}]"
            lines = [highlight(line) for line in wrap(text, size)]
            if caution := CAUTIONS.get(action.dest):
                label = "Caution:"
                caution_lines = wrap(f"{label} {caution}", size)
                lines.append(style(label, BOLD, RED) + style(caution_lines[0][len(label):], RED))
                lines += [style(line, RED) for line in caution_lines[1:]]
            return lines

        rows = [[invocation(a) for a in actions] for _, actions in groups]
        column = 2 + max(len(plain) for group in rows for plain, _ in group) + 3
        stacked = width - column < 40  # narrow terminal: description goes under the flag

        out = [style(self.description, BOLD), ""]
        out += wrap(HELP_INTRO, width)
        out += ["", self.format_usage(style).rstrip()]
        for (title, actions), group_rows in zip(groups, rows, strict=True):
            out += ["", heading(title)]
            for action, (plain, coloured) in zip(actions, group_rows, strict=True):
                if stacked:
                    out.append(f"  {coloured}")
                    out += [f"{' ' * 8}{line}" for line in description(action, width - 8)]
                    continue
                first, *rest = description(action, width - column)
                out.append(f"  {coloured}{' ' * (column - 2 - len(plain))}{first}")
                out += [f"{' ' * column}{line}" for line in rest]

        out += ["", heading("Examples")]
        for note, example_args in HELP_EXAMPLES:
            words = [style(w, BOLD, CYAN) if w.startswith("-") else style(w, ITALIC, YELLOW)
                     for w in example_args.split()]
            out += [f"  {line}" for line in wrap(note, width - 2)]
            out.append("    " + " ".join([style(self.prog, BOLD), *words]))

        out += ["", heading("Exit codes")]
        code_width = max(len(str(code)) for code, _ in EXIT_CODE_HELP) + 2
        for code, meaning in EXIT_CODE_HELP:
            out.append(f"  {style(str(code), BOLD)}{' ' * (code_width - len(str(code)))}{meaning}")

        home = str(Path.home())
        state_dir = "~" + str(STATE_DIR)[len(home):] if str(STATE_DIR).startswith(home + "/") else str(STATE_DIR)
        out += ["", f"Logs and package lists: {style(state_dir + '/', ITALIC, YELLOW)}", ""]
        return "\n".join(out)


# --------------------------------------------------------------------------- main


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = HelpParser(
        description="Upgrade every official and AUR package with yay, with no prompts after the sudo password.",
    )
    preview = parser.add_argument_group("Preview")
    preview.add_argument("-n", "--dry-run", action="store_true",
                         help="Run every check and list pending updates. Changes nothing.")

    scope = parser.add_argument_group("What gets upgraded")
    scope.add_argument("--ignore", action="append", default=[], metavar="PKG",
                       help="Hold PKG back this run. Repeat it, or separate names with commas.")
    scope.add_argument("--no-devel", action="store_true",
                       help="Skip checking -git and other VCS AUR packages for new commits.")
    scope.add_argument("--keep-makedeps", action="store_true",
                       help="Keep build-only dependencies instead of removing them after builds.")
    scope.add_argument("--yay-arg", action="append", default=[], metavar="ARG",
                       help="Pass ARG to yay as is. Repeatable. Write it as --yay-arg=--flag.")

    safety = parser.add_argument_group("Safety checks")
    safety.add_argument("--min-free-gb", type=float, default=3.0, metavar="GB",
                        help="Free space required on /, the pacman cache and the yay build dir.")
    safety.add_argument("--min-boot-mb", type=float, default=100.0, metavar="MB",
                        help="Free space required on a separate /boot partition.")
    safety.add_argument("--allow-battery", action="store_true",
                        help="Run even when the machine is on battery power.")
    safety.add_argument("--ignore-news", action="store_true",
                        help="Upgrade even when unread Arch news asks for manual intervention.")
    safety.add_argument("--resolve-conflicts", action="store_true",
                        help="Let yay auto-confirm package conflicts (--useask).")

    extras = parser.add_argument_group("Snapshot and cleanup")
    extras.add_argument("--snapshot", action="store_true",
                        help="Take a snapper or timeshift snapshot first. Skipped when snap-pac "
                             "or timeshift-autosnap already does it.")
    extras.add_argument("--remove-orphans", action="store_true",
                        help="Remove orphaned dependencies afterwards (pacman -Rns).")
    extras.add_argument("--clean-cache", action="store_true",
                        help="Trim the package cache with paccache afterwards.")
    extras.add_argument("--cache-keep", type=int, default=3, metavar="N",
                        help="How many versions of each package --clean-cache keeps.")

    output = parser.add_argument_group("Run and output")
    output.add_argument("--retries", type=int, default=1, metavar="N",
                        help="Re-run yay up to N more times after a failure, such as a mirror timeout.")
    output.add_argument("--notify", action="store_true", help="Send a desktop notification when finished.")
    output.add_argument("-v", "--verbose", action="store_true", help="Show debug output.")
    output.add_argument("-h", "--help", action="help", help="Show this help and exit.")
    args = parser.parse_args(argv)
    args.ignore = [pkg for value in args.ignore for pkg in value.split(",") if pkg]
    if args.retries < 0 or args.cache_keep < 0:
        parser.error("--retries and --cache-keep must be 0 or more")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    log_file = STATE_DIR / f"{stamp}_yay_update.log"
    setup_logging(log_file, args.verbose)
    prune_old_files(STATE_DIR)
    log.debug("Log file: %s", log_file)

    yay_cmd = build_yay_command(args)
    try:
        check_not_root()
        check_tools()
        instance_lock = acquire_instance_lock()  # noqa: F841  flock is held while this stays referenced
        check_power(args.allow_battery)
        check_network()
        check_disk_space(args.min_free_gb, args.min_boot_mb, yay_current_config())
        check_news(args.ignore_news)

        pending = pending_updates(devel=not args.no_devel)
        show_pending(pending)
        if args.dry_run:
            check_pacman_lock(dry_run=True)
            log.info("Dry run. Would run: %s", shlex.join(yay_cmd))
            return EXIT_OK
        if pending.nothing_to_do:
            log.info("System is up to date.")
            return EXIT_OK

        if not authenticate_sudo():
            log.info("sudo allows only pacman without a password; running yay without --sudoloop.")
            yay_cmd.remove("--sudoloop")
        check_pacman_lock(dry_run=False)
        if args.snapshot:
            take_snapshot(stamp)
        save_package_lists(stamp)
    except PreflightError as exc:
        log.error("%s", exc)
        log.info("Nothing was changed. Log: %s", log_file)
        return EXIT_PREFLIGHT
    except KeyboardInterrupt:
        log.error("Interrupted before the upgrade started.")
        return EXIT_INTERRUPTED

    log_offset = pacman_log_size()
    failed_before = failed_units()
    try:
        refresh_keyring_if_outdated(pending)
        rc = upgrade(yay_cmd, args.retries)
    except RuntimeError as exc:
        log.error("%s", exc)
        rc = EXIT_FAILED
    except KeyboardInterrupt:
        log.error("Interrupted. Run a full upgrade again before installing anything, to avoid a partial upgrade.")
        report(read_changes(log_offset), failed_before, args, cleanup=False)
        return EXIT_INTERRUPTED

    notes = report(read_changes(log_offset), failed_before, args, cleanup=rc == 0)
    if rc == 0:
        log.info("Upgrade finished. Log: %s", log_file)
        if args.notify:
            notify("System upgrade finished", "; ".join(notes) or "No action needed.")
        return EXIT_OK

    log.error("Upgrade failed (yay exit %d). Fix the error shown above, then run this script again. "
              "Until a full upgrade succeeds, do not install single packages. Log: %s", rc, log_file)
    if args.notify:
        notify("System upgrade FAILED", f"yay exited with {rc}. See {log_file}")
    return EXIT_FAILED


if __name__ == "__main__":
    sys.exit(main())
