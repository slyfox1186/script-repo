#!/usr/bin/env python3
"""
CUDA Auto-Installer for Ubuntu 22.04
Installs the newest CUDA toolkit from NVIDIA's network apt repository **if not already installed**,
following https://docs.nvidia.com/cuda/cuda-installation-guide-linux/ (network repository method).
Supports the Ubuntu releases and architectures NVIDIA publishes repositories for.
"""

import argparse
import gzip
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from collections.abc import Iterator, Sequence
from pathlib import Path
from typing import Any

import requests

REPO_BASE_URL = "https://developer.download.nvidia.com/compute/cuda/repos"
KEYRING_DEB = "cuda-keyring_1.1-1_all.deb"
# dpkg architecture -> NVIDIA repository directory (the guide's "Architecture" column)
REPO_ARCHES = {"amd64": "x86_64", "arm64": "sbsa"}
HTTP_TIMEOUT = (10, 60)  # (connect, read) seconds
TOOLKIT_PACKAGE_RE = re.compile(r'cuda-toolkit-\d+-\d+')
# Debian [epoch:]upstream_version[-debian_revision]; CUDA's upstream version is dotted numbers.
DEB_VERSION_RE = re.compile(r'(?:\d+:)?(\d+(?:\.\d+)*)(?:-[0-9A-Za-z.+~]+)?')
# The X-Y series in a versioned CUDA package name: libcublas-13-3, cuda-toolkit-13-3-config-common.
SERIES_PACKAGE_RE = re.compile(r'-(\d+)-(\d+)(?:-|$)')
LOCAL_REPO_RE = re.compile(r'cuda-repo-.+-local')
# Versioned tools pulled in only by cuda-nsight-*-X-Y. Nothing else apt reports as no longer
# required is removed: per NVIDIA's removal guide that can include the NVIDIA driver.
NSIGHT_TOOL_RE = re.compile(r'nsight-(?:compute|systems)-[\d.]+')
# Repository keys that NVIDIA's local-installer instructions copy into /usr/share/keyrings.
LOCAL_KEYRING_RE = re.compile(r'cuda-[0-9A-F]{8}-keyring\.gpg')
# Driver meta packages NVIDIA's removal guide says to mark manual before cleaning up.
DRIVER_PACKAGES = ("nvidia-open", "cuda-drivers")

Version = tuple[int, ...]


def parse_version(text: str) -> Version:
    """CUDA release of a Debian or plain version string: '13.4.2-1' -> (13, 4, 2).

    The package name (cuda-toolkit-13-4) and `nvcc --version` carry only
    major.minor; the patch release is only in the version string. Unexpected
    formats raise ValueError rather than being compared wrongly.
    """
    match = DEB_VERSION_RE.fullmatch(text.strip())
    if not match:
        raise ValueError(f"Unrecognized CUDA version: {text!r}")
    return tuple(int(part) for part in match.group(1).split('.'))


def format_version(version: Version) -> str:
    return '.'.join(map(str, version))


def iter_toolkit_versions(packages_text: str) -> Iterator[tuple[str, Version]]:
    """Yield (package, release) for each cuda-toolkit-X-Y stanza of an apt Packages index."""
    for stanza in re.split(r'\n\s*\n', packages_text):
        fields = dict(re.findall(r'^([\w-]+):[ \t]*(.*)$', stanza, re.MULTILINE))
        package = fields.get('Package', '')
        if TOOLKIT_PACKAGE_RE.fullmatch(package):
            yield package, parse_version(fields['Version'])


def dpkg_status(pattern: str) -> list[tuple[str, str]]:
    """(package, version) of installed packages matching a dpkg-query pattern."""
    result = subprocess.run(
        ["dpkg-query", "-W", "-f", "${Package} ${Version} ${db:Status-Status}\n", pattern],
        capture_output=True, text=True, check=False
    )
    # Exit status 1 only means no package matched the pattern.
    if result.returncode not in (0, 1):
        raise RuntimeError(f"dpkg-query failed: {result.stderr.strip()}")
    return [(package, version) for package, version, status in
            (line.split(' ') for line in result.stdout.splitlines())
            if status == 'installed']


