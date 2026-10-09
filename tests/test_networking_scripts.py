"""Run networking menus in a sandbox; never invoke host network commands."""

import os
import fcntl
from pathlib import Path
import shutil
import subprocess

import pytest


SOURCE = Path(__file__).resolve().parents[1] / "Bash/Networking"
ORIGINAL = """source /etc/network/interfaces.d/*
auto lo eth0 eth1
iface lo inet loopback
iface eth0 inet static
    address 192.168.1.20
    netmask 255.255.255.0
iface eth0 inet6 auto
iface eth1 inet dhcp
    mtu 1400
"""


@pytest.fixture
def sandbox(tmp_path):
    scripts = tmp_path / "scripts"
    shutil.copytree(SOURCE, scripts)
    etc = tmp_path / "etc"
    (etc / "network/interfaces.d").mkdir(parents=True)
    (etc / "network/interfaces").write_text(ORIGINAL)
    (etc / "netplan").mkdir()
    (etc / "netplan/01-netcfg.yaml").write_text("network:\n  version: 2\n")
    stubs = tmp_path / "bin"
    stubs.mkdir()
    log = tmp_path / "commands"
    log.touch()
    for name in ("sudo", "apt", "clear", "ip", "netplan", "ifquery", "ifup", "ifdown"):
        stub = stubs / name
        stub.write_text(
            "#!/bin/bash\nset -e\n"
            'printf "%s %s\\n" "${0##*/}" "$*" >> "$COMMAND_LOG"\n'
            'case "${0##*/}" in\n'
            "sudo) exit 99;;\n"
            "netplan)\n"
            '  if [[ "$1" == get && "$2" == --root-dir=* && "$FAIL_COMMAND" == edit && ! -e "$EDIT_MARKER" ]]; then printf "# external edit\\n" >> "$EDIT_TARGET"; touch "$EDIT_MARKER"; fi\n'
            '  if [[ "$1" == get && "$FAIL_COMMAND" == ipv6 && "${!#}" == *.addresses ]]; then printf "%s\\n" "- ::1"; exit; fi\n'
            '  if [[ "$1" == set ]]; then\n'
            "    root=${2#--root-dir=}\n"
            '    printf "changed\\n" > "$root/etc/netplan/01-netcfg.yaml"\n'
            "  fi\n"
            '  if [[ "$1" == try && "$FAIL_COMMAND" != reject ]]; then printf "Configuration accepted.\\n"; fi\n'
            '  if [[ "$1" == try && "$FAIL_COMMAND" == signal ]]; then kill -TERM "$PPID"; fi\n'
            '  [[ "$1" != "$FAIL_COMMAND" ]];;\n'
            "ifquery)\n"
            '  if [[ "$*" == *".new."* && "$FAIL_COMMAND" == edit ]]; then printf "# external edit\\n" >> "$EDIT_TARGET"; fi\n'
            '  [[ "$FAIL_COMMAND" != ifquery ]] || exit 1\n'
            '  [[ "$FAIL_COMMAND" == included || "$*" != *".probe."* || "$*" == *--list* ]];;\n'
            "ifup|ifdown)\n"
            '  if [[ "${0##*/}" == ifup && "$FAIL_COMMAND" == signal && "$*" != *--force* ]]; then kill -TERM "$PPID"; fi\n'
            '  [[ "${0##*/}" != "$FAIL_COMMAND" ]];;\n'
            "esac\n"
        )
        stub.chmod(0o700)
    # Patch only the disposable copies. Production paths cannot reach the host.
    for script in scripts.glob("*.sh"):
        text = script.read_text()
        text = text.replace(
            "fname=/etc/network/interfaces\n", f"fname={etc / 'network/interfaces'}\n"
        )
        text = text.replace(
            "config_dir=/etc/netplan\n", f"config_dir={etc / 'netplan'}\n"
        )
        text = text.replace("/run/script-repo-networking.lock", str(tmp_path / "lock"))
        text = text.replace("(( EUID == 0 ))", "true")
        script.write_text(text)
    env = dict(
        os.environ, PATH=f"{stubs}:/usr/bin:/bin", COMMAND_LOG=str(log), FAIL_COMMAND=""
    )
    for key in ("SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"):
        env.pop(key, None)
    return scripts, etc, log, env


