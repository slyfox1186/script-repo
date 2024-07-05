# Guide to Setting Up a NAS Storage System on a Linux Ubuntu Jammy Server PC

This comprehensive guide will walk you through setting up a NAS (Network Attached Storage) on a Linux Ubuntu Jammy Jellyfish (22.04) server. By the end of this guide, you'll have a fully functional NAS using Samba for file sharing across your network.

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

- A PC running Ubuntu 22.04 (Jammy Jellyfish)
- External USB hard drive(s) or SSD(s)
- Ethernet cable or reliable Wi-Fi connection
- Another computer for remote configuration (optional)

## Initial Server Setup

1. **Update and Upgrade the System**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **Set a Static IP Address**:
   - Edit the Netplan configuration file:
     ```bash
     sudo nano /etc/netplan/01-netcfg.yaml
     ```
   - Add the following lines, replacing with your network details:
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
   - Apply the Netplan configuration:
     ```bash
     sudo netplan apply
     ```

3. **Install Necessary Packages**:
   ```bash
   sudo apt install samba samba-common-bin -y
   ```

## Installing and Configuring Samba

1. **Install Samba**:
   ```bash
   sudo apt install samba samba-common-bin -y
   ```

2. **Backup the Original Configuration File**:
   ```bash
   sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
   ```

3. **Edit the Samba Configuration File**:
   ```bash
   sudo nano /etc/samba/smb.conf
   ```
   - Add the following to the end of the file:
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

4. **Create a Directory for Your NAS**:
   ```bash
   sudo mkdir -p /srv/nas
   ```

5. **Set Permissions**:
   ```bash
   sudo chown -R nobody:nogroup /srv/nas
   sudo chmod -R 0777 /srv/nas
   ```

6. **Create a Samba User**:
   ```bash
   sudo smbpasswd -a <username>
   ```

7. **Restart Samba**:
   ```bash
   sudo systemctl restart smbd
   ```

## Creating and Sharing Folders

1. **Create Additional Shared Folders**:
   ```bash
   sudo mkdir -p /srv/nas/shared_folder
   ```

2. **Add Folder to Samba Configuration**:
   - Edit `smb.conf` again:
     ```bash
     sudo nano /etc/samba/smb.conf
     ```
   - Add:
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

3. **Restart Samba**:
   ```bash
   sudo systemctl restart smbd
   ```

## Accessing Your NAS

1. **Windows**:
   - Open File Explorer.
   - Type `\\192.168.1.100\NAS` in the address bar and press Enter.
   - Enter your Samba username and password.

2. **macOS**:
   - Open Finder.
   - Press `Cmd + K`.
   - Type `smb://192.168.1.100/NAS` and press Enter.
   - Enter your Samba username and password.

3. **Linux**:
   - Open your file manager.
   - Type `smb://192.168.1.100/NAS` in the address bar and press Enter.
   - Enter your Samba username and password.

## Setting Up Automatic Backups

1. **Install rsync**:
   ```bash
   sudo apt install rsync -y
   ```

2. **Create a Backup Script**:
   ```bash
   sudo nano /usr/local/bin/backup.sh
   ```
   - Add the following:
     ```bash
     #!/bin/bash
     rsync -av --delete /srv/nas /path/to/backup/location
     ```

3. **Make the Script Executable**:
   ```bash
   sudo chmod +x /usr/local/bin/backup.sh
   ```

4. **Schedule the Backup with Cron**:
   ```bash
   sudo crontab -e
   ```
   - Add the following line to run the backup script every day at 2 AM:
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
