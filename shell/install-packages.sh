#!/bin/bash

######################################################################################################
##
##  Script Version: 2.00
##
##  Distro Targets:
##
##           1) Ubuntu Jammy LTS (22.04.1)
##
##  Script Purpose:
##
##           1) Install the most useful runtime packages (popular)
##           2) Install development packages that can be used to compile specific programs from source
##
##  Development Binaries Supported:
##
##           1) FFmpeg (latest stable)
##           2) ImageMagick (latest stable)
##
##  Updates: v2.0)
##
##           1) Added new functions and user menus
##           2) Replaced inferior packages with ones that have more functionality
##           3) Added synaptic (apt packaged manager)
##           4) Added batcat (cat command replacement)
##           5) Added pipenv (virtual environment to run pip packages)
##
##  Instructions:
##
##           1) You must run this script twice due to certain libraries needing to be installed
##              before the other packages have the required files to install themselves
##
######################################################################################################

clear

# VERIFY THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
if [[ "${EUID}" -gt '0' ]]; then
    echo 'You must run this script as root/sudo'
    exit 1
fi

# SET VARIABLES
VERSION='2.00'
echo "Script version ${VERSION}"
echo

# FUNCTION TO DETERMINE IF A
# function to determine if a package is installed or not
installed()
{
    return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1|awk '/ok installed/{print 0;exit}{print 1}')
}

# function to exit the script
exit_fn()
{
    echo
    echo 'Endo of Script.'
    echo
    echo 'This script wil remove itself from your pc in 5 seconds.'
    echo
    echo 'Press Ctrl+Z to force exit the script and prevent it from being removed from your pc.'
    echo
    read -t 10 -p 'Press enter to skip waiting.'
    clear
    rm -r "${0}"
    exit
}


apt1_fn()
{
    clear
    sudo apt autoremove -y
}

apt2_fn()
{
    clear
    sudo apt clean
    sudo apt autoclean
    sudo apt autoremove -y
}

cleanup_fn()
{
    # case code
    case ${1} in
        1)
            echo 'Running: sudo apt autoremove -y'
            echo
            apt1_fn
            exit_fn
            ;;
        2)
            echo 'Running: sudo apt clean; sudo apt autoclean; sudo apt autoremove -y'
            echo
            apt2_fn
            exit_fn
            ;;
        3)
            echo 'This script is exiting.'
            sleep 2
            exit_fn
            ;;
        *)
            echo 'Invalid selection'
            sleep 2
            clear
            cleanup_fn
            ;;
    esac
}

geforce_menu_fn()
{
    # case code
    case ${1} in
        1|Yes|Y|y)
            echo 'You chose install the Geforce Drivers'
            echo
            geforce_fn
            return
            ;;
        2|No|N|n)
            echo 'You chose not to install the Geforce Drivers'
            echo
            return
            ;;
        *)
            echo 'Invalid selection'
            sleep 2
            clear
            geforce_menu_fn
            ;;
    esac
}

# function to install nvidia driver if user chooses to
geforce_fn()
{
    for PKG in ${PKGS[@]}
    do
        if ! installed "${PKG}"; then
            MISSING_PKGS+=" ${PKG}"
        fi
    done

    echo "Installing: Geforce Video Driver ${PKGS:14}:"
    echo '=========================================='
    if [ -n "${MISSING_PKGS}" ]; then
        apt -y install"${MISSING_PKGS}"
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
        unset ANSWER
    else
        echo "The Geforce Video Driver ${PKGS:14} is already installed."
        echo
    fi
}


installed()
{
    return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1|awk '/ok installed/{print 0;exit}{print 1}')
}


###################
## INSTALL PPA'S ##
###################
if ! which grub-customizer >/dev/null 2>&1; then
    add-apt-repository ppa:'danielrichter2007/grub-customizer' -y
fi

#######################
## Standard Packages ##
#######################
PKGS=(alien aptitude aria2 autoconf autogen autogen-doc automake autopoint bash-completion bat binutils bison ccache colordiff curl ddclient dnstop dos2unix git gitk gnome-text-editor gnome-tweaks gparted grub-customizer gufw highlight htop idn2 iftop lshw lzma man-db moreutils nano net-tools network-manager openssh-client openssh-server openssl p7zip-full patch pcre2-utils pcregrep php-cli php-curl php-intl php-sqlite3 pipenv python3 python3-html5lib python3-idna python3-pip qemu rpm sqlite3 synaptic wget xsltproc)

for PKG in "${PKGS[@]}"
do
    if ! installed "${PKG}"; then
        MISSING_PKGS+=" ${PKG}"
    fi
done

echo 'Installing: Standard Packages'
echo '=========================================='
if [ -n "${MISSING_PKGS}" ]; then
    apt -y install"${MISSING_PKGS}"
    echo
else
    echo 'The Standard Packages are already installed.'
    echo
fi
unset MISSING_PKGS

