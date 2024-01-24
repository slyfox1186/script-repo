#!/usr/bin/env bash

#################################################################################################################
##
##  Purpose: Creates the files needed to start aria2c
##           as a background daemon process. You can then
##           use other programs made to work with an active
##           server that will use it to download your files.
##
##           I use the Chrome extension below:
##           https://chrome.google.com/webstore/detail/aria2-explorer/mpkodccbngfoacfalldjimigbofkhgjn
##
##  Action: Start or stop the server.
##
##  Required: Set your own variables at the top of the script.
##
##  Examples:
##             - rpc_listen_port=23657 (default 6800)
##             - dht_listen_port=44321:44330
##
##  Important info: You can use the below link to get the aria2c manual
##                  https://aria2.github.io/manual/en/html/aria2c.html#options
##
#################################################################################################################

clear

start_aria2_fn()
{
    # THIS FILE WILL CREATE THE REQUIRED FILES AND DIRECTORIES TO RUN THE
    # ARAI2 CONFIG FILE AS IT IS CURRENTLY CONFIGURED BY THE FILE ARIA2.CONF.

    conf_file="${HOME}"/.aria2/aria2.conf

    # YOU MUST SET THESE VARIABLES YOURSELF
    rpc_listen_port=
    rpc_secret=
    listen_port=
    dht_listen_port=

    # CREATES THE REQUIRED DIRECTORIES INSIDE THE CURRENT USER'S HOME FOLDER
    # THIS IS ONE OF THE DEFAULT DIRECTORIES ARIA2 LOOKS FOR WHEN RUNNING ARIA2 IN RPC MODE

    # THE DOWNLOADS FOLDER IS INCLUDED DUE TO THE ARIA2 CONFIG FILE THAT WILL BE CREATED BELOW
    # WHICH HAS BEEN CONFIGURED FOR THE DOWNLOADS TO BE THE DEFAULT OUTPUT DIRECTORY WHEN RUNNING IN RPC MODE (WHICH I HIGHLY RECOMMEND USING)

    # I USE THIS AWESOME EXTENSION FOR THE CHROME BROWSER THAT WORKS IN HARMONY WITH ARIA2 WHILE RUNNING IT AS A BACKGROUND DAEMON (RPC MODE).
    # https://chrome.google.com/webstore/detail/aria2-for-chrome/mpkodccbngfoacfalldjimigbofkhgjn

    if [ ! -d "${HOME}"/.aria2 ] || [ ! -d "${HOME}"/Downloads ]; then
        mkdir -p "${HOME}/.aria2" "${HOME}/Downloads" 2>/dev/null
    fi

    # CREATE REQUIRED FILES INSIDE THE CURRENT USER'S HOME DIRECTORY (THESE FILES ARE REQUIRED BY THE CONFIG SCRIPT THAT
    # WILL BE CREATED AFTER THESE COMMANDS ARE FINISHED) IF RUNNING ARIA2 AS A BACKGROUND DAEMON IN (RPC MODE)

    files=(aria2.log cookies.txt dht.dat session.txt)

    for file in ${files[@]}
    do
        if [ ! -f "${HOME}/.aria2/${file}" ]; then
            touch "${HOME}/.aria2/${file}"
        else
            echo "The file '${HOME}/.aria2/${file}' already exists. Skipping ahead."
        fi
    done

    tracker_list="\
    udp://tracker.coppersurfer.tk:6969/announce,\
    http://acg.rip:6699/announce,\
    http://bt.endpot.com:80/announce,\
    http://bt-tracker.gamexp.ru:2710/announce,\
    http://explodie.org:6969/announce,\
    http://h4.trakx.nibba.trade:80/announce,\
    http://mail2.zelenaya.net:80/announce,\
    http://montreal.nyap2p.com:8080/announce,\
    http://newtoncity.org:6969/announce,\
    http://open.acgnxtracker.com:80/announce,\
    http://open.acgtracker.com:1096/announce,\
    http://opentracker.acgnx.se:80/announce,\
    http://open.trackerlist.xyz:80/announce,\
    http://opentracker.xyz:80/announce,\
    http://pow7.com:80/announce,\
    http://retracker.mgts.by:80/announce,\
    http://retracker.sevstar.net:2710/announce,\
    https://opentracker.acgnx.se:443/announce,\
    https://opentracker.co:443/announce,\
    https://opentracker.i2p.rocks:443/announce,\
    https://opentracker.xyz:443/announce,\
    https://t1.hloli.org:443/announce,\
    https://tracker1.520.jp:443/announce,\
    https://tracker2.ctix.cn:443/announce,\
    https://tracker.fastdownload.xyz:443/announce,\
    https://tracker.gbitt.info:443/announce,\
    https://tracker.hama3.net:443/announce,\
    https://tracker.lelux.fi:443/announce,\
    https://tracker.lilithraws.org:443/announce,\
    https://tracker.nanoha.org:443/announce,\
    https://tracker.vectahosting.eu:2053/announce,\
    https://tr.burnabyhighstar.com:443/announce,\
    http://sukebei.tracker.wf:8888/announce,\
    http://t.nyaatracker.com:80/announce,\
    http://torrentclub.tech:6969/announce,\
    http://tracker01.loveapp.com:6789/announce,\
    http://tracker1.itzmx.com:8080/announce,\
    http://tracker2.itzmx.com:6961/announce,\
    http://tracker3.itzmx.com:6961/announce,\
    http://tracker4.itzmx.com:2710/announce,\
    http://tracker.bt4g.com:2095/announce,\
    http://tracker.bz:80/announce,\
    http://tracker.frozen-layer.net:6969/announce,\
    http://tracker.gbitt.info:80/announce,\
    http://tracker.lelux.fi:80/announce,\
    http://tracker.openbittorrent.com:80/announce,\
    http://tracker.opentrackr.org:1337/announce,\
    http://tracker.torrentyorg.pl:80/announce,\
    http://tracker.tvunderground.org.ru:3218/announce,\
    http://tracker.yoshi210.com:6969/announce,\
    http://vps02.net.orel.ru:80/announce,\
    http://www.loushao.net:8080/announce,\
    http://www.proxmox.com:6969/announce,\
    udp://9.rarbg.com:2710/announce,\
    udp://9.rarbg.com:2810/announce,\
    udp://9.rarbg.me:2710/announce,\
    udp://9.rarbg.me:2780/announce,\
    udp://9.rarbg.to:2710/announce,\
    udp://9.rarbg.to:2730/announce,\
    udp://bt1.archive.org:6969/announce,\
    udp://bt2.archive.org:6969/announce,\
    udp://bt.xxx-tracker.com:2710/announce,\
    udp://chihaya.toss.li:9696/announce,\
    udp://denis.stalker.upeer.me:6969/announce,\
    udp://exodus.desync.com:6969/announce,\
    udp://explodie.org:6969/announce,\
    udp://ipv4.tracker.harry.lu:80/announce,\
    udp://newtoncity.org:6969/announce,\
    udp://npserver.intranet.pw:4201/announce,\
    udp://open.demonii.com:1337/announce,\
    udp://open.demonii.si:1337/announce,\
    udp://open.stealth.si:80/announce,\
    udp://opentor.org:2710/announce,\
    udp://opentracker.i2p.rocks:6969/announce,\
    udp://p4p.arenabg.com:1337/announce,\
    udp://qg.lorzl.gq:2710/announce,\
    udp://retracker.akado-ural.ru:80/announce,\
    udp://retracker.lanta-net.ru:2710/announce,\
    udp://retracker.netbynet.ru:2710/announce,\
    udp://retracker.sevstar.net:2710/announce,\
    udp://torrentclub.tech:6969/announce,\
    udp://tracker2.dler.org:80/announce,\
    udp://tracker2.itzmx.com:6961/announce,\
    udp://tracker3.itzmx.com:6961/announce,\
    udp://tracker4.itzmx.com:2710/announce,\
    udp://tracker.cyberia.is:6969/announce,\
    udp://tracker.dler.org:6969/announce,\
    udp://tracker.ds.is:6969/announce,\
    udp://tracker.filemail.com:6969/announce,\
    udp://tracker.filepit.to:6969/announce,\
    udp://tracker.iamhansen.xyz:2000/announce,\
    udp://tracker.leechers-paradise.org:6969/announce,\
    udp://tracker.lelux.fi:6969/announce,\
    udp://tracker.moeking.me:6969/announce,\
    udp://tracker.msm8916.com:6969/announce,\
    udp://tracker.nextrp.ru:6969/announce,\
    udp://tracker.nyaa.uk:6969/announce,\
    udp://tracker.openbittorrent.com:6969/announce,\
    udp://tracker.openbittorrent.com:80/announce,\
    udp://tracker.open-internet.nl:6969/announce,\
    udp://tracker.opentrackr.org:1337/announce,\
    udp://tracker.swateam.org.uk:2710/announce,\
    udp://tracker.tiny-vps.com:6969/announce,\
    udp://tracker.torrent.eu.org:451/announce,\
    udp://tracker.tvunderground.org.ru:3218/announce,\
    udp://tracker-udp.gbitt.info:80/announce,\
    udp://tracker.uw0.xyz:6969/announce,\
    udp://tracker.yoshi210.com:6969/announce,\
    udp://tr.bangumi.moe:6969/announce,\
    udp://uploads.gamecoast.net:6969/announce,\
    udp://v2.iperson.xyz:6969/announce,\
    udp://valakas.rollo.dnsabr.com:2710/announce,\
    udp://vibe.sleepyinternetfun.xyz:1738/announce,\
    udp://wepzone.net:6969/announce,\
    udp://www.peckservers.com:9000/announce,\
    udp://xxxtor.com:2710/announce,\
    udp://zecircle.xyz:6969/announce\
    "

    # CREATE THE ARIA2.CONF FILE THAT HOLDS ALL OF THE SETTINGS USED WHEN RUNNING IN RPC MODE.
    cat > "${conf_file}" <<EOF
# Restart the download from scratch if the corresponding control file doesn't exist. Default: false
allow-overwrite=true
# If false is given, aria2 aborts download when a piece length is different from one in a control file. If true is given, you can proceed but some download progress will be lost. Default: false
allow-piece-length-change=true
# Always resume download. If true is given, aria2 always tries to resume download and if resume is not possible, aborts download. If false is given, when all given URIs do not support resume or aria2 encounters N URIs which does not support resume, aria2 downloads file from scratch. Default: true
always-resume=true
# Enable asynchronous DNS. Default: true
async-dns=false
# Rename the file name if the same file already exists. This option works only in HTTP(S)/FTP download. Default: true
auto-file-renaming=true
auto-save-interval=60
# Enable Local Peer Discovery. If a private flag is set in a torrent, aria2 doesn't use this feature for that download even if true is given. Default: false
bt-enable-lpd=false
# If true is given, after hash check using the --check-integrity option and the file is complete, continue to seed file. If you want to check the file and download it only when it is damaged or incomplete, set this option to false. This option has effect only on BitTorrent download. Default: true
bt-hash-check-seed=true
# Specify the maximum number of peers per torrent. 0 means unlimited. See also --bt-request-peer-speed-limit option. Default: 55
bt-max-peers=55
# Download metadata only. The file(s) described in metadata will not be downloaded. This option has effect only when BitTorrent Magnet URI is used. See also the --bt-save-metadata option. Default: false
bt-metadata-only=false
# If the whole download speed of every torrent is lower than SPEED, aria2 temporarily increases the number of peers to try for more download speed. Configuring this option with your preferred download speed can increase your download speed in some cases. You can append K or M (1K = 1024, 1M = 1024K). Default: 50K
bt-request-peer-speed-limit=50K
# Save metadata as a ".torrent" file. Default: false
bt-save-metadata=false
# Seed previously downloaded files without verifying piece hashes. Default: false
bt-seed-unverified=false
bt-tracker=${torrent_trackers}
bt-tracker-connect-timeout=30
bt-tracker-timeout=30
# Check file integrity by validating piece hashes or a hash of the entire file. This option has effect only in BitTorrent, Metalink downloads with checksums, or HTTP(S)/FTP downloads with --checksum option. If piece hashes are provided, this option can detect damaged portions of a file and re-download them. If a hash of entire file is provided, hash check is only done when file has been already download. This is determined by file length. If hash check fails, file is re-downloaded from scratch. If both piece hashes and a hash of entire file are provided, only piece hashes are used. Default: false
check-integrity=true
# Download the file only when the local file is older than the remote file. This function only works with HTTP(S) downloads only. It does not work if the file size is specified in Metalink. It also ignores Content-Disposition header. If a control file exists, this option will be ignored. This function uses If-Modified-Since header to get only newer file conditionally. When getting modification time of local file, it uses user supplied file name (see --out option) or file name part in URI if --out is not specified. To overwrite existing file, --allow-overwrite is required. Default: false
conditional-get=false
# Set the connect timeout in seconds to establish a connection to HTTP/FTP/proxy server. After the connection is established, this option makes no effect, and --timeout option is used instead. Default: 60
connect-timeout=10
# Handle quoted string in Content-Disposition header as UTF-8 instead of ISO-8859-1, for example, the filename parameter, but not the extended version filename. Default: false
content-disposition-default-utf8=true
# Set log level to output to console. LEVEL is either debug, info, notice, warn, or error. Default: notice
console-log-level=notice
# Continue downloading a partially downloaded file.
continue=true
daemon=true
# Set host and port as entry points to the IPv4 DHT network.
dht-entry-point=dht.transmissionbt.com:43345
# Change the IPv4 DHT routing table file to PATH. Default: ${HOME}/.aria2/dht.dat if present, otherwise $XDG_CACHE_HOME/aria2/dht.dat.
dht-file-path=${HOME}/.aria2/dht.dat
# Set UDP listening port used by DHT(IPv4, IPv6) and UDP tracker. Default: 6881-6999
dht-listen-port=${dht_listen_port}
# The directory to store the downloaded file.
dir=${HOME}/Downloads
# Disable IPv6. This is useful if you have to use broken DNS and want to avoid terribly slow AAAA record lookup. Default: false
disable-ipv6=true
# Enable disk cache. If the SIZE is 0, the disk cache is disabled. This feature caches the downloaded data in memory, which grows to at most SIZE bytes. SIZE can include K or M. Default: 16M
disk-cache=64M
# This option changes the way Download Results is formatted. If OPT is the default, print GID, status, average download speed, and path/URI. If multiple files are involved, the path/URI of first requested file is printed and remaining ones are omitted. If OPT is full, print GID, status, average download speed, percentage of progress and path/URI. The percentage of progress and path/URI are printed for each requested file in each row. If OPT is hide, Download Results is hidden. Default: default
download-result=full
# Download the URIs listed in FILE.
enable-color=true
# Enable IPv4 DHT functionality. It also enables UDP tracker support. If a private flag is set in a torrent, aria2 doesn't use DHT for that download even if true is given. Default: true
enable-dht=true
# Enable IPv6 DHT functionality. If a private flag is set in a torrent, aria2 doesn't use DHT for that download even if true is given.
enable-dht6=false
# Enable HTTP/1.1 persistent connection. Default: true
enable-http-keep-alive=true
# Enable HTTP/1.1 pipelining. Default: false
enable-http-pipelining=false
# Enable Peer Exchange extension. If a private flag is set in a torrent, this feature is disabled for that download even if true is given. Default: true
enable-peer-exchange=true
# Enable JSON-RPC/XML-RPC server. Default: false
enable-rpc=true
# Specify file allocation method. none doesn't pre-allocate file space. prealloc pre-allocates file space before the download begins. This may take some time depending on the size of the file. If you are using newer file systems such as ext4 (with extents support), btrfs, xfs or NTFS(MinGW build only), falloc is your best choice. It allocates large(few GiB) files almost instantly. Don't use falloc with legacy file systems such as ext3 and FAT32 because it takes almost same time as prealloc and it blocks aria2 entirely until allocation finishes. falloc may not be available if your system doesn't have posix_fallocate(3) function. trunc uses ftruncate(2) system call or platform-specific counterpart to truncate a file to a specified length. Possible Values: none, prealloc, trunc, falloc. Default: prealloc
file-allocation=falloc
# If true or mem is specified when a file whose suffix is .torrent or content type is application/x-BitTorrent is downloaded, aria2 parses it as a torrent file and downloads the files mentioned in it. If mem is specified, a torrent file is not written to the disk, but is just kept in memory. If false is specified, the .torrent file is downloaded to the disk, but is not parsed as a torrent and its contents are not downloaded. Default: true
follow-torrent=true
# Save download with the --save-session option even if the download is completed or removed. This option also saves the control file in that situation. This may be useful to save BitTorrent seeding which is recognized as completed state. Default: false
force-save=false
# Fetch URIs in the command line sequentially and download each URI in a separate session, like the usual command-line download utilities. Default: false
force-sequential=false
# Send Accept: deflate, gzip request header, and inflate response if the remote server responds with Content-Encoding: gzip or Content-Encoding: deflate. Default: false
# Some server responds with Content-Encoding: gzip for files which itself is gzipped file. aria2 inflates them anyway because of the response header.
http-accept-gzip=false
# Send HTTP authorization header only when it is requested by the server. If false is set, then the authorization header is always sent to the server. There is an exception: if the user name and password are embedded in URI, authorization header is always sent to the server regardless of this option. Default: false
http-auth-challenge=true
# Send Cache-Control: no-cache and Pragma: no-cache header to avoid cached content. If false is given, these headers are not sent and you can add a Cache-Control header with a directive you like using --header option. Default: false
http-no-cache=true
# Print sizes and speed in human-readable format (e.g., 1.2Ki, 3.4Mi) in the console readout. Default: true
human-readable=true
# Download the URIs listed in FILE. You can specify multiple sources for a single entity by putting multiple URIs on a single line separated by the TAB character. Additionally, options can be specified after each URI line. Option lines must start with one or more white space characters (SPACE or TAB) and must only contain one option per line. Input files can use gzip compression. When FILE is specified as -, aria2 will read the input from stdin. See the Input File subsection for details. See also the --deferred-input option. See also the --save-session option.
input-file=${HOME}/.aria2/session.txt
# Keep unfinished download results even if doing so exceeds --max-download-result. This is useful if all unfinished downloads must be saved in a session file (see --save-session option). Please keep in mind that there is no upper bound to the number of unfinished download result to keep. If that is undesirable, turn this option off. Default: true
keep-unfinished-download-result=true
# Set TCP port number for BitTorrent downloads. Multiple ports can be specified by using, for example, 6881,6885. You can also use - to specify a range: 6881-6999. , and - can be used together: 6881-6889,6999. Default: 6881-6999
listen-port=${listen_port}
# Set TCP port number for BitTorrent downloads. Multiple ports can be specified by using ',' and '-'. Default: 6881-6999
load-cookies=${HOME}/.aria2/cookies.txt
# The file name of the log file. If - is specified, the log is written to stdout. If an empty string("") is specified, or this option is omitted, no log is written to disk at all.
log=${HOME}/.aria2/log.txt
# Set log level to output. LEVEL is either debug, info, notice, warn, or error. Default: debug
log-level=debug
# Close connection if download speed is lower than or equal to this value(bytes per sec). 0 means aria2 does not have the lowest speed limit. You can append K or M (1K = 1024, 1M = 1024K). This option does not affect BitTorrent downloads. Default: 0
lowest-speed-limit=0
# Set the maximum number of parallel downloads for every queue item. See also the --split option. Default: 5
max-concurrent-downloads=5
# The maximum number of connections to one server for each download. Default: 1
max-connection-per-server=16
# Set max download speed per download in bytes/sec. 0 means unrestricted. Default: 0
max-download-limit=0
# Set max overall download speed in bytes/sec. 0 means unrestricted. Default: 0
max-overall-download-limit=0
# Set max overall upload speed in bytes/sec. 0 means unrestricted. Default: 0
max-overall-upload-limit=0
# Set max upload speed per torrent in bytes/sec. 0 means unrestricted. Default: 0
max-upload-limit=0
# When used with --always-resume=false, aria2 downloads the file from scratch when aria2 detects N number of URIs that do not support resumes. If N is 0, aria2 downloads the file from scratch when all given URIs do not support resume. See --always-resume option. Default: 0
max-resume-failure-tries=3
# Set the number of tries. 0 means unlimited. See also --retry-wait. Default: 5
max-tries=3
# Specify preferred protocol. The possible values are http, https, ftp, and none. Specify none to disable this feature. Default: none
metalink-preferred-protocol=none
# aria2 does not split less than 2*SIZE byte range. Possible Values: 1M -1024M. Default: 20M
min-split-size=20M
min-tls-version=TLSv1.2
# No file allocation is made for files whose size is smaller than SIZE. Default: 5M
no-file-allocation-limit=8M
# Disables netrc support. netrc support is enabled by default.
no-netrc=true
# Optimizes the number of concurrent downloads according to the bandwidth available. aria2 uses the download speed observed in the previous downloads to adapt the number of downloads launched in parallel according to the rule N = A + B Log10(speed in Mbps). The coefficients A and B can be customized in the option arguments with A and B separated by a colon. The default values (A=5, B=25) lead to using typically 5 parallel downloads on 1Mbps networks and above 50 on 100Mbps networks. The number of parallel downloads remains constrained under the maximum defined by the --max-concurrent-downloads parameter. Default: false
optimize-concurrent-downloads=false
# Pause download after added. This option is effective only when --enable-rpc=true is given. Default: false
pause=false
# Specify the string used during the BitTorrent extended handshake for the peer’s client version. Default: aria2/$MAJOR.$MINOR.$PATCH, $MAJOR, $MINOR, and $PATCH are replaced by major, minor and patch version number respectively. For instance, aria2 version 1.18.8 has peer agent aria2/1.18.8.
peer-agent=qBittorrent v4.3.9
# Set the method to use in proxy requests. METHOD is either get or tunnel. HTTPS downloads always use tunnel regardless of this option. Default: get
proxy-method=get
# Make aria2 quiet (no console output). Default: false
quiet=false
# Set an http referrer (Referer). This affects all http/https downloads. If * is given, the download URI is also used as the referrer. This may be useful when used together with the --parameterized-uri option
referer=*
# Remove the control file before downloading. Using --allow-overwrite=true, the download always starts from scratch. This will be useful for users behind proxy servers which disables resume.
remove-control-file=false
# Set the seconds to wait between retries. When SEC > 0, aria2 will retry downloads when the HTTP server returns a 503 response. Default: 0
retry-wait=3
# Reuse already used URIs if no unused URIs are left. Default: true
reuse-uri=true
# Add Access-Control-Allow-Origin header field with value * to the RPC response. Default: false
rpc-allow-origin-all=true
# Listen to incoming JSON-RPC/XML-RPC requests on all network interfaces. If false is given, listen only on the local loopback interface. Default: false
rpc-listen-all=false
# Specify a port number for JSON-RPC/XML-RPC server to listen to. Possible Values: 1024 -65535 Default: 6800
rpc-listen-port=${rpc_listen_port}
# Set max size of JSON-RPC/XML-RPC request. If aria2 detects the request is more than SIZE bytes, it drops the connection. Default: 2M
rpc-max-request-size=2M
# Save the uploaded torrent or metalink metadata in the directory specified by the --dir option. If false is given to this option, the downloads added will not be saved by the --save-session option. Default: true
rpc-save-upload-metadata=true
# RPC transport will be encrypted by SSL/TLS. The RPC clients must use the https scheme to access the server. For WebSocket clients, use wss scheme. Use --rpc-certificate and --rpc-private-key options to specify the server certificate and private key.
rpc-secure=false
# Set RPC secret authorization token.
rpc-secret=${rpc_secret}
# Save Cookies to FILE in Mozilla/Firefox(1.x/2.x)/ Netscape format. If FILE already exists, it is overwritten. Session Cookies are also saved and their expiry values are treated as 0. Possible Values:
save-cookies=${HOME}/.aria2/cookies.txt
# Save error/unfinished downloads to FILE on exit.
save-session=${HOME}/.aria2/session.txt
# Save error/unfinished downloads to a file specified by the --save-session option every SEC seconds. If 0 is given, the file will be saved only when aria2 exits. Default: 0
save-session-interval=60
# Specify share ratio. Seed completed torrents until the share ratio reaches RATIO. Specify 0.0 if you intend to do seeding regardless of the share ratio. Default: 1.0
seed-ratio=2.0
# Specify the seeding time in (fractional) minutes. Specifying --seed-time=0 disables seeding after the download is completed.
seed-time=0
# Show console readout. Default: true
show-console-readout=true
# Download a file using N connections. The number of connections to the same host is restricted by the --max-connection-per-server option. Default: 5
split=32
# Set the interval in seconds to output the download progress summary. Setting 0 suppresses the output. Default: 60
summary-interval=0
# Comma-separated list of additional BitTorrent trackers announce URI. Reference: https://github.com/ngosang/trackerslist/
bt-tracker=${tracker_list}
# The directory to store the downloaded file.
# Specify the URI selection algorithm. The possible values are in order, feedback, and adaptive. If in order is given, URI is tried in the order that appeared in the URI list. If feedback is given, aria2 uses download speed observed in the previous downloads and choose fastest server in the URI list. This also effectively skips dead mirrors. The observed download speed is a part of performance profile of servers mentioned in --server-stat-of and --server-stat-if options. If adaptive is given, selects one of the best mirrors for the first and reserved connections. For supplementary ones, it returns mirrors which has not been tested yet, and if each of them has already been tested, returns mirrors which has to be tested again. Otherwise, it doesn't select anymore mirrors. Like feedback, it uses a performance profile of servers. Default:
uri-selector=feedback
# Use the HEAD method for the first request to the HTTP server. Default: false
use-head=false
# Set user agent for HTTP(S) downloads. Default: aria2/$VERSION, $VERSION is replaced by package version.
user-agent=${user_agent}
# Set user agent for HTTP(S) downloads. Default: aria2/$VERSION, $VERSION is replaced by package version.
user-agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
EOF

    # CD INTO DIRECTORIES
    if [ -d "${HOME}/.aria2" ]; then
        cd "${HOME}/.aria2" || exit 1
        clear
        printf "%s\n\n" "Printing the file names located in '${HOME}/.aria2'."
        ls -1AhFSv --color --group-directories-first
    else
        printf "%s\n\n" "Could not cd into '${HOME}/.aria2'. Please check the script for errors."
        exit 1
    fi

    printf "\n%s\n\n%s\n%s\n\n" \
        'Input this into the Chrome extension.' \
        "RPC Listen Port: ${rpc_listen_port}" \
        "RPC Secret: ${rpc_secret}"

    aria2c --conf-path="${HOME}"/.aria2/aria2.conf
}

stop_aria2_fn()
{
    clear

    printf "%s\n\n" 'Stopping Aria2c...'

    if sudo killall -9 aria2c; then
        printf "%s\n\n" 'Success!'
    else
        printf "%s\n\n" 'Failed!'
    fi
}

printf "%s\n\n%s\n%s\n%s\n\n" \
    'Aria2 switch script' \
    '[1] Start Process' \
    '[2] Stop Process' \
    '[3] Exit'
read -p 'Your choices are (1 to 3): ' answer
clear

case "${answer}" in
    1) start_aria2_fn;;
    2) stop_aria2_fn;;
    3) exit 0;;
esac
