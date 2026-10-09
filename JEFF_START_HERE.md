# Script repository status

Updated: 2026-10-09

This release includes all local changes requested by Jeff: seven reorganized Bash alias modules, removal of the former sudo and Claude alias modules, deletion of the two critique documents, and the contributor guide at `/home/jman/tmp/script-repo/AGENTS.md`.

No action is needed from Jeff. The release targets GitHub `slyfox1186/script-repo`, branch `main`.

All seven alias modules passed `bash -n` and `shellcheck -S error`. Loading them together in a clean Bash process succeeded. No full test suite or production build was run.

The current `.bashrc` loads the single `.bash_aliases` file. `arch-scripts.sh` omits the modular alias files and moves an installed alias directory to backup. This release preserves that startup and installer behavior.

The mirror regression's previously recorded final `rr` assertion failure remains outside this release. The active Rust toolchain was previously found to lack rustfmt and Clippy; no Rust changes are included.

Permissions were restored in `/home/jman/tmp/script-repo`, including hidden folders and `.git`. The latest recorded scan found directories at `755`, ordinary files at `644`, executables at `755`, Git object files at `444`, and one private Rust build lock at `600`. No group/other write permissions, special permission bits, or extended ACLs were found. Ownership was preserved.

The permission snapshot is `/home/jman/tmp/2026-10-09_script-repo_permissions_BqiFMM/before.acl`. It predates the pull to `cc654bf8`; restoring it would undo the permission cleanup on the old paths. Only for that rollback, run:

```bash
/usr/sbin/setfacl --restore=/home/jman/tmp/2026-10-09_script-repo_permissions_BqiFMM/before.acl
```
