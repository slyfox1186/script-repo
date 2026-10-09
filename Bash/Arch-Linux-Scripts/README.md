# Personal Bash dotfiles

This directory stores the current `/home/jman` Ubuntu/APT dotfile snapshot. Its
historical `Arch-Linux-Scripts` name does not make these dotfiles an Arch Linux
configuration. The other Arch utilities in this directory are separate scripts.

- `.bash_functions` loads the 14 category files in `.bash_functions.d` with alias
  expansion disabled during parsing.
- `.bashrc` loads `.bash_aliases`, the function loader, and the two startup wrappers.
- `.bash_functions.d/README.md` documents commands and loading.
- `.bash_functions.d/CLEANUP.md` records the cleanup decisions and validation.

`arch-scripts.sh` requires APT, downloads and syntax-checks the complete snapshot
before installation, backs up existing dotfiles privately, and replaces the
function directory so old modules cannot override the new definitions. It also
backs up and removes a legacy modular alias directory, and attempts restoration
from the backup if installation fails.

These are personal settings with paths for Miniconda, CUDA, Cargo, Node, and local
projects. Review those paths before installing on another machine. Credentials
are read from local environment files; those secret files are not included.
