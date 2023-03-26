#!/bin/bash

clear

FILE='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "${FILE}.bak" ]; then cp -f "${FILE}" "${FILE}.bak"; fi

cat <<EOT > "${FILE}"
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
deb [trusted=yes] http://mirror.enzu.com/ubuntu/ bionic main restricted universe multiverse
deb [trusted=yes] http://mirror.genesisadaptive.com/ubuntu/ bionic main restricted universe multiverse
deb [trusted=yes] http://mirror.math.princeton.edu/pub/ubuntu/ bionic main restricted universe multiverse
deb [trusted=yes] http://mirror.pit.teraswitch.com/ubuntu/ bionic main restricted universe multiverse
#
# UPDATES
#
deb [trusted=yes] http://mirror.enzu.com/ubuntu/ bionic-updates main restricted universe multiverse
deb [trusted=yes] http://mirror.genesisadaptive.com/ubuntu/ bionic-updates main restricted universe multiverse
deb [trusted=yes] http://mirror.math.princeton.edu/pub/ubuntu/ bionic-updates main restricted universe multiverse
deb [trusted=yes] http://mirror.pit.teraswitch.com/ubuntu/ bionic-updates main restricted universe multiverse
#
# BACKPORTS
#
deb [trusted=yes] http://mirror.enzu.com/ubuntu/ bionic-backports main restricted universe multiverse
deb [trusted=yes] http://mirror.genesisadaptive.com/ubuntu/ bionic-backports main restricted universe multiverse
deb [trusted=yes] http://mirror.math.princeton.edu/pub/ubuntu/ bionic-backports main restricted universe multiverse
deb [trusted=yes] http://mirror.pit.teraswitch.com/ubuntu/ bionic-backports main restricted universe multiverse

########################################
##                                    ##
##  10Gbps mirrors [ secured HTTPS ]  ##
##                                    ##
########################################
#
# MAIN
#
deb [trusted=yes] https://atl.mirrors.clouvider.net/ubuntu/ bionic main restricted universe multiverse
deb [trusted=yes] https://mirror.fcix.net/ubuntu/ bionic main restricted universe multiverse
deb [trusted=yes] https://mirror.lstn.net/ubuntu/ bionic main restricted universe multiverse
deb [trusted=yes] https://mirror.us.leaseweb.net/ubuntu/ bionic main restricted universe multiverse
deb [trusted=yes] https://mirrors.bloomu.edu/ubuntu/ bionic main restricted universe multiverse
deb [trusted=yes] https://mirrors.wikimedia.org/ubuntu/ bionic main restricted universe multiverse
deb [trusted=yes] https://mirrors.xtom.com/ubuntu/ bionic main restricted universe multiverse
# deb [trusted=yes] https://dal.mirrors.clouvider.net/ubuntu/ bionic main restricted universe multiverse
# deb [trusted=yes] https://la.mirrors.clouvider.net/ubuntu/ bionic main restricted universe multiverse
# deb [trusted=yes] https://mirrors.egr.msu.edu/ubuntu/ bionic main restricted universe multiverse
# deb [trusted=yes] https://mirrors.iu13.net/ubuntu/ bionic main restricted universe multiverse
# deb [trusted=yes] https://nyc.mirrors.clouvider.net/ubuntu/ bionic main restricted universe multiverse
# deb [trusted=yes] https://ubuntu.mirror.shastacoe.net/ubuntu/ bionic main restricted universe multiverse
#
# UPDATES
#
deb [trusted=yes] https://atl.mirrors.clouvider.net/ubuntu/ bionic-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.fcix.net/ubuntu/ bionic-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.lstn.net/ubuntu/ bionic-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.us.leaseweb.net/ubuntu/ bionic-updates main restricted universe multiverse
deb [trusted=yes] https://mirrors.bloomu.edu/ubuntu/ bionic-updates main restricted universe multiverse
deb [trusted=yes] https://mirrors.wikimedia.org/ubuntu/ bionic-updates main restricted universe multiverse
deb [trusted=yes] https://mirrors.xtom.com/ubuntu/ bionic-updates main restricted universe multiverse
# deb [trusted=yes] https://dal.mirrors.clouvider.net/ubuntu/ bionic-updates main restricted universe multiverse
# deb [trusted=yes] https://la.mirrors.clouvider.net/ubuntu/ bionic-updates main restricted universe multiverse
# deb [trusted=yes] https://mirrors.egr.msu.edu/ubuntu/ bionic-updates main restricted universe multiverse
# deb [trusted=yes] https://mirrors.iu13.net/ubuntu/ bionic-updates main restricted universe multiverse
# deb [trusted=yes] https://nyc.mirrors.clouvider.net/ubuntu/ bionic-updates main restricted universe multiverse
# deb [trusted=yes] https://ubuntu.mirror.shastacoe.net/ubuntu/ bionic-updates main restricted universe multiverse
#
# BACKPORTS
#
deb [trusted=yes] https://atl.mirrors.clouvider.net/ubuntu/ bionic-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.fcix.net/ubuntu/ bionic-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.lstn.net/ubuntu/ bionic-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.us.leaseweb.net/ubuntu/ bionic-backports main restricted universe multiverse
deb [trusted=yes] https://mirrors.bloomu.edu/ubuntu/ bionic-backports main restricted universe multiverse
deb [trusted=yes] https://mirrors.wikimedia.org/ubuntu/ bionic-backports main restricted universe multiverse
deb [trusted=yes] https://mirrors.xtom.com/ubuntu/ bionic-backports main restricted universe multiverse
# deb [trusted=yes] https://dal.mirrors.clouvider.net/ubuntu/ bionic-backports main restricted universe multiverse
# deb [trusted=yes] https://la.mirrors.clouvider.net/ubuntu/ bionic-backports main restricted universe multiverse
# deb [trusted=yes] https://mirrors.egr.msu.edu/ubuntu/ bionic-backports main restricted universe multiverse
# deb [trusted=yes] https://mirrors.iu13.net/ubuntu/ bionic-backports main restricted universe multivers
# deb [trusted=yes] https://nyc.mirrors.clouvider.net/ubuntu/ bionic-backports main restricted universe multiverse
# deb [trusted=yes] https://ubuntu.mirror.shastacoe.net/ubuntu/ bionic-backports main restricted universe multiverse
EOT

# Open in editor to verify file contents
if which gedit &> /dev/null; then
    gedit "${FILE}"
elif which nano &> /dev/null; then
    nano "${FILE}"
elif which vim &> /dev/null; then
    vim "${FILE}"
else
    vi "${FILE}"
fi
