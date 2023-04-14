#!/bin/bash

clear

fname='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "${fname}.bak" ]; then cp -f "${fname}" "${fname}.bak"; fi

cat <<EOT > "${fname}"
##      UBUNTU BIONIC
##
##        v22.04.1
##  /etc/apt/sources.list
#
### ALL MIRRORS IN EACH CATAGORY ARE LISTED AS BEING IN THE USA
### IF YOU USE ALL THE LISTS YOU CAN RUN INTO APT COMMAND ISSUES THAT
###    STATE THERE ARE TOO MANY fnameS AND WHAT NOT. JUST AN FYI FOR YOU.
#
#######################
##  Default Mirrors  ##
#######################
#
deb http://archive.ubuntu.com/ubuntu/ bionic main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ bionic-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ bionic-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ bionic-backports main restricted universe multiverse
#
#########################################
##                                     ##
##  20Gbps mirrors [ unsecured HTTP ]  ##
##                                     ##
#########################################
#
# MAIN
#
deb http://mirror.enzu.com/ubuntu/ bionic main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ bionic main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ bionic main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ bionic main restricted universe multiverse
#
# UPDATES
#
deb http://mirror.enzu.com/ubuntu/ bionic-updates main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ bionic-updates main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ bionic-updates main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ bionic-updates main restricted universe multiverse
#
# BACKPORTS
#
deb http://mirror.enzu.com/ubuntu/ bionic-backports main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ bionic-backports main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ bionic-backports main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ bionic-backports main restricted universe multiverse

########################################
##                                    ##
##  10Gbps mirrors [ secured HTTPS ]  ##
##                                    ##
########################################
#
# MAIN
#
deb https://atl.mirrors.clouvider.net/ubuntu/ bionic main restricted universe multiverse
deb https://mirror.fcix.net/ubuntu/ bionic main restricted universe multiverse
deb https://mirror.lstn.net/ubuntu/ bionic main restricted universe multiverse
deb https://mirror.us.leaseweb.net/ubuntu/ bionic main restricted universe multiverse
deb https://mirrors.bloomu.edu/ubuntu/ bionic main restricted universe multiverse
deb https://mirrors.wikimedia.org/ubuntu/ bionic main restricted universe multiverse
deb https://mirrors.xtom.com/ubuntu/ bionic main restricted universe multiverse
# deb https://dal.mirrors.clouvider.net/ubuntu/ bionic main restricted universe multiverse
# deb https://la.mirrors.clouvider.net/ubuntu/ bionic main restricted universe multiverse
# deb https://mirrors.egr.msu.edu/ubuntu/ bionic main restricted universe multiverse
# deb https://mirrors.iu13.net/ubuntu/ bionic main restricted universe multiverse
# deb https://nyc.mirrors.clouvider.net/ubuntu/ bionic main restricted universe multiverse
# deb https://ubuntu.mirror.shastacoe.net/ubuntu/ bionic main restricted universe multiverse
#
# UPDATES
#
deb https://atl.mirrors.clouvider.net/ubuntu/ bionic-updates main restricted universe multiverse
deb https://mirror.fcix.net/ubuntu/ bionic-updates main restricted universe multiverse
deb https://mirror.lstn.net/ubuntu/ bionic-updates main restricted universe multiverse
deb https://mirror.us.leaseweb.net/ubuntu/ bionic-updates main restricted universe multiverse
deb https://mirrors.bloomu.edu/ubuntu/ bionic-updates main restricted universe multiverse
deb https://mirrors.wikimedia.org/ubuntu/ bionic-updates main restricted universe multiverse
deb https://mirrors.xtom.com/ubuntu/ bionic-updates main restricted universe multiverse
# deb https://dal.mirrors.clouvider.net/ubuntu/ bionic-updates main restricted universe multiverse
# deb https://la.mirrors.clouvider.net/ubuntu/ bionic-updates main restricted universe multiverse
# deb https://mirrors.egr.msu.edu/ubuntu/ bionic-updates main restricted universe multiverse
# deb https://mirrors.iu13.net/ubuntu/ bionic-updates main restricted universe multiverse
# deb https://nyc.mirrors.clouvider.net/ubuntu/ bionic-updates main restricted universe multiverse
# deb https://ubuntu.mirror.shastacoe.net/ubuntu/ bionic-updates main restricted universe multiverse
#
# BACKPORTS
#
deb https://atl.mirrors.clouvider.net/ubuntu/ bionic-backports main restricted universe multiverse
deb https://mirror.fcix.net/ubuntu/ bionic-backports main restricted universe multiverse
deb https://mirror.lstn.net/ubuntu/ bionic-backports main restricted universe multiverse
deb https://mirror.us.leaseweb.net/ubuntu/ bionic-backports main restricted universe multiverse
deb https://mirrors.bloomu.edu/ubuntu/ bionic-backports main restricted universe multiverse
deb https://mirrors.wikimedia.org/ubuntu/ bionic-backports main restricted universe multiverse
deb https://mirrors.xtom.com/ubuntu/ bionic-backports main restricted universe multiverse
# deb https://dal.mirrors.clouvider.net/ubuntu/ bionic-backports main restricted universe multiverse
# deb https://la.mirrors.clouvider.net/ubuntu/ bionic-backports main restricted universe multiverse
# deb https://mirrors.egr.msu.edu/ubuntu/ bionic-backports main restricted universe multiverse
# deb https://mirrors.iu13.net/ubuntu/ bionic-backports main restricted universe multivers
# deb https://nyc.mirrors.clouvider.net/ubuntu/ bionic-backports main restricted universe multiverse
# deb https://ubuntu.mirror.shastacoe.net/ubuntu/ bionic-backports main restricted universe multiverse
EOT

# Open in editor to verify file contents
if which gedit &> /dev/null; then
    gedit "${fname}"
elif which nano &> /dev/null; then
    nano "${fname}"
elif which vim &> /dev/null; then
    vim "${fname}"
else
    vi "${fname}"
fi
