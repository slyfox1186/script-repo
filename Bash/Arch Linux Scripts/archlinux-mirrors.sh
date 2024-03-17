#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

<<<<<<< Updated upstream
=======
script_path=$(readlink -f "$BASH_SOURCE[0]")
script_name=$(basename "$script_path")

>>>>>>> Stashed changes
config_list="/etc/pacman.conf"
server_list="/etc/pacman.d/mirrorlist"

if [[ ! -f "$config_list.bak" ]]; then
    cp -f "$config_list" "$config_list.bak"
fi
if [[ ! -f "$server_list.bak" ]]; then
    cp -f "$server_list" "$server_list.bak"
fi

cat > "$config_list" <<'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto



Color
VerbosePkgLists
ParallelDownloads = 10

SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
RemoteFileSigLevel = Required




[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[community]
Include = /etc/pacman.d/mirrorlist


EOF

cat > "$server_list" <<'EOF'
Server = https://forksystems.mm.fcix.net/archlinux/$repo/os/$arch
Server = https://america.mirror.pkgbuild.com/$repo/os/$arch
Server = https://arch.mirror.constant.com/$repo/os/$arch
Server = https://arlm.tyzoid.com/$repo/os/$arch
Server = https://mirror.mia11.us.leaseweb.net/archlinux/$repo/os/$arch
Server = https://mirror.wdc1.us.leaseweb.net/archlinux/$repo/os/$arch
Server = https://dfw.mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.vectair.net/archlinux/$repo/os/$arch
Server = https://mirrors.rit.edu/archlinux/$repo/os/$arch
Server = https://iad.mirrors.misaka.one/archlinux/$repo/os/$arch
Server = https://ord.mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.bjg.at/arch/$repo/os/$arch
Server = https://irltoolkit.mm.fcix.net/archlinux/$repo/os/$arch
Server = https://archlinux.macarne.com/$repo/os/$arch
Server = https://zxcvfdsa.com/arch/$repo/os/$arch
Server = https://mirror.dal10.us.leaseweb.net/archlinux/$repo/os/$arch
Server = https://mirror.sfo12.us.leaseweb.net/archlinux/$repo/os/$arch
Server = https://archmirror1.octyl.net/$repo/os/$arch
Server = https://ftp.osuosl.org/pub/archlinux/$repo/os/$arch
Server = https://mirrors.mit.edu/archlinux/$repo/os/$arch
EOF

if command -v nano &>/dev/null; then
    nano "$fname"
else
    echo -e "\\nThe script failed to locate nano to open the file...\\n"
fi

script_path=$(readlink -f "${BASH_SOURCE[0]}")
script_name=$(basename "$script_path")

[[ -f "$script_name" ]] && rm "$script_name"
