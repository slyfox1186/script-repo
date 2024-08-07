#!/usr/bin/env bash

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or with sudo."
    exit 1
fi

DIR="$HOME/.aria2"
file="$DIR/aria2.conf"

[[ -d "$DIR" ]] && sudo rm -fr "$DIR"
mkdir -p "$DIR"

touch "$DIR/dht.dat" "$DIR/cookies.txt"

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

cat > $file <<EOF
allow-overwrite=true
allow-piece-length-change=true
always-resume=true
auto-file-renaming=true
auto-save-interval=0
bt-tracker=$trackers
console-log-level=warn
content-disposition-default-utf8=true
continue=true
dht-entry-point=dht.transmissionbt.com:6881
dht-file-path=/home/jman/.aria2/dht.dat
dht-listen-port=50101-50109
dir=.
disk-cache=256M
enable-dht6=false
enable-dht=true
enable-peer-exchange=true
enable-rpc=false
file-allocation=falloc
listen-port=50101-50109
load-cookies=/home/jman/.aria2/cookies.txt
max-concurrent-downloads=10
max-connection-per-server=16
max-download-limit=0
max-overall-download-limit=0
min-split-size=64M
quiet=false
save-cookies=/home/jman/.aria2/cookies.txt
seed-ratio=0
seed-time=0
split=32
user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36
EOF

sed -i -e 's/ http/,http/g' -i -e 's/ https/,https/g' -i -e 's/ udp/,udp/g' $file

sudo chmod -R 700 "$DIR"
sudo chown -R "$USER:$USER" "$DIR"
