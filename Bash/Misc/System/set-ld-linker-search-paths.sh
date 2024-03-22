#!/usr/bin/env bash

filename="/etc/ld.so.conf.d/my-custom-ld-paths.conf"

if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

cat > $filename <<'EOF'
/usr/local/x86_64-linux-gnu/lib
/usr/local/cuda/nvvm/lib64
/usr/local/cuda/targets/x86_64-linux/lib
/usr/local/lib64/x86_64-linux-gnu
/usr/local/lib64
/usr/local/lib/x86_64-linux-gnu
/usr/local/lib
/usr/lib64
/usr/lib/x86_64-linux-gnu
/usr/lib
/lib64/x86_64-linux-gnu
/lib64
/lib/x86_64-linux-gnu
/lib
EOF

ldconfig