def installed_nvidia_packages() -> set[str]:
    """Installed packages whose maintainer address is at nvidia.com."""
    result = subprocess.run(
        ["dpkg-query", "-W", "-f", "${binary:Package}\t${Maintainer}\t${db:Status-Status}\n"],
        capture_output=True, text=True, check=True
    )
    return {package for package, maintainer, status in
            (line.split('\t') for line in result.stdout.splitlines())
            if status == 'installed' and maintainer.endswith('@nvidia.com>')}


def simulate_purge(packages: Sequence[str]) -> tuple[set[str], list[str]]:
    """Packages `apt-get remove --purge` would remove, and those it would leave no longer required."""
    result = subprocess.run(
        ["apt-get", "-s", "remove", "--purge", *packages],
        capture_output=True, text=True, check=False,
        env={**os.environ, "LC_ALL": "C"}  # the output parsed below is translated otherwise
    )
    if result.returncode != 0:
        raise RuntimeError(f"apt-get simulation failed: {result.stderr.strip()}")
    removed = set(re.findall(r'^(?:Purg|Remv) (\S+)', result.stdout, re.MULTILINE))
    unneeded = re.search(r'no longer required:\n((?:  .*\n)+)', result.stdout)
    return removed, unneeded.group(1).split() if unneeded else []


