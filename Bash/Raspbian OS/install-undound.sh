#!/usr/bin/env bash

##############################################################################################################
##
##  Purpose: Install unbound on a pc that is already running pi-hole's FTL DNS server.
##
##  Updated: 11.29.23
##
##  Script version: 1.0
##
##############################################################################################################

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

# UFW FIREWALL SETTINGS
service ufw enable
ufw default allow outgoing
ufw default deny incoming
ufw allow '80/tcp'
ufw allow '53/tcp'
ufw allow '53/udp'
ufw allow '67/tcp'
ufw allow '67/udp'
service ufw restart


# DHCPCD SETTINGS
echo 'static domain_name_servers=127.0.0.1' | tee -a '/etc/dhcpcd.conf' >/dev/null

# INSTALL UNBOUND
wget --show-progress 'https://www.internic.net/domain/named.root' -qO- | sudo tee '/var/lib/unbound/root.hints' >/dev/null

cat > '/etc/unbound/unbound.conf.d/pi-hole.conf' <<'EOF'
server:
    # If no logfile is specified, syslog is used
    # logfile: "/var/log/unbound/unbound.log"
    verbosity: 0

    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes

    # May be set to yes if you have IPv6 connectivity
    do-ip6: no

    # You want to leave this to no unless you have *native* IPv6. With 6to4 and
    # Terredo tunnels your web browser should favor IPv4 for the same reasons
    prefer-ip6: no

    # Use this only when you downloaded the list of primary root servers!
    # If you use the default dns-root-data package, unbound will find it automatically
    root-hints: "/var/lib/unbound/root.hints"

    # Trust glue only if it is within the server's authority
    harden-glue: yes

    # Require DNSSEC data for trust-anchored zones, if such data is absent, the zone becomes BOGUS
    harden-dnssec-stripped: yes

    # Don't use Capitalization randomization as it known to cause DNSSEC issues sometimes
    # see https://discourse.pi-hole.net/t/unbound-stubby-or-dnscrypt-proxy/9378 for further details
    use-caps-for-id: no

    # Reduce EDNS reassembly buffer size.
    # IP fragmentation is unreliable on the Internet today, and can cause
    # transmission failures when large DNS messages are sent via UDP. Even
    # when fragmentation does work, it may not be secure; it is theoretically
    # possible to spoof parts of a fragmented DNS message, without easy
    # detection at the receiving end. Recently, there was an excellent study
    # >>> Defragmenting DNS - Determining the optimal maximum UDP response size for DNS <<<
    # by Axel Koolhaas, and Tjeerd Slokker (https://indico.dns-oarc.net/event/36/contributions/776/)
    # in collaboration with NLnet Labs explored DNS using real world data from the
    # the RIPE Atlas probes and the researchers suggested different values for
    # IPv4 and IPv6 and in different scenarios. They advise that servers should
    # be configured to limit DNS messages sent over UDP to a size that will not
    # trigger fragmentation on typical network links. DNS servers can switch
    # from UDP to TCP when a DNS response is too big to fit in this limited
    # buffer size. This value has also been suggested in DNS Flag Day 2020.
    edns-buffer-size: 1232

    # Perform prefetching of close to expired message cache entries
    # This only applies to domains that have been frequently queried
    prefetch: yes

    # One thread should be sufficient, can be increased on beefy machines. In reality for most users running on small networks or on a single machine, it should be unnecessary to seek performance enhancement by increasing num-threads above 1.
    num-threads: 1

    # Ensure kernel buffer is large enough to not lose messages in traffic spikes
    so-rcvbuf: 1m

    # Ensure privacy of local IP ranges
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
    'You are set to paste "127.0.0.1#5335" into the GUI when everything is finally loaded.'
read -p 'Press enter to finish things up.'
clear

echo '127.0.0.1#5335' | xclip -i -rmlastnl -sel clip
1
pihole_ip="$(ip route get 1.2.3.4 | awk '{print $7}')"
firefox "http://$pihole_ip/admin/settings.php?tab=dns"
