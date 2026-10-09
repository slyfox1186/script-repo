#!/usr/bin/env python3
"""
Send a file or folder to another PC over SSH.

Transport is rsync over SSH using key-based auth, so no password is stored,
embedded, or prompted for. A folder is sent *itself*, recursively: with
`-i ./myproj -o /home/username/tmp` the result is `/home/username/tmp/myproj/...`.
"""

from __future__ import annotations

import argparse
import getpass
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path, PurePosixPath

CONNECT_TIMEOUT = 3

# Exit codes, so the script composes cleanly in shell pipelines.
EXIT_OK = 0
EXIT_USAGE = 2  # bad arguments / failed validation
EXIT_PREFLIGHT = 3  # host unreachable, auth failed, rsync missing
EXIT_TRANSFER = 4  # rsync itself failed
EXIT_VERIFY = 5  # transfer reported success but verification disagreed
EXIT_INTERRUPT = 130  # Ctrl-C

GLOB_CHARS = set("*?[]")


# --------------------------------------------------------------------------
# Small output helpers. Color only when stdout is a real terminal.
# --------------------------------------------------------------------------
_TTY = sys.stdout.isatty()


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _TTY else text


# rsync writes straight to fd 1, so our own prints must not sit in a buffer
# waiting for exit -- otherwise piped output arrives out of order.
def info(msg: str) -> None:
    print(f"{_c('36', '::')} {msg}", flush=True)


