#!/bin/bash

clear

fname='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "$fname.bak" ]; then cp -f "$fname" "$fname.bak"; fi

cat <<EOT > "$fname"
##       UBUNTU FOCAL
##
##        v22.04.5
##   /etc/apt/sources.list
#
### ALL MIRRORS IN EACH CATAGORY ARE LISTED AS BEING IN THE USA
### IF YOU USE ALL THE LISTS YOU CAN RUN INTO APT COMMAND ISSUES THAT
###    STATE THERE ARE TOO MANY FILES AND WHAT NOT. JUST AN FYI FOR YOU.
#
#######################
##  Default Mirrors  ##
#######################
#
deb http://archive.ubuntu.com/ubuntu/ focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ focal-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ focal-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ focal-backports main restricted universe multiverse
#
#########################################
##                                     ##
##  20Gbps mirrors [ unsecured HTTP ]  ##
##                                     ##
#########################################
#
# MAIN
#
deb [trusted=yes] http://mirror.enzu.com/ubuntu/ focal main restricted universe multiverse
deb [trusted=yes] http://mirror.genesisadaptive.com/ubuntu/ focal main restricted universe multiverse
deb [trusted=yes] http://mirror.math.princeton.edu/pub/ubuntu/ focal main restricted universe multiverse
deb [trusted=yes] http://mirror.pit.teraswitch.com/ubuntu/ focal main restricted universe multiverse
#
# UPDATES
#
deb [trusted=yes] http://mirror.enzu.com/ubuntu/ focal-updates main restricted universe multiverse
deb [trusted=yes] http://mirror.genesisadaptive.com/ubuntu/ focal-updates main restricted universe multiverse
deb [trusted=yes] http://mirror.math.princeton.edu/pub/ubuntu/ focal-updates main restricted universe multiverse
deb [trusted=yes] http://mirror.pit.teraswitch.com/ubuntu/ focal-updates main restricted universe multiverse
#
# BACKPORTS
#
deb [trusted=yes] http://mirror.enzu.com/ubuntu/ focal-backports main restricted universe multiverse
deb [trusted=yes] http://mirror.genesisadaptive.com/ubuntu/ focal-backports main restricted universe multiverse
deb [trusted=yes] http://mirror.math.princeton.edu/pub/ubuntu/ focal-backports main restricted universe multiverse
deb [trusted=yes] http://mirror.pit.teraswitch.com/ubuntu/ focal-backports main restricted universe multiverse

########################################
##                                    ##
##  10Gbps mirrors [ secured HTTPS ]  ##
##                                    ##
########################################
#
# MAIN
#
deb [trusted=yes] https://atl.mirrors.clouvider.net/ubuntu/ focal main restricted universe multiverse
deb [trusted=yes] https://mirror.fcix.net/ubuntu/ focal main restricted universe multiverse
deb [trusted=yes] https://mirror.lstn.net/ubuntu/ focal main restricted universe multiverse
deb [trusted=yes] https://mirror.us.leaseweb.net/ubuntu/ focal main restricted universe multiverse
deb [trusted=yes] https://mirrors.bloomu.edu/ubuntu/ focal main restricted universe multiverse
deb [trusted=yes] https://mirrors.wikimedia.org/ubuntu/ focal main restricted universe multiverse
deb [trusted=yes] https://mirrors.xtom.com/ubuntu/ focal main restricted universe multiverse
# deb [trusted=yes] https://dal.mirrors.clouvider.net/ubuntu/ focal main restricted universe multiverse
# deb [trusted=yes] https://la.mirrors.clouvider.net/ubuntu/ focal main restricted universe multiverse
# deb [trusted=yes] https://mirrors.egr.msu.edu/ubuntu/ focal main restricted universe multiverse
# deb [trusted=yes] https://mirrors.iu13.net/ubuntu/ focal main restricted universe multiverse
# deb [trusted=yes] https://nyc.mirrors.clouvider.net/ubuntu/ focal main restricted universe multiverse
# deb [trusted=yes] https://ubuntu.mirror.shastacoe.net/ubuntu/ focal main restricted universe multiverse
#
# UPDATES
#
deb [trusted=yes] https://atl.mirrors.clouvider.net/ubuntu/ focal-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.fcix.net/ubuntu/ focal-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.lstn.net/ubuntu/ focal-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.us.leaseweb.net/ubuntu/ focal-updates main restricted universe multiverse
deb [trusted=yes] https://mirrors.bloomu.edu/ubuntu/ focal-updates main restricted universe multiverse
deb [trusted=yes] https://mirrors.wikimedia.org/ubuntu/ focal-updates main restricted universe multiverse
deb [trusted=yes] https://mirrors.xtom.com/ubuntu/ focal-updates main restricted universe multiverse
# deb [trusted=yes] https://dal.mirrors.clouvider.net/ubuntu/ focal-updates main restricted universe multiverse
# deb [trusted=yes] https://la.mirrors.clouvider.net/ubuntu/ focal-updates main restricted universe multiverse
# deb [trusted=yes] https://mirrors.egr.msu.edu/ubuntu/ focal-updates main restricted universe multiverse
# deb [trusted=yes] https://mirrors.iu13.net/ubuntu/ focal-updates main restricted universe multiverse
# deb [trusted=yes] https://nyc.mirrors.clouvider.net/ubuntu/ focal-updates main restricted universe multiverse
# deb [trusted=yes] https://ubuntu.mirror.shastacoe.net/ubuntu/ focal-updates main restricted universe multiverse
#
# BACKPORTS
#
deb [trusted=yes] https://atl.mirrors.clouvider.net/ubuntu/ focal-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.fcix.net/ubuntu/ focal-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.lstn.net/ubuntu/ focal-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.us.leaseweb.net/ubuntu/ focal-backports main restricted universe multiverse
deb [trusted=yes] https://mirrors.bloomu.edu/ubuntu/ focal-backports main restricted universe multiverse
deb [trusted=yes] https://mirrors.wikimedia.org/ubuntu/ focal-backports main restricted universe multiverse
deb [trusted=yes] https://mirrors.xtom.com/ubuntu/ focal-backports main restricted universe multiverse
# deb [trusted=yes] https://dal.mirrors.clouvider.net/ubuntu/ focal-backports main restricted universe multiverse
# deb [trusted=yes] https://la.mirrors.clouvider.net/ubuntu/ focal-backports main restricted universe multiverse
# deb [trusted=yes] https://mirrors.egr.msu.edu/ubuntu/ focal-backports main restricted universe multiverse
# deb [trusted=yes] https://mirrors.iu13.net/ubuntu/ focal-backports main restricted universe multivers
# deb [trusted=yes] https://nyc.mirrors.clouvider.net/ubuntu/ focal-backports main restricted universe multiverse
# deb [trusted=yes] https://ubuntu.mirror.shastacoe.net/ubuntu/ focal-backports main restricted universe multiverse
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
