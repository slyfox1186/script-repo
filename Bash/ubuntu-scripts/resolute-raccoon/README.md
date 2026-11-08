# Resolute Raccoon Bash Configuration

Bash configuration for Ubuntu 26.04 LTS (Resolute Raccoon), copied from a working 26.04 machine.

Source: [slyfox1186/script-repo](https://github.com/slyfox1186/script-repo/tree/main/Bash/ubuntu-scripts/resolute-raccoon)

## Files

Everything is in `user-scripts/` and belongs in your home directory:

| File | Purpose |
| --- | --- |
| `.bashrc` | Interactive shell setup, prompt, history, PATH, conda and nvm |
| `.bash_aliases` | Aliases |
| `.bash_functions` | Loads every `*.sh` file in `.bash_functions.d/` |
| `.bash_functions.d/` | Functions grouped by topic, `01_gui_apps.sh` to `14_utilities.sh` |
| `.bash_functions.d/startup/` | Files `.bashrc` sources at startup (`pip.sh`, `pyenv.sh`, `reminders.sh`) |
| `.bash_functions.d/claudecmd_progress.py` | Live progress display used by `claudecmd` |
| `.bash_profile`, `.profile`, `.bash_logout` | Login shell files |
| `.inputrc`, `.nanorc` | Readline and nano settings |

`.bash_functions.d/README.md` describes the function files, including `codexcmd` and `claudecmd`.

## Installation

This is a personal snapshot, so review the paths in each file before installing. Run these
commands from this folder. The first block backs up every file the copy replaces and stops if
anything fails:

```bash
(
    set -e
    backup=~/dotfiles-backup-$(date +%Y%m%d-%H%M%S)
    mkdir -m 700 "$backup"
    for name in .bashrc .bash_aliases .bash_functions .bash_functions.d .bash_profile .profile \
                .bash_logout .inputrc .nanorc; do
        if [[ -e ~/$name ]]; then
            cp -a ~/"$name" "$backup"/
        fi
    done
    echo "Backup saved in $backup"
)
```

Continue only if it printed `Backup saved in ...`. The parentheses run it in a subshell, so a
failure stops the backup without closing your terminal.

Then install. `.bash_functions.d` is replaced as a whole, because the loader sources every
`*.sh` file in it and old modules left behind would override the new functions:

```bash
rm -rf ~/.bash_functions.d
cp -a user-scripts/. ~/
exec bash -l
```

`exec bash -l` starts a fresh shell, so functions from the old files do not stay defined.

## Requirements

- Miniconda at `~/miniconda3`: `.bashrc` runs its conda hook, and `claudecmd` runs
  `claudecmd_progress.py` with `~/miniconda3/bin/python` (standard library only).
- Rust's `~/.cargo/env`, which `.bashrc`, `.bash_profile` and `.profile` source.
- The `claude` CLI for `claudecmd` and the `codex` CLI for `codexcmd`. `switch_provider` also
  needs `~/.codex/switch_provider_codex.py` and `~/.claude/switch_provider_claude.py`, which are
  not in this repository.
- Some aliases point at the author's own projects and machines (for example the JDESKTOP transfer
  script); edit or remove them for your system.
- `.bashrc` sources `~/.claude/secrets.env` when it exists. That file holds API keys and is not
  part of this repository.
