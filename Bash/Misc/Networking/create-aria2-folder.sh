#!/usr/bin/env bash

# Check if the script is being run as root or with sudo
if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or with sudo."
    exit 1
fi

# Generate a random 30-character RPC secret
rpc_secret=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 30)
echo "Generated RPC secret: $rpc_secret"

# Define the directory and configuration file paths
DIR="$HOME/.aria2"
CONFIG_FILE="$DIR/aria2.conf"

# Remove the existing .aria2 directory if it exists and create a new one
[[ -d "$DIR" ]] && sudo rm -fr "$DIR"
mkdir -p "$DIR"

# Create necessary files for aria2
touch "$DIR/cookies.txt" "$DIR/dht.dat"

# List of trackers to be added to the aria2 configuration
trackers=(
    "http://bittorrent-tracker.e-n-c-r-y-p-t.net:1337/announce"
    "http://bvarf.tracker.sh:2086/announce"
    "http://ch3oh.ru:6969/announce"
    "http://open.acgnxtracker.com:80/announce"
    "http://open.acgtracker.com:1096/announce"
    "http://p4p.arenabg.com:1337/announce"
    "http://t.overflow.biz:6969/announce"
    "http://tr.kxmp.cf:80/announce"
    "http://tracker.bt4g.com:2095/announce"
    "http://tracker.ccp.ovh:6969/announce"
    "http://tracker.dler.org:6969/announce"
    "http://tracker.edkj.club:6969/announce"
    "http://tracker.files.fm:6969/announce"
    "http://tracker.gbitt.info:80/announce"
    "http://tracker.mywaifu.best:6969/announce"
    "http://tracker.netmap.top:6969/announce"
    "http://tracker.renfei.net:8080/announce"
    "http://tracker1.itzmx.com:8080/announce"
    "http://wepzone.net:6969/announce"
    "http://wg.mortis.me:6969/announce"
    "https://opentracker.i2p.rocks:443/announce"
    "https://t1.hloli.org:443/announce"
    "https://tracker.cloudit.top:443/announce"
    "https://tracker.gbitt.info:443/announce"
    "https://tracker.imgoingto.icu:443/announce"
    "https://tracker.lilithraws.org:443/announce"
    "https://tracker.loligirl.cn:443/announce"
    "https://tracker.netmap.top:8443/announce"
    "https://tracker.renfei.net:443/announce"
    "https://tracker.tamersunion.org:443/announce"
    "https://tracker.yemekyedim.com:443/announce"
    "https://tracker1.520.jp:443/announce"
    "https://tracker1.ctix.cn:443/announce"
    "https://www.peckservers.com:9443/announce"
    "udp://1c.premierzal.ru:6969/announce"
    "udp://6.pocketnet.app:6969/announce"
    "udp://6ahddutb1ucc3cp.ru:6969/announce"
    "udp://bittorrent-tracker.e-n-c-r-y-p-t.net:1337/announce"
    "udp://bt.ktrackers.com:6666/announce"
    "udp://bt1.archive.org:6969/announce"
    "udp://bt2.archive.org:6969/announce"
    "udp://d40969.acod.regrucolo.ru:6969/announce"
    "udp://epider.me:6969/announce"
    "udp://exodus.desync.com:6969/announce"
    "udp://explodie.org:6969/announce"
    "udp://free.publictracker.xyz:6969/announce"
    "udp://ipv4.rer.lol:2710/announce"
    "udp://isk.richardsw.club:6969/announce"
    "udp://moonburrow.club:6969/announce"
    "udp://movies.zsw.ca:6969/announce"
    "udp://new-line.net:6969/announce"
    "udp://oh.fuuuuuck.com:6969/announce"
    "udp://open.demonii.com:1337/announce"
    "udp://open.dstud.io:6969/announce"
    "udp://open.free-tracker.ga:6969/announce"
    "udp://open.stealth.si:80/announce"
    "udp://open.tracker.cl:1337/announce"
    "udp://open.tracker.ink:6969/announce"
    "udp://open.u-p.pw:6969/announce"
    "udp://opentracker.i2p.rocks:6969/announce"
    "udp://opentracker.io:6969/announce"
    "udp://p4p.arenabg.com:1337/announce"
    "udp://public.tracker.vraphim.com:6969/announce"
    "udp://retracker01-msk-virt.corbina.net:80/announce"
    "udp://ryjer.com:6969/announce"
    "udp://su-data.com:6969/announce"
    "udp://tamas3.ynh.fr:6969/announce"
    "udp://thinking.duckdns.org:6969/announce"
    "udp://tracker-udp.gbitt.info:80/announce"
    "udp://tracker.0x7c0.com:6969/announce"
    "udp://tracker.auctor.tv:6969/announce"
    "udp://tracker.bittor.pw:1337/announce"
    "udp://tracker.cubonegro.lol:6969/announce"
    "udp://tracker.dler.org:6969/announce"
    "udp://tracker.dump.cl:6969/announce"
    "udp://tracker.edkj.club:6969/announce"
    "udp://tracker.filemail.com:6969/announce"
    "udp://tracker.fnix.net:6969/announce"
    "udp://tracker.internetwarriors.net:1337/announce"
    "udp://tracker.moeking.me:6969/announce"
    "udp://tracker.opentrackr.org:1337/announce"
    "udp://tracker.qu.ax:6969/announce"
    "udp://tracker.skyts.net:6969/announce"
    "udp://tracker.srv00.com:6969/announce"
    "udp://tracker.t-rb.org:6969/announce"
    "udp://tracker.theoks.net:6969/announce"
    "udp://tracker.therarbg.com:6969/announce"
    "udp://tracker.therarbg.to:6969/announce"
    "udp://tracker.tiny-vps.com:6969/announce"
    "udp://tracker.torrent.eu.org:451/announce"
    "udp://tracker.tryhackx.org:6969/announce"
    "udp://tracker1.bt.moack.co.kr:80/announce"
    "udp://tracker1.myporn.club:9337/announce"
    "udp://tracker2.dler.org:80/announce"
    "udp://ttk2.nbaonlineservice.com:6969/announce"
    "udp://uploads.gamecoast.net:6969/announce"
    "udp://wepzone.net:6969/announce"
)

