#!/usr/bin/env bash

# Source common utilities
source "$(dirname "$0")/common-utils.sh"

# Verify the script has root access before continuing
require_root

fname=/etc/apt/sources.list

# Make a backup of the sources list
backup_file "$fname"

cat > "$fname" <<'EOF'
# clouvider.net - Atlanta, GA
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy-updates main restricted universe multiverse
deb https://atl.mirrors.clouvider.net/ubuntu/ jammy-backports main restricted universe multiverse

# Ubuntu Security
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse

# pilotfiber.com
# deb https://mirror.pilotfiber.com/ubuntu/ jammy main restricted universe multiverse
# deb https://mirror.pilotfiber.com/ubuntu/ jammy-updates main restricted universe multiverse
# deb https://mirror.pilotfiber.com/ubuntu/ jammy-backports main restricted universe multiverse

# teraswitch.com
# deb http://mirror.pit.teraswitch.com/ubuntu/ jammy main restricted universe multiverse
# deb http://mirror.pit.teraswitch.com/ubuntu/ jammy-updates main restricted universe multiverse
# deb http://mirror.pit.teraswitch.com/ubuntu/ jammy-backports main restricted universe multiverse
EOF

# Open an editor to view the changes
open_editor "$fname"
