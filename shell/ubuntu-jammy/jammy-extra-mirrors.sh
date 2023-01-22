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
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
#
#########################################
##                                     ##
##  20Gbps mirrors [ unsecured HTTP ]  ##
##                                     ##
#########################################
#
# MAIN
#
deb [trusted=yes] http://mirror.enzu.com/ubuntu/ jammy main restricted universe multiverse
deb [trusted=yes] http://mirror.genesisadaptive.com/ubuntu/ jammy main restricted universe multiverse
deb [trusted=yes] http://mirror.math.princeton.edu/pub/ubuntu/ jammy main restricted universe multiverse
deb [trusted=yes] http://mirror.pit.teraswitch.com/ubuntu/ jammy main restricted universe multiverse
#
# UPDATES
#
deb [trusted=yes] http://mirror.enzu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb [trusted=yes] http://mirror.genesisadaptive.com/ubuntu/ jammy-updates main restricted universe multiverse
deb [trusted=yes] http://mirror.math.princeton.edu/pub/ubuntu/ jammy-updates main restricted universe multiverse
deb [trusted=yes] http://mirror.pit.teraswitch.com/ubuntu/ jammy-updates main restricted universe multiverse
#
# BACKPORTS
#
deb [trusted=yes] http://mirror.enzu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb [trusted=yes] http://mirror.genesisadaptive.com/ubuntu/ jammy-backports main restricted universe multiverse
deb [trusted=yes] http://mirror.math.princeton.edu/pub/ubuntu/ jammy-backports main restricted universe multiverse
deb [trusted=yes] http://mirror.pit.teraswitch.com/ubuntu/ jammy-backports main restricted universe multiverse

########################################
##                                    ##
##  10Gbps mirrors [ secured HTTPS ]  ##
##                                    ##
########################################
#
# MAIN
#
deb [trusted=yes] https://atl.mirrors.clouvider.net/ubuntu/ jammy main restricted universe multiverse
deb [trusted=yes] https://mirror.fcix.net/ubuntu/ jammy main restricted universe multiverse
deb [trusted=yes] https://mirror.lstn.net/ubuntu/ jammy main restricted universe multiverse
deb [trusted=yes] https://mirror.stjschools.org/ubuntu/ jammy main restricted universe multiverse
deb [trusted=yes] https://mirror.us.leaseweb.net/ubuntu/ jammy main restricted universe multiverse
deb [trusted=yes] https://mirrors.bloomu.edu/ubuntu/ jammy main restricted universe multiverse
# deb [trusted=yes] https://dal.mirrors.clouvider.net/ubuntu/ jammy main restricted universe multiverse
# deb [trusted=yes] https://la.mirrors.clouvider.net/ubuntu/ jammy main restricted universe multiverse
# deb [trusted=yes] https://mirrors.egr.msu.edu/ubuntu/ jammy main restricted universe multiverse
# deb [trusted=yes] https://mirrors.iu13.net/ubuntu/ jammy main restricted universe multiverse
# deb [trusted=yes] https://mirrors.wikimedia.org/ubuntu/ jammy main restricted universe multiverse
# deb [trusted=yes] https://mirrors.xtom.com/ubuntu/ jammy main restricted universe multiverse
# deb [trusted=yes] https://nyc.mirrors.clouvider.net/ubuntu/ jammy main restricted universe multiverse
# deb [trusted=yes] https://ubuntu.mirror.shastacoe.net/ubuntu/ jammy main restricted universe multiverse
#
# UPDATES
#
deb [trusted=yes] https://atl.mirrors.clouvider.net/ubuntu/ jammy-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.fcix.net/ubuntu/ jammy-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.lstn.net/ubuntu/ jammy-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.stjschools.org/ubuntu/ jammy-updates main restricted universe multiverse
deb [trusted=yes] https://mirror.us.leaseweb.net/ubuntu/ jammy-updates main restricted universe multiverse
deb [trusted=yes] https://mirrors.bloomu.edu/ubuntu/ jammy-updates main restricted universe multiverse
# deb [trusted=yes] https://dal.mirrors.clouvider.net/ubuntu/ jammy-updates main restricted universe multiverse
# deb [trusted=yes] https://la.mirrors.clouvider.net/ubuntu/ jammy-updates main restricted universe multiverse
# deb [trusted=yes] https://mirrors.egr.msu.edu/ubuntu/ jammy-updates main restricted universe multiverse
# deb [trusted=yes] https://mirrors.iu13.net/ubuntu/ jammy-updates main restricted universe multiverse
# deb [trusted=yes] https://mirrors.wikimedia.org/ubuntu/ jammy-updates main restricted universe multiverse
# deb [trusted=yes] https://mirrors.xtom.com/ubuntu/ jammy-updates main restricted universe multiverse
# deb [trusted=yes] https://nyc.mirrors.clouvider.net/ubuntu/ jammy-updates main restricted universe multiverse
# deb [trusted=yes] https://ubuntu.mirror.shastacoe.net/ubuntu/ jammy-updates main restricted universe multiverse
#
# BACKPORTS
#
deb [trusted=yes] https://atl.mirrors.clouvider.net/ubuntu/ jammy-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.fcix.net/ubuntu/ jammy-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.lstn.net/ubuntu/ jammy-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.stjschools.org/ubuntu/ jammy-backports main restricted universe multiverse
deb [trusted=yes] https://mirror.us.leaseweb.net/ubuntu/ jammy-backports main restricted universe multiverse
deb [trusted=yes] https://mirrors.bloomu.edu/ubuntu/ jammy-backports main restricted universe multiverse
# deb [trusted=yes] https://dal.mirrors.clouvider.net/ubuntu/ jammy-backports main restricted universe multiverse
# deb [trusted=yes] https://la.mirrors.clouvider.net/ubuntu/ jammy-backports main restricted universe multiverse
# deb [trusted=yes] https://mirrors.egr.msu.edu/ubuntu/ jammy-backports main restricted universe multiverse
# deb [trusted=yes] https://mirrors.iu13.net/ubuntu/ jammy-backports main restricted universe multivers
# deb [trusted=yes] https://mirrors.wikimedia.org/ubuntu/ jammy-backports main restricted universe multiverse
# deb [trusted=yes] https://mirrors.xtom.com/ubuntu/ jammy-backports main restricted universe multiverse
# deb [trusted=yes] https://nyc.mirrors.clouvider.net/ubuntu/ jammy-backports main restricted universe multiverse
# deb [trusted=yes] https://ubuntu.mirror.shastacoe.net/ubuntu/ jammy-backports main restricted universe multiverse
EOT

# Open in editor to verify file contents
if which nano; then
    nano "${HOME}/.bashrc"
else
    vi "${HOME}/.bashrc"
fi