PKGS=(autodep8 automake1.11 autopkgtest autoproject bcpp bind9-dev binutils-dev binutils-multiarch binutils-multiarch-dev bisonc++ build-essential calc-dev cargo ccbuild ccdiff clang clang-11 clang-12 clang-13 clang-14 clang-format clang-format-11 clang-format-12 clang-format-13 clang-format-14 clang-tidy clang-tidy-11 clang-tidy-12 clang-tidy-13 clang-tidy-14 clang-tools cmake cmake-extras copyright-update cppcheck-gui cpplint crossbuild-essential-amd64 cutils dbus-x11 debcargo device-tree-compiler devscripts diffstat disktype doxygen dpkg-dev dput erlang-base erlang-ssh erlang-ssl erlang-syntax-tools erlang-tools fasm fastboot fftw-dev flex g++ gawk gcc-10-cross-base-ports gcc-10-multilib gccgo-10 gccgo-11 gccgo-12 gccgo-9 gcc-multilib gcc-opt gengetopt gobjc++-10-multilib gobjc++-12 gobjc++-12-multilib golang gperf gtk-doc-tools intltool ir.lv2 lib32stdc++6 lib32z1 libbz2-dev libcppunit-dev libdmalloc-dev libfl-dev libgc-dev libghc-html-conduit-dev libghc-html-dev libghc-http2-dev libghc-http-api-data-dev libghc-http-client-dev libghc-http-client-tls-dev libghc-http-common-dev libghc-http-conduit-dev libghc-http-date-dev libghc-http-dev libghc-http-link-header-dev libghc-http-media-dev libghc-http-reverse-proxy-dev libghc-http-streams-dev libghc-http-types-dev libglib2.0-dev libgvc6 libgvc6-plugins-gtk libheif-dev libhttp-parser-dev libimage-librsvg-perl libjemalloc-dev libjxp-java libjxr0 libjxr-tools liblilv-dev liblvm2-dev liblz-dev liblzma-dev liblzo2-dev libmimalloc2.0 libmimalloc-dev libnabrit-dev libncurses5 libncurses5-dev libnet-ifconfig-wrapper-perl libnet-nslookup-perl libnghttp2-dev libperl-dev libpstoedit-dev libraqm0 libraqm-dev libraw20 libraw-dev librsvg2-bin librsvg2-dev librsvg2-doc librust-jemalloc-sys-dev librust-malloc-buf-dev libsdl-pango1 libsdl-pango-dev libsratom-dev libssl-dev libstdc++5 libsuil-0-0 libtalloc-dev libtbbmalloc2 libtool libtool-bin libvslvm-dev libzstd1 libzstd-dev libzzip-dev lilv-utils lintian linux-source llvm llvm-13 llvm-dev lv2-dev lv2file lv2vocoder lzma-dev make mono-devel mtd-utils python3-talloc-dev r-cran-rsvg repo ripper ruby-all-dev ruby-dev ruby-rsvg2 rustc rust-src shtool tcl-dev texinfo tk-dev tkpng tty-share u-boot-tools ui-auto uuid-dev wget2-dev zipalign)

for PKG in "${PKGS[@]}"
do
if ! installed "${PKG}"; then
        MISSING_PKGS+=" ${PKG}"
    fi
done

echo 'Installing: General Dev Libraries'
echo '=========================================='
if [ -n "${MISSING_PKGS}" ]; then
    apt -y install"${MISSING_PKGS}"
    echo
else
    echo 'The General Devlopment Packages are already installed.'
    echo
fi
unset MISSING_PKGS

#####################################
## Development Libraries - GParted ##
#####################################
PKGS=(btrfs-progs exfat-fuse exfatprogs f2fs-tools hfsprogs hfsutils jfsutils libtsk-dev nilfs-tools reiser4progs reiserfsprogs)

for PKG in "${PKGS[@]}"
do
    if ! installed "${PKG}"; then
        MISSING_PKGS+=" ${PKG}"
    fi
done

echo 'Installing: GParted Development Libraries'
echo '=========================================='
if [ -n "${MISSING_PKGS}" ]; then
    apt -y install"${MISSING_PKGS}"
    echo
else
    echo 'The GParted Development Packages are already installed.'
    echo
fi
unset MISSING_PKGS

####################################
## Development Libraries - FFmpeg ##
####################################
PKGS=(bzip2-doc git google-perftools libaom-dev libass-dev libzip-dev libdav1d-dev libfreetype6-dev libgoogle-perftools-dev libgoogle-perftools4 libmp3lame-dev libnuma-dev libsdl2-dev libunistring-dev libva-dev libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev m4 meson nasm ninja-build pkg-config yasm zlib1g-dev)

for PKG in "${PKGS[@]}"
do
    if ! installed "${PKG}"; then
        MISSING_PKGS+=" ${PKG}"
    fi
done

echo 'Installing: FFmpeg Development Libraries'
echo '=========================================='
if [ -n "${MISSING_PKGS}" ]; then
    apt -y install"${MISSING_PKGS}"
    echo
else
    echo 'The FFmpeg Development Packages are already installed.'
    echo
fi
unset MISSING_PKGS

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
        "urllib3 >= 1.26.12" \
        1>&- 2>&-
'

##############################
## GEFORCE VIDEO DRIVER 520 ##
##############################

clear

PKGS=(nvidia-driver-520)

clear
echo "Do you want to install: ${PKGS}?"
echo '
    1) Yes
    2) No
'

read -p 'Your choices are (1 or 2): ' ANSWER
echo

geforce_menu_fn "${ANSWER}"
unset ANSWER

#####################################
## PROMPT USER TO CLEANUP PACKAGES ##
#####################################

clear

echo 'Do you want to run: sudo apt'
echo
echo '1) autoremove'
echo '2) clean | autoclean | autoremove'
echo '3) exit menu'

read -p 'Your choices are (1 to 3): ' ANSWER
echo

cleanup_fn "${ANSWER}"
unset ANSWER
