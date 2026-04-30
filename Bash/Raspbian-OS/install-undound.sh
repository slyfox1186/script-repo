#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root/sudo."
    exit 1
fi

pkgs=(gufw ufw unbound wget xclip)

missing_pkgs=()
for pkg in "${pkgs[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
        missing_pkgs+=("$pkg")
    fi
done

if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
    apt update
    apt -y install "${missing_pkgs[@]}"
    apt autoclean
    clear
fi

ufw enable
ufw default allow outgoing
ufw default deny incoming
ufw allow '80/tcp'
ufw allow '53/tcp'
ufw allow '53/udp'
ufw allow '67/tcp'
ufw allow '67/udp'
ufw reload

echo 'static domain_name_servers=127.0.0.1' | tee -a '/etc/dhcpcd.conf' >/dev/null

wget --show-progress 'https://www.internic.net/domain/named.root' -qO- | tee '/var/lib/unbound/root.hints' >/dev/null

cat > '/etc/unbound/unbound.conf.d/pi-hole.conf' <<'EOF'
server:
    verbosity: 0

    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes

    do-ip6: no

    prefer-ip6: no

    root-hints: "/var/lib/unbound/root.hints"

    harden-glue: yes

    harden-dnssec-stripped: yes

    use-caps-for-id: no

    edns-buffer-size: 1232

    prefetch: yes

    num-threads: 1

    so-rcvbuf: 1m

    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
EOF

systemctl restart unbound

echo 'edns-packet-max=1232' | tee '/etc/dnsmasq.d/99-edns.conf' >/dev/null

clear

printf "%s\n\n" \
    'When you are ready we will open the browser to the Pi-Hole GUI and copy required unbound DNS Server 1 text into the clipboard.'
read -rp 'Press enter to finish things up.'
clear

pihole_ip="$(ip route get 1.2.3.4 | awk '{print $7}')"
firefox "http://$pihole_ip/admin/settings.php?tab=dns"
