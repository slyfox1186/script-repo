#!/bin/bash

########################################################################################
##
## Script version 1.00
##
## This script is meant for use on distro Ubuntu Jammy LTS (22.04.1)
##
## Purpose: Install desireable runtime and developmental packages
##          used to build packages from source code.
##
## Packages you can build from source code include:
##          1) FFmpeg
##          2) More to come with future updates (check script version number at the top)
##
########################################################################################

clear

# Set global variables
VERSION='1.00'

echo "Script version ${VERSION}"
echo

# function to determine if a package is installed or not
installed()
{
    return "$(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 |
    awk '/ok installed/{print 0;exit}{print 1}')"
}

# function to exit the script
exit_fn()
{
    echo 'Installation complete.'
    echo
    exit
}

# function to install nvidia driver if user chooses to
geforce_fn()
{
    for PKG5 in "${PKGS5[@]}"
    do
        if ! installed "${PKG5}"; then
            MISSING_PKGS5+=" ${PKG5}"
        fi
    done

    echo "Installing: Geforce Video Driver ${PKGS5:14}:"
    echo '=========================================='
    if [ -n "${MISSING_PKGS5}" ]; then
        EXECUTE_CMD5="apt -y install${MISSING_PKGS5}"
        echo ${EXECUTE_CMD5}
        echo
        echo 'The Geforce video driver was successfully installed!'
        echo
        echo 'Do you want to reboot now?'
        echo
        read -p 'Enter: [Y]es or [N]o: ' ANSWER
        if [ "${ANSWER}" = 'Y' ]; then
            reboot
        else
            echo
            echo 'Make sure to reboot asap to enable the newly installed video drivers!'
            echo
        fi
    else
        echo "The Geforce Video Driver ${PKGS5:14} is installed."
        echo
    fi
}

#######################
## Standard Packages ##
#######################
PKGS1=(alien aptitude aria2 autoconf autogen autogen-doc automake autopoint bash-completion binutils bison ccache colordiff curl ddclient dnstop dos2unix git gitk gnome-text-editor gparted grub-customizer highlight htop idn2 iftop libtool lshw lzma man-db moreutils nano net-tools network-manager openssh-client openssh-server openssl p7zip-full patch php-cli php-curl php-intl php-sqlite3 python3 python3-html5lib python3-idna python3-pip qemu rpm sqlite3 wget xsltproc)

for PKG1 in "${PKGS1[@]}"
do
    if ! installed "${PKG1}"; then
        MISSING_PKGS1+=" ${PKG1}"
    fi
done

echo 'Installing: Standard Packages'
echo '=========================================='
if [ -n "${MISSING_PKGS1}" ]; then
    EXECUTE_CMD1="apt -y install${MISSING_PKGS1}"
    ${EXECUTE_CMD1}
    echo
else
    echo 'All Standard Packages are installed.'
    echo
fi

#####################################
## Development Libraries - General ##
#####################################
# Note: gcc-multilib was uninstalled when gcc-10-i686-linux-gnu-base was installed.
PKGS2=(binutils-dev build-essential cmake dbus-x11 device-tree-compiler disktype doxygen dpkg-dev fftw-dev flex g++ gawk gcc-10-i686-linux-gnu gcc-10-i686-linux-gnu-base gcc-10-multilib gcc-10-cross-base-ports gengetopt gperf gtk-doc-tools intltool lib32stdc++6 lib32z1 libbz2-dev libcppunit-dev libdmalloc-dev libfl-dev libgc-dev libghc-html-conduit-dev libghc-html-dev libghc-http2-dev libghc-http-api-data-dev libghc-http-client-dev libghc-http-client-tls-dev libghc-http-common-dev libghc-http-conduit-dev libghc-http-date-dev libghc-http-dev libghc-http-link-header-dev libghc-http-media-dev libghc-http-reverse-proxy-dev libghc-http-streams-dev libghc-http-types-dev libglib2.0-dev libgvc6 libgvc6-plugins-gtk libheif-dev libhttp-parser-dev libimage-librsvg-perl libjemalloc-dev libjxp-java libjxr0 libjxr-tools liblz-dev liblzma-dev liblzo2-dev libncurses5 libncurses5-dev libnet-ifconfig-wrapper-perl libnet-nslookup-perl libnghttp2-dev libpstoedit-dev libraqm0 libraqm-dev libraw20 libraw-dev librsvg2-bin librsvg2-dev librsvg2-doc libsdl-pango1 libsdl-pango-dev libssl-dev libstdc++5 libtool-bin libzstd1 libzstd-dev libzzip-dev lzma-dev make mtd-utils r-cran-rsvg ruby-rsvg2 shtool texinfo u-boot-tools uuid-dev wget2-dev)

for PKG2 in "${PKGS2[@]}"
do
    if ! installed "${PKG2}"; then
        MISSING_PKGS2+=" ${PKG2}"
    fi
done

echo 'Installing: General Development Libraries'
echo '=========================================='
if [ -n "${MISSING_PKGS2}" ]; then
    EXECUTE_CMD2="apt -y install${MISSING_PKGS2}"
    ${EXECUTE_CMD2}
    echo
else
    echo 'All General Development Libraries are installed.'
    echo
fi

#####################################
## Development Libraries - GParted ##
#####################################
PKGS3=(btrfs-progs exfat-fuse exfatprogs f2fs-tools hfsprogs hfsutils jfsutils libtsk-dev nilfs-tools reiser4progs reiserfsprogs)

for PKG3 in "${PKGS3[@]}"
do
    if ! installed "${PKG3}"; then
        MISSING_PKGS3+=" ${PKG3}"
    fi
