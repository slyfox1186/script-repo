#!/usr/bin/env bash


clear

if [ "$EUID" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script as root/sudo.'
    exit 1
fi

pkgs=(gufw ufw unbound wget xclip)

for pkg in ${pkgs[@]}
do
    missing_pkg="$(dpkg -l | grep -o "$pkg")"
    
    if [ -z "$missing_pkg" ]; then
        missing_pkgs+=" $pkg"
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt update
    sudo apt -y install $missing_pkgs
    sudo apt autoclean
    clear
fi

service ufw enable
ufw default allow outgoing
ufw default deny incoming
ufw allow '80/tcp'
ufw allow '53/tcp'
ufw allow '53/udp'
ufw allow '67/tcp'
ufw allow '67/udp'
service ufw restart


echo 'static domain_name_servers=127.0.0.1' | tee -a '/etc/dhcpcd.conf' >/dev/null

wget --show-progress 'https://www.internic.net/domain/named.root' -qO- | sudo tee '/var/lib/unbound/root.hints' >/dev/null

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

service unbound restart

echo 'edns-packet-max=1232' | tee '/etc/dnsmasq.d/99-edns.conf' >/dev/null

clear

printf "%s\n%s\n\n"                                                                                                                  \
    'When you are ready we will open the browser to the Pi-Hole GUI and copy required unbound DNS Server 1 text into the clipboard.' \
read -p 'Press enter to finish things up.'
clear

1
pihole_ip="$(ip route get 1.2.3.4 | awk '{print $7}')"
firefox "http://$pihole_ip/admin/settings.php?tab=dns"
