# Script repository status

Updated: 2026-10-09

The review and improvements to `/home/jman/tmp/script-repo/Bash/Networking/`
are complete locally. Both existing entry points now use the shared
`networking-common.sh` helper. Keep all three files together.

No action is required from Jeff. Jeff approved committing and pushing this release
to GitHub `slyfox1186/script-repo`, branch `main`.

The networking tools now validate input, preview changes, retain fresh backups,
check command failures, and recover files after failure or interruption. Netplan
validates in a temporary root and uses timed confirmation. The ifupdown tool
preserves unrelated interfaces, IPv6 stanzas, and retained options; it offers
save-only operation and refuses immediate activation over SSH.

Read `/home/jman/tmp/script-repo/Bash/Networking/README.md` for requirements,
usage, supported configurations, and recovery instructions. Neither tool installs
packages or switches the machine's network manager. Netplan requires modern
`get`, `set`, `generate`, and `try` commands; complex configurations need manual
editing.

Validation: 56 focused sandbox tests passed using Python 3.13.15 and pytest 9.1.1.
All three shell files passed Bash syntax checks and full ShellCheck. The new test
file passed Ruff 0.16.6 lint and formatting checks and Python compilation. Diff
whitespace checks passed. No full suite, production build, or live network changes
were run. Neither Netplan nor ifupdown is installed on this development machine.
Their real parsers, DHCP/DNS behavior, and activation remain unverified.

The next validation step before production use is a disposable Debian/Ubuntu
machine with the matching network backend and a local console. The focused check
can be repeated without changing networking:

```bash
/home/jman/miniconda3/envs/agent-duet/bin/python -m pytest /home/jman/tmp/script-repo/tests/test_networking_scripts.py -q
```

Previous project facts retained for continuity:

- `.bashrc` loads the single `.bash_aliases` file. `arch-scripts.sh` omits modular
  alias files and backs up an installed alias directory. This work does not alter
  that startup or installer behavior.
- The mirror regression has a previously recorded `rr` assertion failure. The
  Rust toolchain was previously found to lack rustfmt and Clippy. Neither area
  was changed or re-tested in this task.
- The prior permission cleanup retained ownership and removed group/other write
  access, special permission bits, and extended ACLs. Its old-path snapshot is
  `/home/jman/tmp/2026-10-09_script-repo_permissions_BqiFMM/before.acl`, predating
  the pull to `cc654bf8`. It is not a rollback for this networking work.