def run(sandbox, name, answers, failure=""):
    scripts, _, _, env = sandbox
    env = dict(env, FAIL_COMMAND=failure)
    return subprocess.run(
        ["bash", str(scripts / name)],
        input=answers,
        text=True,
        capture_output=True,
        env=env,
        timeout=10,
        check=False,
    )


def test_ifupdown_dhcp_preserves_other_interfaces_and_ipv6(sandbox):
    result = run(sandbox, "set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n2\n")
    assert result.returncode == 0, result.stderr
    contents = (sandbox[1] / "network/interfaces").read_text()
    assert "iface eth0 inet dhcp" in contents
    assert "iface eth0 inet6 auto" in contents
    assert "iface eth1 inet dhcp\n    mtu 1400" in contents
    assert "iface lo inet loopback" in contents


def test_ifupdown_invalid_agreement_does_not_write(sandbox):
    result = run(
        sandbox, "set-static-or-dhcp-ip-address.sh", "invalid\n1\neth0\n1\n2\n"
    )
    assert result.returncode != 0
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL


def test_ifupdown_rejects_ipv4_injection(sandbox):
    result = run(
        sandbox, "set-static-or-dhcp-ip-address.sh", "1\n2\neth0\n192.168.1.2;reboot\n"
    )
    assert result.returncode != 0
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL


def test_netplan_exit_does_not_install_packages(sandbox):
    result = run(sandbox, "netplan.sh", "3\n")
    assert result.returncode == 0, result.stderr
    if sandbox[2].exists():
        assert "apt " not in sandbox[2].read_text()


def test_netplan_failed_validation_restores_configuration(sandbox):
    path = sandbox[1] / "netplan/01-netcfg.yaml"
    before = path.read_bytes()
    result = run(sandbox, "netplan.sh", "1\neth0\n1\n", "generate")
    assert result.returncode != 0
    assert path.read_bytes() == before
    assert "netplan try" not in sandbox[2].read_text()


def test_netplan_zero_exit_rejection_restores_configuration(sandbox):
    path = sandbox[1] / "netplan/01-netcfg.yaml"
    before = path.read_bytes()
    result = run(sandbox, "netplan.sh", "1\neth0\n1\n", "reject")
    assert result.returncode != 0
    assert path.read_bytes() == before


@pytest.mark.parametrize(
    "name,answers",
    [
        ("netplan.sh", "1\neth0\n2\n"),
        ("set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n2\n"),
    ],
)
def test_cancel_preserves_configuration(sandbox, name, answers):
    result = run(sandbox, name, answers)
    assert result.returncode == 0, result.stderr
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL
    assert (
        sandbox[1] / "netplan/01-netcfg.yaml"
    ).read_text() == "network:\n  version: 2\n"
    assert not list(sandbox[1].rglob("*backup*"))


@pytest.mark.parametrize(
    "name,answers",
    [
        ("netplan.sh", ""),
        ("netplan.sh", "1\n"),
        ("netplan.sh", "1\neth0\n"),
        ("set-static-or-dhcp-ip-address.sh", ""),
        ("set-static-or-dhcp-ip-address.sh", "1\n"),
        ("set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n"),
    ],
)
def test_eof_fails_without_writing(sandbox, name, answers):
    result = run(sandbox, name, answers)
    assert result.returncode != 0
    assert "Input ended" in result.stderr
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL
    assert (
        sandbox[1] / "netplan/01-netcfg.yaml"
    ).read_text() == "network:\n  version: 2\n"


