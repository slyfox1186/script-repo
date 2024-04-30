# Automating Arch Linux Installation with Gnome Using Bash

Hello, r/archlinux community!

I'm thrilled to share a comprehensive bash script that significantly streamlines the Arch Linux installation process for a Gnome and GDM Environment. This script is meticulously designed to reduce the manual command line work typically involved in installing Arch Linux. It allows for an efficient setup process by automating many steps and incorporating the Gnome desktop environment. Below, I detail the script's functionality, benefits, and how you can use its command line arguments for a tailored installation.

#### **What the Script Does**:

This script simplifies the Arch Linux installation with the following automated steps:

1. **Disk Setup**: It partitions the disk using GPT, creating designated partitions for EFI, swap, and root. Users can specify the number and sizes of partitions, allowing for tailored disk configuration.

2. **Filesystem Creation**: Applies appropriate filesystems to the partitions, such as FAT32 for EFI and ext4 for root.

3. **Base System Installation**: Uses `pacstrap` to install essential packages, including the Linux kernel, Gnome desktop, system utilities, and network management tools.

4. **System Configuration**: Sets up system preferences like timezone, localization, network configurations, and user accounts with sudo privileges.

5. **Bootloader Setup**: Installs and configures GRUB for EFI, ensuring the system boots successfully post-installation.

6. **Final Steps**: Activates necessary services such as NetworkManager and generates the fstab file to manage system mount points at startup.

#### **Command Line Arguments**:

The script supports various command line arguments to predefine settings, minimizing manual input:

- `-u USERNAME`: Sets the non-root username.
- `-p USER_PASSWORD`: Sets the non-root user password.
- `-r ROOT_PASSWORD`: Sets the root password.
- `-c COMPUTER_NAME`: Sets the computer name.
- `-t TIMEZONE`: Sets the timezone (default: US/Eastern).
- `-d DISK`: Specifies the target disk (e.g., /dev/sdX or /dev/nvmeXn1).
- `-h`: Displays a help message outlining these options.

#### **Benefits of Using This Script**:

1. **Efficiency**: Drastically reduces installation time and effort.
2. **Consistency**: Ensures a uniform and error-free installation process.
3. **Customizability**: Provides flexibility through user inputs and command line arguments.
4. **Educational Value**: Assists new users in understanding the Linux setup process.
5. **Repeatability**: Ideal for deploying multiple Arch Linux setups with Gnome.

## **Installation Instructions**

### Step 1 - Pre Installer

#### Load into the Arch Linux USB bootloader

1. **Locate the drive you want to format:** `fdisk -l | less`
2. **Install cURL:** `pacman -Sy --noconfirm curl`
3. **Download the Step 1 script:** `curl -LSso step1.sh https://arch1.optimizethis.net`
4. **Make executable:** `chmod +x step1.sh`
5. **Execute script:** `./step1.sh -u yourUsername -p yourPassword -r yourRootPassword -c yourComputerName -t yourTimezone -d yourDisk`
6. **Answer each prompt**

### Step 2 - Post Installer
#### The below steps are done only after rebooting into the Arch OS that was installed in step 1

1. **Login with root (use the root password that you set in step 1)**
2. **Download the Step 2 script:** `curl -LSso step2.sh https://arch2.optimizethis.net`
3. **Make executable:** `chmod +x step2.sh`
4. **Execute script:** `./step2.sh`
5. **Answer each prompt**
6. **Load straight into the Gnome GUI OR reboot first (recommended)**

#### **Conclusion**:

This script is meticulously crafted to make Arch Linux installation with Gnome seamless and user-friendly, catering to both newcomers and seasoned Linux enthusiasts. By including command line arguments, it allows for quick setups in automated setups such as scripting deployments for multiple machines.

The custom download links forward to the GitHub hosted RAW files for each script.

`https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/Arch%20Linux/arch-linux-with-gnome-step-1.sh`
`https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/Arch%20Linux/arch-linux-with-gnome-step-2.sh`

We welcome your feedback and contributions to further refine and enhance the script's functionality and user experience.

Happy installing, and I eagerly anticipate your thoughts and contributions!
