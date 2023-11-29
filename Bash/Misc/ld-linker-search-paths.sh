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
/usr/local/ssl/lib
/usr/local/x86_64-linux-gnu/lib
/usr/local/lib64
/usr/local/lib
/usr/local/cuda-12.3/targets/x86_64-linux/lib
/usr/local/cuda-12.3/nvvm/lib64
EOF

clear
sudo ldconfig -v
