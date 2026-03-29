#!/usr/bin/env bash

# Exit script on error
set -e

# Function to log and display messages
log() {
    echo -e "\e[1;32m$1\e[0m"
}

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo or run as root."
    exit 1
fi

# Cleanup function to handle partial failures
cleanup() {
    log "Cleaning up partial configurations..."
    mdadm --stop /dev/md0 || true
    mdadm --stop /dev/md1 || true
    umount /mnt/raid || true
    rm -rf /mnt/raid
    rm -rf /tmp/cset_uuid
}

# Trap errors and run cleanup
trap cleanup ERR

log "Updating package lists and installing necessary packages..."
apt update
if ! apt install -y mdadm lvm2 bcache-tools nvme-cli; then
    echo "Failed to install required packages."
    exit 1
fi

log "Rescanning SCSI and NVMe buses..."
# Rescan SCSI devices
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done

# Rescan NVMe namespaces
nvme ns-rescan /dev/nvme0 || true
nvme ns-rescan /dev/nvme1 || true
nvme ns-rescan /dev/nvme2 || true

log "Checking for devices..."
lsblk

# HDDs to be included in the RAID 10 array
hdds=("/dev/sdc" "/dev/sdd" "/dev/sde" "/dev/sdf")

# SSDs to be included in the RAID 0 array
ssds=("/dev/nvme1n1" "/dev/nvme2n1")

# Function to check and unmount existing partitions if needed
unmount_drive_if_needed() {
    local drive=$1
    if mount | grep -q "^${drive}"; then
        log "Unmounting ${drive}..."
        if ! umount ${drive}*; then
            echo "Failed to unmount ${drive}"
            exit 1
        fi
    fi
}

# Function to clear any existing RAID metadata
clear_raid_metadata() {
    local drive=$1
    log "Clearing RAID metadata on ${drive}..."
    mdadm --zero-superblock --force ${drive}* || true
}

# Function to stop any active RAID arrays
stop_raid_arrays() {
    log "Stopping any active RAID arrays..."
    mdadm --stop /dev/md0 || true
    mdadm --stop /dev/md1 || true
}

# Function to create new partition tables and partitions
partition_drive() {
    local drive=$1
    if [ ! -b "$drive" ]; then
        echo "Device $drive not found. Please check the device names."
        exit 1
    fi
    unmount_drive_if_needed "$drive"
    clear_raid_metadata "$drive"
    log "Creating GPT partition table on ${drive}..."
    if ! parted -s $drive mklabel gpt; then
        echo "Failed to create partition table on ${drive}"
        exit 1
    fi
    log "Creating primary partition on ${drive}..."
    if ! parted -s -a optimal $drive mkpart primary 0% 100%; then
        echo "Failed to create partition on ${drive}"
        exit 1
    fi
    log "Informing the kernel about partition table changes on ${drive}..."
    if ! partprobe $drive; then
        echo "Failed to inform the kernel about partition table changes on ${drive}. Reboot might be required."
        exit 1
    fi
}

# Stop any active RAID arrays
stop_raid_arrays

# Partition the HDDs and SSDs
for hdd in "${hdds[@]}"; do
    partition_drive "$hdd"
done

for ssd in "${ssds[@]}"; do
    partition_drive "$ssd"
done

# Wait for the kernel to re-read the partition table
sleep 5

# Get the new partition names (assumes they are named drive1, drive2, etc.)
hdd_partitions=("${hdds[@]/%/1}")
ssd_partitions=("${ssds[@]/%/1}")

# Create RAID 10 array with the new HDD partitions
log "Creating RAID 10 array with HDDs..."
if ! mdadm --create --verbose /dev/md0 --level=10 --raid-devices=4 ${hdd_partitions[@]}; then
    echo "Failed to create RAID 10 array"
    exit 1
else
    sleep 1
fi

# Monitor RAID 10 creation progress
log "RAID 10 array creation in progress. This may take some time."
while cat /proc/mdstat | grep -q 'resync'; do
    cat /proc/mdstat
    sleep 10
