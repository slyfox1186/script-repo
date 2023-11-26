#!/usr/bin/env bash

clear

if [ "${EUID}" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script with root/sudo permissions.'
    exit 1
fi

printf "%s\n%s\n\n"                                           \
    'Creating a custom config file for the ld linker command' \
    '======================================================='
sleep 2

cat > '/etc/ld.so.conf.d/jman-custom-libraries.conf' <<'EOF'
/ust/local/lib64
/ust/local/lib
/usr/share/texinfo/lib
/usr/local/x86_64-linux-gnu/lib
/usr/local/ssl/lib
/usr/local/lib64
/usr/local/lib
/usr/local/cuda-12.3/targets/x86_64-linux/lib
/usr/local/cuda-12.3/nvvm/lib64
/usr/lib64
/usr/lib
/lib/x86_64-linux-gnu
/lib64
/lib
EOF

random_dir="$(mktemp -d)"

# REMOVE ANY DUPLICATE LINES TO AVOIDE UNWATED LINKER OVERLOAD
awk '!NF || !seen[$0]++' '/etc/ld.so.conf.d/jman-custom-libraries.conf' > "${random_dir}/jman-custom-libraries.conf"
sudo cp -f "${random_dir}/jman-custom-libraries.conf" '/etc/ld.so.conf.d/'
sudo rm -fr "${random_dir}"

clear
sudo ldconfig -v
