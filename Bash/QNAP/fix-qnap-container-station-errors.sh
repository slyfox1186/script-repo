#!/usr/bin/env bash



container_volume1="/share/<FOLDER HERE>/Container"

container_volume2="/share/<FOLDER HERE>/.qpkg"

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Use as $0 [set|unset] <UID>"
  exit 1
fi

if [ "$1" == "set" ]; then
    setfacl -m user:$2:rx "$container_volume1"
    setfacl -m user:$2:rx "$container_volume1"/container-station-data/lib
    setfacl -m user:$2:rx "$container_volume1"/container-station-data/lib/lxd
    setfacl -m user:$2:rx "$container_volume2"/container-station
    setfacl -m user:$2:rx "$container_volume2"/container-station/lib
    setfacl -m user:$2:rx "$container_volume2"/container-station/var
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
