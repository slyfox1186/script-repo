# Script-Repository
## Comprised of a mix of my favorite scripts for both Windows and Linux.

### This repository was created as a way to share my most useful custom scripts in the hopes that they
  - Are a benefit to others
  - To make them open to the public with the hope that it will lead to improvements in the each scripts overall efficiency and usefulness.
  
### The script languages
  - AutoHotkey
  - Batch
  - Powershell
  - Shell / Bash
  - Windows Registry.



## The filter lists
  - **[Adlist](https://raw.githubusercontent.com/slyfox1186/pihole-regex/main/domains/adlist/adlists.txt)**
  - **[Exact Blacklist](https://raw.githubusercontent.com/slyfox1186/pihole-regex/main/domains/blacklist/exact-blacklist.txt)**
  - **[Exact Whitelist](https://raw.githubusercontent.com/slyfox1186/pihole-regex/main/domains/whitelist/exact-whitelist.txt)**
  - **[RegEx Blacklist](https://raw.githubusercontent.com/slyfox1186/pihole-regex/main/domains/blacklist/regex-blacklist.txt)**
  - **[RegEx Whitelist](https://raw.githubusercontent.com/slyfox1186/pihole-regex/main/domains/whitelist/regex-whitelist.txt)**
  
## Requirements and other important information
* **Made for:** Pi-hole (FTLDNS) v5+
  - Website: [https://pi-hole.net/](https://pi-hole.net/)

* **Required Packages:**
  - **Python3**
    - sudo apt install python3
  - **SQLite3**
    - sudo apt install sqlite3

* **Adlist info:** If you choose the "remove adlists" option it should only affect the lists added by this script.

## If you're *not* on the PC that's running Pi-hole
* **Use your ssh client of choice (examples below)**
  - **[OpenSSH](https://www.openssh.com/)**
  - **[PuTTY](https://www.putty.org/)**
  - **[Termius](https://termius.com/)**

## **The user will be prompted to press a key to advance their choices**
* **Input examples**
  - **[A]** to ***Add***
  - **[R]** to ***Remove***
  - **[S]** to ***Skip***
  - ***Any number***

## To execute, run one of the below commands

### RegEx and Exact
```
wget -qN - -i https://pi.optimizethis.net; sudo bash run.sh
```
### Adlists
```
wget -qO adlist.sh https://adlist.optimizethis.net; sudo bash adlist.sh
```