@pytest.mark.parametrize(
    "value", ["lo", "-eth0", "eth0;reboot", "eth0\\niface", "a" * 16]
)
def test_invalid_interface_is_rejected(sandbox, value):
    result = run(sandbox, "netplan.sh", f"1\n{value}\n1\n")
    assert result.returncode != 0
    assert "netplan set" not in sandbox[2].read_text()


@pytest.mark.parametrize(
    "cidr", ["256.1.1.1/24", "192.168.1.2/33", "01.2.3.4/24", "1.2.3.4", "1.2.3.4/08"]
)
def test_invalid_cidr_is_rejected(sandbox, cidr):
    result = run(sandbox, "netplan.sh", f"2\neth0\n{cidr}\n")
    assert result.returncode != 0
    assert "Invalid IPv4" in result.stderr


def test_ifupdown_static_dns_and_preserved_options(sandbox):
    path = sandbox[1] / "network/interfaces"
    original = ORIGINAL.replace(
        "    netmask 255.255.255.0",
        "    netmask 255.255.255.0\n    mtu 1450\n    pre-up echo retained\n    wpa-psk private-fixture",
    )
    path.write_text(original)
    result = run(
        sandbox,
        "set-static-or-dhcp-ip-address.sh",
        "1\n2\neth0\n192.168.1.30\n255.255.255.0\n192.168.1.255\n192.168.1.1\n1.1.1.1\n8.8.8.8\n0\n1\n2\n",
    )
    assert result.returncode == 0, result.stderr
    contents = path.read_text()
    assert "    dns-nameservers 1.1.1.1 8.8.8.8\n" in contents
    assert "    address 192.168.1.30\n" in contents
    assert "    address 192.168.1.20\n" not in contents
    assert (
        "    mtu 1450\n    pre-up echo retained\n    wpa-psk private-fixture"
        in contents
    )
    assert "private-fixture" not in result.stdout
    backups = list(path.parent.glob("interfaces.backup.*"))
    assert len(backups) == 1
    assert backups[0].read_text() == original


@pytest.mark.parametrize("failure", ["ifquery", "included", "ifdown", "ifup"])
def test_ifupdown_failures_preserve_original(sandbox, failure):
    result = run(
        sandbox, "set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n1\n", failure
    )
    assert result.returncode != 0
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL
    assert "ip addr flush" not in sandbox[2].read_text()


def test_ifupdown_activation_uses_old_config_and_no_flush(sandbox):
    result = run(sandbox, "set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n1\n")
    assert result.returncode == 0, result.stderr
    commands = sandbox[2].read_text()
    assert "ifdown --interfaces=" in commands
    assert "interfaces.backup." in commands
    assert "ifup eth0" in commands
    assert "ip addr flush" not in commands


def test_ifupdown_ssh_activation_is_rejected(sandbox):
    sandbox[3]["SSH_CONNECTION"] = "192.0.2.1 12345 192.0.2.2 22"
    result = run(sandbox, "set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n1\n")
    assert result.returncode != 0
    assert "Activation over SSH" in result.stderr
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL
    assert "ifdown " not in sandbox[2].read_text()


@pytest.mark.parametrize("failure", ["set", "generate", "get", "try", "reject"])
def test_netplan_failures_preserve_original(sandbox, failure):
    path = sandbox[1] / "netplan/01-netcfg.yaml"
    result = run(sandbox, "netplan.sh", "1\neth0\n1\n", failure)
    assert result.returncode != 0
    assert path.read_text() == "network:\n  version: 2\n"