done

# Create RAID 0 array with the new SSD partitions
log "Creating RAID 0 array with SSDs..."
if ! mdadm --create --verbose /dev/md1 --level=0 --raid-devices=2 ${ssd_partitions[@]}; then
    echo "Failed to create RAID 0 array"
    exit 1
else
    sleep 1
fi

# Monitor RAID 0 creation progress
log "RAID 0 array creation in progress. This may take some time."
while cat /proc/mdstat | grep -q 'resync'; do
    cat /proc/mdstat
    sleep 10
done

# Initialize the RAID 0 array (SSDs) as a cache device
log "Initializing the RAID 0 array as a cache device..."
if ! make-bcache -C /dev/md1; then
    echo "Failed to initialize the cache device"
    exit 1
fi

# Attach the cache to the RAID 10 array (HDDs)
log "Attaching the cache device to the RAID 10 array..."
if ! make-bcache -B /dev/md0; then
    echo "Failed to register the backing device"
    exit 1
fi
bcache-super-show /dev/md0 | grep cset.uuid > /tmp/cset_uuid
cache_set_uuid=$(cat /tmp/cset_uuid | awk '{print $2}')
echo $cache_set_uuid > /sys/fs/bcache/register
if ! echo /dev/md1 > /sys/fs/bcache/$cache_set_uuid/cache0/attach; then
    echo "Failed to attach the cache device"
    exit 1
fi

# Create ext4 filesystem on the cached RAID 10 array
log "Creating ext4 filesystem on the cached RAID 10 array..."
if ! mkfs.ext4 /dev/bcache0; then
    echo "Failed to create filesystem"
    exit 1
fi

# Create mount point
log "Creating mount point at /mnt/raid..."
mkdir -p /mnt/raid

# Mount the RAID array
log "Mounting the RAID array..."
if ! mount /dev/bcache0 /mnt/raid; then
    echo "Failed to mount RAID array"
    exit 1
fi

# Backup current fstab file
log "Backing up current /etc/fstab..."
if ! cp /etc/fstab /etc/fstab.backup; then
    echo "Failed to backup /etc/fstab"
    exit 1
fi

# Get UUID of the bcache device
bcache_uuid=$(blkid -s UUID -o value /dev/bcache0)
if [ -z "$bcache_uuid" ]; then
    echo "Failed to get UUID for /dev/bcache0"
    exit 1
fi

# Add entry to /etc/fstab to mount RAID array at boot
log "Updating /etc/fstab..."
if ! echo "UUID=$bcache_uuid /mnt/raid ext4 defaults,noatime,user,uid=1000,gid=1000,nofail 0 2" >> /etc/fstab; then
    echo "Failed to update /etc/fstab"
    exit 1
fi

# Verify RAID array status
log "Verifying RAID array status..."
if ! mdadm --detail /dev/md0; then
    echo "Failed to get details for RAID 10 array"
    exit 1
fi
if ! mdadm --detail /dev/md1; then
    echo "Failed to get details for RAID 0 array"
    exit 1
fi

# Verify filesystem is mounted
log "Verifying filesystem is mounted..."
if ! df -h | grep /mnt/raid; then
    echo "Filesystem is not mounted"
    exit 1
fi

# Clear the screen and display final information
clear
log "RAID setup complete and mounted at /mnt/raid"
echo "========================================"
echo "RAID 10 Array (HDDs): /dev/md0"
mdadm --detail /dev/md0
echo "----------------------------------------"
echo "RAID 0 Array (SSDs, used as cache): /dev/md1"
mdadm --detail /dev/md1
echo "----------------------------------------"
echo "Cache Set UUID: $cache_set_uuid"
echo "----------------------------------------"
echo "Filesystem mounted at /mnt/raid:"
df -h | grep /mnt/raid
echo "========================================"
echo "Don't forget to check the RAID status regularly using 'cat /proc/mdstat' and 'mdadm --detail /dev/md0'."
