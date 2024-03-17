#!/Usr/bin/env bash

clear

if [ "$EUID" -ne '0' ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

file=/usr/share/dbus-1/services/org.freedesktop.Notifications.service

cat > "$file" <<EOF
[D-BUS Service]
Name=org.freedesktop.Notifications
Exec=/usr/lib/notification-daemon-1.0/notification-daemon
EOF