class CudaInstaller:
    def __init__(self, force=False, keep_old=False):
        self.force = force
        self.keep_old = keep_old
        self.session = requests.Session()
        self.packages_content = None
        self.ubuntu_version = None  # e.g. "24.04"
        self.ubuntu_tag = None      # e.g. "ubuntu2404"
        self.repo_url = None        # set after OS detection

    def check_os(self):
        """Detect the Ubuntu release and architecture and select the matching NVIDIA repository."""
        try:
            os_release = platform.freedesktop_os_release()
        except OSError as e:
            print(f"Cannot verify OS: {e}")
            return False

        if os_release['ID'] != 'ubuntu' or 'VERSION_ID' not in os_release:
            print("This script is designed for Ubuntu only.")
            return False

        arch = subprocess.run(["dpkg", "--print-architecture"],
                              capture_output=True, text=True, check=True).stdout.strip()
        if arch not in REPO_ARCHES:
            print(f"Unsupported architecture: {arch}")
            return False

        self.ubuntu_version = os_release['VERSION_ID']
        self.ubuntu_tag = "ubuntu" + self.ubuntu_version.replace(".", "")
        self.repo_url = f"{REPO_BASE_URL}/{self.ubuntu_tag}/{REPO_ARCHES[arch]}"
        print(f"Detected Ubuntu {self.ubuntu_version} ({self.ubuntu_tag}, {arch})")
        return True

    def check_sudo(self):
        """Verify cached sudo access."""
        return subprocess.run(['sudo', '-n', 'true'], capture_output=True, check=False).returncode == 0

    def get_installed_cuda_version(self) -> Version | None:
        """Return the newest installed CUDA toolkit release, e.g. (13, 4, 2), or None."""
        versions = [parse_version(version) for package, version in dpkg_status("cuda-toolkit-*")
                    if TOOLKIT_PACKAGE_RE.fullmatch(package)]
        if versions:
            return max(versions)

        # Not installed with apt (e.g. the runfile installer): ask the toolkit on PATH.
        nvcc = shutil.which("nvcc")
        if nvcc is None:
            return None
        version_json = Path(nvcc).resolve().parent.parent / "version.json"
        try:
            return parse_version(json.loads(version_json.read_text())["cuda"]["version"])
        except (OSError, ValueError, KeyError, TypeError):
            pass
        result = subprocess.run([nvcc, "--version"], capture_output=True, text=True, check=False)
        match = re.search(r'release (\d+\.\d+)', result.stdout)
        return parse_version(match.group(1)) if match else None

    def get_packages_content(self):
        """Download and cache the repository's Packages index (tries .gz first)."""
        if self.packages_content is not None:
            return self.packages_content

        # Try compressed first (1.2MB vs 5MB)
        for suffix in ('.gz', ''):
            url = f"{self.repo_url}/Packages{suffix}"
            try:
                response = self.session.get(url, timeout=HTTP_TIMEOUT)
                response.raise_for_status()
                data = gzip.decompress(response.content) if suffix else response.content
                self.packages_content = data.decode('utf-8')
            except (requests.RequestException, OSError, EOFError, UnicodeDecodeError) as e:
                print(f"Could not fetch Packages{suffix}: {e}")
                continue
            print(f"Fetched package metadata from Packages{suffix}")
            return self.packages_content

        print("Failed to download package metadata.")
        return None

    def get_latest_toolkit(self) -> tuple[str, Version]:
        """Return the newest (package, release) in NVIDIA's repository, e.g. ('cuda-toolkit-13-4', (13, 4, 2))."""
        content = self.get_packages_content()
        if content is None:
            raise RuntimeError("Could not download package metadata")

        toolkits = list(iter_toolkit_versions(content))
        if not toolkits:
            raise RuntimeError("No CUDA versions found in repository")
        return max(toolkits, key=lambda toolkit: toolkit[1])

    def download(self, url, destination):
        """Stream url to the destination path."""
        print(f"\nDownloading {url}...")
        with self.session.get(url, timeout=HTTP_TIMEOUT, stream=True) as response:
            response.raise_for_status()
            with open(destination, 'wb') as f:
                f.writelines(response.iter_content(chunk_size=64 * 1024))
        print("  OK")

    def run_command(self, command, description):
        """Run a command with its output on the terminal; raise if it fails.

        No timeout: killing apt or dpkg midway can leave the package database
        half-configured.
        """
        print(f"\n{description}...")
        print(f"  $ {' '.join(command)}")
        result = subprocess.run(command, check=False)
        if result.returncode != 0:
            raise RuntimeError(f"{description} failed (exit code {result.returncode})")
        print("  OK")

    def install_keyring(self):
        """Install NVIDIA's cuda-keyring package: the repository's signing key, apt source and pin file."""
        if dpkg_status("cuda-keyring") and not self.force:
            print("\ncuda-keyring is already installed; repository is configured.")
        else:
            with tempfile.TemporaryDirectory() as tmp:
                deb_path = Path(tmp) / KEYRING_DEB
                self.download(f"{self.repo_url}/{KEYRING_DEB}", deb_path)
                self.run_command(["sudo", "dpkg", "-i", str(deb_path)], "Installing cuda-keyring")
        self.remove_legacy_source()

    def remove_legacy_source(self):
        """Remove the apt source earlier versions of this script wrote, which duplicates cuda-keyring's.

        Only an unmodified copy is removed, and only while cuda-keyring's own
        sources file exists, so the repository never ends up unconfigured.
        """
        legacy = Path(f"/etc/apt/sources.list.d/cuda-{self.ubuntu_tag}.list")
        written = f"deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] {self.repo_url} /"
        try:
            if legacy.read_text().strip() != written:
                return
        except FileNotFoundError:
            return
        keyring_files = subprocess.run(["dpkg-query", "-L", "cuda-keyring"],
                                       capture_output=True, text=True, check=False).stdout.split()
        if not any(path.startswith("/etc/apt/sources.list.d/") and Path(path).is_file()
                   for path in keyring_files):
            return
        self.run_command(["sudo", "rm", "--", str(legacy)],
                         f"Removing {legacy}, which duplicates cuda-keyring's apt source")

    def remove_old_installs(self, series: Version):
        """Purge CUDA toolkits older than `series` and every local-installer repository.

        Packages are named explicitly and never autoremoved (see NSIGHT_TOOL_RE),
        and nothing is removed if apt would also take any package not selected here.
        """
        print("\n--- Removing outdated CUDA installations ---")
        self.keep_driver()
        targets = {
            package for package in installed_nvidia_packages()
            if LOCAL_REPO_RE.fullmatch(package)
            or ((match := SERIES_PACKAGE_RE.search(package))
                and (int(match[1]), int(match[2])) < series)
        }
        if targets:
            removed, unneeded = simulate_purge(sorted(targets))
            unexpected = removed - targets
            if unexpected:
                raise RuntimeError("purging outdated CUDA packages would also remove "
                                   f"{', '.join(sorted(unexpected))}; nothing was removed")
            targets.update(p for p in unneeded if NSIGHT_TOOL_RE.fullmatch(p))
            self.run_command(["sudo", "apt-get", "-y", "remove", "--purge", *sorted(targets)],
                             f"Purging {len(targets)} outdated CUDA packages")
        else:
            print("\nNo outdated CUDA packages are installed.")
        self.remove_unused_local_keyrings()
        self.report_unmanaged_installs(series)

    def keep_driver(self):
        """Mark the driver meta package manually installed, as NVIDIA's removal guide instructs.

        CUDA 13.3 and earlier installed the driver as a dependency; once those
        toolkits are gone apt would otherwise offer to autoremove the driver.
        """
        auto = subprocess.run(["apt-mark", "showauto", *DRIVER_PACKAGES],
                              capture_output=True, text=True, check=True).stdout.split()
        if auto:
            self.run_command(["sudo", "apt-mark", "manual", *auto],
                             "Marking the NVIDIA driver as manually installed")

    def remove_unused_local_keyrings(self):
        """Delete local-installer repository keys that no package owns and no apt source uses."""
        sources_d = Path("/etc/apt/sources.list.d")
        sources = [Path("/etc/apt/sources.list"), *(sources_d.iterdir() if sources_d.is_dir() else [])]
        in_use = "\n".join(path.read_text() for path in sources if path.is_file())
        unused = [
            str(key) for key in sorted(Path("/usr/share/keyrings").glob("cuda-*-keyring.gpg"))
            if LOCAL_KEYRING_RE.fullmatch(key.name) and key.name not in in_use
            and subprocess.run(["dpkg-query", "-S", str(key)], capture_output=True,
                               check=False).returncode != 0
        ]
        if unused:
            self.run_command(["sudo", "rm", "--", *unused],
                             "Removing unused local-installer repository keys")

    def report_unmanaged_installs(self, series: Version):
        """List older /usr/local/cuda-X.Y trees apt does not manage; they are never deleted blindly."""
        for path in sorted(Path("/usr/local").glob("cuda-*")):
            match = re.fullmatch(r'cuda-(\d+)\.(\d+)', path.name)
            if path.is_symlink() or not match or (int(match[1]), int(match[2])) >= series:
                continue
            uninstaller = path / "bin" / "cuda-uninstaller"
            if uninstaller.exists():
                print(f"\nRunfile install of CUDA {match[1]}.{match[2]} found; remove it with: "
                      f"sudo {uninstaller}")
            else:
                print(f"\n{path} still holds files that no package owns; "
                      "delete it if you no longer need them.")

    def install_cuda(self):
        """Main installation process using the network repository method."""
        print("CUDA Auto-Installer for Ubuntu")
        print("=" * 50)

        # Pre-installation checks
        if not self.check_os():
            return False

        if not self.check_sudo():
            print("This script requires sudo access. Please run 'sudo -v' first.")
            return False

        print("System checks passed\n")

        try:
            installed = self.get_installed_cuda_version()
            if installed:
                print(f"Installed CUDA version: {format_version(installed)}")
            else:
                print("No existing CUDA installation detected.")

            package, latest = self.get_latest_toolkit()
            print(f"Latest CUDA toolkit version: {format_version(latest)}")

            if installed and installed >= latest and not self.force:
                state = "already installed" if installed == latest else "older than the installed version"
                print(f"\nCUDA {format_version(latest)} is {state}. Nothing to do.")
                print("Use --force to reinstall.")
                return True

            print("\nInstallation plan:")
            print(f"  Repository : {self.repo_url}")
            print(f"  Keyring    : {KEYRING_DEB}")
            print(f"  Package    : {package} ({format_version(latest)})")
            print("  Cleanup    : "
                  + ("skipped (--keep-old)" if self.keep_old else
                     f"purge CUDA older than {format_version(latest[:2])} and local-installer repositories"))

            self.install_keyring()
            self.run_command(["sudo", "apt-get", "update"], "Updating package list")
            install = ["sudo", "apt-get", "-y", "install"]
            if self.force:
                install.append("--reinstall")
            self.run_command([*install, package], f"Installing {package}")

        except (RuntimeError, ValueError, OSError, requests.RequestException,
                subprocess.SubprocessError) as e:
            print(f"\nInstallation failed: {e}")
            return False

        series = format_version(latest[:2])
        print("\n" + "=" * 50)
        print(f"CUDA {format_version(latest)} installation completed successfully!")

        cleaned = True
        if not self.keep_old:
            try:
                self.remove_old_installs(latest[:2])
            except (RuntimeError, OSError, subprocess.SubprocessError) as e:
                print(f"\nCleanup of outdated CUDA installations failed: {e}")
                cleaned = False

        print("\nTo complete setup, add this to ~/.bashrc (replacing any older CUDA PATH entry):")
        print(f"  export PATH=/usr/local/cuda-{series}/bin${{PATH:+:${{PATH}}}}")
        print("Then run: source ~/.bashrc")
        print("Verify with: nvcc --version")
        print("The toolkit does not include the NVIDIA driver; install a compatible driver separately.")
        return cleaned


