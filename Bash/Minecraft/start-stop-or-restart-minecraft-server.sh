#!/usr/bin/env bash





IP=ip or address here
PW=password here
PORT=rcon port here
SCRIPT=name of start script here <name.sh> (This should be included in the files you downloaded from curseforge)

clear
echo -e "Minecraft Server Launcher\\n"
echo '[1] Start Server'
echo '[2] Stop Server'
echo '[3] Restart Server'
echo -e "[4] Exit\\n"
read -p 'Enter a number: ' i
clear

if [[ $i -eq 1 ]]; then
    echo -e "[i] Executing command: screen -d -m -S mc ./$SCRIPT\\n    - Please wait for the server to completely load before reconnecting.\\n"
    screen -d -m -S mc ./$SCRIPT
    echo
elif [[ $i -eq 2 ]]; then
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is stopping in 30 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say Please save all work!"
    echo -e "[i] Server stopping in 30 seconds...\\n    - Warning users to save their work within 30 seconds..." && \
    echo -e "[i] Warning users to save their work within 30 seconds..."
    sleep 15
    echo -e "[i] Server stopping in 15 seconds...\\n    - Warning users to save their work within 15 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is stopping in 15 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say Please save all work NOW!"
    sleep 10
    echo -e "[i] Server stopping in  5 seconds...\\n    - Warning users to save their work within  5 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is stopping in 5 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say Please save all work NOW!"
    sleep 5
    echo -e "[i] Server stopping..."
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say Server stopping!" save-all stop && \
    sudo killall -9 java && \
    echo -e "[i] The server has stopped.\\n"
elif [[ $i -eq 3 ]]; then
    echo -e "[i] Server restarting in 30 seconds...\\n    - Warning users to save their work within 30 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is restarting in 30 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say Please save all work!"
    sleep 15
    echo -e "[i] Server restarting in 15 seconds...\\n    - Warning users to save their work within 15 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is restarting in 15 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say Please save all work NOW!"
    sleep 10
    echo -e "[i] Server restarting in  5 seconds...\\n    - Warning users to save their work within  5 seconds..."
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say The server is restarting in 5 seconds!"
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say Please save all work NOW!"
    sleep 5
    echo -e "[i] Server restarting...\\n"
    mcrcon -H $IP -P $PORT -p $PW -w 2 "say Server restarting!" save-all stop && \
    sudo killall -9 java && \
    echo -e "[i] Executing command: screen -d -m -S mc ./$SCRIPT\\n    - Please wait for the server to completely load before reconnecting.\\n"
    screen -d -m -S mc ./$SCRIPT
    echo
elif [[ $i -eq 4 ]]; then
    clear; ls -1AXhF --group-directories-first --color
fi
