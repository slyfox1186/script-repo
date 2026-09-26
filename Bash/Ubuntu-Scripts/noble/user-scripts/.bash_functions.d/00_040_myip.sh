#!/usr/bin/env bash

myip() {
    echo "LAN: $(ip route get 1.2.3.4 | awk '{print $7}')"
    echo "WAN: $(curl -fsS "https://checkip.amazonaws.com")"
}
