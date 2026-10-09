# Source installers

These scripts build software from source and install it under versioned prefixes
in `/usr/local/programs`, with links in `/usr/local/bin` where applicable. Keep
using each script's existing command name. Every installer remains standalone;
there is no additional helper file to download.

Most installers require Debian or Ubuntu and APT. Autoconf, Automake, Ninja, and
Wget contain their own package-manager or dependency controls. Read the chosen
script's help and package list before running it. `build-gnutls.sh` builds the
Guile GnuTLS bindings, rather than the core GnuTLS library.

## Build resources and options

The legacy installers accept `JOBS` as a positive integer. Without an override,
they use `nproc`, respecting the CPUs available to the process. GCC accepts the
same override and otherwise leaves two available cores free when possible, with
a minimum of one job. Ninja and Wget retain their existing `--jobs` options.

For example:

```bash
JOBS=2 bash /home/jman/tmp/script-repo/Bash/installer-scripts/gnu-software/build-bash.sh --version 5.3
bash /home/jman/tmp/script-repo/Bash/installer-scripts/gnu-software/build-all-gnu.sh --help
```

The example build performs compilation and may install dependencies with sudo.
Run most scripts as your normal user. Automake and glibc retain their requirement
to run as root. Build one installer at a time; publication into the same install
prefix is not serialized across processes.

The Bash, Findutils, Gawk, Grep, Gzip, Nano, Readline, Sed, and Tar installers
accept `--version`, `--compiler gcc|clang`, `--list`, and `--uninstall`.
Version and compiler validation happens before package changes. Combine
`--uninstall --version VERSION` to select the installation to remove. Programs
with fixed releases retain their existing versions; this update does not upgrade
all pinned releases.

## Downloads, workspaces, and failures

Downloads use the configured browser user agent, retries, and connection or
transfer timeouts. Curl rejects HTTP errors and permits only HTTPS, including
redirects. The installers stop on failed downloads, extraction, configuration,
and build commands rather than continuing into installation.

Legacy workspaces and GCC's main build directory are private directories made
with `mktemp`. Existing directories in the launch location are preserved. The
legacy cleanup prompts accept `y`/`n` or `1`/`2`; an empty answer or end-of-input
retains the files. Successful automatic-cleanup scripts retain that behavior.
GCC, Ninja, and Wget retain their separate cleanup controls.

Publication skips absent files and empty globs, creates destination directories,
preserves binary names, and refuses to replace an existing directory with a
symlink in the directory-link helper. Compiler-selecting installers use `g++`
for GCC and `clang++` for Clang.

GCC verifies source archives with `gpgv` using the GNU keyring fetched over HTTPS
into a private directory. Missing or bad signatures stop the build. Its upstream
prerequisite recipe keeps checksum verification and runs through private download
wrappers that set the user agent and timeouts and upgrade GCC infrastructure
URLs to HTTPS. Prerequisite failures stop configuration. Saved static binaries
go into the original launch directory, outside the temporary build tree.

glibc remains under `/usr/local/programs/glibc-2.39`. Its tests must pass before
installation. The installer does not link its libraries or binaries into global
directories or modify `/etc/localtime`. Programs that need this glibc must use
the installed dynamic loader explicitly. This is not an operating-system glibc
upgrade procedure.

## Verification

The focused regression tests intercept network, compiler, package-manager, and
privileged commands. Filesystem-publication checks use real links and copies in
temporary directories. Repeat them with:

```bash
bash /home/jman/tmp/script-repo/tests/gnu_installers_test.sh
bash /home/jman/tmp/script-repo/tests/source_git_repo_version_test.sh
```

These checks do not prove each package compiles against every distribution's
current libraries. No GNU installer, full build, or real package installation
was run during this update. Validate actual builds and installed programs on a
disposable machine before using them on a working system.
