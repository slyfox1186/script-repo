#!/usr/bin/env bash

# FIX QNAP QuTS HERO ACL PERMISSIONS FOR THE CONTAINER STATION APP.
# WINDOWS CAUSES ACL PERMISSION ERRORS THAT YOU MUST FIX... THE CONTAINERS WONT RUN WITHOUT THIS UNTIL QNAP FIXES IT.
# I AM NOT HOPEFUL BECAUSE I AM BEING ASKED FOR THE SECOND TIME BY QNAP WHAT MY ISSUES ARE AFTER I ALREADY EXPLAINED THEM.

## YOU MUST PASS ARGUMENTS TO THE SCRIPT.
# EXAMPLE: ./fix-qnap-container-station-errors.sh set 1000000

## FOLDER 01
# FIND THE FOLDER THAT CONTAINS THE 'Container' FOLDER
# EXAMPLE: container_volume1="/share/ZFS22_DATA/Container"
container_volume1="/share/<FOLDER HERE>/Container"

## FOLDER 02
# FIND THE FOLDER THAT CONTAINS THE '.qpkg' FOLDER
# EXAMPLE: container_volume2="/share/ZFS530_DATA/.qpkg"
container_volume2="/share/<FOLDER HERE>/.qpkg"

# VERIFY THAT ARGUMENTS WERE PASSED TO THE SCRIPT
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Use as $0 [set|unset] <UID>"
  exit 1
fi

# IF SET OR UNSET IS THE FIRST ARGUMENT RUN THE COMMANDS BELOW
# OTHERWISE THROW AN ERROR
if [ "$1" == "set" ]; then
    setfacl -m user:$2:rx "$container_volume1"
    setfacl -m user:$2:rx "$container_volume1"/container-station-data/lib
    setfacl -m user:$2:rx "$container_volume1"/container-station-data/lib/lxd
    setfacl -m user:$2:rx "$container_volume2"/container-station
    setfacl -m user:$2:rx "$container_volume2"/container-station/lib
    setfacl -m user:$2:rx "$container_volume2"/container-station/var
   # setfacl -R -m user:$2:rx "$container_volume2"/container-station ## RECURSIVE
    setfacl -R -m user:$2:rx "$container_volume2"/container-station/usr
    setfacl -m user:$2:rx /var/lib/lxd
    setfacl -m user:$2:rx /var/lib/lxd/containers
    setfacl -m user:$2:rx /var/lib/lxd/devices
    setfacl -m user:$2:rx /var/lib/lxd/shmounts
    setfacl -m user:$2:rx /var/lib/lxd/snapshots
    setfacl -m user:$2:rx /var/lib/lxd/storage-pools
    setfacl -m user:$2:rx /var/lib/lxd/storage-pools/default/containers
	sleep 2
  elif [ "$1" == "unset" ]; then
    setfacl -R -x user:$2 "$container_volume1"
    setfacl -R -x user:$2 "$container_volume2"/container-station
    setfacl -R -x user:$2 /var/lib/lxd/
    setfacl -x user:$2 /var/lib/lxd
	sleep 2
  else
    echo "Invalid operation"
    exit 1
fi