# ─── Help screen ─────────────────────────────────────────────────────────────
# The same block is pasted into each standalone script in this folder; keep the copies identical.

_HELP_MAX_WIDTH = 100
_HELP_FLAG_MAX_WIDTH = 28
_HELP_DEFAULT_RE = re.compile(r'\s*(\(default: [^)]*\))$')
_HELP_STYLES = {
    'heading': '\033[1m\033[96m',
    'flag': '\033[92m',
    'value': '\033[93m',
    'bold': '\033[1m',
    'dim': '\033[2m',
}


def _metavar(action: argparse.Action) -> str:
    """Display name for an action's value; argparse also allows a tuple metavar."""
    if isinstance(action.metavar, tuple):
        return ' '.join(action.metavar)
    return action.metavar or action.dest.upper()


def _help_color_enabled() -> bool:
    """Color help on a terminal unless NO_COLOR, TERM=dumb or --no-color opts out; FORCE_COLOR opts in."""
    if os.environ.get('NO_COLOR') or '--no-color' in sys.argv:
        return False
    if os.environ.get('FORCE_COLOR'):
        return True
    return sys.stdout.isatty() and os.environ.get('TERM') != 'dumb'


class HelpParser(argparse.ArgumentParser):
    """ArgumentParser with a short usage line and a grouped, colored help screen.

    Sections are the parser's argument groups, in order. ``examples`` holds
    ``(what it does, arguments after the program name)`` pairs. Automatic -h is
    off, so add ``-h/--help`` with ``action='help'`` to the group it belongs in.
    """

    def __init__(self, *, title: str, version: str = '',
                 examples: Sequence[tuple[str, str]] = (), **kwargs: Any) -> None:
        super().__init__(add_help=False, **kwargs)
        self.help_title = title
        self.help_version = version
        self.help_examples = examples

    def _positional_usage(self) -> list[str]:
        parts = []
        for action in self._actions:
            if action.option_strings or action.help == argparse.SUPPRESS:
                continue
            name = _metavar(action)
            forms: dict[object, str] = {'?': f'[{name}]', '*': f'[{name} ...]', '+': f'{name} ...'}
            parts.append(forms.get(action.nargs, name))
        return parts

    def format_usage(self) -> str:
        return f"usage: {' '.join([self.prog, '[OPTIONS]', *self._positional_usage()])}\n"

    def error(self, message: str):
        self.print_usage(sys.stderr)
        self.exit(2, f"{self.prog}: error: {message}\nRun '{self.prog} --help' to see all options.\n")

    def format_help(self) -> str:
        use_color = _help_color_enabled()

        def paint(text: str, style: str) -> str:
            return f"{_HELP_STYLES[style]}{text}\033[0m" if use_color and text else text

        def help_text(action) -> str:
            text = action.help or ''
            return text % {**vars(action), 'prog': self.prog} if '%' in text else text

        width = min(shutil.get_terminal_size((_HELP_MAX_WIDTH, 24)).columns, _HELP_MAX_WIDTH)
        # Action groups are argparse's only record of section membership and order.
        sections = [
            (group.title or '', [a for a in group._group_actions
                           if a.option_strings and a.help != argparse.SUPPRESS])
            for group in self._action_groups
        ]
        sections = [(title, actions) for title, actions in sections if actions]
        all_options = [a for _, actions in sections for a in actions]

        def split_flags(action) -> tuple[str, str, str]:
            shorts = [o for o in action.option_strings if not o.startswith('--')]
            longs = [o for o in action.option_strings if o.startswith('--')]
            short = ', '.join(shorts) + (', ' if shorts and longs else '')
            metavar = ''
            if action.nargs != 0:
                metavar = _metavar(action)
                if action.nargs in ('+', '*'):
                    metavar += '...'
                elif action.nargs == '?':
                    metavar = f'[{metavar}]'
            return short, ', '.join(longs), metavar

        short_col = max((len(split_flags(a)[0]) for a in all_options), default=0)

        def flag_cell(action) -> tuple[str, str]:
            short, long, metavar = split_flags(action)
            plain = short.rjust(short_col) + long + (f" {metavar}" if metavar else '')
            colored = (' ' * (short_col - len(short)) + paint(short, 'flag')
                       + paint(long, 'flag')
                       + (f" {paint(metavar, 'value')}" if metavar else ''))
            return plain, colored

        flag_width = min(max((len(flag_cell(a)[0]) for a in all_options), default=0),
                         _HELP_FLAG_MAX_WIDTH)
        help_col = 2 + flag_width + 3
        # Too narrow for two columns: put each description under its flags.
        stacked = width - help_col < 24
        text_col = short_col + 4 if stacked else help_col
        text_width = max(width - text_col, 20)

        def row(plain: str, colored: str, text: str) -> list[str]:
            match = _HELP_DEFAULT_RE.search(text)
            body = text[:match.start()] if match else text
            lines = textwrap.wrap(body, text_width) or ['']
            if match:
                default = match.group(1)
                if len(lines[-1]) + 1 + len(default) <= text_width:
                    lines[-1] = f"{lines[-1]} {paint(default, 'dim')}".lstrip()
                else:
                    lines.append(paint(default, 'dim'))
            indent = ' ' * text_col
            if stacked or len(plain) > flag_width:
                return [f"  {colored}"] + [indent + line for line in lines]
            first = f"  {colored}{' ' * (help_col - 2 - len(plain))}{lines[0]}"
            return [first] + [indent + line for line in lines[1:]]

        def heading(title: str) -> list[str]:
            return ['', paint(title.upper(), 'heading')]

        out = [paint(self.help_title, 'heading')
               + (paint(f" v{self.help_version}", 'dim') if self.help_version else '')]
        if self.description:
            out += textwrap.wrap(self.description, width)

        out += heading("Usage")
        out.append(' '.join([f"  {paint(self.prog, 'bold')}", paint('[OPTIONS]', 'flag'),
                             *(paint(p, 'value') for p in self._positional_usage())]))
        for action in self._actions:
            if not action.option_strings and action.help != argparse.SUPPRESS:
                name = _metavar(action)
                out.append('')
                out += row(name, paint(name, 'value'), help_text(action))

        for title, actions in sections:
            out += heading(title)
            for action in actions:
                out += row(*flag_cell(action), help_text(action))

        if self.help_examples:
            out += heading("Examples")
            for what, cmd_args in self.help_examples:
                out.append(f"  {paint('# ' + what, 'dim')}")
                out.append(f"  {paint('$', 'dim')} {paint(self.prog, 'bold')} {cmd_args}".rstrip())
        out.append('')
        return '\n'.join(out)