def ok(msg: str) -> None:
    print(f"{_c('32', 'OK')} {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"{_c('33', 'WARNING')} {msg}", file=sys.stderr, flush=True)


def die(msg: str, code: int, hint: str | None = None) -> None:
    """Print an error (plus optional actionable hint) and exit."""
    print(f"{_c('31', 'ERROR')} {msg}", file=sys.stderr, flush=True)
    if hint:
        print(f"        {hint}", file=sys.stderr, flush=True)
    sys.exit(code)


def human_bytes(n: int) -> str:
    step = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if step < 1024 or unit == "TB":
            return f"{step:.0f} {unit}" if unit == "B" else f"{step:.1f} {unit}"
        step /= 1024
    return f"{step:.1f} TB"


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------
def looks_like_file_path(remote_path: str) -> bool:
    """True if the path's last segment carries a plausible file extension.

    Used to catch `-o /home/username/tmp/backup.7z` when the input is a folder.
    Deliberately conservative: a trailing slash always means 'directory', and
    only short alphanumeric suffixes count, so `/srv/data` and `/home/username/tmp`
    are not mistaken for files. False positives (e.g. `/opt/python3.13`) can be
    overridden with --force.
    """
    if remote_path.endswith("/"):
        return False
    suffix = PurePosixPath(remote_path).suffix
    return bool(suffix) and 1 < len(suffix) <= 8 and suffix[1:].isalnum()


def validate_input(raw: str) -> Path:
    """Resolve -i to an absolute path and confirm we can actually read it."""
    src = Path(raw).expanduser()
    try:
        src = src.resolve(strict=True)
    except FileNotFoundError:
        die(
            f"input path does not exist: {raw}",
            EXIT_USAGE,
            "Check the spelling, or pass an absolute path.",
        )
    except OSError as exc:
        die(f"cannot resolve input path {raw}: {exc}", EXIT_USAGE)

    # A root-like path has no basename, so there would be no folder name to
    # create on the far side -- and sending '/' would mean the whole filesystem.
    if not src.name or src.parent == src:
        die(
            f"refusing to transfer the filesystem root: {src}",
            EXIT_USAGE,
            "Name an actual file or folder, e.g. -i ./docs",
        )

    if not (src.is_file() or src.is_dir()):
        die(
            f"input is neither a regular file nor a directory: {src}",
            EXIT_USAGE,
            "Sockets, FIFOs and device nodes are not supported.",
        )
    if not os.access(src, os.R_OK):
        # getpass.getuser(), not os.getlogin(): the latter raises when there is
        # no controlling terminal (cron, pipes, systemd units).
        die(f"input is not readable by {getpass.getuser()}: {src}", EXIT_USAGE)
    if src.is_dir() and not os.access(src, os.X_OK):
        die(f"input directory is not traversable: {src}", EXIT_USAGE)
    return src


def validate_output(raw: str, src: Path, force: bool) -> tuple[str, bool]:
    """Validate -o against the input kind.

    Returns (remote_path, rename_mode). In rename_mode the output names the
    destination file itself; otherwise it names the destination *directory*
    that the input is placed inside.
    """
    out = raw.strip()
    if not out:
        die("--output is empty", EXIT_USAGE)

    if not out.startswith("/"):
        die(
            f"--output must be a FULL absolute path on the remote host, got: {out!r}",
            EXIT_USAGE,
            f"Try: -o /home/username/tmp/{out.lstrip('./')}",
        )

    # Normalise `//a//b/` -> `/a/b`, but remember whether a trailing slash was
    # given, since that is an explicit "this is a directory" signal.
    had_trailing_slash = out.endswith("/")
    normalised = PurePosixPath(os.path.normpath(out)).as_posix()

    if ".." in PurePosixPath(out).parts:
        die(
            f"--output must not contain '..': {out}",
            EXIT_USAGE,
            "Pass the fully-resolved destination path instead.",
        )
    if normalised == "/":
        die(
            "--output of '/' is refused as a destination",
            EXIT_USAGE,
            "Pick a real target directory, e.g. /home/username/tmp",
        )

    # The check the user specifically asked for: a folder must not be sent to
    # something that looks like a file.
    if src.is_dir() and not had_trailing_slash and looks_like_file_path(normalised):
        if not force:
            die(
                f"input is a DIRECTORY but --output looks like a FILE: {normalised}",
                EXIT_USAGE,
                (
                    f"A folder cannot be written to a filename. Drop the extension:\n"
                    f"          -o {PurePosixPath(normalised).parent.as_posix()}\n"
                    f"        ...which will create "
                    f"{PurePosixPath(normalised).parent.as_posix()}/{src.name}\n"
                    f"        If {normalised!r} really is a directory, re-run with --force."
                ),
            )
        warn(f"--force given: treating {normalised!r} as a directory despite its extension.")

    # A file sent to an explicit filename is a rename; anything else is
    # "drop the input inside this directory".
    rename_mode = src.is_file() and not had_trailing_slash and looks_like_file_path(normalised)
    return normalised, rename_mode


# --------------------------------------------------------------------------
# Exclude handling
# --------------------------------------------------------------------------
def split_exclude_values(raw_values: list[str]) -> list[str]:
    """Flatten repeated -e flags and comma-separated lists into single tokens.

    `-e a,b -e c` and `-e "a, b, c"` both yield ['a', 'b', 'c'].
    """
    tokens: list[str] = []
    for chunk in raw_values:
        for piece in chunk.split(","):
            piece = piece.strip()
            if piece:
                tokens.append(piece)
    return tokens


def resolve_exclude(token: str, src: Path) -> str | None:
    """Turn one user-supplied exclude into an rsync pattern.

    A bare name (no slash) is left alone so it matches at any depth. A path is
    anchored to the exact location it names -- which, because we send the source
    directory itself, must be prefixed with the source's own basename:
    excluding `myproj/node_modules` requires the pattern `/myproj/node_modules`,
    NOT `/node_modules` (verified against rsync 3.2.7 and 3.5.0).

    Returns None if the token cannot possibly match, having warned the user.
    """
    token = token.rstrip("/")
    if not token:
        return None

    # No slash => a plain name or glob. rsync matches it at any depth, which is
    # exactly what people mean by `-e node_modules`. Pass straight through.
    if "/" not in token:
        return token

    has_glob = any(ch in GLOB_CHARS for ch in token)

    if src.is_file():
        warn(f"exclude {token!r} ignored: the input is a single file, not a folder.")
        return None

    candidate = Path(token).expanduser()
    rel: str | None = None

    if candidate.is_absolute():
        # A full path must lie inside the input folder to mean anything.
        try:
            rel = candidate.resolve().relative_to(src).as_posix()
        except (ValueError, OSError):
            if not has_glob:
                warn(
                    f"exclude {token!r} ignored: it is not inside the input folder "
                    f"({src})."
                )
                return None
            # Globbed absolute path we cannot resolve -- try a literal prefix strip.
            src_prefix = f"{src.as_posix()}/"
            if token.startswith(src_prefix):
                rel = token[len(src_prefix):]
            else:
                warn(f"exclude {token!r} ignored: it is not inside the input folder ({src}).")
                return None
    else:
        # Relative: prefer 'relative to the input folder', then fall back to
        # 'relative to the shell's CWD'. Whichever actually exists wins.
        if (src / token).exists():
            rel = token
        else:
            try:
                cwd_rel = (Path.cwd() / token).resolve().relative_to(src).as_posix()
                rel = cwd_rel
            except (ValueError, OSError):
                rel = token  # keep as given; may still be a glob that matches
                if not has_glob and not (src / token).exists():
                    warn(
                        f"exclude {token!r} does not exist under {src} -- "
                        f"it will simply match nothing."
                    )

    if rel is None or not rel or rel == ".":
        return None
    # Anchor to the transfer root, which includes the source directory name.
    return f"/{src.name}/{rel}"


def build_exclude_patterns(raw_values: list[str], src: Path) -> list[str]:
    patterns: list[str] = []
    for token in split_exclude_values(raw_values):
        pattern = resolve_exclude(token, src)
        if pattern and pattern not in patterns:
            patterns.append(pattern)
    return patterns


# --------------------------------------------------------------------------
# Remote helpers
# --------------------------------------------------------------------------
def ssh_base(args: argparse.Namespace) -> list[str]:
    """SSH command prefix. BatchMode keeps it non-interactive: key auth only."""
    return [
        "ssh",
        "-p", str(args.port),
        "-o", "BatchMode=yes",
        "-o", f"ConnectTimeout={CONNECT_TIMEOUT}",
        "-o", "StrictHostKeyChecking=accept-new",
        f"{args.user}@{args.host}",
    ]


def preflight(args: argparse.Namespace) -> None:
    """Fail fast and legibly before moving any bytes."""
    if shutil.which("rsync") is None:
        die("rsync is not installed locally", EXIT_PREFLIGHT, "Install it: sudo pacman -S rsync")
    if shutil.which("ssh") is None:
        die("ssh is not installed locally", EXIT_PREFLIGHT)

    info(f"Connecting to {args.user}@{args.host}:{args.port} ...")
    probe = subprocess.run(
        ssh_base(args) + ["command -v rsync >/dev/null && echo RSYNC_OK"],
        capture_output=True,
        text=True,
    )
    if probe.returncode != 0:
        detail = (probe.stderr or "").strip().splitlines()
        tail = detail[-1] if detail else f"ssh exited {probe.returncode}"
        die(
            f"cannot reach {args.host}:{args.port} over SSH -- {tail}",
            EXIT_PREFLIGHT,
            (
                "Checks: is the host powered on? is sshd running and listening on "
                f"port {args.port}? is your key in ~/.ssh/authorized_keys there?\n"
                f"        Test by hand: ssh -p {args.port} {args.user}@{args.host}"
            ),
        )
    if "RSYNC_OK" not in probe.stdout:
        die(
            f"rsync is not installed on {args.host}",
            EXIT_PREFLIGHT,
            "Install it there: sudo pacman -S rsync",
        )
    ok("Reachable, and rsync is present on both ends.")


def ensure_remote_dir(args: argparse.Namespace, remote_dir: str) -> None:
    """mkdir -p the destination directory, and refuse if it is an existing file."""
    if args.dry_run:
        info(f"[dry-run] would ensure remote directory exists: {remote_dir}")
        return
    quoted = shlex.quote(remote_dir)
    script = (
        f"if [ -e {quoted} ] && [ ! -d {quoted} ]; then echo NOT_A_DIR; exit 9; fi; "
        f"mkdir -p {quoted} && [ -w {quoted} ] && echo DIR_OK || {{ echo NOT_WRITABLE; exit 10; }}"
    )
    res = subprocess.run(ssh_base(args) + [script], capture_output=True, text=True)
    out = (res.stdout or "") + (res.stderr or "")
    if "NOT_A_DIR" in out:
        die(
            f"remote path exists but is a FILE, not a directory: {remote_dir}",
            EXIT_USAGE,
            "Choose a different --output, or remove that file on the remote host.",
        )
    if "NOT_WRITABLE" in out:
        die(f"remote directory is not writable by {args.user}: {remote_dir}", EXIT_PREFLIGHT)
    if res.returncode != 0 or "DIR_OK" not in out:
        die(
            f"could not create remote directory {remote_dir}: {out.strip() or res.returncode}",
            EXIT_PREFLIGHT,
        )


# --------------------------------------------------------------------------
# Transfer
# --------------------------------------------------------------------------
def build_rsync(args: argparse.Namespace, src: Path, dest_spec: str, *, dry: bool) -> list[str]:
    cmd = [
        "rsync",
        "-a",  # archive: recurse + preserve perms, times, symlinks, devices
        "-h",  # human-readable sizes
        "--partial",  # keep partial files so an interrupted run can resume
        "-e", f"ssh -p {args.port} -o BatchMode=yes -o StrictHostKeyChecking=accept-new",
    ]
    if dry:
        cmd.append("--dry-run")
    if not args.quiet:
        cmd += ["--info=progress2", "--human-readable"]
    if args.delete:
        cmd.append("--delete")
    for pattern in args.exclude_patterns:
        cmd += ["--exclude", pattern]

    # No trailing slash on a directory source => rsync copies the directory
    # ITSELF into the destination, which is the behavior we want.
    cmd.append(str(src))
    cmd.append(dest_spec)
    return cmd


def local_size(src: Path) -> tuple[int, int]:
    """Return (file_count, total_bytes), skipping anything unreadable."""
    if src.is_file():
        return 1, src.stat().st_size
    files = 0
    total = 0
    for root, _dirs, names in os.walk(src, onerror=lambda _e: None):
        for name in names:
            try:
                total += os.lstat(os.path.join(root, name)).st_size
                files += 1
            except OSError:
                pass
    return files, total


def verify(args: argparse.Namespace, src: Path, dest_spec: str) -> None:
    """Re-run rsync in dry-run mode; a clean run means nothing is left to send."""
    info("Verifying ...")
    cmd = build_rsync(args, src, dest_spec, dry=True)
    cmd = [c for c in cmd if c not in ("--info=progress2", "--human-readable")]
    cmd.insert(1, "--itemize-changes")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        die(f"verification run failed: {(res.stderr or '').strip()}", EXIT_VERIFY)

    # Ignore rsync's summary lines, plus directory entries that differ only in
    # metadata (itemize codes starting "cd" or ".d") -- those are not lost data.
    pending = [
        line
        for line in (res.stdout or "").splitlines()
        if line
        and not line.startswith(("sending", "sent ", "total size"))
        and not line.startswith("cd")
        and not line.startswith(".d")
    ]
    if pending:
        warn(f"{len(pending)} item(s) still differ after transfer:")
        for line in pending[:10]:
            print(f"        {line}", file=sys.stderr)
        if len(pending) > 10:
            print(f"        ... and {len(pending) - 10} more", file=sys.stderr)
        sys.exit(EXIT_VERIFY)
    ok("Verified: remote matches local.")


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
DESCRIPTION = """
Send a file or folder to another PC over SSH.

Specify the destination with -H/--host, -p/--port, and -u/--user.
All three connection arguments are required; no personal defaults are stored.

Uses rsync over an SSH key -- no password is stored, embedded, or asked for.
Transfers resume if interrupted, and are verified against the remote afterwards.

-o is the CONTAINER FOLDER. Whatever you send is placed INSIDE it; the output
folder itself is never replaced, renamed, or merged over, and anything already
in it is left alone. It is created for you if it does not exist. Trailing
slashes on -i and -o make no difference -- both are normalised before use.

  A FOLDER is sent as itself, recursively:
      -i ./docs    -o /home/username/tmp   ->   /home/username/tmp/docs/...
      -i ./docs/   -o /home/username/tmp/  ->   /home/username/tmp/docs/...   (identical)
  A FILE lands inside the output folder:
      -i ./log.txt -o /home/username/tmp   ->   /home/username/tmp/log.txt
  A FILE -- and only a file -- may be renamed on arrival by naming it in full:
      -i ./a.7z    -o /home/username/tmp/b.7z   ->   /home/username/tmp/b.7z

Nothing on the remote is ever deleted unless you explicitly pass --delete, and
even then only inside the folder being transferred, never its neighbors.
""".strip()

EPILOG = """
EXAMPLES
  Example connection: -H 192.168.1.100 -p 22 -u username
  Replace the example IP, SSH port, and username with your destination details.
  Preview what would be sent, moving nothing:
      %(prog)s -H 192.168.1.100 -p 22 -u username -i ./myproj -o /home/username/tmp --dry-run

  Send a folder, skipping dependency and build dirs:
      %(prog)s -H 192.168.1.100 -p 22 -u username -i ./myproj -o /home/username/tmp -e node_modules,.next

  Repeat -e, comma-separate, or both -- these three are identical:
      -e node_modules -e .git
      -e node_modules,.git
      -e "node_modules, .git"

  Exclude one specific path rather than every folder of that name:
      %(prog)s -H 192.168.1.100 -p 22 -u username -i ./myproj -o /home/username/tmp -e src/generated

  Mirror a folder, deleting remote files you have deleted locally:
      %(prog)s -H 192.168.1.100 -p 22 -u username -i ./myproj -o /home/username/tmp --delete

EXCLUDE RULES  (-e / --exclude)
  A bare NAME -- no slash -- matches at ANY depth:
      -e node_modules      skips myproj/node_modules AND myproj/a/b/node_modules
      -e '*.log'           skips every .log file anywhere

  A PATH -- contains a slash -- matches that ONE location only:
      -e src/generated     skips myproj/src/generated, nothing else
      -e 'build/*.o'       skips .o files directly in myproj/build

  Paths may be relative or absolute:
      relative   read against the input folder first, then your shell's CWD
      absolute   must lie inside the input folder; converted for you
      Anything that cannot match is reported as a warning, never silently
      dropped -- so a typo shows up instead of quietly transferring the folder.

  Quote globs ('*.log') so your shell does not expand them first.

EXIT CODES
      0  success
      2  bad arguments
      3  cannot reach host / auth failed
      4  transfer failed
      5  verification mismatch
    130  interrupted (partial data kept, re-runnable)
""".strip()


def ssh_port(raw: str) -> int:
    """Parse a TCP port before attempting any connection."""
    try:
        port = int(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("SSH port must be an integer from 1 to 65535") from exc
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("SSH port must be an integer from 1 to 65535")
    return port


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=Path(sys.argv[0]).name,
        description=DESCRIPTION,
        epilog=EPILOG,
        formatter_class=lambda prog: argparse.RawDescriptionHelpFormatter(
            prog, max_help_position=30, width=min(shutil.get_terminal_size((100, 24)).columns, 100)
        ),
        add_help=False,
    )

    required = parser.add_argument_group("required")
    required.add_argument(
        "-i", "--input", required=True, metavar="PATH",
        help="Local file or folder to send. Relative or absolute; ~ is expanded. "
             "A folder is sent recursively, including the folder itself.",
    )
    required.add_argument(
        "-o", "--output", required=True, metavar="REMOTE_PATH",
        help="FULL absolute path on the remote host. Normally the destination "
             "DIRECTORY the input is placed inside. For a file input you may "
             "instead give a complete target filename to rename it on arrival. "
             "Created automatically if missing.",
    )

    filtering = parser.add_argument_group("filtering")
    filtering.add_argument(
        "-e", "--exclude", action="append", default=[], metavar="PATTERN",
        help="Skip matching files/folders. Repeatable, and each value may be a "
             "comma-separated list. Bare names match at any depth; values "
             "containing a slash match one exact path. See EXCLUDE RULES below.",
    )

    preview = parser.add_argument_group("preview and safety")
    preview.add_argument(
        "-n", "--dry-run", action="store_true",
        help="Show exactly what would transfer, moving no data. Use this first.",
    )
    preview.add_argument(
        "--delete", action="store_true",
        help="Mirror mode: DELETE remote files that no longer exist locally. "
             "Asks for confirmation unless --yes is given.",
    )
    preview.add_argument(
        "--no-verify", action="store_true",
        help="Skip the post-transfer comparison against the remote.",
    )
    preview.add_argument(
        "--force", action="store_true",
        help="Override the folder-sent-to-a-filename guard. Rarely correct.",
    )
    preview.add_argument(
        "-y", "--yes", action="store_true",
        help="Assume yes for confirmation prompts (for unattended runs).",
    )

    connection = parser.add_argument_group("connection")
    connection.add_argument(
        "-H", "--host", required=True, metavar="ADDR",
        help="Destination PC's LAN IP or hostname (required).",
    )
    connection.add_argument(
        "-p", "--port", type=ssh_port, required=True, metavar="N",
        help="Destination SSH port, 1-65535 (required; usually 22).",
    )
    connection.add_argument(
        "-u", "--user", required=True, metavar="NAME",
        help="SSH username on the destination PC (required).",
    )

    output = parser.add_argument_group("output")
    output.add_argument(
        "-q", "--quiet", action="store_true",
        help="Suppress the live progress meter. Errors are still shown.",
    )
    output.add_argument(
        "-h", "--help", action="help",
        help="Show this help and exit.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    src = validate_input(args.input)
    remote_path, rename_mode = validate_output(args.output, src, args.force)
    args.exclude_patterns = build_exclude_patterns(args.exclude, src)

    # Work out the destination directory to create, the rsync destination
    # spec, and the final resting path (for reporting).
    if rename_mode:
        remote_dir = PurePosixPath(remote_path).parent.as_posix()
        dest_spec = f"{args.user}@{args.host}:{shlex.quote(remote_path)}"
        final_path = remote_path
    else:
        remote_dir = remote_path
        dest_spec = f"{args.user}@{args.host}:{shlex.quote(remote_path)}/"
        final_path = f"{remote_path}/{src.name}"

    count, total = local_size(src)
    kind = "directory" if src.is_dir() else "file"
    info(f"Input   : {src}  ({kind}, {count} file(s), {human_bytes(total)})")
    info(f"Output  : {args.user}@{args.host}:{final_path}")
    if rename_mode:
        info("Mode    : rename on arrival")
    if args.exclude_patterns:
        info(f"Excludes: {', '.join(args.exclude_patterns)}")

    if args.delete and not args.yes and not args.dry_run:
        warn(f"--delete will REMOVE remote files under {remote_dir} that are absent locally.")
        try:
            if input("        Type 'yes' to continue: ").strip().lower() != "yes":
                info("Aborted.")
                return EXIT_OK
        except EOFError:
            die("--delete needs confirmation; re-run with --yes", EXIT_USAGE)

    preflight(args)
    ensure_remote_dir(args, remote_dir)

    cmd = build_rsync(args, src, dest_spec, dry=args.dry_run)
    info(("[dry-run] " if args.dry_run else "") + "Transferring ...")
    result = subprocess.run(cmd)
    if result.returncode != 0:
        die(
            f"rsync failed with exit code {result.returncode}",
            EXIT_TRANSFER,
            "Nothing was left half-written that rsync cannot resume; re-run to continue.",
        )

    if args.dry_run:
        ok("Dry run complete -- no data was transferred.")
        return EXIT_OK

    ok(f"Transferred to {args.host}:{final_path}")
    if not args.no_verify:
        verify(args, src, dest_spec)
    return EXIT_OK


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nInterrupted. Partial data is kept; re-run to resume.", file=sys.stderr)
        sys.exit(EXIT_INTERRUPT)
