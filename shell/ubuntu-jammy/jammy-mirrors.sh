#!/bin/bash

clear

fname='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "$fname.bak" ]; then cp -f "$fname" "$fname.bak"; fi

cat <<EOT > "$fname"
#!/bin/bash

clear

FILE='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "$fname.bak" ]; then cp -f "$fname" "$fname.bak"; fi

cat <<EOT > "$fname"
##      UBUNTU JAMMY
##
##        v22.04.1
##  /etc/apt/sources.list
#
### ALL MIRRORS IN EACH CATAGORY ARE LISTED AS BEING IN THE USA
### IF YOU USE ALL THE LISTS YOU CAN RUN INTO APT COMMAND ISSUES THAT
###    STATE THERE ARE TOO MANY FILES AND WHAT NOT. JUST AN FYI FOR YOU.
#
#######################
##  Default Mirrors  ##
#######################
#
# deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
# deb-src http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
#
#########################################
##                                     ##
##  20Gbps mirrors [ unsecured HTTP ]  ##
##                                     ##
#########################################
#
# MAIN
#
deb http://mirror.enzu.com/ubuntu/ jammy main restricted universe multiverse
deb-src http://mirror.enzu.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ jammy main restricted universe multiverse
deb-src http://mirror.genesisadaptive.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ jammy main restricted universe multiverse
deb-src http://mirror.math.princeton.edu/pub/ubuntu/ jammy main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ jammy main restricted universe multiverse
deb-src http://mirror.pit.teraswitch.com/ubuntu/ jammy main restricted universe multiverse
#
# UPDATES
#
deb http://mirror.enzu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb-src http://mirror.enzu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ jammy-updates main restricted universe multiverse
deb-src http://mirror.genesisadaptive.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ jammy-updates main restricted universe multiverse
deb-src http://mirror.math.princeton.edu/pub/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ jammy-updates main restricted universe multiverse
deb-src http://mirror.pit.teraswitch.com/ubuntu/ jammy-updates main restricted universe multiverse
#
# BACKPORTS
#
deb http://mirror.enzu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb-src http://mirror.enzu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ jammy-backports main restricted universe multiverse
deb-src http://mirror.genesisadaptive.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ jammy-backports main restricted universe multiverse
deb-src http://mirror.math.princeton.edu/pub/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ jammy-backports main restricted universe multiverse
deb-src http://mirror.pit.teraswitch.com/ubuntu/ jammy-backports main restricted universe multiverse
EOT

# Open in editor to verify file contents
if which gedit &>/dev/null; then
    gedit "$fname"
elif which nano &>/dev/null; then
    nano "$fname"
elif which vim &>/dev/null; then
    vim "$fname"
else
    vi "$fname"
fi
