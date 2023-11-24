#!/usr/bin/env bash

########################################################################################################################################
##
##  GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/install-discord.sh
##
##  Purpose: Install the latest Discord version sourced from the official website
##
##  Features: Fully automated, self-updating script.
##
##  Updated: 11.24.23
##
##  Script version: 1.1
##
##  Improvements:
##                - All scripts will be run in a random temporary directory to avoid any possible unforeseen problems that happen
##                  when you run a script in an unknown directory that contains many unknown files that could have the same names.
##
########################################################################################################################################

clear

if [ "${EUID}" -eq '0' ]; then
    printf "%s\n\n" 'You must run this script WITHOUT root/sudo.'
    exit 1
fi

# CREATE VARIABLES
script_ver=1.1
random_dir="$(mktemp -d)"
cwd="${PWD}"
current_ver=35
cnt="${current_ver}"
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

# DISPLAY SCRIPT VERSION
printf "%s\n%s\n\n"                                 \
    "Discord Update Script - version ${script_ver}" \
    '======================================================'
sleep 2

# COPY THE MASTER SCRIPT TO THE RANDOM DIRECTORY AND CD INTO IT
cp "${cwd}"/install-discord.sh "${random_dir}"
cd "${random_dir}" || exit 1

# INSTALL REQUIRED APT PACKAGES
pkgs=(curl wget)

for pkg in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "${pkg}")"

    if [ -z "${missing_pkg}" ]; then
        missing_pkgs+=" ${pkg}"
    fi
done

if [ -n "${missing_pkgs}" ]; then
    sudo apt -y install ${missing_pkgs}
    clear
else
    printf "%s\n" 'The APT packages are already installed'
fi

# CREATE DISCORD DOWNLOAD SCRIPT
cat > 'download_discord.sh' <<EOF
#!/usr/bin/env bash

clear

user_agent='${user_agent}'

printf "%s\n%s\n"        \\
    'Installing Discord' \\
    '==================================='
sleep 2

#
# DOWNLOAD THE DISCORD DEBIAN ARCHIVE
#

if [ ! -f 'discord-0.0.${current_ver}.deb' ]; then
    wget --show-progress -U '${user_agent}' -cq 'https://dl.discordapp.net/apps/linux/0.0.${current_ver}/discord-0.0.${current_ver}.deb'
fi
EOF

# DISCOVER THE LATEST UPDATE
until false
do
    test_url="$(curl -A "${user_agent}" -is "https://dl.discordapp.net/apps/linux/0.0.${cnt}/discord-0.0.${cnt}.deb" | head -n 1 | grep -o '200')"
    if [[ "${test_url}" != '200' ]]; then
        ((cnt--))
        latest_ver="${cnt}"
        break
    elif [[ "${test_url}" = '200' ]]; then
        ((cnt++))
        continue
    fi
done

# PARSE THE CURRENT VERSION AND INSTALL DISCORD
if [ "${latest_ver}" = "${current_ver}" ]; then
    clear
    printf "%s\n\n%s\n\n"                      \
        'The Discord version has not changed!' \
        'Executing install script in 5 seconds...'
    sleep 5
else
    clear
    printf "%s\n\n%s\n\n"                     \
        'A new Discord version was detected!' \
        'Executing install script in 5 seconds...'
    sleep 5
    # UPDATE THE INSTALLER SCRIPT WITH THE CURRENT VERSION
    sed -i "s/0.0.${current_ver}/0.0.${latest_ver}/g" 'download_discord.sh'
    # UPDATE THE MASTER SCRIPT WITH THE CURRENT VERSION
    cp -f 'install-discord.sh' 'install-discord.bak'
    sed -E -i "s/^current_ver\=[0-9]+/current_ver\=${latest_ver}/g" 'install-discord.bak'
    mv 'install-discord.bak' "${cwd}/install-discord.sh"
fi

# CONCAT THE INSTALL CODE TO THE DOWNLOAD SCRIPT
cat >> 'download_discord.sh' <<'EOF'

for i in *.deb
do
    printf "\n%s\n%s\n"                           \
        "Executing the Debian archive file: ${i}" \
        '==============================================='
    sudo apt -y install ./"${i}"
    sudo rm "${i}"
done
EOF

# EXECUTE THE DOWNLOAD SCRIPT
bash 'download_discord.sh'

# REMOVE THE LEFTOVER FILES
sudo rm -fr "${random_dir}"