# (what it does, arguments after the program name)
HELP_EXAMPLES = [
    ("Install the newest CUDA toolkit unless it is already installed", ""),
    ("Reinstall it even if it is already up to date", "--force"),
    ("Install the newest toolkit but keep older CUDA versions alongside it", "--keep-old"),
]


def main():
    parser = HelpParser(
        title="CUDA Auto-Installer",
        description=(
            "Detect your Ubuntu version, find the newest CUDA toolkit release (e.g. 13.4.2) "
            "in NVIDIA's apt repository, and install it unless it is already installed. "
            "After a successful install it purges older CUDA toolkits and local-installer "
            "repositories. Run 'sudo -v' first: the script needs cached sudo access."
        ),
        examples=HELP_EXAMPLES,
    )
    options = parser.add_argument_group("Options")
    options.add_argument("--force", action="store_true",
                         help="Reinstall cuda-keyring and the toolkit package even if the "
                              "newest version is already installed")
    options.add_argument("--keep-old", action="store_true",
                         help="After installing, keep older CUDA toolkits and local-installer "
                              "repositories instead of purging them")
    options.add_argument("-h", "--help", action="help", help="Show this help and exit")
    args = parser.parse_args()

    installer = CudaInstaller(force=args.force, keep_old=args.keep_old)
    try:
        succeeded = installer.install_cuda()
    except KeyboardInterrupt:
        print("\n\nInstallation cancelled by user.")
        sys.exit(130)
    sys.exit(0 if succeeded else 1)


if __name__ == "__main__":
    main()
