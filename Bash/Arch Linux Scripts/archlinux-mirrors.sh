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

# Make a backup of the file
if [[ ! -f "$config_list.bak" ]]; then
    cp -f "$config_list" "$config_list.bak"
fi
if [[ ! -f "$server_list.bak" ]]; then
    cp -f "$server_list" "$server_list.bak"
fi

cat > "$config_list" <<'EOF'
#
# /etc/pacman.conf
#
# See the pacman.conf(5) manpage for option and repository directives
#
# GENERAL OPTIONS
#
[options]
# The following paths are commented out with their default values listed.
# If you wish to use different paths, uncomment and update the paths.
#RootDir     = /
#DBPath      = /var/lib/pacman/
#CacheDir    = /var/cache/pacman/pkg/
#LogFile     = /var/log/pacman.log
#GPGDir      = /etc/pacman.d/gnupg/
#HookDir     = /etc/pacman.d/hooks/
HoldPkg     = pacman glibc
#XferCommand = /usr/bin/curl -L -C - -f -o %o %u
#XferCommand = /usr/bin/wget --passive-ftp -c -O %o %u
#CleanMethod = KeepInstalled
Architecture = auto

# Pacman won't upgrade packages listed in IgnorePkg and members of IgnoreGroup
#IgnorePkg   =
#IgnoreGroup =

#NoUpgrade   =
#NoExtract   =

# Misc options
#UseSyslog
Color
#NoProgressBar
# We cannot check disk space from within a chroot environment
#CheckSpace
VerbosePkgLists
ParallelDownloads = 10

# By default, pacman accepts packages signed by keys that its local keyring
# trusts (see pacman-key and its man page), as well as unsigned packages.
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
RemoteFileSigLevel = Required

# NOTE: You must run `pacman-key --init` before first using pacman; the local
# keyring can then be populated with the keys of all official Arch Linux
# packagers with `pacman-key --populate archlinux`.

#
# REPOSITORIES
#   - can be defined here or included from another file
#   - pacman will search repositories in the order defined here
#   - local/custom mirrors can be added here or in separate files
#   - repositories listed first will take precedence when packages
#     have identical names, regardless of version number
#   - URLs will have $repo replaced by the name of the current repo
#   - URLs will have $arch replaced by the name of the architecture
#
# Repository entries are of the format:
#       [repo-name]
#       Server = ServerName
#       Include = IncludePath
#
# The header [repo-name] is crucial - it must be present and
# uncommented to enable the repo.
#

# The testing repositories are disabled by default. To enable, uncomment the
# repo name header and Include lines. You can add preferred servers immediately
# after the header, and they will be used before the default mirrors.

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[community]
Include = /etc/pacman.d/mirrorlist

#[testing]
#Include = /etc/pacman.d/mirrorlist

#[community-testing]
#Include = /etc/pacman.d/mirrorlist
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

# Open an editor to view the changes
if command -v nano &>/dev/null; then
    nano "$fname"
else
    echo -e "\\nThe script failed to locate nano to open the file...\\n"
fi

script_path=$(readlink -f "${BASH_SOURCE[0]}")
script_name=$(basename "$script_path")

[[ -f "$script_name" ]] && rm "$script_name"
