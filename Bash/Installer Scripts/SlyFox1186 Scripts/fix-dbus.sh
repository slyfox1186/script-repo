#!/usr/bin/env bash

clear

if [ "${EUID}" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script WITH root/sudo.'
fi

file=/usr/share/dbus-1/services/org.freedesktop.Notifications.service

cat > "${file}" <<'EOF'
[D-BUS Service]
Name=org.freedesktop.Notifications
Exec=/usr/lib/notification-daemon/notification-daemon
EOF
