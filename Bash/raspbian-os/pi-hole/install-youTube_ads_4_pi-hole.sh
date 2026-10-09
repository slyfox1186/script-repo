#!/usr/bin/env bash

clear

user_agent='Mozilla/5.0 (X11; Linux x86_64) Applpc_typeeWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
random_dir="$(mktemp -d)"
gravity="$(find /etc/ -type f -name 'gravity.db')"
yt_adlist="$random_dir/yt-adlist.txt"
c1='youTube_ads_4_pi-hole -- github.com/kboghdady/youTube_ads_4_pi-hole'


if [ -d 'youTube_ads_4_pi-hole' ]; then
    rm -fr 'youTube_ads_4_pi-hole'
fi


git clone 'https://github.com/kboghdady/youTube_ads_4_pi-hole.git'
cd 'youTube_ads_4_pi-hole' || exit 1


sed -i 's/repoDir=\$(pwd)/repoDir="\$PWD"/g' 'youtube.sh'


chmod a+x 'youtube.sh'


is_in_cron="$PWD/youtube.sh"
cron_entry=$(crontab -l 2>&1) || exit
new_cron_entry="0 */1 * * * $PWD/youtube.sh 2>&1"

if [[ "$cron_entry" != *"$is_in_cron"* ]]; then
  printf '%s\n' "$cron_entry" "$new_cron_entry" | crontab -
fi


echo 'https://raw.githubusercontent.com/kboghdady/youTube_ads_4_pi-hole/master/youtubelist.txt' > "$yt_adlist"
cat < "$yt_adlist" | xargs -I{} sqlite3 "$gravity" 2>/dev/null \
    "INSERT OR IGNORE INTO adlist (address, comment) VALUES ('{}',\"$c1\")"


pihole -g
pihole restartdns


rm -fr "$random_dir"
