# The loopback network interface
auto lo
iface lo inet loopback
# The primary network interface
auto eth0
iface eth0 inet static
address 192.168.2.40
netmask 255.255.255.0
broadcast 192.168.2.255
gateway 192.168.2.1
#dns-domain sweet. home
#dns-nameservers 192.168.2.254 1.1.1.1 8.8.8.8
