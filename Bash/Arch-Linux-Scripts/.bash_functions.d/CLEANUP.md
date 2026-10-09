# Bash function cleanup — 2026-10-09

All issues from the function review were handled locally. Familiar names remain
where they provide useful shortcuts. No system package upgrades, container
updates, clipboard writes, or FFmpeg builds were performed to validate them.

| Functions | Full path | Decision and reason |
|---|---|---|
| `7z_1`, `7z_5`, `7z_9` | `/home/jman/.bash_functions.d/04_compression.sh` | Keep the presets and share `_7z_archive`. Include hidden files, normalize trailing slashes, stage archives privately, verify before publication, check source metadata during compression and before deletion, and reject protected targets, symbolic links, existing archives, or an output inside the source. |
| `nh`, `nhe`, `nhs`, `nhse` | `/home/jman/.bash_functions.d/07_process_management.sh` | Keep the listing and quiet variants. Share launch logic, preserve every argument, reject an empty command, and authenticate sudo before detaching. |
| `bat`, `batn` | `/home/jman/.bash_functions.d/03_text_processing.sh` | Keep both; `batn` now calls `bat -n`, removing duplicate lookup and installation logic. |
| `big_files`, `big_file` | `/home/jman/.bash_functions.d/09_file_analysis.sh` | Keep their distinct outputs. Reuse `big_file` for the file section, validate positive counts, use NUL-separated records for sorting, and propagate pipeline failures. Sizes remain disk usage, including sparse-file behavior. |
| `big_img`, `jpgsize` | `/home/jman/.bash_functions.d/09_file_analysis.sh` | Share `_jpg_files_over_size`; keep default and prompted thresholds. Both print absolute paths and match JPG extensions without regard to case. Remove editor launch and temporary-file leakage. |
| `fix` | `/home/jman/.bash_functions.d/05_package_management.sh` | Attempt DPKG configuration, run one APT dependency repair even if initial configuration fails, and retry configuration after successful repair when needed. Propagate repair or retry failures. Preserve package-manager locking. |
| `st` | `/home/jman/.bash_functions.d/14_utilities.sh` | Keep the time shortcut, remove the unnecessary `cut` and `grep` stages. |
| standalone `display_help` | `/home/jman/.bash_functions.d/14_utilities.sh` | Remove redundant, uncalled Reddit help. Keep `rdvc --help` and the scoped helper used by `port_manager`. Clear the obsolete definition during reload. |
| `sai` | `/home/jman/.bash_functions.d/13_ai_tools.sh` | Repair copying when xclip is present. Support `clip.exe` as the Windows alternative and propagate failures. Preserve the user's existing text. |
| `aie` | `/home/jman/.bash_functions.d/13_ai_tools.sh` | Remove the launcher for a nonexistent instructions script; inventing its missing behavior would be unjustified. Clear it during reload. |
| `switch_to_local`, `stl` | `/home/jman/.bash_functions.d/13_ai_tools.sh` | Remove the inactive backup-file toggle rather than inventing provider configuration or swapping settings unsafely. Keep `switch_provider`; it does not gain a local-provider option. |
| `pyenv` wrapper | `/home/jman/.bash_functions.d/startup/pyenv.sh`; `/home/jman/.bashrc` | Keep the Conda warning and explicitly source the wrapper after pyenv path initialization. |
| `nvme_temp` | `/home/jman/.bash_functions.d/06_system_admin.sh` | Query each existing NVMe block device using its own path. Report no devices or failed queries instead of printing empty values as success. |
| `drp` | `/home/jman/.bash_functions.d/06_system_admin.sh` | Accept one or more container names/IDs, or list containers and prompt. Apply the selected policy only to those targets and propagate Docker failures. |
| `pipu`, `pipua` | `/home/jman/.bash_functions.d/08_dev_tools.sh` | Keep `pipu` as a compatibility wrapper. Upgrade all outdated non-editable packages together without frozen version pins, then run `pip check`. Remove the automatic `--break-system-packages` retry. JSON parsing uses the absolute Miniconda interpreter. |
| `ffs`, `ffr`, `ffrv`, FFmpeg option in `script_repo` | `/home/jman/.bash_functions.d/12_multimedia.sh`; `/home/jman/.bash_functions.d/08_dev_tools.sh` | The old download URL now returns HTTP 404. Fetch the full current repository, preserve local changes, invoke `build-ffmpeg.py` with the existing `install-ffmpeg` interpreter, and retain support for legacy shell files. Share the current launcher with the script menu and accept explicit options. Run the builder as the user rather than through sudo. |
| `mywget` | `/home/jman/.bash_functions.d/11_networking.sh` | Use `--output-document` so the requested filename belongs to the downloaded content, rather than the Wget log. |
| `padl` | `/home/jman/.bash_functions.d/11_networking.sh` | Keep the clipboard workflow. Prefer Linux xclip, support Windows PowerShell, normalize CRLF text, validate two fields, and propagate clipboard failures. |

The current FFmpeg entry point, interpreter policy, and command options were
checked against the live [upstream repository](https://github.com/slyfox1186/ffmpeg-build-script)
and its help output. No installer was executed.

## Backup and verification

Private backup and regression artifacts:
`/home/jman/.local/state/bash-functions-cleanup/20261009T073822Z/`.
The `original/` directory preserves the loader, modules, startup files, shell
startup configuration, and aliases with their original permissions.

- Regression script: `regression.sh`; results: `regression-after.log`.
- 47 isolated scenarios passed. Coverage includes dependency repair after failed
  initial DPKG configuration, repair/retry failures, and real 7-Zip round trips with
  hidden files, spaces, all presets, archive verification, and deletion of a
  scratch source only after successful verification. Maintenance actions are
  mocked, including APT, pip upgrades, Docker, NVMe, clipboard writes, and builds.
- Interactive and login Bash startup passed in pseudo-terminals, including
  `pyenv`, `pip`, preserved commands, and absence of retired definitions.
- Bash syntax checks cover the loader, all 16 module/startup scripts, `.bashrc`,
  and the regression script. ShellCheck reports no errors or warnings in these
  module files; external-source informational notes remain.
- Running the earlier 39-scenario suite against the private original copy
  detected 33 failures; the repaired copy passed all 39. The final suite adds
  symlink protection and current FFmpeg repository/runner checks.

During the first original-code replay, an insufficiently isolated protected-path
test started reading host files into a private scratch archive. The process was
stopped, scratch artifacts were removed, and protected targets were mocked before
repeating the replay. The backed-up source hashes remained intact. The corrected
test never archives or deletes host targets.

Remaining limits: live desktop clipboard access, real package repair/upgrades,
Docker changes, privileged NVMe queries, and a complete FFmpeg build were not
performed. Other functions outside the reviewed issue list were preserved.
