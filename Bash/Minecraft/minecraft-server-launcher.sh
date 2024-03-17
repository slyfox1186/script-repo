#!/usr/bin/env bash
#
pushd "$PWD" || exit 1
#
clear
#
### Important script information below
#
### IP = server WAN on LAN address that hosts the Minecraft server
#
### PW = rcon password (set in server.properties)
#
### PORT = server default rcon port (change if needed and is set in server.properties)
#
### SCRIPT = the default server start script that comes with the server files you download
###          from the Curseforge Desktop App (or you can google "Curseforge + the mod pack name")
#
### Download server files via Curseforge Desktop App
#     1) Use the Curseforge app to install the mod of your choosing (requires overwolf.exe)
#     2) Click the 3 dots in the mod's main menu and use the drop-down menu to select
#        "Download Server Files"
#     3) Transport the server files to the Linux (Debian) pc you want to run the server on
#     4) Set the below variables as needed for this script to work successfully
#
IP=192.168.1.40
PW=47j8a8&
PORT=25575
SCRIPT=start.sh
#
### Install the mcrcon package if not found
### Use Git to download the repository and then install with the make command
#
if [ ! -f '/usr/local/bin/mcrcon' ]; then
    git clone 'https://github.com/Tiiffi/mcrcon.git'
    cd mcrcon || exit 1
    make "-j$(nproc)"
    sudo make install
