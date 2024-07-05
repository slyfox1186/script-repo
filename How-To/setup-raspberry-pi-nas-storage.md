# The Ultimate Guide to Setting Up a Raspberry Pi 5 as a Home Storage NAS

This guide will walk you through setting up a Raspberry Pi 5 as a home storage NAS (Network Attached Storage). By the end of this guide, you'll have a fully functional NAS using Samba for file sharing across your network.

## Table of Contents

1. [Introduction](#introduction)
2. [Requirements](#requirements)
3. [Setting Up the Raspberry Pi](#setting-up-the-raspberry-pi)
4. [Installing the Operating System](#installing-the-operating-system)
5. [Configuring the Network](#configuring-the-network)
6. [Installing and Configuring Samba](#installing-and-configuring-samba)
7. [Creating and Sharing Folders](#creating-and-sharing-folders)
8. [Accessing Your NAS](#accessing-your-nas)
9. [Setting Up Automatic Backups](#setting-up-automatic-backups)
10. [Troubleshooting](#troubleshooting)
11. [Conclusion](#conclusion)

## Introduction

A Network Attached Storage (NAS) allows you to store and share files across your network, accessible from any device. The Raspberry Pi 5 is a powerful and cost-effective solution for building a home NAS.

## Requirements

- Raspberry Pi 5
- Power supply for Raspberry Pi
- MicroSD card (32GB or larger recommended)
- External USB hard drive(s) or SSD(s)
- Ethernet cable or Wi-Fi dongle (if not using built-in Wi-Fi)
- Keyboard, mouse, and monitor (for initial setup)
- Another computer for remote configuration (optional)

## Setting Up the Raspberry Pi

1. **Download Raspberry Pi Imager**: Download and install the Raspberry Pi Imager from the [official website](https://www.raspberrypi.org/software/).

2. **Flash the OS**:
   - Insert the MicroSD card into your computer.
   - Open Raspberry Pi Imager.
   - Choose "Raspberry Pi OS (32-bit)" as the OS.
   - Select your MicroSD card.
   - Click "Write" to flash the OS onto the MicroSD card.

3. **Initial Boot**:
   - Insert the MicroSD card into the Raspberry Pi.
   - Connect the keyboard, mouse, and monitor.
   - Power on the Raspberry Pi.

4. **Initial Configuration**:
   - Follow the on-screen instructions to set up your Raspberry Pi.
   - Update the system: 
     ```bash
     sudo apt update && sudo apt upgrade -y
     ```

## Installing the Operating System

1. **Update and Upgrade**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **Install Necessary Packages**:
   ```bash
   sudo apt install samba samba-common-bin -y
   ```

## Configuring the Network

1. **Set a Static IP Address**:
   - Edit the DHCP client configuration:
     ```bash
     sudo nano /etc/dhcpcd.conf
     ```
   - Add the following lines, replacing with your network details:
     ```conf
     interface eth0
     static ip_address=192.168.1.100/24
     static routers=192.168.1.1
     static domain_name_servers=192.168.1.1
     ```

2. **Reboot to Apply Changes**:
   ```bash
   sudo reboot
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
     comment = Raspberry Pi NAS
     path = /home/pi/nas
     browseable = yes
     writeable = yes
     only guest = no
     create mask = 0777
     directory mask = 0777
     public = no
     ```

4. **Create a Directory for Your NAS**:
   ```bash
   mkdir -p /home/pi/nas
   ```

5. **Set Permissions**:
   ```bash
   sudo chown -R pi:pi /home/pi/nas
   sudo chmod -R 777 /home/pi/nas
   ```

6. **Create a Samba User**:
   ```bash
   sudo smbpasswd -a pi
   ```

7. **Restart Samba**:
   ```bash
   sudo systemctl restart smbd
   ```

## Creating and Sharing Folders

1. **Create Additional Shared Folders**:
   ```bash
   mkdir -p /home/pi/nas/shared_folder
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
     path = /home/pi/nas/shared_folder
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
   nano /home/pi/backup.sh
   ```
   - Add the following:
     ```bash
     #!/bin/bash
     rsync -av --delete /home/pi/nas /path/to/backup/location
     ```

3. **Make the Script Executable**:
   ```bash
   chmod +x /home/pi/backup.sh
   ```

4. **Schedule the Backup with Cron**:
   ```bash
   crontab -e
   ```
   - Add the following line to run the backup script every day at 2 AM:
     ```cron
     0 2 * * * /home/pi/backup.sh
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

You have successfully set up a Raspberry Pi 5 as a home storage NAS. You can now store and access your files from any device on your network. With automatic backups in place, your data is secure and easily recoverable. Enjoy your new NAS!
