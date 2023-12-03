#!/usr/bin/env bash

clear

if [ "${EUID}" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script with root/sudo permissions.'
    exit 1
fi

printf "%s\n%s\n\n"                                           \
    'Creating a custom config file for the ld linker'         \
    '======================================================='
sleep 2

cat > '/etc/ld.so.conf.d/user-local-libs.conf' <<'EOF'
/usr/local/x86_64-linux-gnu/lib
/usr/local/cuda/nvvm/lib64
/usr/local/cuda/targets/x86_64-linux/lib
/usr/local/lib64
/usr/local/lib
/usr/lib64
/usr/lib
/lib64
/lib
EOF

sudo ldconfig
