#!/usr/bin/env bash

clear

file='/usr/share/dbus-1/services/org.freedesktop.Notifications.service'

cat > "$file" <<EOF
[D-BUS Service]
Name=org.freedesktop.Notifications
Exec=/usr/lib/notification-daemon-1.0/notification-daemon
EOF
