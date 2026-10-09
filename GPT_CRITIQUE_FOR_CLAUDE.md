# Stage 2 independent review for Claude Code

## 1. Review verdict

**Requires changes.** Stage 1 was an investigation and proposal exercise, not an implementation: the handoff explicitly says no implementation was changed. This report reviews the existing code at `a7421387c784ee7a3689b656e1be486b3aecd582` and independently evaluates the proposed corrections. It does not sign off on an unimplemented candidate.

There are **23 confirmed finding groups: 9 high, 12 medium, and 2 low**, plus **3 meaningful improvement opportunities**. Severity here reflects consequence: high includes data loss or compromised transaction safety; medium includes broken workflows and substantive compatibility/reliability problems; low includes limited legacy-input or exit-status problems. A group can include multiple manifestations of one causal defect. This is not a count of every affected function.

Priority:

1. Prevent destructive cleanup of source data and unowned directories (F01–F03).
2. Fix pip preview mutation, rollback/RECORD validation, shared-file handling, and installation-location control (F04–F08).
3. Correct resolver policy before adopting P15a, and close the newly verified aria2 destination escape (F09, F12).
4. Repair the functional and compatibility defects below, then add meaningful regression coverage. The static baseline passes but did not detect these failures.

Stage 1's most consequential proposals need refinement. Archive success alone does not protect all original data. A checkout marker alone does not protect later user changes. Omitting broken requirers from the solver can remove their version protection. P15c is more than harmless option injection: an appropriately indented injected `dir=..` escaped the download destination in a local runtime probe. P15g's pre-commit crash recovery is not itself evidence of an incorrect transaction policy.

## 2. Repository state

| Item | Observed state |
| --- | --- |
| Claude's baseline | `a7421387c784ee7a3689b656e1be486b3aecd582` |
| Current HEAD | Same full commit |
| Branch | `main` |
| Tracking branch | `origin/main`; local tracking comparison `+0 -0` |
| Worktrees | One worktree, this repository |
| Initial index/tracked files | No staged or unstaged tracked changes |
| Initial untracked content | `CLAUDE_CRITIQUE_REQUEST.md` only |
| Stage 1 discrepancy | None in observed branch, commit, or working-tree state |
| Reviewed change range | `50791ff4..HEAD`; 12 diff paths, +7721/-225; the deleted old Compose filename plus its replacement account for the handoff's 11 current files |
| Stage 2 permitted change | This report, `GPT_CRITIQUE_FOR_CLAUDE.md`, only |

The tracking comparison uses the existing local remote-tracking ref; no fetch or claim of fresh remote equality is implied. No commit, push, deployment, publication, release, stash, reset, merge, or history alteration was performed. A pre-write fingerprint records content and file modes for all **695 existing working-tree files**, including ignored files and Claude's handoff, excluding `.git`. The final per-path comparison found **all 695 unchanged, no removed files, and only this report added**. GPT changed no repository content except this report and implemented no recommendation.

Scratch probes, fixtures, bytecode, logs, and an exported HEAD live outside the repository at `/tmp/codex-script-review.7UTgF2`. They are review evidence, not committed tests. Package managers and installers were never allowed to modify the real host or any real environment. Package-resolution commands used `--dry-run`; destructive helper probes operated only on disposable scratch data or intercepted the destructive command.

## 3. What was inspected

