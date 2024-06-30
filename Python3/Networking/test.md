# Python Network Share Manager

**Link**: [manage_network_shares.py](https://github.com/slyfox1186/script-repo/blob/main/Python3/Networking/manage_network_shares.py)

## What My Project Does

This Python script provides a user-friendly, terminal-based interface for managing network shares on Linux systems. Key features include:

- Mount and unmount network shares
- Add or remove entries in /etc/fstab for persistent mounting (optional)
- Create symlinks in the user's home directory for easy access
- Automatically refresh the file manager to reflect changes
- Interactive menu for selecting which shares to mount/unmount
- Supports CIFS/SMB protocol (easily extendable to other protocols)

## Target Audience

This tool is designed for:

- Linux users who frequently work with network shares
- Anyone looking for an easier way to manage network shares without manual terminal commands

## Comparison

While there are GUI tools like "Disk Utility" or "Gnome Disks" for managing mounts, this script offers several advantages:

1. **Automation**: Handles mounting, fstab entries, and symlink creation in one go.
2. **Customizable**: Easy to modify for specific needs or to add support for other network protocols.
3. **Batch Operations**: Can mount/unmount multiple shares at once.
4. **Lightweight**: Doesn't require additional GUI libraries or dependencies.

Compared to manual terminal commands, this script:
- Reduces the chance of errors in fstab entries
- Saves time by automating repetitive tasks
- Provides a more user-friendly interface for those less comfortable with command-line operations

## How to Install

1. Ensure you have Python 3.6 or later installed on your system.
2. Download the `manage_network_shares.py` file from the provided GitHub link.
3. Make the script executable:
   ```
   chmod +x manage_network_shares.py
   ```

## How to Use

1. Open the `manage_network_shares.py` file in a text editor.
2. Locate and update the following variables at the top of the script if desired:
   - `DEFAULT_IP_ADDRESS`: Set this to the default IP address of your network share server.
   - `DEFAULT_USERNAME`: Set this to your default username for accessing the shares.
   - `DEFAULT_PASSWORD`: Set this to your default password for accessing the shares.
   - `SHARE_NAMES`: Update this list with the names of the folders you want to mount. For example:
     ```python
     SHARE_NAMES = [
         "Documents",
         "Pictures",
         "Videos"
     ]
     ```
3. Save the changes to the file.
4. Open a terminal and navigate to the directory containing the script.
5. Run the script with sudo privileges:
   ```
   sudo ./manage_network_shares.py -ip YOUR_IP_ADDRESS -u YOUR_USERNAME -p YOUR_PASSWORD [-fp YOUR_FOLDER_PREFIX] [-n]
   ```
   - `-ip YOUR_IP_ADDRESS`: Specify the IP address of the network share.
   - `-u YOUR_USERNAME`: Specify the username for the share.
   - `-p YOUR_PASSWORD`: Specify the password for the share.
   - `[-fp YOUR_FOLDER_PREFIX]`: Optional. Specify a custom folder prefix.
   - `[-n]`: Optional. Add this flag if you do not want to modify the /etc/fstab for persistent mounting.
6. Follow the on-screen prompts to add or remove network shares:
   - Use arrow keys to navigate
   - Press Space to select/deselect shares
   - Press Enter to confirm your selection
7. The script will automatically mount/unmount the selected shares and update the system accordingly.

## How to share folders on Windows

To set up folders on a Windows PC for remote sharing, follow these steps:

1. **Choose the folder to share**:
   - Right-click on the folder you want to share.
   - Select "Properties".

2. **Enable sharing**:
   - In the Properties window, click on the "Sharing" tab.
   - Click on "Advanced Sharing".
   - Check the box next to "Share this folder".
   - Click "Apply" and then "OK".

3. **Set permissions**:
   - Back in the Sharing tab, click on "Share".
   - Choose who you want to share the folder with. For full access, you can select "Everyone".
   - Click "Add".
   - Set the Permission Level to "Read/Write".
   - Click "Share" and then "Done".

4. **Note the share name**:
   - The share name is typically the folder name, but you can change it in the "Advanced Sharing" settings.
   - This is the name you'll use in the `SHARE_NAMES` list in the Python script.

5. **Enable network discovery**:
   - Open the Control Panel.
   - Go to "Network and Sharing Center".
   - Click on "Change advanced sharing settings".
   - Ensure "Network discovery" is turned on.

6. **Find your Windows IP address**:
   - Open Command Prompt.
   - Type `ipconfig` and press Enter.
   - Look for the "IPv4 Address" under your active network adapter.
   - Use this IP address for the `IP_ADDRESS` variable in the Python script.

## User Account Name and Password Example

- If running this on Ubuntu.
- Unless you have set a specific `USERNAME` and `PASSWORD` in the Windows `Network and Sharing` settings the following will most likely apply.
- The `USERNAME` to log in will most likely be your Ubuntu username.
- The password will be your login password on Ubuntu.
- Use these credentials for the `USERNAME` and `PASSWORD` variables or arguments when executing the Python script.

## Safety Measures

The script has been designed with several safety measures to ensure it is considered 'safe to run' by experienced Linux users:

1. **Command Quoting**: The script uses `shlex.quote` to ensure that command arguments are safely quoted to prevent shell injection vulnerabilities.
2. **Detailed Error Handling**: Enhanced error messages for better clarity and logging.
3. **Resource Cleanup**: Ensures proper cleanup of mount points and symbolic links.
4. **Comprehensive Logging**: Detailed logging to help diagnose issues if something goes wrong.
5. **No Persistent Changes (Optional)**: The script includes an optional `-n` or `--no-fstab` argument to prevent modifications to the `/etc/fstab` file for users who do not want persistent mounting.
6. **User Feedback**: Provides clear and detailed feedback to the user during execution, ensuring a user-friendly experience.

## Important Safety Inforamtion
Remember to keep your system and shared folders secure by using strong passwords and only sharing with trusted networks and users.
It is **ALWAYS** recommended to pass arguments instead of hardcoding sensitive information like usernames and passwords in a script.

Note: The script creates log files at `/tmp/shared_folder_manager.log`. Check these logs if you encounter any issues.