def test_netplan_static_arguments_and_acceptance(sandbox):
    result = run(
        sandbox,
        "netplan.sh",
        "2\neth0\n192.168.1.30/24\n192.168.1.1\n1.1.1.1\n8.8.8.8\n0\n1\n",
    )
    assert result.returncode == 0, result.stderr
    commands = sandbox[2].read_text()
    assert "gateway4: null" in commands
    assert "addresses: [192.168.1.30/24]" in commands
    assert "routes: [{to: default, via: 192.168.1.1}]" in commands
    assert "addresses: [1.1.1.1,8.8.8.8]" in commands
    assert "netplan generate --root-dir=" in commands
    assert "netplan try --timeout 120" in commands
    assert "netplan apply" not in commands
    backups = list((sandbox[1] / "netplan").glob(".network-backup.*"))
    assert len(backups) == 1
    assert (backups[0] / "01-netcfg.yaml").read_text() == "network:\n  version: 2\n"
    assert backups[0].stat().st_mode & 0o777 == 0o700
    assert (sandbox[1] / "netplan/01-netcfg.yaml").read_text() == "changed\n"
    assert (sandbox[1] / "netplan/01-netcfg.yaml").stat().st_mode & 0o777 == 0o600


def test_netplan_ipv6_is_not_overwritten(sandbox):
    result = run(sandbox, "netplan.sh", "1\neth0\n1\n", "ipv6")
    assert result.returncode != 0
    assert "IPv6" in result.stderr
    assert "netplan set" not in sandbox[2].read_text()


def test_ifupdown_signal_attempts_runtime_recovery(sandbox):
    result = run(
        sandbox, "set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n1\n", "signal"
    )
    assert result.returncode != 0
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL
    assert "ifup --force eth0" in sandbox[2].read_text()


@pytest.mark.parametrize(
    "netmask,broadcast,gateway",
    [
        ("255.0.255.0", "192.168.1.255", "192.168.1.1"),
        ("255.255.255.0", "192.168.2.255", "192.168.1.1"),
        ("255.255.255.0", "192.168.1.255", "192.168.2.1"),
    ],
)
def test_invalid_static_subnet_is_rejected(sandbox, netmask, broadcast, gateway):
    result = run(
        sandbox,
        "set-static-or-dhcp-ip-address.sh",
        f"1\n2\neth0\n192.168.1.20\n{netmask}\n{broadcast}\n{gateway}\n",
    )
    assert result.returncode != 0
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL


def test_ifupdown_duplicate_ipv4_stanza_is_rejected(sandbox):
    path = sandbox[1] / "network/interfaces"
    before = ORIGINAL + "iface eth0 inet dhcp\n"
    path.write_text(before)
    result = run(sandbox, "set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n2\n")
    assert result.returncode != 0
    assert path.read_text() == before


