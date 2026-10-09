# Bash functions

`~/.bash_functions` is the loader for this directory. `.bashrc` sources it once, after `.bash_aliases`.

- The loader disables alias expansion while the function files are parsed, exports the shared ANSI colors, sources every first-level `*.sh` file in filename order, then restores the caller's alias-expansion setting.
- Each numbered file groups functions by type: `01_gui_apps.sh`, `02_filesystem.sh`, `03_text_processing.sh`, `04_compression.sh`, `05_package_management.sh`, `06_system_admin.sh`, `07_process_management.sh`, `08_dev_tools.sh`, `09_file_analysis.sh`, `10_security.sh`, `11_networking.sh`, `12_multimedia.sh`, `13_ai_tools.sh`, `14_utilities.sh`. Nested helpers stay inside their parent function.
- Functions resolve each other when called, not when loaded, so a function may call one defined in a later file.
- `startup/pyenv.sh` and `startup/pip.sh` are sourced explicitly at their original positions in `.bashrc`, so they retain their initialization timing and are not loaded by the first-level glob.

To reload the functions in the current terminal:

```bash
source /home/jman/.bash_functions
```

The provider menu is `switch_provider`; its definition is in `13_ai_tools.sh`. `add_claude_mcp` reads `CONTEXT7_API_KEY` from the environment, which `~/.claude/secrets.env` sets.

The function files keep private permissions because the originals were private.

The cleanup decisions and verification are recorded in [CLEANUP.md](CLEANUP.md).
Open a new terminal to pick up the complete cleanup, including the `pyenv` startup
wrapper. Reloading only `~/.bash_functions` updates the category functions and
clears the retired `aie`, `switch_to_local`/`stl`, and standalone `display_help`.

Useful changes:

- `7z_1`, `7z_5`, and `7z_9` share one implementation. Run them outside the source
  directory; existing archives are preserved, hidden files are included, and
  deletion is offered only after compression and archive verification succeed.
  Source metadata is checked during compression and again before deletion;
  detected changes keep the source. Archives are staged privately before publication.
- `nh`, `nhe`, `nhs`, and `nhse` now forward all command arguments. The sudo
  variants authenticate before detaching.
- `big_files` retains its folder and file sections; `big_file` supplies the shared
  file listing. `big_img [MiB]` defaults to 10 MiB. `jpgsize [MiB]` prompts when
  omitted. Both JPG commands print absolute paths, including uppercase extensions,
  without opening an editor or leaving temporary files.
- `pipu` calls `pipua`: all outdated non-editable packages are upgraded in one
  resolver invocation, followed by `pip check`. Neither bypasses externally
  managed environment protection.
- `drp [CONTAINER...]` prompts for containers when omitted, then prompts for a
  restart policy. `padl` reads `FILENAME URL` from the Linux or Windows clipboard;
  the filename cannot contain spaces.
- `ffs [OPTIONS...]` clones or fast-forwards a clean checkout in
  `~/.local/share/ffmpeg-build-script`, then runs its current Python builder through
  `~/miniconda3/envs/install-ffmpeg/bin/python`. It refuses unrelated directories
  or local changes. `ffr PATH [OPTIONS...]` and `ffrv` support the current Python
  builder and legacy shell scripts, running as your user. Without options they
  request a build with GPL/non-free components and latest dependencies.