- Read the complete 608-line `CLAUDE_CRITIQUE_REQUEST.md`, complete `CHANGELOG.md`, `README.md`, `SECURITY.md`, and `.github/workflows/python-package.yml`; checked the applicable global/project/Python review instructions. No repository/nested `AGENTS.md` or `CLAUDE.md` was found by the instruction search.
- Examined Git status, HEAD, branch/tracking state, worktrees, recent history, change statistics, and the trim/downloader/README diffs. The prior sweeps' explicitly settled warning classes were not reopened.
- Traced `Python3/pip_updater.py`: environment discovery/base refusal → activation → lock/recovery → health baseline → live/cached scan and selection → two resolver passes → plan confirmation/re-resolution → artifact download → wheel and installed RECORD ownership → journal/apply → verification/rollback/recovery. Inspected curses selection, background refresh, hold caching, subprocess streaming, and user-visible outcome messages. Progress-only presentation code was examined selectively; this is not a claim to have verified every line of every corpus file.
- Traced `Python3/llama_cpp_installer.py`: host/CUDA detection, tool and compiler selection, package setup, checkout and removal, configure/build commands, staged installation, smoke tests, cleanup and exit handling.
- Read the current Compose, Miniconda, 7-Zip, and CUDA installers and `kill_discord.sh`; reviewed the complete trim-video path and the downloader rename. Inspected all 18 compress/delete function bodies in the seven files listed under F01, plus the Batch file specifically requested by the handoff.
- Checked installed **pip 26.1.2** source under `/home/jman/miniconda3/lib/python3.13/site-packages/pip/`: option parsing, installation schemes, wheel installation/RECORD rewriting, per-package uninstall/install ordering, and uninstall path enumeration. Used pure/parser calls and fake requirements, not actual package installation.
- Consulted current primary sources for [Python zip compatibility](https://docs.python.org/3/library/functions.html#zip), [pip configuration](https://pip.pypa.io/en/stable/topics/configuration/), [yanked-file policy](https://packaging.python.org/en/latest/specifications/file-yanking/), [Apple df source](https://github.com/apple-oss-distributions/file_cmds/blob/main/df/df.c), and upstream llama.cpp [top-level CMake](https://github.com/ggml-org/llama.cpp/blob/master/CMakeLists.txt), [GGML options](https://github.com/ggml-org/llama.cpp/blob/master/ggml/CMakeLists.txt), [CUDA CMake](https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cuda/CMakeLists.txt), and [UI asset provisioning](https://github.com/ggml-org/llama.cpp/blob/master/scripts/ui-assets.cmake). Checked live NVIDIA/Miniconda endpoints, README DNS names, and GitHub workflow state. These network observations are from 2026-09-26 and can change.

### Disposition of every Stage 1 proposal

| Proposal | Independent disposition |
| --- | --- |
| P1 | **Needs change:** failure deletion confirmed at all 18 sites; also fix archive-inside-source and legacy hidden-file loss. See F01. Consolidation is optional. |
| P2 | **Confirmed:** mocked namespace execution reproduced apt full-upgrade and exit 0 without Compose. F11. |
| P3 | **Confirmed:** actual host compiler discovery reproduced empty vs GCC 14/13 results. F10. |
| P4 | **Needs change:** unowned deletion confirmed; a marker is insufficient permission to delete a retained tree later. Extend the same fix to 7-Zip. F02. |
| P5 | **Needs change:** empty library-path entry confirmed; joining whole strings does not remove embedded empty elements in an existing value. F17. |
| P6 | **Confirmed:** official runtime API change supports the 3.9 incompatibility; no 3.9 execution was performed. F20. |
| P7 | **Confirmed:** negative subprocess return code is passed unchanged to `sys.exit`. F23. |
| P8 | **Needs change:** non-conda deletion confirmed; canonicalize paths and reject dangerous aliases/symlink cases before checking `/` and home. Move all top-level initialization behind the proposed source guard. F03. |
| P9 | **Confirmed:** GNU-only df option is incompatible with Apple's implementation. Check the installation filesystem as well. F18. |
| P10 | **Needs change:** dispatch/order/full-upgrade defects confirmed; missing *both* curl and wget triggers the prerequisite failure, not either one alone. Preserve platform prerequisites and avoid implicit whole-system upgrades. F18. |
| P11 | **Needs change:** insecure allocation and leftover directory confirmed. `mktemp` is the primary fix; merely removing the installer still leaves the workspace. Preserve explicitly kept artifacts deliberately. F19. |
| P12 | **Confirmed for all 18 README hostnames tested:** all unresolved, with authoritative NXDOMAIN for `7z`. This does not establish the state of every possible wildcard name or registrant identity. F21. |
| P13 | **Confirmed limitation; improvement I01:** disabled workflow and pytest exit 5 reproduced. Compilation on 3.9 alone does not catch `zip(strict=...)`. |
| P14 | **Confirmed documentation gaps; improvement I02:** don't replace one unsupported “tested” promise with another inferred from directory names. |
| P15a | **Needs change:** conflicting roots/downgrade reproduced. Skipping a requirer wholesale is incomplete; ordinary displayed new dependencies are not inherently a defect. F09 and section 6. |
| P15b | **Confirmed:** mocked main with real journal recovery called rollback in dry-run. F04. Cache writes are separable from package mutation. |
| P15c | **Needs change:** decoded-newline acceptance confirmed; encoded indentation plus `dir=..` produces an actual destination escape. F12. |
| P15d | **Confirmed:** all three legacy version examples produce invalid requirements. Prefer a target-side packaging parser to copying a large version regex. F22. |
| P15e | **Confirmed behavior, policy improvement I03:** refusing all yanked rollback wheels can strand an update, but refusal is permitted by the packaging specification. |
| P15f | **Needs change:** header destination is wrong; the distribution argument is the requirement's spelling. Query the target pip scheme instead of assuming normalization, and cover generated bytecode too. F13. |
| P15g | **Partly refuted:** rollback before a durable complete journal is conservative recovery, not proof of corruption. The incorrect SIGHUP exit code is confirmed in F23. See section 6. |

## 4. Confirmed issues

### F01 — High — Compress/delete helpers can destroy the only copy, including after successful compression

**Locations:** Arch `Bash/Arch-Linux-Scripts/.bash_functions.d/04_compression.sh:119`, `:133`, `:146`, and corresponding ZIP logic at `:227`, `:241`, `:254`; also the legacy functions identified below.

**Evidence and impact:** An independently extracted-function probe covered all **18** sites. With `7z` returning 2 and deletion answer `1`, every site deleted the scratch source and returned 0. Two additional probes used the real `/usr/local/bin/7z`: (a) from `src/sub`, compressing the absolute `src` path reported `Everything is Ok`, then removed both `src` and the newly created `src/sub/src.7z`; (b) the legacy Arch `7z_1` successfully archived a visible file but omitted `src/.secret`, then deleted it with the source. P1's proposed exit check and archive test do not catch either successful-compression case.

The 18 sites are in these seven exact files:

| File | Functions / source anchors |
| --- | --- |
| `Bash/Arch-Linux-Scripts/.bash_functions` | `7z_1/5/9` at 703/738/773; deletion prompts 724/759/794 |
| `Bash/Arch-Linux-Scripts/.bash_functions.d/04_compression.sh` | `7z_compress` / `zip_compress`; archive/deletion locations above |
| `Bash/Ubuntu-Scripts/jammy/user-scripts/.bash_functions.d/04_compression.sh` | `7z_compress`; deletion prompt 115 |
| `Bash/Debian-Scripts/bookworm/user-scripts/.bash_functions` | `7z_1/5/9`; deletion prompts 758/793/828 |
| `Bash/Debian-Scripts/bookworm/user-scripts/plain-scripts/.bash_functions` | `7z_1/5/9`; deletion prompts 843/870/897 |
| `Bash/Raspbian-OS/user-scripts/.bash_functions` | `7z_1/5/9`; deletion prompts 752/787/822 |
| `Bash/Ubuntu-Scripts/jammy-bak/user-scripts/.bash_functions` | `7z_1/5/9`; deletion prompts 758/793/828 |

**Correction:** Guard compression failure and archive existence/integrity, include hidden entries without leaking shell options, and prove the resolved output archive is outside the resolved source tree before allowing source deletion. Preserve safe handling of spaces, leading dashes, absolute paths and trailing slashes; the plain Bookworm variant's `./"$source_dir"/*` must not misinterpret an absolute source. Refusing existing output is a simple safe default for the new Arch helpers. A small shared Arch helper is justified only if it simplifies these checks without changing existing shortcut contracts.

**Stage 3 validation:** Run failure/missing-7z/disk-failure mocks at all 18 sites; real 7z/ZIP happy paths with visible and hidden files; an output within source; a pre-existing archive; spaced, absolute, dash-prefixed and trailing-slash paths. Verify source survival on every failed/incomplete case and that the sole retained archive survives a successful deletion.

### F02 — High — Two installers delete pre-existing working directories without ownership or discard authorization

**Locations:** `Python3/llama_cpp_installer.py:886` `remove_existing_repo`, callers `sync_repo_to_latest:918` and `sync_repo_to_pr:926`, cleanup `:1371`; `Bash/Installer-Scripts/SlyFox1186-Scripts/7zip_installer.sh:6`, `:297–298`, `:331–333`.

**Evidence and impact:** Calling the actual llama removal function on a scratch unmarked tree containing `valuable.txt` deleted it. It runs before the network lookup/clone and regardless of `--keep`. Independently, the 7-Zip installer sets `working=$PWD/7zip-install-script` and executes `sudo rm -fr` on any existing directory there. Its `--no-cleanup` does not protect that directory on a later run. User-added source, models or other files can be lost. Stage 1's statement that 7-Zip was otherwise sound missed the same class of problem.

**Correction:** Prefer a unique per-run work directory and clean only the directory created by this invocation; print the retained path for `--keep`/`--no-cleanup`. Alternatively fail safely on any existing path and let the user move it. A marker documents creation, not continuing ownership of every subsequently added file, so do not treat a historical marker as unconditional discard permission. Resolve network prerequisites before destroying any explicitly disposable prior state. Apply safe ownership checks to end-of-run cleanup too.

**Stage 3 validation:** Unmarked tree, marked-but-user-modified retained tree, file, symlink, failed network lookup/clone, second invocation after keep, and simultaneous invocations. All pre-existing user content must remain intact unless its deletion was specifically authorized.

### F03 — High — Miniconda overwrite accepts arbitrary existing directories

**Locations:** `Bash/Misc/Conda/install_conda.sh:227–285`, especially `get_install_directory:264–272`; caller `main:455`.

**Evidence and impact:** Extracting these functions unchanged, selecting a scratch non-conda directory, and intercepting `rm` produced `MOCK rm -fr <directory>` and returned that path. `~` normalizes to the real home directory in the same path. The prompt describes an overwrite, but the log incorrectly asserts an existing Miniconda installation and no conda identity check exists.

**Correction:** Refuse dangerous resolved destinations including root and home; reject symlink/alias ambiguities and nonempty non-conda directories. Require positive identification before replacing a conda tree and clearly state that its environments are removed. An empty directory can be handled without recursive removal. Preserve the existing overwrite-vs-update semantics unless deliberately changed. A source guard must encompass the current top-level `set`, temporary-directory creation and initialization, not merely the final `main` call, so sourcing for tests is actually side-effect free.

**Stage 3 validation:** Test home/root plus aliases (`..`, redundant slashes, symlink parents), non-conda directory, empty directory, real-looking conda directory, refusal, EOF, and failed removal. Never run these cases against real home; use intercepted deletion or isolated fixtures.

### F04 — High — `--dry-run` performs package recovery

**Locations:** `Python3/pip_updater.py:4659–4668` in `main`, `recover_incomplete_transactions:3943–3998`, `rollback_transaction:3893–3940`.

**Evidence and impact:** With a scratch `applying` journal, mocked environment discovery/health/scan, and only `rollback_transaction` replaced by a call recorder, actual `main()` printed the preview-only promise and invoked rollback. In production that path uninstalls introduced packages and force-reinstalls old ones. The dry-run check occurs much later than recovery.

**Correction:** Give preview recovery a genuinely non-mutating inspection path. For an applicable incomplete mutation journal, stop with an actionable recovery-required message before presenting a plan. Do not claim a meaningful plan for a half-applied environment. Preview should not delete transaction workspaces; retain the environment lock for coordination. Cache/lock writes need not violate the CLI's explicit “without changing packages” contract, but do not describe them as a completely write-free operation. Skipping unrelated stale-lock cleanup in preview is sensible, not a substitute for fixing package recovery.

**Stage 3 validation:** Drive `main` with dry-run for every journal state and assert zero install/uninstall/rollback calls and unchanged journals. Check normal recovery still works. Include malformed journals and journals for other prefixes.

### F05 — High — Wheel RECORD contents bypass the ownership checks and can poison rollback

**Locations:** `Python3/pip_updater.py:3030–3136` `inspect_wheel`, `validate_new_wheels:3663`, `_install_local_wheels:4154`, rollback `:3893`; installed pip `operations/install/wheel.py:233–263,708–725` and `req/req_uninstall.py:58–88`.

**Evidence and impact:** A scratch wheel with ordinary safe ZIP member names but an extra RECORD row `../../../bin/python,,` passed `inspect_wheel` and `validate_new_wheels` even with `bin/python` in the conda-owned path set. The protected path is absent from the checker's targets. Pip's actual `get_csv_rows_for_installed` preserved the unmatched row, and its actual `uninstallation_paths` mapped that row to the fixture prefix's `bin/python`. A later rollback/reinstall can therefore remove a file the preflight explicitly meant to protect. No protected file was actually removed in this probe. This establishes a malformed-artifact validation gap, not a claim that arbitrary installed Python code can be made safe by wheel inspection.

**Correction:** Validate wheel RECORD rows and their installation/uninstallation mapping as well as ZIP members. Reject unexpected/orphan rows, unsafe destinations and claims on other ownership domains; account for pip-generated legitimate rows. Apply equivalent checks to rollback wheels. Ensure validation occurs before any mutation, not after an unsafe RECORD has become uninstall authority.

**Stage 3 validation:** Crafted RECORD rows targeting the interpreter, another package, a path outside the prefix, an absent ZIP member, malformed/duplicate entries, and normal valid wheels. In a disposable Stage 3 environment force rollback after installing the adversarial fixture and prove protected sentinel files survive; corrected code should reject it before installation.

### F06 — High — Shared-file validation ignores uninstall/install order and cannot restore the previous shared bytes

**Locations:** `Python3/pip_updater.py:3724–3772` in `validate_new_wheels`, `apply_transaction:4188`, `rollback_transaction:3893`; pip `req/__init__.py:72–108`.

**Evidence and impact:** Two old distributions A/B claim `shared.py`; new A contains it and new B omits it. The actual validator accepts that plan because the path appears in the union of new targets. Pip replaces packages one at a time: uninstall A, install A, uninstall B, install B can remove A's newly written file. Executing the actual pip orchestration with fake requirements operating only on a scratch sentinel returned two successful installations with the shared file absent. Version checks and dependency checks need not detect that loss. Separately, reinstalling old A/B wheels does not necessarily restore the pre-transaction winner's bytes when shared files differ: the old ordering/content is not journaled.

**Correction:** Make shared-path safety account for the actual deletion/write sequence, and verify expected files after application. A conservative first correction can reject plans whose shared paths cannot be preserved/restored deterministically. If retaining support, preserve the pre-transaction shared bytes/metadata and restore them during rollback, and define safe installation ordering or a final verified restoration pass. Treat different content at shared paths explicitly instead of assuming every namespace overlap is equivalent.

**Stage 3 validation:** Both A/B orders, writer-before-remover, differing shared bytes, identical namespace files, one claimant retained, both replaced, interruption between packages, and rollback. Verify file bytes/existence, not just versions or `pip check`.

### F07 — High — Rollback artifacts are not verified to the same standard as update artifacts

**Locations:** `Python3/pip_updater.py:3479–3500` pip download fallback; `prepare_transaction:4092–4113`; `rollback_transaction:3912–3917`.

**Evidence and impact:** New wheels are checked against plan SHA-256 and ownership. Old wheels are checked only for distribution-set and version agreement after download. A preparation probe supplied an expected old SHA-256 of 64 zeroes and an actual valid old wheel with a different hash; preparation still returned `prepared`. Network/download boundaries were mocked, while the preparation and old-wheel inspection logic were real. The pip fallback resolves `name==version` afresh and does not enforce the old resolver's hash. The journal also stores no old artifact hashes, and recovery installs the wheelhouse without re-verifying it. Old-wheel target collisions are not validated either.

**Correction:** Match every rollback wheel to its resolved name/version/hash and validate its install/delete effects before marking prepared. Persist artifact identity/hashes in the journal, flush required recovery artifacts before recording mutation readiness, and re-verify them before recovery uses them. Do not assert successful checksum validation for artifacts that only passed a version check. Preserve a clear recovery-required failure if a rollback artifact is missing or changed.

**Stage 3 validation:** Different wheel with the same version, tampered old wheel, old wheel colliding with conda/unrelated files, pip fallback selection differing from the report, missing wheel on restart, and modified new wheel between prepare/apply. Prove rejection precedes mutation whenever possible.

### F08 — High — Inherited pip installation-location settings bypass the prefix model

**Locations:** `Python3/pip_updater.py:1199–1201` `pip_command`, `activate_environment:2136–2212`, `environment_layout:2969`, `_install_local_wheels:4154–4185`; pip `commands/install.py:399–418,554–571`.

**Evidence and impact:** `-I` is Python isolation, not isolation from pip's configuration. In actual `python -B -I` child processes, pip option parsing retained injected `PIP_PREFIX`, `PIP_TARGET`, and `PIP_ROOT` paths outside the target. The updater adopts the activated environment wholesale and neither rejects effective location overrides nor makes its ownership model use them. In particular `PIP_PREFIX`/`PIP_ROOT` can redirect writes while the updater inspects the original prefix. A subsequent failed version check does not undo files written elsewhere, and rollback inherits the same misconfiguration. Some `PIP_TARGET` scenarios may fail earlier due to ignore-installed resolution; the finding does not assume every override reaches mutation.

**Correction:** Establish and enforce the effective installation scheme for all mutation commands. Reject unsupported destination/user-site overrides from both environment and config, or construct a controlled pip configuration that guarantees the selected prefix. Retain supported index/auth/certificate settings deliberately; blindly adding `--isolated` can break private indexes without addressing every config source. [Pip documents its configuration sources and precedence](https://pip.pypa.io/en/stable/topics/configuration/).

**Stage 3 validation:** Environment and config-file forms of `prefix`, `root`, `target`, and `user`, including activation hooks that set them. Use outside-prefix sentinels and a private-index fixture. Verify install and rollback write only inside the intended prefix and that refusal occurs before deletion.

### F09 — High — Resolver policy cannot handle existing conflicts safely as proposed

**Locations:** `Python3/pip_updater.py:2592–2616` `retained_environment_pins`, `resolve_update_plan:2803–2813,2858–2927`, postflight `:4210–4221`, and result display `:4427,4577`.

**Evidence and impact:** Independent local-wheel pip dry-runs reproduced (1) unsatisfiable A==1 requiring B<2 with retained B==2, blocking unrelated C==2, and (2) a bare B resolving to B==1.9 against A==1 although the scenario's installed B is 2.0. The resolver output is consumed without a semantic downgrade guard. The updater describes it as an update and `--yes` accepts it. Omitting A as P15a proposes makes the unrelated solve succeed, but removes A's own exact-version root and all of its other caps. If A is reached as a dependency, an unselected A can move; if A has another currently satisfied requirement, that constraint can disappear until postflight.

**Correction:** Separate constraints protecting retained installed versions from the root requirements used to expose applicable dependencies. Exempting an already-broken dependency edge must not silently exempt the entire holder from version protection. Preserve its other healthy requirements, evaluate markers in the target interpreter, and validate the prospective environment before mutation when feasible. At minimum enforce explicitly that installed unselected packages cannot change. Use a real PEP 440 comparator for current/proposed versions and refuse downgrade by default, or require a separate explicit downgrade acknowledgment that `--yes` alone cannot supply. Do not embed an ad hoc version comparator.

Raw `pip check` line sets include package versions: a pre-existing A→B conflict whose installed B changes generates a new string even if the same requirement remains broken. If supporting updates around existing conflicts, define and test the semantic regression rule; the current exact-string check is conservative but does not implement “same broken edge is allowed” semantics.

**Stage 3 validation:** Unrelated update with baseline conflict; missing baseline dependency; broken holder with a second healthy cap; unselected broken holder reached transitively; requested downgrade; healthy-environment cap; markers/extras using a target Python different from the updater. Check both confirmed plan and the re-resolved plan, and verify no unselected installed package changes.

### F10 — Medium — Ccache-first PATH hides usable GCC pairs

**Locations:** `Python3/llama_cpp_installer.py:632–680`, `_is_ccache_shim:494`.

**Evidence and impact:** Actual host probe: `/usr/lib/ccache:/usr/bin` yielded `[]`, while `/usr/bin` yielded GCC 14 and 13. The first `which` result is rejected without searching later executable candidates, blocking an otherwise viable build.

**Correction:** Search all PATH candidates for each compiler name until a non-shim executable file is found, then validate the matched GCC/G++ pair. Retain `_make_toolchain`'s checks. No evidence justifies rejecting every other wrapper, such as distcc, merely by analogy.

**Stage 3 validation:** Both tested PATHs, shim-only, missing counterpart, mismatched major, executable directory, symlinked real compiler, and unversioned pair. Finally run the existing nvcc compatibility probe in the intended build environment.

### F11 — Medium — Missing curl branch exits without Compose and upgrades unrelated system packages

**Location:** `Bash/Misc/docker_compose_multi_arch_installer.sh:297–311`.

**Evidence and impact:** In an unprivileged root user namespace with apt/sleep/fetch stubs and no curl in PATH, actual `main` ran `apt update`, `apt -y full-upgrade`, `apt install -y curl`, then exited 0 without calling fetch. This both violates the installer's purpose and broadens host changes. Non-apt systems cannot use that branch.

**Correction:** P2's guarded dependency-only apt-get path followed by the normal fetch flow is appropriate. If no supported installer is available, fail clearly. Never use a full-system upgrade to obtain curl. Confirm curl is available before continuing.

**Stage 3 validation:** Curl present/missing; apt-get success/failure/absent; fetch called exactly once on success; no full-upgrade invocation; meaningful nonzero failures.

### F12 — Medium — Decoded wheel filename injects aria2 options and escapes the destination

**Locations:** `Python3/pip_updater.py:1115–1128` and `download_with_aria2:3413–3427`.

**Evidence and impact:** `wheel_filename_from_url` accepted a URL basename ending in `pkg-1.0-py3-none-any.whl%0A%20%20dir=..%0A%20%20out=escape.whl`. The decoded text becomes indented per-download aria2 options. A loopback HTTP fixture and real aria2, using the production input-file format plus checksum and no-overwrite flags, exited 0 and wrote `escape.whl` outside the requested download directory. This corrects Stage 1's assertion that rejecting `/` alone prevents escape. The subsequent wheelhouse check may fail, but the external write already happened. Exploit reachability depends on a hostile/malformed index report reaching this helper; no public index was attacked or shown to serve such a report.

**Correction:** Validate the decoded basename against a strict wheel filename grammar/allowlist that excludes all whitespace, controls, separators and option syntax; validate again at the downloader input boundary. P15c's restrictive allowlist is a reasonable starting point when checked against supported wheel filenames. Preserve hash verification, but do not rely on it to constrain the destination.

**Stage 3 validation:** Encoded CR/LF, spaces/tabs, `dir=..`, repeated `out=`, encoded slash/backslash/NUL, normal local-version filenames, and actual aria2 input parsing. Assert no request/file creation occurs for rejected names and no files appear outside the transaction directory.

### F13 — Medium — The wheel target model differs from pip for headers and generated bytecode

**Locations:** `Python3/pip_updater.py:2969–2990`, `inspect_wheel:3097–3130`, shared-path guard `:3755–3772`; pip `locations/_sysconfig.py:176–197`, `req/req_install.py:779–795`, `operations/install/wheel.py:624–643`.

**Evidence and impact:** Actual pip requirement `My_Pkg==1.0` has `req.name == 'My_Pkg'`; `make_install_req_from_link` preserves it, and `get_scheme(candidate.req.name).headers` returned `/home/jman/miniconda3/include/python3.13/My_Pkg`. The updater constructs install specifications from the manifest's plan names (`:4110,4193`); pip uses that requirement name for its scheme. The updater mapped fixture `.data/headers/demo.h` to `include/python3.13/demo.h` instead of pip's per-distribution directory. Canonicalizing the name unconditionally is not equivalent to using the requirement passed to pip. Virtualenv-specific header layout further argues against hardcoding the scheme.

The updater also models generated scripts but not generated `.pyc` files. With old A/B RECORDs sharing `shared.py` and `__pycache__/shared.cpython-313.pyc`, updating A with a wheel containing `shared.py` was rejected as deleting the shared `.pyc`, even though pip's default install force-compiles that source. Ownership checks can therefore miss actual generated destinations and falsely refuse legitimate shared-namespace updates.

**Correction:** Derive relevant scheme and bytecode destinations from the target interpreter/pip behavior, including the precise requirement name. Model generated and uninstall-added targets consistently. Handle compilation failure and existing filesystem symlinks explicitly; do not assume a generated file exists solely because compilation was intended.

**Stage 3 validation:** Header wheels with mixed case/underscore names, target-version bytecode tags, shared Python namespaces, generated scripts, conda ownership at actual destinations, and comparison to a disposable real pip install/uninstall RECORD.

### F14 — Medium — Cached holds prevent a valid joint dependency update

**Locations:** `Python3/pip_updater.py:1679–1698`, `filter_outdated_packages:1658`, `main:4720` selection, and retained pins `:2813`.

**Evidence and impact:** `_still_valid_hold` excludes B solely because its latest version and installed capper A version are unchanged. Suppose installed A1 requires B<2 and B1.9 is installed. A prior B-only attempt records that hold. Later A2 requires B>=2 and both A2/B2 are available. `--all` filters B out before selecting A; the resolver pins retained B1.9 and cannot resolve A2. The hold predicate returned “held back by a” in the probe, and the resulting A2/B1.9 joint requirements failed in the local-wheel solver. `--refresh` still calls the same hold filtering, so it does not fix this.

**Correction:** Treat holds as selection-context-dependent. Reconsider held packages when their cappers are selected for update, or display holds without removing them from joint resolution. Preserve explicit package selection as a way to retry a hold. Consider installed-version and target-interpreter marker context when retaining hold records.

**Stage 3 validation:** Record B's hold, publish/select A2, then verify `--all --refresh` can jointly update A/B without manual cache deletion. Check B-only remains held while A1 stays installed, and changes in interpreter/installed B invalidate stale records.

### F15 — Medium — Subprocess streaming kills live children at EOF and can block outside its timeout

**Location:** `Python3/pip_updater.py:107–210`, especially stdin write `:152–166`, loop `:170–193`, cleanup `:195–208`.

**Evidence and impact:** A child closing stdout/stderr and then sleeping 0.8 seconds returned **-9 in about 0.01 seconds** from actual `stream_command(timeout=2)`: EOF ends the read loop and the `finally` block kills a still-live process. A second child that did not read stdin caused a 1 MB synchronous write to ignore the function's 0.1-second timeout; an outer 0.6-second timeout was needed. EOF is not process completion, and stdin backpressure can stall aria2 input before deadline checks start.

**Correction:** After EOF, wait/poll for process completion while honoring the same deadline and ticks; kill only on interruption/error/deadline. Write stdin incrementally through nonblocking I/O integrated with the read loop, or another bounded mechanism that cannot deadlock against stdout. Handle partial writes. Preserve deterministic reaping and error propagation.

**Stage 3 validation:** Silent child, early EOF followed by success/failure, large stdin with slow/no reader, simultaneous large output, timeout, and termination during installation. Verify successful children keep their true exit code and no child remains active after an aborted transaction.

### F16 — Medium — Llama smoke-test failures still reach a successful build verdict

**Locations:** `Python3/llama_cpp_installer.py:323–334` `capture_all`, `main:1353–1409`.

**Evidence and impact:** `capture_all` forces `check=False` and returns only text. A probe supplying a child return code 127 with `loader failure` returned that text normally. The version/device callers never see the status; the version field can become the loader error, the source tree is cleaned, and `result_banner(True, ...)` is reached. Existence/executable-bit checks do not establish that the binaries run.

**Correction:** Preserve and enforce return codes for smoke tests. A successful device query reporting no CUDA devices may remain a warning, but command failure must not become BUILD SUCCEEDED. Prefer verifying built binaries before replacing working installed binaries; decide recovery behavior if a post-install check fails and retain useful diagnostics/source.

**Stage 3 validation:** `--version` exits 127/1 with stderr, empty successful version response, failed `--list-devices`, valid no-GPU response, and valid GPU response. Confirm failure is nonzero and no success banner is emitted; test preservation of previous installed binaries where applicable.

### F17 — Medium — Empty library-path components add the working directory to loader search

**Location:** `Python3/llama_cpp_installer.py:1093–1102`.

**Evidence and impact:** With an unset old value, the expression produces `/usr/local/cuda/lib64::/usr/lib/x86_64-linux-gnu`. Actual `LD_DEBUG=libs ... /bin/true` showed relative hwcap search directories and the empty component. Child build/smoke processes can load libraries from their working directory.

**Correction:** Join nonempty path elements, splitting inherited values first if the invariant is “no empty components.” The proposed `_join_paths(*parts)` only filters empty whole arguments and leaves `a::b` untouched. Remove the unrelated library directory from PATH and avoid unnecessary duplication of default loader directories.

**Stage 3 validation:** Unset, empty, populated, leading/trailing-colon and embedded-double-colon values; verify emitted child environment and loader search omit implicit current-directory entries.

### F18 — Medium — Miniconda platform checks and dependency setup contradict advertised support

**Locations:** `Bash/Misc/Conda/install_conda.sh:70–104`, `:182–190`, `:209–223`, `main:445–455`; `7zip_installer.sh:97–128`.

**Evidence and impact:** `check_prerequisites` runs before installation of missing tools, and fails when neither downloader exists or tar is missing. Dependency installation then runs unconditionally and rejects unlisted IDs even when tools exist. Both installers use `pacman -Syu` to obtain utilities. Apple's [df implementation](https://github.com/apple-oss-distributions/file_cmds/blob/main/df/df.c) has no GNU `--output=avail`; strict-mode Miniconda execution fails there on macOS. The space check also uses home before the installation path is known, so it checks the wrong filesystem for a custom mount.

**Correction:** Detect/install only missing prerequisites, use supported ID then tokenized ID_LIKE fallback, verify tools afterward, and avoid a surprise full-system upgrade. If distro policy requires an upgrade, report that prerequisite separately. Use portable numeric disk-space output and inspect the selected installation location or its existing parent. Ensure failures from a package manager are propagated, particularly in the non-strict 7-Zip script. Review the full macOS path as well: `sort -uV` in `list_python_versions:367` needs platform verification rather than assuming the df change completes portability.

**Stage 3 validation:** Missing both/one downloader, tar missing, all tools present, Mint/Pop-like ID_LIKE fixtures, unsupported distro, package manager failure, Arch command capture, separate install filesystem, and macOS execution. No real dependency install was done in Stage 2.

### F19 — Medium — Miniconda temporary workspace is not securely allocated

**Locations:** `Bash/Misc/Conda/install_conda.sh:8–12`, downloaded script execution `:108–128`, cleanup `:302–312`.

**Evidence and impact:** Timestamp plus Bash RANDOM followed by `mkdir -p` is neither exclusive nor an ownership check; a precreated directory/symlink is accepted. Downloaded scripts are then executed, including a `sudo bash` 7-Zip installer. There is no workspace cleanup trap, and deleting the Miniconda installer alone leaves the directory/log and other artifacts behind. This is a local shared-temp attack surface, not merely a cosmetic naming problem.

**Correction:** Allocate an exclusive private `mktemp -d` directory, initialize it inside execution, and define failure/signal/success cleanup. Preserve a requested kept installer and useful log at a deliberate private location, with explicit paths and without silently overwriting user files. Keeping the existing prompt is a reasonable default; removing it is not needed for the security fix. Quote all artifact paths.

**Stage 3 validation:** Confirm mode/ownership, concurrent runs, preplanted-path refusal, spaces in TMPDIR, failed download, interruption, successful cleanup, and keep choice. Use fixtures; do not execute downloaded installers merely to test cleanup.

### F20 — Medium — Llama checkout description breaks the documented Python 3.9 floor

**Location:** `Python3/llama_cpp_installer.py:913` `dict(zip(keys, fields, strict=False))`.

**Evidence and impact:** The repository's CHANGELOG explicitly retains Python 3.9 compatibility; CI names 3.9. Python's [official documentation](https://docs.python.org/3/library/functions.html#zip) records `strict` as added in 3.10. The call therefore fails at runtime on 3.9, after earlier installer work. Parsing/compilation under a grammar floor does not test builtin keyword support.

**Correction:** Remove the redundant keyword, as proposed. Do not change the support floor incidentally.

**Stage 3 validation:** Execute `describe_head` using Python 3.9 against a disposable repository or a controlled `capture` return, and exercise normal/error results. No 3.9 interpreter was executed during Stage 2.

### F21 — Medium — All README install domains tested are unresolved

**Locations:** `README.md` install commands; `Bash/Installer-Scripts/SlyFox1186-Scripts/build-menu.sh` and other tracked `optimizethis.net` callers.

**Evidence and impact:** Extracted all **18 distinct README hostnames** and queried each with `getent hosts`: every one failed to resolve. `dig +time=5 +tries=1 +norec 7z.optimizethis.net A @dns1.p08.nsone.net` returned authoritative NXDOMAIN. These documented entry points cannot currently fetch their scripts from this environment. A domain registration record would not establish that the maintainer still controls its account, so that part of Stage 1's security narrative is not treated as verified.

**Correction:** Preserve the owner choice between restoring DNS and replacing URLs. A repository-only alternative should use a verified hostname-to-script map, handle removed targets explicitly, and update menu/caller paths consistently. Do not mechanically map dead OS versions to invented scripts. Stage 2 neither changed DNS nor published replacement commands.

**Stage 3 validation:** Resolve each published hostname or fetch every replacement URL with failure-sensitive HTTP handling, inspect the returned script, and exercise menu selection with download/execute stubs. No installer execution is necessary just to validate the map.

### F22 — Low — Retained version syntax admits invalid exact requirements

**Locations:** `Python3/pip_updater.py:46`, `retained_environment_pins:2610–2615`.

**Evidence and impact:** `1.0-custom`, `0.23ubuntu1`, and `2012j` all matched SAFE_VERSION but failed actual pip-vendored `Requirement('pkg==...')` parsing. `1.0.post1+local` passed both. One legacy nonconforming installed distribution can block all attempted solves containing its invalid pin.

**Correction:** Validate exact pins with the target's supported packaging parser. If a distribution cannot be represented, explain the skipped constraint or refuse safely under the documented policy; do not silently invent a valid version. Coordinate with F09 so dropping a malformed pin does not authorize replacing an unselected package. Prefer reuse of a parser already provided by target pip over copying a large regex.

**Stage 3 validation:** All four examples plus epochs, pre/post/dev/local releases, case normalization, invalid names and target-pip compatibility. This is a legacy metadata case, not evidence that current pip normally installs invalid versions.

### F23 — Low — Signal-derived exit codes are incorrect

**Locations:** `Python3/llama_cpp_installer.py:1458`; `Python3/pip_updater.py:58–68,4869–4871`.

**Evidence and impact:** Llama passes a negative child status directly to `sys.exit`, so -9 becomes 247 rather than 137. Pip stores only a signal message and maps every `UpdateInterrupted` to 143, including SIGHUP, conventionally 129. Shell supervisors receive the wrong cause. These conclusions follow directly from the exit paths; no real updater was terminated during a package mutation.

**Correction:** Normalize negative child return codes as `128 - returncode`. Carry the actual signal number in `UpdateInterrupted` and exit `128 + signum`; retain explicit SIGINT 130 behavior and rollback semantics.

**Stage 3 validation:** Child SIGKILL, SIGTERM, SIGHUP and SIGINT in disposable command/transaction fixtures; verify both cleanup/recovery outcome and outer shell status.

## 5. Meaningful improvement opportunities

### I01 — Restore useful automated validation rather than a permanently failing test placeholder

**Current limitation/evidence:** `gh workflow list -a -R slyfox1186/script-repo` reported `Python package` as `disabled_manually`. Pytest on an exported HEAD returned **5**, no tests collected. The configured flake8 second pass is explicitly `--exit-zero`; merely scanning Bash Python files is not proof that step fails. Static checks alone also pass the runtime defects in this report.

**Benefit/approach:** Retain a lightweight workflow enforcing the documented Ruff/ShellCheck/syntax baseline and add focused regressions for destructive helpers and transaction invariants. Run actual relevant code under the declared Python floor. Once real tests exist, missing collection should fail rather than globally accepting pytest exit 5. Prefer repair over deletion because it prevents these specific regressions; enabling a remote workflow remains a separate external action for Stage 3 under its authorization.

**Tradeoff/validation:** Keep tests isolated from real root, network installs, home and conda environments. Run workflow-equivalent commands and the actual matrix, then inspect a real GitHub run if enabling it. Do not claim py_compile catches runtime API availability.

### I02 — Make OS/security documentation truthful

**Current limitation/evidence:** README still claims tested support including removed bionic/focal/bullseye trees; its featured-script subsections repeat older OS lists. SECURITY.md contains instructions to the author and a placeholder version support table.

**Benefit/approach:** Distinguish scripts present/targeted from platforms actually tested. Update the overview and relevant featured entries consistently. Ask the owner only for the actual support/security contact policy, not to authorize obvious corrections already in scope. Do not fabricate a support SLA or claim all remaining OS directories are validated.

**Tradeoff/validation:** Conservative wording makes fewer promises but is supportable. Check every named OS against maintained scripts and recorded runtime evidence; verify links and the owner's chosen reporting route.

### I03 — Consider allowing an exact yanked artifact solely for rollback

**Current limitation/evidence:** `resolve_exact_download_artifacts:3345` rejects `is_yanked`, even for an already-installed exact version that must be backed up before upgrading. This can prevent leaving a yanked version when that is the only recoverable wheel. It is a restrictive policy, not a violation of the [yanking specification](https://packaging.python.org/en/latest/specifications/file-yanking/), which permits refusal.

**Benefit/approach:** Consider accepting a hash-verified, ownership-safe, exact installed version solely in the rollback wheelhouse with a clear warning. Continue to reject yanked update targets. Coordinate with F07; accepting more rollback artifacts without fixing their verification would worsen safety.

**Tradeoff/validation:** Rollback may restore the already-existing problematic version. Use a local simple-index fixture with a yanked old release and a normal new release; verify explicit rollback-only acceptance, warnings, target rejection and restoration behavior. No live yanked package was installed during this review.

## 6. Rejected or disproven concerns

- **Stage 1 implemented fixes:** Refuted by the handoff itself and clean tracked diff. This is a proposal review over existing committed code, not candidate validation.
- **Batch grep match proves active original-file deletion:** Refuted. `Batch/convert-webp-file-to-multi-sized-icon.bat:64–65` contains a commented-out deletion command. It is not another active P1 site. Other Batch behaviors were not audited corpus-wide.
- **P15c cannot escape because slashes are rejected:** Refuted by the indented `dir=..` runtime probe. An initial probe without indentation printed aria2 unsupported-URI errors and did not escape; proper input-file option indentation was necessary. This distinction is preserved rather than claiming the initial attempt succeeded.
- **Any newly introduced dependency is an unauthorized updater defect:** Not established. The implementation explicitly groups new dependencies in the preview, confirms the complete plan and validates ownership. The real P15a concerns are impossible baseline roots and unguarded downgrades, plus preserving unselected installed packages when changing policy. Conda duplicate-file collisions have a dedicated preflight path; no claim is made that every missing dependency bypasses it.
- **P15g must block signals to prevent rollback after successful verification:** Not established. Verification before the durable `complete` write is still an uncommitted transaction. Recovery restoring the old state is a conservative choice. Signal masking does not address SIGKILL/power loss or failed journal writes. Define the durable commit point and test it; do not add masking solely because a pre-commit crash causes rollback. SIGHUP's exit status remains F23.
- **Cache writes necessarily violate the dry-run package promise:** Refuted as a blanket claim. The CLI explicitly promises no package changes. The dangerous package recovery is F04; private cache/coordination writes can be allowed if described accurately.
- **MP4 edit-list start necessarily exposes the prior keyframe:** Disproved for the tested MPEG-4 fixture. A 10-second, 25 fps, GOP-50 MP4 trimmed at 3 seconds produced 7.000000 seconds and a first decoded-frame MD5 equal to the source decoded at 3 seconds (`a3e444e43e40353dffd4a7c7341f9afb`). This does not certify all codecs/players; the script documents edit-list support and retained preroll.
- **CUDA preview mutates host packages/profile:** Not observed. The inspected dry-run branches skip mutation and the live `--dry-run --no-profile` run printed commands only, selecting CUDA toolkit 13.4. It wrote its documented temporary downloads/log. No real toolkit installation or GPU runtime was verified.
- **Base/name ambiguity, user-site interpreter imports, simple ZIP traversal/symlinks, and same-prefix updater concurrency lack guards:** Source has explicit base-prefix rejection, exact-prefix/ambiguous-name handling, Python `-I`, wheel member path/symlink checks and per-prefix flock. Preserve them. Python `-I` is insufficient for pip location config (F08), and ZIP member safety is insufficient for RECORD authority (F05). Locks coordinate cooperating updater instances, not external pip/conda processes.
- **Llama CUDA/UI options are obviously obsolete:** Current primary-source inspection found the used FA-quants, CUDA graphs/NCCL, native/OpenMP/ccache and UI controls. Both UI controls matter because npm build and HF download are separately gated. This establishes option existence, not a successful build against a future moving master or the beta PR.
- **The rename is inconsistent:** The downloader/README changes point to the current 7-Zip filename. No tracked stale old 7-Zip/Compose filename reference was found by the final search.
- **Additional Miniconda ARM/x86 URL breakage based on naming alone:** Not confirmed. HEAD requests to both URLs examined returned HTTP 200. Artifact compatibility/current contents were not established, so no unsupported “404” finding is made.
- **Style-warning cleanup, unused `batch_mode`, personal paths, distcc speculation, channel-policy changes:** No new corrective recommendation. These either have no demonstrated practical defect here, were settled by the prior sweep, or are owner policy outside the required causal fixes.

## 7. Validation performed

All Python review commands used `/home/jman/miniconda3/bin/python`, as expressly specified by the handoff for this standalone-script corpus. `conda env list` was inspected; interpreter was Python **3.13.14**, pip **26.1.2**, pytest **9.1.1**. Imports used `-B` or redirected bytecode. No packages were installed.

### State and static validation commands

| Command | Result |
| --- | --- |
| `pwd`; `git status --short`; `git rev-parse HEAD`; `git branch --show-current`; `git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'`; `git status --branch --porcelain=v2`; `git worktree list --porcelain` | State in section 2; repeated state checks remained consistent. |
| `git log -12 --oneline`; `git diff --stat 50791ff4 HEAD`; `git diff 50791ff4 HEAD -- Bash/Installer-Scripts/FFmpeg/trim_video.py Python3/download_master.py README.md` | Verified history/scope and actual focused diffs. |
| `git diff --check`; `git diff --cached --check` | Passed, no output. |
| Final `git diff --exit-code`; `git diff --cached --exit-code`; branch/HEAD/tracking recheck | Tracked/index diffs empty; same HEAD, main, origin/main, +0/-0. Final status contains only the pre-existing handoff and new report as untracked files. |
| Inline `.../python -B -` comparing each path's `lstat().st_mode` and SHA-256 against `/tmp/codex-script-review.7UTgF2/baseline.json`; checking report headings/findings/proposals/source-path existence and trailing whitespace | All 695 pre-existing files unchanged; only report added. All 9 required sections, F01–F23, I01–I03 and every Stage 1 proposal disposition present; referenced repository paths checked. Report read back completely. |
| `git diff --no-index --check /dev/null GPT_CRITIQUE_FOR_CLAUDE.md` | No whitespace diagnostics; exit 1 reflects the new-file difference from `/dev/null`, not a whitespace error. |
| `/home/jman/miniconda3/bin/conda env list` and `.../python -B -c 'import sys, pip, pytest; ...'` | Environment inventory and versions above. |
| `/home/jman/miniconda3/bin/ruff check Python3 --no-cache --select F,E9,B904,B007,S113,S324` | All checks passed. |
| `git ls-files -z '*.sh' \| xargs -0 -n 1 bash -n` | Passed. |
| `git ls-files -z '*.sh' \| xargs -0 shellcheck -S error -f gcc` | Passed. |
| `/home/jman/miniconda3/bin/python -B -W error::SyntaxWarning -` running `py_compile.compile` and `ast.parse(..., feature_version=(3,9))` on each `git ls-files -z '*.py'` path | All **64** passed. Each compiled `cfile` was `/tmp/codex-script-review.7UTgF2/compile-<index>.pyc`; no in-repo bytecode. |
| `git archive HEAD` via subprocess, extracted using `tarfile.extractall(..., filter='data')` under the scratch root; then `/home/jman/miniconda3/bin/python -B -m pytest -q -p no:cacheprovider` in that export | No tests ran; **exit 5**, not a test-suite pass. |

The read-only source inspections used `rg`, `git grep`, `git ls-files`, bounded `sed`/`nl`, and `cat` on the sources listed in section 3. Searching a guessed `.github/workflows/codeql.yml` failed because it is absent; `rg --files --hidden .github` showed only `python-package.yml`. Remote CodeQL's active state therefore does not imply a checked-in CodeQL workflow. No file was created to fill that gap.

### Isolated behavioral commands and outcomes

The following harnesses are retained in the scratch root for convenient reruns. They import unchanged repository functions; the fixtures/call interception and expected behavior are described in the corresponding findings, so the report does not require access to this conversation. They are one-run fixture scripts, not idempotent project tests.

| Command / precise probe | Result |
| --- | --- |
| `.../python -B /tmp/codex-script-review.7UTgF2/shell_probes.py` | 18/18 failed-compression cases deleted source; real archive-inside-source and hidden-file-loss cases reproduced. Compose under `/usr/bin/unshare -r /bin/bash -c <source + stubs + main>` exited 0 without fetch. No real sudo/package operation. |
| `.../python -B /tmp/codex-script-review.7UTgF2/probes.py` | Reproduced GCC discovery, unowned llama removal, decoded-newline acceptance, invalid version pins, pip parser location override, early-EOF child kill, dry-run recovery call, header/RECORD model gaps, accepted wrong rollback hash, accepted unsafe shared-file plan and cached-hold predicate. Mocks were used for environment/network/mutation boundaries as described above. |
| `.../python -B /tmp/codex-script-review.7UTgF2/resolver_probes.py` | Constructed small wheel ZIP fixtures without building/installing packages. For each case ran `.../python -B -I -m pip --isolated install --dry-run --ignore-installed --no-cache-dir --disable-pip-version-check --no-index --find-links <scratch>/resolver-wheels --only-binary=:all: --report <scratch>/<case>.json <specs>`. Conflicting retained roots exit 1; bare B selects 1.9; omitting broken A allows unrelated C; stale-hold A2/B1.9 fails. These are resolver probes against a modeled installed baseline, not real environment updates. |
| `.../python -B /tmp/codex-script-review.7UTgF2/aria_probe.py` | Loopback-only HTTP and real aria2 with `--input-file=- --dir=<scratch destination> --auto-file-renaming=false --allow-overwrite=false --check-integrity=true`. First non-indented payload did not escape; second attempt initially hit existing-fixture `FileExistsError`; final fresh, indented payload exited 0 and created the parent-directory sentinel wheel. All outputs remained inside the overall scratch root. |
| `.../python -B /tmp/codex-script-review.7UTgF2/final_probes.py` | RECORD ownership check passed the unsafe row; pip path enumerator resolved protected interpreter path; actual pip loop with fake requirements lost shared sentinel; shared bytecode false refusal; failed llama smoke result returned normally; real `python -B -I` pip parsers retained injected PREFIX/TARGET/ROOT settings. |
| Inline `.../python -B -` calling pip `make_install_req_from_link(Link('file:///tmp/My_Pkg-1.0-py3-none-any.whl'), install_req_from_line('My_Pkg==1.0'))`, then `get_scheme(candidate.req.name).headers` | Preserved `My_Pkg==1.0`; header scheme ended in `include/python3.13/My_Pkg`. Parser/scheme call only; no wheel read or installation. |
| Inline `.../python -B -` running outer `subprocess.run(..., timeout=.6)` around `stream_command(child_sleep_2s, input_data=b'x'*1000000, timeout=.1, tick=.02)` | Outer timeout expired; internal deadline did not bound stdin write. Short-lived scratch child exited afterward. |
| Inline Bash-function extraction of Miniconda lines 227–286 with `log(){ :; }`, intercepted `rm`, and scratch existing-directory input plus `y` | Function accepted non-conda removal, exit 0. Real home/environment untouched. |
| `LD_DEBUG=libs LD_LIBRARY_PATH='/usr/local/cuda/lib64::/usr/lib/x86_64-linux-gnu' /bin/true 2>&1 \| rg -m 1 'LD_LIBRARY_PATH'` | Loader output included relative hwcap/empty search component. |
| `bash <absolute CUDA installer path> --dry-run --no-profile`, from scratch cwd | Exit 0; selected `cuda-toolkit-13-4`; printed dpkg/apt commands; no system mutation. Log `/tmp/cuda-install.8KjWyY.log` retained. |
| `/home/jman/miniconda3/bin/ffmpeg -nostdin -v error -f lavfi -i testsrc2=size=128x96:rate=25:duration=10 -c:v mpeg4 -g 50 -y source.mp4`, scratch cwd | Created disposable video. |
| `.../python -B <absolute trim_video.py> -i source.mp4 --start 3 -v` | Exit 0; output in scratch, log in `trim.log`. |
| `.../ffprobe -v error -show_entries format=duration -of default=nw=1 source_trimmed.mp4`; `.../ffmpeg -v error -ss 3 -i source.mp4 -frames:v 1 -f md5 -`; same MD5 command on trimmed file without `-ss` | Duration 7.000000; matching first decoded-frame hashes. |

### External/read-only verification

- `dig +time=5 +tries=1 +norec 7z.optimizethis.net A @dns1.p08.nsone.net`: authoritative NXDOMAIN. `getent hosts <hostname>` for the 18 names extracted from README: all unresolved.
- `gh workflow list -a -R slyfox1186/script-repo`: Python package disabled; CodeQL, Dependency Graph and Dependabot Updates active. No GitHub settings changed.
- HTTP HEAD using Python `urllib.request.Request(..., method='HEAD')`, timeout 10 seconds, for `https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-armv7l.sh` and `.../Miniconda3-latest-Linux-x86.sh`: both 200. No artifact execution or package installation.
- Primary documentation/source page reads and targeted searches are linked in sections 3–6. FreeBSD's df manual was also read, then Apple's own source used to support the macOS finding. Upstream CMake inspection supports only the specifically checked options. No browser/UI rendering, production deployment or GPU build was claimed.

### Validation deliberately not performed

- No real updater/install/uninstall/conda transaction, system dependency installation, migration, package installation, GPU compile/install, or signal injection into a real environment. Stage 3 should run corrected transaction tests in disposable environments and preserve outside-prefix sentinels.
- No formatter/fix-mode linter, dependency install/update, generated repository artifacts or cache-writing test invocation. Pytest ran on an external export; bytecode/fixtures stayed external.
- No Python 3.9 runtime, macOS, Windows Batch, physical hardware inference, fresh Miniconda ToS flow, or full application compatibility test. Stage 3 needs those environments to close the relevant uncertainty.
- No re-enabling workflow, fixing DNS, committing, pushing or publishing. Those remain Stage 3 actions under the actual authorization and release instructions, not completed Stage 2 work.

## 8. Remaining risks and uncertainty

1. **Scope:** This is a thorough review of the affected utility paths and linked risks, not certification of all 695 files or every unrelated Windows/Rust/Perl script. The Rust subtree has its own Cargo project; the handoff's “no package/build/tests” should be understood as the reviewed Python/Bash convention, not a literal description of every subtree.
2. **Real transaction restoration:** No environment was actually upgraded/rolled back. F05–F08 have concrete validator/parser/order evidence, but real pip/conda integration after correction must verify bytes, modes, RECORDs, generated files, and restart behavior. Dependency metadata alone cannot prove import/runtime health. Locally modified pip-owned files may differ from a freshly fetched same-version wheel; Stage 3 must define whether such changes are refused or backed up before promising exact restoration.
3. **Durability and external concurrency:** Atomic fsynced manifests do not by themselves prove recovery-wheel data survives power loss. Check artifact and directory flushing before the durable applying transition. A per-prefix updater lock does not stop external pip/conda changes; test concurrent change detection and document the cooperation boundary. No power-loss or external-manager race test was performed.
4. **Journal schema/corruption:** Recovery only recognizes specific statuses; missing/unknown status can fall through without recovery or refusal. No normal writer in this version was shown to emit such a journal, so this is a corruption/forward-compatibility concern rather than a demonstrated normal-run defect. Add schema/version/status validation before relying on a journal to authorize mutation, and test malformed recovery data in Stage 3.
5. **Platform/runtime floor:** Python 3.9 incompatibility is backed by the documented builtin API, not an executed 3.9 test. Mac df incompatibility is source-backed, not a macOS run. Miniconda's other macOS utilities, fresh bootstrap/ToS behavior, and old architecture artifacts still require appropriate runtime validation.
6. **Network state:** DNS and master-branch CMake can change. Refresh them when correcting/shipping. No assertion is made about registrant identity or every external hostname in the corpus. Stage 1's reported 7-Zip/Compose release versions and all asset statuses were not comprehensively rechecked by Stage 2.
7. **Archive completeness:** The probes used small static fixtures. Files changing during compression can defeat a simplistic “7z test succeeded therefore safe to delete” interpretation. Stage 3 should either prevent destructive cleanup when the source changes or document/enforce a quiescent-input requirement; select a practical method rather than treating archive CRC as proof of source coverage.
8. **Small-terminal curses behavior:** Selection logic was read, but terminal resize/minimum-height behavior was not exercised. Neither selector checks height before fixed-row writes. A PTY test would resolve the risk of `curses.error`; this has not been promoted to a confirmed runtime defect.

## 9. Claude implementation checklist

- [ ] Independently verify this report against the recorded commit/current worktree before implementing. Preserve any new user/concurrent changes; do not assume this clean baseline persists.
- [ ] Fix F01–F03 first: protect all archive inputs and retained output, and stop installers deleting arbitrary/pre-existing trees. Preserve existing CLI/shortcut contracts where safe.
- [ ] Make preview recovery non-mutating (F04) and test through `main`, not just a helper.
- [ ] Correct RECORD and rollback artifact validation, actual target schemes, shared-file ordering/restoration, and pip location control together (F05–F08, F13). Establish these invariants before expanding rollback artifact policy.
- [ ] Redesign P15a narrowly with constraints/healthy-edge preservation and explicit downgrade handling; fix context-dependent holds (F09, F14). Do not implement “skip all broken holders” as the entire fix.
- [ ] Reject decoded filename injection at both relevant boundaries (F12), using the indented aria2 reproduction.
- [ ] Repair GCC discovery, Compose continuation, subprocess lifetime/backpressure, and llama smoke-test failure propagation (F10–F11, F15–F16).
- [ ] Complete the LD path, Miniconda dependency/platform/temp safety, Python floor, invalid-pin and exit-status fixes (F17–F20, F22–F23).
- [ ] Prepare a verified DNS/URL correction map for the owner decision (F21); keep external DNS actions separate from code review authorization.
- [ ] Evaluate I01–I03 on their merits: useful CI/regressions, truthful support/security docs, and rollback-only yanked-file policy. No cosmetic corpus rewrite is recommended.
- [ ] Run the documented Ruff/ShellCheck/Bash/Python baseline, focused regressions for each accepted correction, actual Python-floor tests, disposable pip/conda install-failure-recovery tests, and relevant platform/installer checks. A clean static baseline is not sufficient evidence for transaction or data-loss fixes.
- [ ] Review all resulting diffs and the worktree, document remaining environment gaps, and only then carry out the appropriate Stage 3 Git/release workflow under its applicable instructions. **Stage 2 performed no shipping.**

The report is the complete Stage 2 handoff. No recommendation above has been applied to repository implementation.