fi
#
### Install HTOP Process Monitor
#
if [ ! -f '/usr/bin/htop' ]; then sudo apt -y install htop; fi
#
### Install Screen package if not found
#
if [ ! -f '/usr/bin/screen' ]; then sudo apt -y install screen; fi
#
### Set color vars
#
BLUE="\033[34m"
CYAN="\033[36m"
GREEN="\033[32m"
MAGENTA="\033[35m"
RED="\033[31m"
RESET="\033[0m"
YELLOW="\033[33m"
#
### Set color functions
#
greenprint() { printf "$GREEN%s$RESET\n" "$1"; }
blueprint() { printf "$BLUE%s$RESET\n" "$1"; }
redprint() { printf "$RED%s$RESET\n" "$1"; }
yellowprint() { printf "$YELLOW%s$RESET\n" "$1"; }
magentaprint() { printf "$MAGENTA%s$RESET\n" "$1"; }
cyanprint() { printf "$CYAN%s$RESET\n" "$1"; }
#
### Set misc functions
#
fn_remindUser() { clear; echo 'Please input one of the available choices.'; }
fn_exit() { clear; exit 0; }
fn_fail() { clear; echo -e "\\n[i] Invalid input: Please try a different choice.\\n"; exit 1; }
clear
#
### Fast stop server
#
fn_faststop_server() {
    echo -e "Server shutdown command executed... please wait.\\n"
    mcrcon -H $IP -P $PORT -p $PW -w 10 "say Server stopping!" save-all stop && \
    sudo killall java && \
    echo -e "[i] The server has stopped.\\n"
    echo
    sleep 3
    htop
}
#
### Restart server
#
fn_restart_server() {
    echo -e "[i] Server restarting in 30 seconds...\\n    - Warning users to save their work within 30 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is restarting in 30 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 13 "say Please save all work!"
    echo -e "[i] Server restarting in 15 seconds...\\n    - Warning users to save their work within 15 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is restarting in 15 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 8 "say Please save all work NOW!"
    echo -e "[i] Server restarting in  5 seconds...\\n    - Warning users to save their work within 5 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 1 "say The server is restarting in 5 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 4 "say Please save all work NOW!"
    echo -e "[i] Server restarting...\\n"
    mcrcon -H $IP -P $PORT -p $PW -w 10 "say Server restarting!" save-all stop && \
    sudo killall java && \
    echo -e "[i] Executing command: screen -dmS mc ./"$SCRIPT"\\n    - Please wait for the server to completely load before reconnecting.\\n"
    screen -dmS mc ./"$SCRIPT"
    echo
    sleep 3
    htop
}
#
### Stop server
#
fn_stop_server() {
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is stopping in 30 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 13 "say Please save all work!"
    echo -e "[i] Server stopping in 30 seconds...\\n    - Warning users to save their work within 30 seconds..." && \
    echo -e "[i] Warning users to save their work within 30 seconds..."
    echo -e "[i] Server stopping in 15 seconds...\\n    - Warning users to save their work within 15 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is stopping in 15 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 8 "say Please save all work NOW!"
    echo -e "[i] Server stopping in  5 seconds...\\n    - Warning users to save their work within 5 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 1 "say The server is stopping in 5 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 4 "say Please save all work NOW!"
    echo -e "[i] Server stopping..."
    mcrcon -H $IP -P $PORT -p $PW -w 10 "say Server stopping!" save-all stop && \
    sudo killall java && \
    echo -e "[i] The server has stopped.\\n"
    echo
    sleep 3
    htop
}
#
### Start server
#
fn_start_server() {
    local SCRIPT
    echo -e "[i] Executing command: screen -dmS mc ./$SCRIPT\\n    - Please wait for the server to completely load before reconnecting.\\n"
    screen -dmS mc ./"$SCRIPT"
    echo
    sleep 2
    htop
}
#
### Start subemenu section
#
### submenu4
#
submenu4() {
    local i
    echo -e "$(cyanprint 'Fast Stop the server?')"
echo -ne "
$(greenprint '1)') Yes
$(magentaprint '2)') No
$(redprint '3)') Exit
Make a choice: "
    read -r i
    case $i in
    1)
        clear
        fn_faststop_server
        fn_exit
        ;;
    2)
        clear
        mainmenu
        ;;
    3)
        fn_exit
        ;;
    *)
        fn_fail
        ;;
    esac
}
#
### submenu3
#
submenu3() {
    local i
    echo -e "$(cyanprint 'Restart the server?')"
    echo -ne "
$(greenprint '1)') Yes
$(magentaprint '2)') No
$(redprint '3)') Exit
Make a choice: "
    read -r i
    case $i in
    1)
        clear
        fn_restart_server
        fn_exit
        ;;
    2)
        clear
        mainmenu
        ;;
    3)
        fn_exit
        ;;
    *)
        fn_fail
        ;;
    esac
}
#
### submenu2
#
submenu2() {
    local i
    echo -e "$(cyanprint 'Stop the server?')"
    echo -ne "
$(greenprint '1)') Yes
$(magentaprint '2)') No
$(redprint '3)') Exit
Make a choice: "
    read -r i
    case $i in
    1)
        clear
        fn_stop_server
        fn_exit
        ;;
    2)
        clear
        mainmenu
        ;;
    3)
        fn_exit
        ;;
    *)
        fn_fail
        ;;
    esac
}
#
### submenu1
#
submenu1() {
    local i
    echo -e "$(cyanprint 'Start the server?')"
    echo -ne "
$(greenprint '1)') Yes
$(magentaprint '2)') No
$(redprint '3)') Exit
Make a choice: "
    read -r i
    case $i in
    1)
        clear
        fn_start_server
        fn_exit
        ;;
    2)
        clear
        mainmenu
        ;;
    3)
        fn_exit
        ;;
    *)
        fn_fail
        ;;
    esac
}
#
### Main Menu
#
mainmenu() {
    local i
    echo -e "$(magentaprint '[i] Minecraft Server Launcher')"
    echo -ne "
$(greenprint '1)') Start Server
$(redprint '2)') Stop Server
$(yellowprint '3)') Restart Server
$(cyanprint '4)') Fast Stop Server
$(magentaprint '5)') Exit
Make a choice: "
    read -r i
    case $i in
    1)
        clear
        submenu1
        ;;
    2)
        clear
        submenu2
        ;;
    3)
        clear
        submenu3
        ;;
    4)
        clear
        submenu4
        ;;
    5)
        fn_exit
        ;;
    *)
        fn_fail
        ;;
    esac
}
#
mainmenu
