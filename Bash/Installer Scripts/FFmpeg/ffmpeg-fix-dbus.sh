#!/Usr/bin/env bash

clear

if [ "$EUID" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script as root/sudo.'
    exit 1
fi

file=/usr/share/dbus-1/services/org.freedesktop.Notifications.service

cat > "$file" <<EOF
[D-BUS Service]
Name=org.freedesktop.Notifications
Exec=/usr/lib/notification-daemon-1.0/notification-daemon
EOF