@pytest.mark.parametrize(
    "name,answers",
    [
        ("netplan.sh", "1\neth0\n1\n"),
        ("set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n2\n"),
    ],
)
def test_shared_lock_rejects_concurrent_changes(sandbox, name, answers):
    lock = sandbox[0].parent / "lock"
    with lock.open("w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = run(sandbox, name, answers)
    assert result.returncode != 0
    assert "Another networking script" in result.stderr
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL
    assert (
        sandbox[1] / "netplan/01-netcfg.yaml"
    ).read_text() == "network:\n  version: 2\n"


@pytest.mark.parametrize(
    "name,answers,relative",
    [
        ("netplan.sh", "1\neth0\n1\n", "netplan/01-netcfg.yaml"),
        (
            "set-static-or-dhcp-ip-address.sh",
            "1\n1\neth0\n1\n2\n",
            "network/interfaces",
        ),
    ],
)
def test_symlink_configuration_is_rejected(sandbox, name, answers, relative):
    path = sandbox[1] / relative
    target = path.with_suffix(".original")
    path.rename(target)
    before = target.read_bytes()
    path.symlink_to(target)
    result = run(sandbox, name, answers)
    assert result.returncode != 0
    assert path.is_symlink()
    assert target.read_bytes() == before


@pytest.mark.parametrize(
    "name,answers,command,pattern",
    [
        ("netplan.sh", "1\neth0\n1\n", "cp", "*.network-new.*"),
        (
            "set-static-or-dhcp-ip-address.sh",
            "1\n1\neth0\n1\n1\n",
            "mv",
            "*/network/interfaces",
        ),
    ],
)
def test_install_failure_restores_original(sandbox, name, answers, command, pattern):
    stub = sandbox[0].parent / "bin" / command
    marker = sandbox[0].parent / "write-failure"
    stub.write_text(
        "#!/bin/bash\n"
        f'if [[ "${{!#}}" == {pattern} && ! -e "$WRITE_FAILURE_MARKER" ]]; then\n'
        '    printf failed > "$WRITE_FAILURE_MARKER"\n'
        "    exit 42\n"
        "fi\n"
        f'exec /usr/bin/{command} "$@"\n'
    )
    stub.chmod(0o700)
    sandbox[3]["WRITE_FAILURE_MARKER"] = str(marker)
    result = run(sandbox, name, answers)
    assert result.returncode != 0
    assert marker.exists()
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL
    assert (
        sandbox[1] / "netplan/01-netcfg.yaml"
    ).read_text() == "network:\n  version: 2\n"
    assert "restored" in result.stderr


def test_ifupdown_preserves_file_permissions(sandbox):
    path = sandbox[1] / "network/interfaces"
    path.chmod(0o640)
    result = run(sandbox, "set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n2\n")
    assert result.returncode == 0, result.stderr
    assert path.stat().st_mode & 0o777 == 0o640


@pytest.mark.parametrize(
    "name,answers",
    [
        ("netplan.sh", "1\neth0\n1\n"),
        ("set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n2\n"),
    ],
)
def test_missing_dependency_fails_without_writing(sandbox, name, answers):
    (sandbox[0].parent / "bin/ip").unlink()
    # Hide any host ip command while leaving the utilities needed to start Bash.
    for command in ("bash", "dirname"):
        (sandbox[0].parent / "bin" / command).symlink_to(shutil.which(command))
    sandbox[3]["PATH"] = str(sandbox[0].parent / "bin")
    result = run(sandbox, name, answers)
    assert result.returncode != 0
    assert "Required command is missing: ip" in result.stderr
    assert (sandbox[1] / "network/interfaces").read_text() == ORIGINAL


def test_activation_does_not_pass_lock_to_backend_children(sandbox):
    stub = sandbox[0].parent / "bin/ifup"
    stub.write_text(
        "#!/bin/bash\n"
        "for descriptor in /proc/$$/fd/*; do\n"
        '    if [[ $(readlink "$descriptor") == "$NETWORK_LOCK_PATH" ]]; then exit 64; fi\n'
        "done\n"
        "exit 0\n"
    )
    sandbox[3]["NETWORK_LOCK_PATH"] = str(sandbox[0].parent / "lock")
    result = run(sandbox, "set-static-or-dhcp-ip-address.sh", "1\n1\neth0\n1\n1\n")
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize(
    "name,answers,relative",
    [
        ("netplan.sh", "1\neth0\n1\n", "netplan/01-netcfg.yaml"),
        (
            "set-static-or-dhcp-ip-address.sh",
            "1\n1\neth0\n1\n2\n",
            "network/interfaces",
        ),
    ],
)
def test_edit_during_preview_is_not_overwritten(sandbox, name, answers, relative):
    path = sandbox[1] / relative
    original = path.read_text()
    sandbox[3]["EDIT_TARGET"] = str(path)
    sandbox[3]["EDIT_MARKER"] = str(sandbox[0].parent / "edited")
    result = run(sandbox, name, answers, "edit")
    assert result.returncode != 0
    assert "changed during the preview" in result.stderr
    assert path.read_text() == original + "# external edit\n"
    assert not list(sandbox[1].rglob("*backup*"))


def test_netplan_signal_restores_original(sandbox):
    result = run(sandbox, "netplan.sh", "1\neth0\n1\n", "signal")
    assert result.returncode != 0
    assert (
        sandbox[1] / "netplan/01-netcfg.yaml"
    ).read_text() == "network:\n  version: 2\n"
    assert "restored" in result.stderr
