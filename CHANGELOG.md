# CHANGELOG

Log of corpus-wide bug sweeps performed on `Python3/` and `Bash/`. Purpose: record every change, its reasoning, and the triage knowledge needed to repeat this task without re-litigating settled decisions.

## 2026-07-05 — Second corpus-wide sweep (deep semantic pass)

**Method:** baseline (`ruff` + `shellcheck -S error` + `py_compile` + `bash -n`) was already clean from the 2026-07-04 sweep, so this pass mined `shellcheck -S warning` and broader ruff rule sets for candidates, fanned out read-only scout agents per directory group, then independently verified every claim against the code (and against live tools where possible) before fixing. Every fix below was re-verified with `bash -n` + `shellcheck -S error` (Bash) or the ruff baseline + `py_compile` (Python).

### Directory removals (user-directed)
- **Deleted `Bash/Ubuntu-Scripts/bionic`, `Bash/Ubuntu-Scripts/focal`, `Bash/Debian-Scripts/bullseye`** — user instruction: drop Bullseye and all pre-jammy Ubuntu versions (EOL/old). `jammy`, `jammy-bak`, `Noble`, `bookworm` remain. Git history preserves the deleted trees.

### High-severity functional bugs (verified by execution or full trace)

- **`dpkg-query -W -f '$Status\n'` (unbraced) never matches** — proved live: dpkg-query prints the literal string `$Status`, so `installed()` always returned "not installed" and scripts reinstalled their full package list every run. Fixed to `'${Status}\n'` in `Ubuntu-Scripts/focal/focal-pkgs.sh` (since deleted with focal), `GitHub-Projects/Download-Tools/build-dl-tools.sh`, and `build-dl-tools` (extensionless variant).
- **`dpkg -l | grep -o "$pkg"` substring dependency checks (15 sites, class eliminated)** — matches any package whose name/description merely *contains* the target (e.g. `libtool` matched by `libtool-bin`), silently skipping needed installs. Replaced with `dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -o 'ok installed'` (keeps the surrounding `-z` logic identical) in: build-mainline.sh, build-all-git-safer.sh, build-all-git.sh, build-libboost.sh, build-dbus.sh, build-attr.sh, build-yasm.sh, build-diffutils.sh, build-curl-with-openssl-quic.sh, build-nasm.sh, build-garbage-collector.sh, build-autoconf-archive.sh, plus conditional forms in `Raspbian-OS/Pi-Hole/change-the-defaultt-web-port.sh`, `Raspbian-OS/user-scripts/raspi-scripts.sh`, `Debian-Scripts/bookworm/**` (x2). Special cases: `Arch-Linux-Scripts/.bash_functions` `cmf()` used **dpkg on Arch** → now `pacman -Qi`; `build-ffmpeg-NDI.sh` checked for `nvidia-smi` as a *package* (it's a binary) → now `command -v nvidia-smi`.
- **`Installer-Scripts/Gentoo/install-gentoo.sh` — rewritten.** Three fatal defects: (1) everything after the bare `chroot /mnt/gentoo /bin/bash` ran on the **host** after the user exited the interactive chroot (`chpasswd`, `grub-install`, kernel build against the live system); (2) `wget .../stage3-amd64-*.tar.xz` cannot work — wget does not glob URLs; (3) `${DRIVE_NAME}2` produces wrong partition names for NVMe/MMC (needs `p` separator, e.g. `nvme1n1p2`). Now: resolves the stage3 tarball from `latest-stage3-amd64-openrc.txt`, handles the `p` partition suffix, and executes stage 2 *inside* the chroot via a generated `/root/gentoo-stage2.sh` (tty stays attached so `nano`/`emerge --ask` remain interactive; credentials passed via env, script removed afterwards). Duplicate grub/syslog/net blocks from the old script were dropped in the restructure.
- **`GitHub-Projects/build-mainline.sh:125` — inverted install check**: `if sudo make install; then fail_fn` — a *successful* install triggered the failure handler and exit 1; a real failure was silently ignored. Fixed to `if ! sudo make install`.
- **`build-ffmpeg-NDI.sh` — WSL dispatch entirely dead + `VER` clobber**: `OS=WSL2` overwrote the distro name, then the inner `case "${OS}"` tested `WSL2` against `Ubuntu|Debian` → package installation never ran for any WSL user. Also `VER=msft` clobbered the release number that ~7 later version checks (`18.04`/`20.04`/`22.04`/`11`/`12`) rely on, corrupting them all under WSL, and made the `20.04|msft` case arm unreachable (SC2221/2222). Fixed by capturing `orig_os` before the overwrite, dispatching on it, and keeping `VER` intact (WSL packages now flow through `*_wsl_pkgs` vars, which are empty for non-WSL). Pattern mirrors the sibling `build-ffmpeg.sh`, which already solved this with `STATIC_VER`/`VARIABLE_OS`.
- **`build-ffmpeg.sh` `download_cuda()`** — the keyring-copy path `/var/cuda-repo-${distro}${version//./-}-local` was missing a hyphen for Ubuntu/WSL (only worked on Debian); fixed with a version-anchored glob `/var/cuda-repo-*"${version}"-local/`. The `if [ -n "$cuda_keyring_file" ]` block below it was permanently dead (both `cuda_keyring_file` and `cuda_repo_dir` never assigned) and redundant — NVIDIA's local-installer .deb registers the apt repo itself — so it was deleted.
- **jammy `04_compression.sh`** (the jammy `.bash_functions.d` tree is the *old* copy; Arch's was already modernized and served as the reference):
  - `zipr()`: `sh -c "unzip -o -d "${0%.*}" "$0""` — the nested quotes expanded `$0` in the *calling* shell once (yielding "bash"), never per-file; completely broken. Fixed to the Arch idiom `sh -c 'unzip -o -d "${1%.*}" "$1"' _ {}`.
  - `untar()`: inner cleanup loop ran `sudo chown -R`/`chmod -R 755` over **every directory in `$PWD`** (including unrelated ones like `.git`), once per archive. Now scoped to the just-extracted `$dirname` only.
- **`08_file_analysis.sh` `ffp()` (both Arch + jammy copies, kept byte-identical)** — root-privileged command injection: `find -exec bash -c "identify ... {}; echo {}"` substitutes the filename *into the script text*; a crafted `*.jpg` filename executes as root. Fixed to pass the filename as a positional arg (`bash -c '... "$1"' _ {}`) and write via `sudo tee` (the old user-shell redirect also failed in root-only directories — SC2024).
- **`08_file_analysis.sh` `jpgs()` (both copies)** — fixed `/tmp/img-sizes.txt` (predictable shared path, symlink race, cross-user collision) → per-run `mktemp -d`, matching the file's own convention.
- **`GitHub-Projects/build-all-git.sh`** — numbering scheme never worked: downloads save as `build-X.sh` but `mv build-X` (no extension) always failed, and the "corrective" second loop had a wrong file list with off-by-one counts. Replaced both loops with one `printf '%02d'` rename.
- **`Networking/set-static-or-dhcp-ip-address.sh:145`** — the "enter 0 to stop" check hardcoded `$nameserver1` for all four prompts, so entering `0` at prompts 2–4 stored a literal `0` as a nameserver in `/etc/network/interfaces`. Fixed with indirect expansion `${!ns_var}`, unsetting the right variable, and decrementing `cnt`.
- **`Misc/File-Editing/find-blank-lines.sh`** — running with just `-f FILE` (the documented default) crashed (`[[: -gt: unary operator expected`): `min`/`max` had no defaults despite help text promising `1`/`inf`; also `max_val` would compare the string "inf" numerically, `${YELLOW}` was used but never defined, and the `h|--help` case arm was unreachable under getopts. All fixed; functionally tested both invocations.
- **awk `'!seen[${0}]++'` — hard syntax error** (`${0}` is invalid awk; proved by execution): `Arch-Linux-Scripts/.bash_functions` `rmd()` (live helper, never worked) + 2 sites in `FFmpeg/backup-files/repo-full.sh`. Fixed to `$0`.

### Unassigned-variable bugs (SC2154 — each traced to intent via sibling scripts)

- `build-curl-with-openssl-quic.sh`: `user_agent` used in 7 `curl -A` calls, never set → added (matches `build-mainline.sh`/`build-dl-tools.sh` convention). `csuffix` passed to configure but no suffix feature exists in this script → removed the argument (an empty quoted arg confuses configure). Also renamed the mislabeled `ngtcp2-1.58.0` artifacts — the content is **nghttp2** 1.58.0 (built as "HTTP2") — and fixed `ngtcp2-1.1.0.tar.gz` naming for a `.tar.xz` download.
- `build-curl-git.sh`: `Missing_packages` vs `missing_packages` case typo → the apt-install branch for missing deps **never ran**; undefined `log` call → `printf`; dead `csuffix` removed; `--enable-ares="$workspace"` (never assigned; c-ares comes from apt here) → `--enable-ares`.
- `build-yasm.sh`: `user_agent` added (same class).
- `build-python2.sh`: `pc_type` never set → `--build/--host/--target=` got empty triplets; added `pc_type=$(gcc -dumpmachine)` (sibling convention).
- `build-libgcrypt.sh`: `install_dir` never set → `cp` targeted `/bin`; fixed to the actual prefix `/usr/local/programs/$archive_name2/bin` used by its configure.
- `build-libpng.sh`: `elif ${latest}` referenced a var with no `--latest` parser anywhere (dead feature the messages advertise) → added `latest=false` + arg parser; fixed embedded typo "oudebugtdated".
- `build-dl-tools.sh`: aria2's prefix used unassigned `install_dir` → `install_prefix` (script's actual convention); `g_ver="$g_ver//cares-/"` missing `${}` braces literally appended the text `//cares-/` to the version → fixed substitution, dropped the dead `g_tag`.
- GNU-Software `web_repo` (build-gnutls.sh, build-texinfo.sh, build-which.sh): never assigned in this directory (it's a GitHub-Projects convention); all GNU siblings hardcode the URL → hardcoded.
- `build-bash.sh`/`build-grep.sh`: `--with-libiconv-prefix="$libiconv_prefix"` unassigned → `/usr` (matches all 7 libiconv-consuming siblings).
- `SlyFox1186-Scripts/build-gparted.sh`: `web_repo` added at top.
- `build-mainline.sh`: dead `pem_file` cleanup block deleted (script has no cert feature).
- `build-ffmpeg-NDI.sh:1640`: `-DCMAKE_INSTALL_PREFIX="$install_prefix"` (unassigned → CMake fell back to /usr/local, escaping the sandboxed workspace) → `"$workspace"`, matching every surrounding library build and the sibling script; dead `ff_cmd`/`ffmpeg_url` block (vestige of pre-git tarball fetch) deleted.

### Dead/broken option wiring

- `GNU-Software/build-all-gnu.sh`: `pkks+=` typo → nano's build deps never installed on the selective path; dead `make|wget)` case arm shadowed by earlier arms (SC2221/2222) deleted.
- `build-texinfo.sh`: `-d`/`-s` flags parsed but never applied → wired `${dmalloc_opt:+...}`/`${shared_opt:+...}` into configure; unreachable `--help` case alternative and stray `shift` removed; getopts optstring trimmed `":hndpst"` → `":hds"` (n/p/t had no handlers); unguarded `cd build`.
- `build-which.sh`: `-s/--silent` was a no-op because configure hardcoded `--enable-silent-rules` → now opt-in via the flag, matching the help text.
- jammy `06_process_management.sh` `run_py()`: `eval "clear; redis-cli flushall && python3 app.py"` — a redis failure silently prevented the app from starting; restructured without eval, flush failure now returns explicitly (Arch-copy semantics). Also fixed SC2027 unquoting in `kill_process`.
- jammy `07_dev_tools.sh`: `venv()` synced to the Arch array-based implementation (`arg="$@"` scalar collapse corrupted spaced args; also fixes the `printf '\%s'` menu bug); `show_rpath()` synced (quoted expansion + resolve check before `sudo chrpath`).
- jammy `03_text_processing.sh`: `pipe=$@` → `pipe="$*"` (x2); `bat()`/`batn()` `eval "$(command -v batcat)" "$@"` re-split args (spaces broke) → `command batcat "$@"`.
- jammy `01_gui_apps.sh`: same eval class in `gedit`/`gted`/`geds`/`gteds` → `command X "$@"` / `sudo -Hu root X "$@"`.
- jammy `11_multimedia.sh` `imow()`: `LD_PRELOAD="libtcmalloc.so"` assigned as a dead shell var (child never saw it) → command-prefix form, as the Arch copy already does.

### Hardening / cleanup

- Unguarded `cd` before dangerous ops in scripts without `set -e`: `build-gperftools.sh` (`cd build`; also stopped `cd`-ing *into* the dir it then `sudo rm -fr`s — now removes from the parent), `build-grub-customizer.sh` (guards `git clone` + `cd` with its own `fail()`), `build-tilix.sh`, `Misc/System/secure-router-reboot.sh`.
- `Misc/System/create-ssh-keys.sh`: `grep -q "$(cat pubkey)"` treated key material as a regex (false "already present" matches possible) → `grep -qFx`.
- `Python3/image_quality_ranker.py`: wrote `folder_info.json` **and a bash script it then executes** under the shared `/tmp` (symlink race / TOCTOU, multi-user collision) → per-user `~/.cache/image_quality_ranker` (kept because the JSON persists between runs, so mkdtemp would break the cache semantics).
- `Python3/CUDA/update_cuda.py`: `/tmp/cuda_updater_log` → `~/.cache/cuda_updater` (version logs persist between runs).
- Python polish: `RUF010` redundant `str()` in f-strings (pihole_admin.py x2, quit_smoking.py); `RUF059` unused unpacked vars → `_` (squid_proxy_manager, torrent_tracker_checker, search_prices_on_google, pihole_admin — all verified incidental, no wrong-variable bugs behind them); `RUF012` → `ClassVar` annotations in source_git_repo_version.py.
- Dead code removed: never-wired firewall vars in `squid-proxy.sh` (fwld_* are firewalld service names but the script uses hardcoded iptables/ufw; wiring them would be invented behavior), dead `local missing_pkgs=()` in both `jammy-pkgs.sh` copies, duplicate `bzip2` in build-autoconf-archive.sh pkgs.

### Deliberately NOT changed (triage decisions — don't re-fix)

- **`[[ " ${list} " =~ " $item " ]]` (SC2076, 7 sites)**: intentional whitespace-delimited membership idiom; literal matching is the point.
- **SC2207/SC2206 array splits**: all split version numbers / package names / country codes — no whitespace risk in context.
- **SC2155 (`local x=$(...)`, ~50 sites)**: stylistic; none of the scripts rely on the masked exit codes.
- **SC2034 dead constants** (`script_ver`, colors, etc.): declared-but-unused metadata, harmless.
- **`domain_lookup.py` `noqa: ANN401`/`BLE001`**: RUF100 calls them unused only because those rule families aren't in the baseline select; both carry written justifications for a stricter pass — kept.
- **`check_port()` `local -A` multi-declare** (jammy 05_system_admin.sh): tested in bash — works via assoc `[0]` element; odd but functional.
- **`FFmpeg/backup-files/repo-full.sh`**: orphaned backup snippet (nothing sources it; `ver_file`/`workspace` undefined; `pre_check_ver` called with no args). Fixed only the mechanical awk `${0}` errors; initializing the missing vars would be guesswork. Candidate for deletion — ask the user.
- **`wmv-to-mp4.sh` SC2043** (`for cmd in ffpb`): extensible dependency-check idiom; the real file loop uses `find -print0` correctly.
- **S605/S104/S105/S110/S314/S318 (Python)**: all verified intentional in context (hardcoded `os.system('clear')`, deliberate LAN bind for a local LLM server, overridable argparse default, parse-of-own-generated-XML).
- **False positives annotated with `shellcheck disable` + reason**: SC2154 in set-static-or-dhcp-ip-address.sh (dynamic `read ... nameserver$cnt`), SC2024 in `jpgs()` (user-owned mktemp target is intentional).

### Verification state after this sweep
- `shellcheck -S error`: clean (all `Bash/**/*.sh`); `bash -n`: clean.
- `ruff check Python3 --select F,E9,B904,B007,S113,S324`: clean; `py_compile -W error::SyntaxWarning`: clean.
- `shellcheck -S warning` count: 304 → 222; every remaining warning is in the accepted classes above.
- `find-blank-lines.sh` functionally tested; `dpkg-query` fix proven against live dpkg.

## 2026-07-04 — First sweep (commit ee4f3bc4)
Corpus-wide bug sweep + flagship modernizations (Python3, Bash). Established the clean baseline: `ruff --select F,E9,B904,B007,S113,S324` + `py_compile`, `shellcheck -S error` + `bash -n`. B905 (`zip` strict=) deliberately skipped corpus-wide for Python 3.9 compat. E731 lambdas in find_large_files_and_folders.py intentional.
