# Networking scripts

These are interactive Linux IPv4 configuration tools. Run the tool that matches
the network manager already used by the machine. Keep `networking-common.sh` in
the same directory as both entry points. The helper is sourced, not run directly.
Neither script installs packages or switches network managers.

Use a local console when activating changes. A syntactically valid configuration
can still have the wrong gateway, DNS servers, or address for your network.
Successful activation commands do not prove Internet connectivity.

## Netplan

```bash
sudo bash /home/jman/tmp/script-repo/Bash/Networking/netplan.sh
```

Requires Netplan with `get`, `set --root-dir`, `generate --root-dir`, and `try`,
plus `ip`, `flock`, and standard GNU utilities. The menu offers DHCP, static IPv4,
and exit. Static input uses CIDR notation and accepts up to three IPv4 DNS servers;
blank or `0` ends the DNS list.

The script uses the native Netplan setter, retains the configured renderer and
unrelated definitions, and validates a copy of the `/etc`, `/lib`, and `/run`
Netplan YAML hierarchy in a private temporary root. It previews the changed
fields before asking to save. It aborts if `/etc/netplan` YAML files changed during
the preview. Only files with changed contents are installed, using an atomic
rename per file and mode `600`.

This tool configures `network.ethernets.<interface-name>`. Configurations using a
different Netplan ID with `match` or `set-name`, Wi-Fi, bonds, bridges, VLANs, and
policy routing should be edited manually. The selected interface's address list,
static routes, legacy `gateway4`, and DNS address list are replaced. Existing IPv6
addresses, DNS addresses, or routes in those lists cause the script to stop.
Other settings, including DHCPv6 and DNS search domains, are preserved. The native
setter may normalize YAML formatting and comments in files it rewrites.

Before installation, every `/etc/netplan/*.yaml` file is backed up inside a unique
root-only `/etc/netplan/.network-backup.YYYY-MM-DD_HHMMSS.XXXXXX` directory. The
script runs `netplan try --timeout 120` and requires its explicit acceptance
message. Some versions return zero after a successful rejection and rollback,
so exit status alone is insufficient. Failure or interruption restores the saved
YAML files and regenerates the old backend configuration. Netplan handles runtime
rollback; verify the actual connection from a local console if a test fails.

For manual recovery, identify the backup path printed by the script, compare its
YAML files with `/etc/netplan`, restore the original files, and remove YAML files
created by the failed change. Then run `sudo netplan generate` and test the restored
configuration from a local console with `sudo netplan try --timeout 120`. Do not
reboot until the on-disk configuration has been checked.

References: [Netplan set](https://netplan.readthedocs.io/en/stable/netplan-set/),
[Netplan get](https://netplan.readthedocs.io/en/stable/netplan-get/),
[Netplan try and rollback caveats](https://netplan.readthedocs.io/en/stable/netplan-try/),
[Canonical's try implementation](https://github.com/canonical/netplan/blob/main/netplan_cli/cli/commands/try_command.py).

## ifupdown

```bash
sudo bash /home/jman/tmp/script-repo/Bash/Networking/set-static-or-dhcp-ip-address.sh
```

Requires `ip`, `ifquery`, `ifup`, `ifdown`, `flock`, `awk`, and standard GNU
utilities. `/etc/network/interfaces` must be a regular file. The static menu
collects an IPv4 address, contiguous netmask, matching broadcast, gateway in the
same subnet, and up to four IPv4 DNS servers. Blank or `0` ends the DNS list.
`dns-nameservers` requires an installed resolver integration, such as the
ifupdown hooks provided with resolvconf; writing the option alone does not change
the running resolver.

The script replaces the selected `iface <name> inet` stanza's method and IPv4/DNS
fields, preserving other options, interfaces, activation lines, and IPv6 stanzas.
A new interface receives an `auto` line if no activation line exists. Duplicate
IPv4 stanzas, mapping stanzas, and definitions for the selected interface in
included files cause the script to stop for manual editing. `ifquery` checks the
candidate without activating it. Its parser does not validate the behavior of
retained hooks or prove that an address belongs to your actual network.

Before saving, the script previews only the changed IPv4 fields, checks for edits
to the original file, and creates a fresh
`/etc/network/interfaces.backup.YYYY-MM-DD_HHMMSS.XXXXXX` backup. Installation
uses an atomic rename and preserves the original file metadata. Choose save only
to leave the running network alone. Immediate activation over an SSH session is
refused because ifupdown has no timed rollback.

For activation, `ifdown` reads the backup's old settings, then the file is replaced
and `ifup` reads the new settings. There is no blanket address flush. Failed or
interrupted activation restores the old file and attempts `ifup --force` with
the old configuration. If that recovery fails, use the local console and the
printed backup path. Backups are retained after success and failure.

Reference: [Debian ifupdown command documentation](https://manpages.debian.org/bookworm/ifupdown/ifquery.8.en.html).

## Validation and limits

Both scripts share `/run/script-repo-networking.lock` to prevent simultaneous
changes by these tools. This lock does not coordinate with other network editors.
Avoid editing configuration or running other network management commands while
a script is active. Interrupted disk writes have file recovery; runtime recovery
is best effort and cannot guarantee connectivity.

Focused tests use temporary files and mock network commands. They exercise the
menus, generated ifupdown content, Netplan command arguments, backups, errors,
EOF, signals, shared locking, and recovery without changing the host network.

```bash
bash -n /home/jman/tmp/script-repo/Bash/Networking/networking-common.sh
bash -n /home/jman/tmp/script-repo/Bash/Networking/netplan.sh
bash -n /home/jman/tmp/script-repo/Bash/Networking/set-static-or-dhcp-ip-address.sh
shellcheck /home/jman/tmp/script-repo/Bash/Networking/*.sh
/home/jman/miniconda3/envs/agent-duet/bin/python -m pytest /home/jman/tmp/script-repo/tests/test_networking_scripts.py -q
```

The interpreter above was verified locally with Python 3.13 and pytest. CI uses
the repository's Python 3.9/3.13 environments. Real Netplan/ifupdown parsing,
DHCP/DNS behavior, and network activation still need a disposable Debian/Ubuntu
machine with those tools installed. Neither backend is installed on the current
development machine, and its live network was not changed during verification.
