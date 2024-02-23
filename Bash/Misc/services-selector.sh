#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    printf "%s\n\n" "You must run this script with root/sudo."
    exit 1
fi

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GREEN_BOLD='\033[1;32m'
RED_BOLD='\033[1;31m'
NC='\033[0m' # No Color

# Declare services with descriptions
declare -A services=(
    [accounts-daemon]="Manages user accounts. While it's the backbone of desktop environments, servers can slim down by sidelining it unless specific user account management features are needed."
    [acpid]="Listens to ACPI events for adept power management. A guardian for laptops and desktops ensuring energy efficiency, yet an optional companion for servers."
    [alsa-restore]="Restores ALSA (Advanced Linux Sound Architecture) settings at boot. Non-essential for systems without audio requirements."
    [anacron]="Runs scheduled tasks. A diligent scheduler for machines with a bedtime, making sure no task is left behind."
    [apache2]="Apache web server, a staple for web hosting. Keep it running if you're serving up websites; otherwise, feel free to bench it."
    [apparmor]="Mandatory access control framework, keeping applications in check."
    [apport]="Collects crash reports. Useful for debugging, but can be disabled to streamline system performance."
    [auditd]="Keeps a keen eye on system events, a cornerstone for those who treat security with the reverence it deserves."
    [avahi-daemon]="Facilitates network service discovery. Handy for finding printers and files on the network, but if solitude is more your style, it's safe to disable."
    [bind9]="A Domain Name System (DNS) server, crucial for translating domain names into IP addresses. Unless you're running your own DNS server, you might not need it."
    [binfmt-support]="Supports extra binary formats. Essential for running non-native binaries, optional for others."
    [blk-availability]="Checks block device availability. Key for systems using SAN or similar technologies, optional for others."
    [bluetooth]="Manages Bluetooth devices. Essential for wireless peripherals, otherwise it's just taking up space."
    [cassandra]="A NoSQL champion for managing large datasets across distributed systems. Overkill for simple applications."
    [celery]="An asynchronous task queue for distributed systems. Essential for Python-based applications needing a robust background job mechanism."
    [colord]="Color management service that's more of a luxury than a necessity. Tailor-made for the color-conscious."
    [console-setup]="Configures console font and keyboard layout. Important for non-English keyboards, optional for others."
    [consul]="A service mesh maestro for managing microservices architecture with ease. Overhead for simple setups."
    [containerd]="A container runtime necessity if Docker is your container platform of choice. Otherwise, it's just another item on the menu."
    [cron]="Runs scheduled tasks. Without it, you'd be a full-time clock watcher."
    [cups]="Prints documents. Without it, you might resort to handwriting. If your world is paperless, it's optional."
    [cups-browsed]="Discovers network printers. Necessary for network printing, optional if not used."
    [dbus]="The postal service of your system, delivering messages between applications. Removing it would be like pulling the cornerstone from a bridge."
    [ddclient]="Updates dynamic DNS services with your current IP. Crucial for dynamic DNS users, optional for static IPs."
    [dhcpd]="Dishes out IP addresses on your network. Without a network to manage, it's like a lifeguard at an empty pool."
    [django]="A high-level Python Web framework for perfectionists with deadlines. Not needed for non-web projects."
    [docker]="Runs containers. Like virtual machines, but lighter and faster."
    [elasticsearch]="A search and analytics engine, essential for data-hungry applications. Overkill for simple search tasks."
    [etcd]="A distributed key-value store, acting as the backbone for clustered services. Not for the solitary servers."
    [fail2ban]="Blocks suspicious IP addresses. A digital bouncer for your server."
    [firewalld]="A gatekeeper managing firewall rules. Essential for network security, but overprotective for isolated networks."
    [flask]="A micro web framework for Python enthusiasts. Not required for non-web projects."
    [fwupd]="Keeps your firmware fresh. Optional but recommended to keep your hardware in check."
    [gdm]="The GNOME Display Manager. It's what greets you with a login screen."
    [geoclue]="Offers location services. Handy for location-based applications, otherwise it's just loitering."
    [gitlab]="A DevOps platform that's like a Swiss Army knife for developers. Not necessary for solo projects."
    [grafana]="Turns data chaos into visual insights. A must-have for monitoring aficionados, otherwise it's just eye candy."
    [gunicorn]="A Python WSGI HTTP Server, bridging the gap between dynamic web applications and the web. Essential for web deployments, otherwise it's taking a backseat."
    [hadoop]="Processes big data across clusters of computers. A heavyweight for data processing, but a bystander for small data tasks."
    [haproxy]="Balances the load like a pro, ensuring no server gets left behind. Essential for high-availability setups, optional for modest deployments."
    [haveged]="Generates entropy. Ensuring randomness, because predictability is boring."
    [httpd]="Another name for Apache2. A web server that's as essential as it is prevalent."
    [irqbalance]="Evens out the CPU load, making sure every core pulls its weight. A team player on multi-core systems."
    [jenkins]="Automates the repetitive, turning the mundane into the automated. Not needed if you prefer the scenic route."
    [kafka]="A distributed streaming platform, a messenger at scale. Overhead for simple messaging needs."
    [kerneloops]="Collects kernel errors. Valuable for diagnosing issues, but optional for the everyday user."
    [keyboard-setup]="Configures the keyboard on boot. Essential for custom keyboard layouts, optional for standard setups."
    [kmod]="Handles kernel modules. Think of it as a mechanic for your system's engine."
    [kmod-static-nodes]="Creates static device nodes for the kernel. Necessary for certain hardware, but generally automatic."
    [kubernetes]="Orchestrates containers, ensuring they play nicely together. Overkill for simple or solo-container setups."
    [lm-sensors]="Monitors system sensors. Crucial for temperature and voltage monitoring, optional for basic setups."
    [logrotate]="Rotates, compresses, and mails system logs. A janitor for your log files."
    [logstash]="Processes and ships logs, turning verbosity into clarity. Essential for log management, otherwise it's just noise."
    [lvm2-monitor]="Monitors LVM2 mirrors, snapshots, etc. Important for systems using LVM, optional for others."
    [mariadb]="A relational database, crucial for storing data with care. Optional if your data lives elsewhere."
    [memcached]="Speeds up dynamic web applications by caching data. Essential for high-traffic sites, otherwise it's on standby."
    [ModemManager]="Manages mobile broadband modems. Essential for mobile internet, unnecessary for wired connections."
    [mongodb]="A NoSQL database for when relationships are too complicated. Not needed for simple data storage needs."
    [mysql]="Another relational database stalwart, holding data close. Optional if you're not managing databases."
    [mysqld]="The MySQL database server. Where data goes to be organized."
    [networkd-dispatcher]="Scripts dispatcher for systemd-networkd. Useful for dynamic network configurations, optional otherwise."
    [NetworkManager]="Manages network connections. Central for dynamic network management, but can be replaced by alternatives."
    [NetworkManager-wait-online]="Waits for network to be online. Essential for services requiring network at startup, optional for others."
    [network]="Manages network settings. Without it, you might not get online."
    [nginx]="A high-performance web server. For when speed is of the essence."
    [nmbd]="NetBIOS name server, part of Samba. Necessary for Windows network interoperability, optional otherwise."
    [nodejs]="The runtime of choice for JavaScript server-side scripting. Not required for non-JavaScript projects."
    [nordvpnd]="NordVPN daemon. Essential for NordVPN users, irrelevant for others."
    [ntpd]="Keeps time in sync, because every second counts. Essential for time-sensitive applications."
    [openvpn]="A secure tunnel for your data. Essential for private networking, optional if you're not networking."
    [packagekit]="Provides a software installation interface. Useful for desktop users, optional for servers."
    [php7.2-fpm]="A fast-moving target for PHP applications, ensuring they're up and running. Not needed if PHP isn't your language of choice."
    [plexmediaserver]="A media server software to organize and stream your multimedia collection."
    [plymouth-quit-wait]="Manages the shutdown screen, ensuring a graceful exit."
    [plymouth-read-write]="Switches the root filesystem to read-write mode during boot."
    [plymouth-start]="Displays the boot screen. The first visual cue that your system is waking up."
    [polkit]="Authorizes system actions for users. Removing it would be like removing the locks from your doors."
    [postfix]="Delivers your mail, no postage required. Essential for email servers, optional for the rest."
    [postgresql]="A sophisticated relational database, for when data relationships matter. Optional if your data is elsewhere."
    [power-profiles-daemon]="Manages power profiles for optimal energy use. Eco-friendly tech stewardship."
    [preload]="Predicts and preloads applications you'll use. A time saver, making your system feel faster."
    [prometheus]="Monitors services, keeping a watchful eye on performance. Essential for monitoring, otherwise it's just collecting dust."
    [rabbitmq]="A message broker ensuring messages find their way. Essential for distributed systems, optional for the rest."
    [redis]="Stores data with lightning speed. A must-have for high-speed caching, optional for slow-paced environments."
    [rsyslog]="Logs system messages, a diary for your system. Essential for diagnostics."
    [rsyslog]="System logging service. It's your system's diary; important unless you prefer guesswork."
    [rtkit-daemon]="Gives real-time priorities to certain processes. For when timing is everything."
    [samba]="Shares files and printers with Windows systems. Essential for mixed environments, optional for the rest."
    [sendmail]="A mail transfer agent. It's how your server sends emails."
    [setvtrgb]="Sets the terminal's RGB colors, making the console a bit brighter."
    [smartd]="Keeps an eye on your disks' health. Because an ounce of prevention is worth a pound of cure."
    [smbd]="SMB/CIFS server, also part of Samba. Vital for file sharing with Windows machines, optional otherwise."
    [snap.canonical-livepatch.canonical-livepatchd]="Provides live kernel patching, reducing reboots and enhancing security."
    [snapd.apparmor]="Integrates snap applications with AppArmor for enhanced security."
    [snapd]="Manages snap packages. Essential for snap enthusiasts, optional for purists."
    [snapd.seeded]="Indicates that the initial set of snaps has been installed, making your snap environment ready."
    [snmpd]="Collects and organizes information about managed devices on IP networks. Essential for network management, otherwise it's eavesdropping."
    [ssh]="Opens the door to remote management. Without it, you're stuck at the console."
    [switcheroo-control]="Manages hybrid graphics, letting you switch between GPUs. Power when you need it, savings when you don't."
    [syslog]="Logs system messages. Like rsyslog, it's keeping track of your system's story."
    [systemd-binfmt]="Adds support for additional binary formats, expanding the types of executables your system can run."
    [systemd-fsck@dev-disk-by-uuid-B4B4-EDBE]="Checks and repairs file systems at boot. It's like a health check-up for your disks."
    [systemd-journald]="Collects and stores logging data. A meticulous record keeper, essential for system diagnostics."
    [systemd-journald]="Logs system events, a historian for your system. Essential for keeping track of system narratives."
    [systemd-journal-flush]="Ensures journal logs are promptly written to disk, safeguarding your system's memory of events."
    [systemd-logind]="Manages user logins, ensuring a warm welcome and a proper goodbye. Essential for multi-user systems."
    [systemd-modules-load]="Loads kernel modules at boot, equipping your system with necessary drivers and capabilities."
    [systemd-oomd]="Manages out-of-memory situations, making tough decisions to keep your system running."
    [systemd-random-seed]="Seeds the random number generator, enhancing system security through randomness."
    [systemd-remount-fs]="Remounts filesystems at boot, ensuring they're ready and accessible."
    [systemd-resolved]="Manages network name resolution, translating domain names into IP addresses."
    [systemd-sysctl]="Applies kernel runtime parameters, fine-tuning system performance and security."
    [systemd-sysusers]="Creates system users and groups, setting the stage for managed access."
    [systemd-timesyncd]="Keeps time in sync. Without it, you're living in the past... or the future."
    [systemd-tmpfiles-setup]="Creates temporary files and directories, ensuring a clean and orderly system."
    [systemd-tmpfiles-setup-dev]="Sets up special file systems under /dev, organizing device nodes."
    [systemd-udevd]="Manages device nodes, making sure your hardware is correctly integrated with the system."
    [systemd-udev-trigger]="Triggers udev to populate /dev, ensuring your devices are ready to use."
    [systemd-update-utmp]="Updates login records, keeping track of who's coming and going on your system."
    [systemd-user-sessions]="Manages user sessions, ensuring a secure and orderly multi-user environment."
    [thermald]="Prevents your system from overheating. If you like your computer crispy, skip it; otherwise, it's pretty cool."
    [tomcat]="A Java application server, a cozy environment for Java applications. Not required for non-Java projects."
    [ubuntu-fan]="Manages the FAN network overlay, enhancing network scalability and isolation."
    [udisks2]="Manages disk drives. Essential for managing storage devices."
    [ufw]="Uncomplicated Firewall. Your first line of defense, unless you like living on the edge."
    [unattended-upgrades]="Automatically upgrades packages, keeping your system fresh. Optional but recommended for peace of mind."
    [upower]="Manages power states. Important for battery-powered devices, optional for plugged-in machines."
    [user@1000]="Handles user processes, ensuring resources are allocated and managed effectively."
    [user-runtime-dir@1000]="Manages user-specific runtime directories, ensuring a personalized and secure environment."
    [vsftpd]="A light, secure FTP server. Essential if you're in the file transfer business, otherwise it's on the sidelines."
    [whoopsie]="Reports system crashes. For those who want to help improve Ubuntu."
    [wpa_supplicant]="Manages Wi-Fi security, keeping your wireless connections safe and sound."
    [xinetd]="A super-server that listens on behalf of other services. Optional unless you're hosting a variety of network services."
    [zookeeper]="Coordinates distributed systems, ensuring everyone's on the same page. Not needed for standalone systems."
)

