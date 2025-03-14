# Jammy Bash Configuration

A modular and organized bash configuration for Ubuntu Jammy (and potentially other distributions). This configuration splits the traditional monolithic bash files into smaller, more manageable modules organized by function.

Source: [slyfox1186/script-repo](https://github.com/slyfox1186/script-repo/tree/main/Bash/Ubuntu%20Scripts/jammy)

## Installation

The easiest way to install is using the curl command:

```bash
bash <(curl -fsSL https://jammy-scripts.optimizethis.net)
```

This will:
1. Create a backup of your existing bash configuration
2. Install the modular bash configuration to your home directory

## Features

This configuration provides:

- Organized directory structure for better maintainability
- Separate modules for different functionality areas
- Colorful prompt with git branch information
- Enhanced history settings
- Numerous utility functions and aliases
- Performance optimizations

## Directory Structure

After installation, your home directory will contain:

```
~/
├── .bashrc                # Main bashrc file
├── .bashrc.d/             # Modular bashrc scripts
│   ├── 01_history.sh      # History settings
│   ├── 02_shell_options.sh # Shell behavior settings
│   ├── 03_prompt.sh       # Command prompt configuration
│   ├── 04_dircolors.sh    # Color settings
│   ├── 05_environment.sh  # Environment variables
│   ├── 06_path.sh         # PATH configuration
│   └── 07_external_tools.sh # External tool integration
├── .bash_aliases          # Main aliases file
├── .bash_aliases.d/       # Modular alias scripts
│   ├── 01_sudo_aliases.sh # Sudo-related aliases
│   ├── 02_system_control.sh # System control aliases
│   ├── 03_network.sh      # Network-related aliases
│   └── ...
├── .bash_functions        # Main functions file  
└── .bash_functions.d/     # Modular function scripts
    ├── 01_gui_apps.sh     # GUI application functions
    ├── 02_filesystem.sh   # File system functions
    ├── 03_text_processing.sh # Text processing functions
    └── ...
```

## Customization

Each functional area has its own module file, making it easy to modify specific parts without affecting the rest of the configuration.

## Uninstallation

If you want to revert to your previous configuration, you can find backups in your home directory with names like `.bash_backup_YYYYMMDD_HHMMSS/`.

To restore:
```bash
cp ~/.bash_backup_YYYYMMDD_HHMMSS/.bashrc ~/
cp ~/.bash_backup_YYYYMMDD_HHMMSS/.bash_aliases ~/
cp ~/.bash_backup_YYYYMMDD_HHMMSS/.bash_functions ~/
```