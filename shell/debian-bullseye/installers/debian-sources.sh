#!/bin/bash

clear

FILE='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "${FILE}.bak" ]; then
    cp -f "${FILE}" "${FILE}.bak"
fi

cat <<EOT > "${FILE}"
###########################
##     DEBIAN BULLSEYE
##
##         v11
##  /etc/apt/sources.list
##
###########################

### ALL MIRRORS IN EACH CATAGORY ARE LISTED AS BEING IN THE USA
### IF YOU USE ALL THE LISTS YOU CAN RUN INTO APT COMMAND ISSUES THAT
###    STATE THERE ARE TOO MANY FILES AND WHAT NOT. JUST AN FYI FOR YOU.

#######################
##  Default Mirrors  ##
#######################
deb http://deb.debian.org/debian bullseye main
deb http://deb.debian.org/debian bullseye-updates main
deb http://security.debian.org/debian-security bullseye-security main
deb http://ftp.debian.org/debian bullseye-backports main

# MAIN
deb http://atl.mirrors.clouvider.net/debian bullseye main
deb http://debian.mirror.constant.com/debian bullseye main
deb http://debian.osuosl.org/debian bullseye main
deb http://ftp.us.debian.org/debian bullseye main
deb http://mirror.cogentco.com/debian bullseye main
deb http://mirror.steadfast.net/debian bullseye main
deb http://mirror.us.leaseweb.net/debian bullseye main
deb http://mirrors.wikimedia.org/debian bullseye main
deb http://nyc.mirrors.clouvider.net/debian bullseye main

# UPDATES
deb http://atl.mirrors.clouvider.net/debian bullseye-updates main
deb http://debian.mirror.constant.com/debian bullseye-updates main
deb http://debian.osuosl.org/debian bullseye-updates main
deb http://ftp.us.debian.org/debian bullseye-updates main
deb http://mirror.cogentco.com/debian bullseye-updates main
deb http://mirror.steadfast.net/debian bullseye-updates main
deb http://mirror.us.leaseweb.net/debian bullseye-updates main
deb http://mirrors.wikimedia.org/debian bullseye-updates main
deb http://nyc.mirrors.clouvider.net/debian bullseye-updates main

# BACKPORTS
deb http://atl.mirrors.clouvider.net/debian bullseye-backports main
deb http://debian.mirror.constant.com/debian bullseye-backports main
deb http://debian.osuosl.org/debian bullseye-backports main
deb http://ftp.us.debian.org/debian bullseye-backports main
deb http://mirror.cogentco.com/debian bullseye-backports main
deb http://mirror.steadfast.net/debian bullseye-backports main
deb http://mirror.us.leaseweb.net/debian bullseye-backports main
deb http://mirrors.wikimedia.org/debian bullseye-backports main
deb http://nyc.mirrors.clouvider.net/debian bullseye-backports main
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
