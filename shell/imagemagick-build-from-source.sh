    #!/bin/bash

    #################################################################
    ##
    ## GitHub: https://github.com/slyfox1186
    ##
    ## Purpose: Builds ImageMagick 7 from source code that is
    ##          obtained from their official GitHub page.
    ##
    ## Function: ImageMagick is the leading open source command line
    ##           image processor. It can blur, sharpen, warp, reduce,
    ##           file size, ect... It is fantastic.
    ##
    ## Last Updated: 01.30.23
    ##
    #################################################################

    clear
    set -u

    ##
    ## VERIFY THAT THE SCRIPT HAS ROOT ACCESS BEFORE CONTINUING
    ##

    if [ "${EUID}" -gt '0' ]; then
        echo 'You must run this script as root/sudo'
        echo
        exit 1
    fi

    ##
    ## IMAGEMAGICK VERSION
    ##

    IMVER='7.1.0-60'
    LVER='1.2.59'

    ######################
    ## CREATE FUNCTIONS ##
    ######################

    ##
    ## EXIT SCRIPT
    ##

    exit_fn()
    {
        clear

        # SHOW THE NEWLY INSTALLED MAGICK VERSION
        if ! magick -version 2>/dev/null; then
            clear
            echo "Error: the script failed to execute the command 'magick -version'."
            echo
            echo 'Info: try running the command manually to see if it will work.'
            echo
            echo 'If needed, create a support ticket: https://github.com/slyfox1186/script-repo/issues'
            echo
            exit 1
        fi

        echo
        echo 'The script has finished.'
        echo '=========================='
        echo
        echo 'Make sure to star this repository to show your support!'
        echo 'https://github.com/slyfox1186/script-repo'
        echo
        rm -f "${0}"
        exit 0
    }

    ##
    ## DELETE FILES
    ##

    del_files_fn()
    {
        if [[ "${1}" -eq '1' ]]; then
            rm -fr "${2}" "${3}" "${4}" "${5}"
        elif [[ "${1}" -eq '2' ]]; then
            exit_fn
        else
            echo 'Error: Bad user input.'
            echo
            read -p 'Press Enter to exit.'
            exit_fn
        fi
    }

    # function to determine if a package is installed or not
    installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

    ##
    ## Required ImageMagick Developement Packages
    ##
        
    magick_packages_fn()
    {
        clear
        echo 'Installing: ImageMagick Developement Packages'
        echo '=============================================='
        sleep 3

        PKGS=(autoconf automake build-essential google-perftools libc-devtools libcpu-features-dev libcrypto++-dev libdmalloc-dev libdmalloc5 libgc-dev libgc1 libgl2ps-dev libglib2.0-dev libgoogle-perftools-dev libgoogle-perftools4 libheif-dev libjemalloc-dev libjemalloc2 libjpeg-dev libmagickcore-6.q16hdri-dev libmimalloc-dev libmimalloc2.0 libopenjp2-7-dev libpng++-dev libpng-dev libpng-tools libpng16-16 libpstoedit-dev libraw-dev librust-bzip2-dev librust-jpeg-decoder+default-dev libtcmalloc-minimal4 libtiff-dev libtool libwebp-dev libzip-dev pstoedit)

        for PKG in ${PKGS[@]}
        do
            if ! installed "${PKG}"; then
                MISSING_PKGS+=" ${PKG}"
            fi
        done
        
        if [ -n "${MISSING_PKGS-}" ]; then
            for i in "${MISSING_PKGS}"
            do
                apt -y install ${i}
            done
            echo 'The ImageMagick Development Libraries have been installed.'
        else
            clear
            echo 'The ImageMagick Development Libraries are already installed.'
        fi
        
        sleep 3
        clear
    }

    clear
    echo 'Starting libpng12 build'
    echo '=========================='
    echo
    sleep 2

    # set variables for libpng12
    LURL="https://sourceforge.net/projects/libpng/files/libpng12/${LVER}/libpng-${LVER}.tar.xz/download"
    LDIR="libpng-${LVER}"
    LTAR="${LDIR}.tar.xz"

    # download libpng12 source code
    if [ ! -f "${LTAR}" ]; then wget --show-progress -cqO "${LTAR}" "${LURL}"; fi

    # uncompress source code to folder
    if ! tar -xf "${LTAR}"; then
        clear
        echo 'Error: The tar command failed to extract the downloaded file.'
        echo
        echo 'Please create a support ticket: https://github.com/slyfox1186/script-repo/issues'
        echo
        exit 1
    fi

    # CHANGE WORKING DIRECTORY TO LIBPNG'S SOURCE CODE DIRECTORY
    cd "${LDIR}" || exit 1

    # NEED TO RUN AUTOGEN SCRIPT FIRST SINCE THIS IS A WAY NEWER SYSTEM THAN THESE FILES ARE USED TO
    ./autogen.sh

    # RUN CONFIGURE SCRIPT
    ./configure --prefix='/usr/local'

    # INSTALL LIBPNG12
    make install

    # CHANGE WORKING DIRECTORY BACK TO PARENT FOLDER
    cd ../ || exit 1

    ##
    ## START IMAGEMAGICK BUILD
    ##

    clear
    echo 'Starting ImageMagick Build'
    echo '=============================='
    echo
    sleep 2

    # REQUIRED + EXTRA OPTIONAL PACKAGES FOR IMAGEMAGICK TO BUILD SUCCESSFULLY
    magick_packages_fn

    # SET VARIABLES FOR IMAGEMAGICK
    IMURL='https://imagemagick.org/archive/ImageMagick.tar.gz'
    IMDIR="ImageMagick-${IMVER}"
    IMTAR="${IMDIR}.tar.gz"

    # DOWNLOAD IMAGEMAGICK SOURCE CODE
    if [ ! -f "${IMTAR}" ]; then
        echo 'Downloading ImageMagick Source Code'
        echo '======================================'
        echo
        wget --show-progress -cqO "${IMTAR}" "${IMURL}"
        clear
    fi

    # CREATE OUTPUT FOLDER FOR TAR FILES
    if [ ! -d "${IMDIR}" ]; then
        mkdir -p "${IMDIR}"
    fi

    # UNCOMPRESS SOURCE CODE TO FOLDER
    if ! tar -xf "${IMTAR}"; then
        clear
        echo 'Error: The tar command failed to extract any files'
        echo
        echo 'Please create a support ticket: https://github.com/slyfox1186/script-repo/issues'
        echo
        exit 1
    fi

    cd "${IMDIR}" || exit 1

    # EXPORT THE PKG CONFIG PATHS TO ENABLE SUPPORT DURING THE BUILD
    PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
    export PKG_CONFIG_PATH

    ./configure \
        --enable-ccmalloc \
        --enable-legacy-support \
        --with-autotrace \
        --with-dmalloc \
        --with-flif \
        --with-gslib \
        --with-heic \
        --with-jemalloc \
        --with-modules \
        --with-perl \
        --with-tcmalloc \
        --with-quantum-depth=16

    # RUNNING MAKE COMMAND WITH PARALLEL PROCESSING
    echo "executing: make -j$(nproc --all)"
    echo '==================================='
    echo
    make "-j$(nproc -all)"

    # INSTALLING FILES TO /usr/local/bin/
    echo
    echo 'executing: make install'
    echo '==================================='
    echo
    make install

    # LDCONFIG MUST BE RUN NEXT IN ORDER TO UPDATE FILE CHANGES OR THE MAGICK COMMAND WILL NOT WORK
    ldconfig /usr/local/lib >dev/null

    # CD BACK TO THE PARENT FOLDER
    cd ../ || exit 1

    # PROMPT USER TO CLEAN UP BUILD FILES
    echo
    echo 'Do you want to remove the build files?'
    echo '======================================'
    echo
    echo '[1] Yes'
    echo '[2] No'
    echo
    read -p 'Your choices are (1 or 2): ' ANSWER
    clear

    del_files_fn "${ANSWER}" "${LDIR}" "${IMDIR}" "${LTAR}" "${IMTAR}"
    exit_fn