done

echo 'Installing: GParted Development Libraries'
echo '=========================================='
if [ -n "${MISSING_PKGS3}" ]; then
    EXECUTE_CMD3="apt -y install${MISSING_PKGS3}"
    ${EXECUTE_CMD3}
    echo
else
    echo 'All GParted Development Libraries are installed.'
    echo
fi

####################################
## Development Libraries - FFmpeg ##
####################################
PKGS4=(bzip2-doc git google-perftools libaom-dev libass-dev libzip-dev libdav1d-dev libfreetype6-dev libgoogle-perftools-dev libgoogle-perftools4 libmp3lame-dev libnuma-dev libsdl2-dev libunistring-dev libva-dev libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev m4 meson nasm ninja-build pkg-config yasm zlib1g-dev)

for PKG4 in "${PKGS4[@]}"
do
    if ! installed "${PKG4}"; then
        MISSING_PKGS4+=" ${PKG4}"
    fi
done

echo 'Installing: FFmpeg Development Libraries'
echo '=========================================='
if [ -n "${MISSING_PKGS4}" ]; then
    EXECUTE_CMD4="apt -y install${MISSING_PKGS4}"
    ${EXECUTE_CMD4}
    echo
else
    echo 'All FFmpeg Development Libraries are installed.'
    echo
fi

###########################
## Upgrade: Python3 pip3 ##
###########################
echo 'Upgrading: Python3 Pip3:'
echo '=========================================='
sudo -u jman bash -c 'pip install --upgrade pip'
echo

######################################
## Installing: Python3 pip3 Modules ##
######################################
echo 'Installing: Python3 Pip3 Modules:'
echo '=========================================='
sudo -u jman bash -c '\
    pip install \
        --use-pep517 \
        "ansicolors >= 1.1.8" \
        "attrs >= 22.1.0" \
        "beautiful >= 0.0.2" \
        "beautiful-console >= 0.7" \
        "beautiful-time >= 0.2" \
        "beautifulsoup4 >= 4.11.1" \
        "black >= 22.10.0" \
        "boto3 >= 1.25.4" \
        "botocore >= 1.28.4" \
        "certifi >= 2022.9.24" \
        "chardet2 >= 2.0.3" \
        "click >= 8.1.3" \
        "cliff == 2.7.0" \
        "clip >= 0.1.0" \
        "colorama == 0.4.4" \
        "cryptography >= 0.3.2" \
        "emoji >= 2.2.0" \
        "ffpb >= 0.4.1" \
        "Flask >= 2.2.2" \
        "google-api-core >= 2.10.2" \
        "http_request >= 1.2" \
        "idna >= 3.4" \
        "jinja2 >= 3.1.2" \
        "jmespath >= 1.0.1" \
        "matplotlib <= 3.6.1" \
        "mbp >= 1.5.0" \
        "moviepy >= 1.0.3" \
        "muti-thread >= 1.1.10" \
        "numpy >= 1.23.4" \
        "open-url >= 2.1.0" \
        "os-shell >= 1.0.3" \
        "pandas >= 1.5.1" \
        "pendulum >= 2.1.2" \
        "pillow >= 9.3.0" \
        "pip-search-color >= 0.2.7" \
        "progress >= 1.6" \
        "prompt-toolkit >= 3.0.31" \
        "pybeauty >= 1.0" \
        "pytest >= 7.2.0" \
        "pytest-subprocess >= 1.4.2" \
        "python-dateutil >= 2.8.2" \
        "pyyaml == 5.4.1" \
        "request-boost >= 0.6" \
        "request-params >= 0.0.3" \
        "requests >= 2.28.1" \
        "request_tester >= 0.18" \
        "s3transfer >= 0.6.0" \
        "scikit-learn >= 1.1.3" \
        "seaborn >= 0.12.1" \
        "setuptools >= 65.5.0" \
        "shell >= 1.0.1" \
        "shell-cache >= 2020.12.3" \
        "shell-multiprocess >= 1.0.2" \
        "shell-proc >= 1.2.1" \
        "shell-scripter >= 0.0.1" \
        "simplejson >= 3.17.6" \
        "six >= 1.16.0" \
        "terminaltables >= 3.1.10" \
        "termius >= 1.2.15" \
        "tqdm >= 4.64.1" \
        "tqdm-thread >= 0.1.1" \
        "twine >= 4.0.1" \
        "typing-extensions >= 4.4.0" \
        "unc2url >= 0.1.0" \
        "url-downloader >= 1.0.5" \
        "url-matcher >= 0.2.0" \
        "url-regex >= 1.0.4" \
        "url-scraper >= 1.0.2" \
        "url-strip >= 0.2.1" \
        "url2text >= 0.7" \
        "url2word >= 0.1.5" \
        "urllib3 >= 1.26.12"
'
echo

##############################
## GEFORCE VIDEO DRIVER 520 ##
##############################

PKGS5=(nvidia-driver-520)

echo "Do you want to install: ${PKGS5}?"
  echo '
  1) Yes
  2) No
  '

read -p 'Your choice (1 or 2): ' CHOICE
echo

# case code
case ${CHOICE} in
    1|Yes|Y|y)
        echo 'You chose Yes'
        echo
        geforce_fn
        exit_fn
        ;;
    2|No|N|n)
        echo 'You chose No'
        echo
        exit_fn
        ;;
    *)
        echo 'Invalid selection'
        echo
        echo 'The script will now exit with value 1'
        echo
        exit 1
        ;;
esac
