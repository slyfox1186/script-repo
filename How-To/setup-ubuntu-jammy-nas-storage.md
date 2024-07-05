# Guide to Setting Up a NAS Storage System on a Linux Ubuntu Jammy Server PC

This guide will provide you with all the information you need to set up a NAS (Network Attached Storage) on a Linux Ubuntu Jammy Jellyfish (22.04) server. We'll cover the necessary hardware, software, and step-by-step instructions to get your NAS up and running.

## Table of Contents

1. [Introduction](#introduction)
2. [Requirements](#requirements)
3. [Initial Server Setup](#initial-server-setup)
4. [Installing and Configuring Samba](#installing-and-configuring-samba)
5. [Creating and Sharing Folders](#creating-and-sharing-folders)
6. [Accessing Your NAS](#accessing-your-nas)
7. [Setting Up Automatic Backups](#setting-up-automatic-backups)
8. [Troubleshooting](#troubleshooting)
9. [Conclusion](#conclusion)

## Introduction

A Network Attached Storage (NAS) allows you to store and share files across your network, accessible from any device. Setting up a NAS on a Linux Ubuntu Jammy server is a powerful and flexible solution for your home or small office.

## Requirements

### Hardware

- **PC running Ubuntu 22.04 (Jammy Jellyfish)**: This will be your NAS server.
- **Internal or External Storage Drives**:
  - Internal HDD/SSD: These can be mounted inside your PC case and connected via SATA.
  - External USB HDD/SSD: These connect via USB and offer flexibility in adding or removing storage.

### Why Choose Internal or External Drives?

- **Internal Drives**:
  - Pros: Usually faster data transfer rates, more secure since they are inside the case, and no additional power supply required.
  - Cons: Less flexible for expansion, more challenging to add/remove drives.

- **External Drives**:
  - Pros: Easy to add or remove, portable, can be used with other devices, and do not require opening the PC case.
  - Cons: Slightly slower transfer rates compared to internal drives, may require an additional power source.

### Other Necessary Hardware

- **Power supply for the PC**
- **Ethernet cable or reliable Wi-Fi connection**
- **Keyboard, mouse, and monitor for initial setup (optional, can use SSH later)**

### Software

- **Ubuntu 22.04 (Jammy Jellyfish)**: The operating system for your NAS.
- **Samba**: Software that provides SMB/CIFS protocol to share files over a network.
- **rsync**: A utility for efficiently transferring and synchronizing files.

## Initial Server Setup

### Step 1: Install Ubuntu 22.04

1. **Download Ubuntu 22.04 ISO**:
   - Download from the [official Ubuntu website](https://ubuntu.com/download/desktop).

2. **Create a Bootable USB Drive**:
   - Use software like [Rufus](https://rufus.ie/) for Windows or [Etcher](https://www.balena.io/etcher/) for macOS/Linux to create a bootable USB drive.

3. **Install Ubuntu**:
   - Insert the bootable USB drive into your PC and boot from it.
   - Follow the on-screen instructions to install Ubuntu 22.04.

### Step 2: Update and Upgrade the System

1. **Open Terminal**:
   - You can do this by pressing `Ctrl+Alt+T`.

2. **Run the Following Commands**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

### Step 3: Set a Static IP Address

1. **Edit the Netplan Configuration File**:
   ```bash
   sudo nano /etc/netplan/01-netcfg.yaml
   ```

2. **Add the Following Configuration**:
   ```yaml
   network:
     version: 2
     ethernets:
       eth0:
         dhcp4: no
         addresses: [192.168.1.100/24]
         gateway4: 192.168.1.1
         nameservers:
           addresses: [192.168.1.1, 8.8.8.8]
   ```

3. **Apply the Configuration**:
   ```bash
   sudo netplan apply
   ```

## Installing and Configuring Samba

### Step 1: Install Samba

1. **Run the Following Command**:
   ```bash
   sudo apt install samba samba-common-bin -y
   ```

### Step 2: Backup the Original Configuration File

1. **Run the Following Command**:
   ```bash
   sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
   ```

### Step 3: Edit the Samba Configuration File

1. **Open the Configuration File**:
   ```bash
   sudo nano /etc/samba/smb.conf
   ```

2. **Add the Following to the End of the File**:
   ```conf
   [NAS]
   comment = Ubuntu NAS
   path = /srv/nas
   browseable = yes
   writeable = yes
   only guest = no
   create mask = 0777
   directory mask = 0777
   public = no
   ```

### Step 4: Create a Directory for Your NAS

1. **Run the Following Command**:
   ```bash
   sudo mkdir -p /srv/nas
   ```

### Step 5: Set Permissions

1. **Run the Following Commands**:
   ```bash
   sudo chown -R nobody:nogroup /srv/nas
   sudo chmod -R 0777 /srv/nas
   ```

### Step 6: Create a Samba User

1. **Run the Following Command**:
   ```bash
   sudo smbpasswd -a <username>
   ```

### Step 7: Restart Samba

1. **Run the Following Command**:
   ```bash
   sudo systemctl restart smbd
   ```

## Creating and Sharing Folders

### Step 1: Create Additional Shared Folders

1. **Run the Following Command**:
   ```bash
   sudo mkdir -p /srv/nas/shared_folder
   ```

### Step 2: Add Folder to Samba Configuration

1. **Edit the Samba Configuration File**:
   ```bash
   sudo nano /etc/samba/smb.conf
   ```

2. **Add the Following Configuration**:
   ```conf
   [SharedFolder]
   comment = Shared Folder
   path = /srv/nas/shared_folder
   browseable = yes
   writeable = yes
   only guest = no
   create mask = 0777
   directory mask = 0777
   public = no
   ```

### Step 3: Restart Samba

1. **Run the Following Command**:
   ```bash
   sudo systemctl restart smbd
   ```

## Accessing Your NAS

### From Windows

1. **Open File Explorer**.
2. **Type `\\192.168.1.100\NAS` in the Address Bar and Press Enter**.
3. **Enter Your Samba Username and Password**.

### From macOS

1. **Open Finder**.
2. **Press `Cmd + K`**.
3. **Type `smb://192.168.1.100/NAS` and Press Enter**.
4. **Enter Your Samba Username and Password**.

### From Linux

1. **Open Your File Manager**.
2. **Type `smb://192.168.1.100/NAS` in the Address Bar and Press Enter**.
3. **Enter Your Samba Username and Password**.

## Setting Up Automatic Backups

### Step 1: Install rsync

1. **Run the Following Command**:
   ```bash
   sudo apt install rsync -y
   ```

### Step 2: Create a Backup Script

1. **Open a New Script File**:
   ```bash
   sudo nano /usr/local/bin/backup.sh
   ```

2. **Add the Following Script**:
   ```bash
   #!/bin/bash
   rsync -av --delete /srv/nas /path/to/backup/location
   ```

### Step 3: Make the Script Executable

1. **Run the Following Command**:
   ```bash
   sudo chmod +x /usr/local/bin/backup.sh
   ```

### Step 4: Schedule the Backup with Cron

1. **Open the Crontab Editor**:
   ```bash
   sudo crontab -e
   ```

2. **Add the Following Line to Run the Backup Script Every Day at 2 AM**:
   ```cron
   0 2 * * * /usr/local/bin/backup.sh
   ```

## Troubleshooting

- **Check Samba Status**:
  ```bash
  sudo systemctl status smbd
  ```
- **Check Samba Logs**:
  ```bash
  sudo tail -f /var/log/samba/log.smbd
  ```
- **Check Network Configuration**:
  ```bash
  ip a
  ```

## Conclusion

You have successfully set up a NAS storage system on a Linux Ubuntu Jammy server. Your NAS is now ready to store and share files across your network. With automatic backups in place, your data is secure and easily recoverable. Enjoy your new NAS setup!