# Create aria2 configuration file with the specified settings
cat > "$CONFIG_FILE" <<EOF
allow-overwrite=true                        # Allow overwriting files
allow-piece-length-change=true              # Allow changing piece length during download
always-resume=true                          # Always resume downloads
auto-save-interval=0                        # Disable auto-saving to reduce disk I/O
bt-tracker=${trackers[@]}                   # Set list of trackers
console-log-level=error                     # Set log level to error
content-disposition-default-utf8=true       # Use UTF-8 for Content-Disposition header
continue=true                               # Continue downloading even after restarting aria2
dht-entry-point=dht.transmissionbt.com:6881 # Entry point for DHT
dht-file-path=$DIR/dht.dat                  # Path to DHT file
dht-listen-port=50101-50109                 # Listening ports for DHT
dir=.                                       # Set the default download directory
disk-cache=512M                             # Set disk cache size to 512MB
enable-dht6=false                           # Disable DHT for IPv6
enable-dht=true                             # Enable DHT (Distributed Hash Table)
enable-peer-exchange=true                   # Enable peer exchange with other clients

# Enable RPC mode
enable-rpc=true                             # Enable RPC mode
rpc-allow-origin-all=true                   # Allow all origins to access RPC interface
rpc-listen-all=true                         # Listen on all network interfaces for RPC
rpc-listen-port=6800                        # Set RPC listening port
rpc-secret=$rpc_secret                      # Set RPC secret for secure access

file-allocation=none                        # Disable file pre-allocation
listen-port=50101-50109                     # Set listening ports
load-cookies=$DIR/cookies.txt               # Load cookies from specified file
max-concurrent-downloads=10                 # Set maximum concurrent downloads
max-connection-per-server=16                # Set maximum connections per server
max-download-limit=0                        # No limit on download speed
max-overall-download-limit=0                # No limit on overall download speed
min-split-size=64M                          # Set minimum split size for each download
quiet=false                                 # Disable quiet mode
save-cookies=$DIR/cookies.txt               # Save cookies to specified file
seed-ratio=0                                # Do not seed after download
seed-time=0                                 # Do not seed for any amount of time
split=32                                    # Set the number of splits per download
user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36 # Set user agent string
EOF

# Replace spaces with commas in the tracker list within the configuration file
sed -i -e 's/ http/,http/g' -i -e 's/ https/,https/g' -i -e 's/ udp/,udp/g' "$CONFIG_FILE"

# Set the permissions for the .aria2 directory and its contents
chmod -R 700 "$DIR"
chown -R "$USER:$USER" "$DIR"
