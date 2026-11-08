# Source .bashrc directly for login shells (SSH).
# Do NOT source .profile — it prepends ~/.local/bin to PATH after conda
# has already activated, which shadows conda's binaries with system-python
# versions that lack the installed packages.
# .bashrc already sets up PATH, cargo, conda, pyenv, nvm, and everything else.

[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"

source "$HOME/.cargo/env"