print_service_description() {
    local service="$1"
    if [[ -n "${services[$service]}" ]]; then
        echo -e "${YELLOW}Description:${NC} ${services[$service]}"
    else
        echo -e "${RED}Description unavailable.${NC}"
    fi
}

show_services() {
    echo -e "${MAGENTA}List of Installed Services:${NC}\n"
    mapfile -t existing_services < <(systemctl list-units --type=service --state=active,enabled --no-pager --no-legend | awk '{print $1}' | sed 's/.service$//')
    local index=1
    for service in "${existing_services[@]}"; do
        if [[ -n "${services[$service]}" ]]; then
            echo -e "${GREEN}${index}${CYAN}) ${GREEN}${service} ${YELLOW}-${NC} ${services[$service]}"
        else
            echo -e "${GREEN}${index}${CYAN}) ${GREEN}${service} ${YELLOW}-${NC} Description unavailable."
        fi
        ((index++))
    done
    echo -e "${RED}00${CYAN}) ${RED}Exit${NC}"
}

main() {
    while true; do
        clear
        show_services
        echo
        echo -e "${CYAN}Enter the number of the service or '00' to exit:${NC} "
        read -r service_num

        if [[ "$service_num" == "00" ]]; then
            echo -e "${GREEN_BOLD}Exiting script.${NC}"
            exit 0
        elif [[ "$service_num" =~ ^[0-9]+$ ]] && (( service_num > 0 && service_num <= ${#existing_services[@]} )); then
            clear
            local service_name=${existing_services[service_num-1]}
            echo -e "${YELLOW}Service selected:${NC} $service_name"
            print_service_description "$service_name"
            echo -e "\\nChoose an action:\\n"
            echo -e "1) ${GREEN}Start${NC}"
            echo -e "2) ${YELLOW}Stop${NC}"
            echo -e "3) ${BLUE}Enable${NC}"
            echo -e "4) ${RED}Disable${NC}"
            echo -e "5) ${CYAN}Return${NC}"
            echo
            read -p "Enter choice (1-5): " action
            case $action in
                1) systemctl start "$service_name".service && echo -e "${GREEN_BOLD}Service started successfully.${NC}" ;;
                2) systemctl stop "$service_name".service && echo -e "${GREEN_BOLD}Service stopped successfully.${NC}" ;;
                3) systemctl enable "$service_name".service && echo -e "${GREEN_BOLD}Service enabled successfully.${NC}" ;;
                4) systemctl disable "$service_name".service && echo -e "${GREEN_BOLD}Service disabled successfully.${NC}" ;;
                5) ;;
                *) echo -e "${RED_BOLD}Invalid choice, please try again.${NC}" ;;
            esac
        else
            echo -e "${RED_BOLD}Invalid input, please enter a valid number from the list.${NC}"
        fi
        echo
        sleep 2
    done
}

main
