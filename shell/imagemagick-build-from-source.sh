    #!/bin/bash

    #################################################################
    ##
    ## GITHUB: HTTPS://GITHUB.COM/SLYFOX1186
    ##
    ## PURPOSE: BUILDS IMAGEMAGICK 7 FROM SOURCE CODE THAT IS
    ##          OBTAINED FROM THE OFFICIAL IMAGEMAGICK GITHUB PAGE.
    ##
    ## FUNCTION: IMAGEMAGICK IS THE LEADING OPEN SOURCE COMMAND LINE
    ##           IMAGE PROCESSOR. IT CAN BLUR, SHARPEN, WARP, REDUCE
    ##           FILE SIZE, ECT... IT IS FANTASTIC.
    ##
    ## LAST UPDATED: 02.16.23
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
    ## VERSION INFORMATION VARIABLES
    ##

    script_ver='1.62'
    imver='7.1.0-62'
    pngver='1.2.59'

    ######################
    ## CREATE FUNCTIONS ##
    ######################

    ##
    ## EXIT SCRIPT FUNCTION
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
    ## DELETE FILES FUNCTION
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

    # FUNCTION TO DETERMINE IF A PACKAGE IS INSTALLED OR NOT
    installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

    # FAILED DOWNLOAD/EXTRACTIONS FUNCTION
    extract_fail_fn()
    {
        clear
        echo 'Error: The tar command failed to extract any files.'
        echo
        echo 'Please create a support ticket: https://github.com/slyfox1186/script-repo/issues'
        echo
        exit 1
    }

    ##
    ## REQUIRED IMAGEMAGICK DEVELOPEMENT PACKAGES
    ##
        
    magick_packages_fn()
    {
        clear
        echo 'Installing: ImageMagick Developement Packages'
        echo '=============================================='
        sleep 3

        pkgs=(autoconf automake build-essential google-perftools libc-devtools libcpu-features-dev libcrypto++-dev libdmalloc-dev libdmalloc5 libgc-dev libgc1 libgl2ps-dev libglib2.0-dev libgoogle-perftools-dev libgoogle-perftools4 libheif-dev libjemalloc-dev libjemalloc2 libjpeg-dev libmagickcore-6.q16hdri-dev libmimalloc-dev libmimalloc2.0 libopenjp2-7-dev libpng++-dev libpng-dev libpng-tools libpng16-16 libpstoedit-dev libraw-dev librust-bzip2-dev librust-jpeg-decoder+default-dev libtcmalloc-minimal4 libtiff-dev libtool libwebp-dev libzip-dev pstoedit)

        for pkg in ${pkgs[@]}
        do
            if ! installed "${pkg}"; then
                missing_pkgs+=" ${pkg}"
            fi
        done
        
        if [ -n "${missing_pkgs-}" ]; then
            for i in "${missing_pkgs}"
            do
                apt -y install ${i}
            done
            clear
            echo 'The ImageMagick Development Libraries have been installed.'
        else
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

    # SET VARIABLES FOR LIBPNG12
    pngurl="https://sourceforge.net/projects/libpng/files/libpng12/${pngver}/libpng-${pngver}.tar.xz/download"
    pngdir="libpng-${pngver}"
    pngtar="${pngdir}.tar.xz"

    # DOWNLOAD LIBPNG12 SOURCE CODE
    if [ ! -f "${pngtar}" ]; then
        wget --show-progress -cqO "${pngtar}" "${pngurl}"
    fi

    # UNCOMPRESS SOURCE CODE TO FOLDER
    if ! tar -xf "${pngtar}"; then
        extract_fail_fn
    fi

    # CHANGE WORKING DIRECTORY TO LIBPNG'S SOURCE CODE DIRECTORY
    cd "${pngdir}" || exit 1

    # NEED TO RUN AUTOGEN SCRIPT FIRST SINCE THIS IS A WAY NEWER SYSTEM THAN THESE FILES ARE USED TO
    ./autogen.sh

    # RUN CONFIGURE SCRIPT
    ./configure --prefix='/usr/local'

    # INSTALL LIBPNG12
    make install

    # CHANGE WORKING DIRECTORY BACK TO PARENT FOLDER
    cd ../ || exit 1

    #############################
    ## START IMAGEMAGICK BUILD ##
    #############################

    clear
    echo "Starting ImageMagick Build: v${script_ver}"
    echo '=============================='
    echo
    sleep 3

    # REQUIRED + EXTRA OPTIONAL PACKAGES FOR IMAGEMAGICK TO BUILD SUCCESSFULLY
    magick_packages_fn

    # SET VARIABLES FOR IMAGEMAGICK
    imurl='https://imagemagick.org/archive/ImageMagick.tar.gz'
    imdir="ImageMagick-${imver}"
    imtar="${imdir}.tar.gz"

    # DOWNLOAD IMAGEMAGICK SOURCE CODE
    if [ ! -f "${imtar}" ]; then
        echo 'Downloading ImageMagick Source Code'
        echo '======================================'
        echo
        wget --show-progress -cqO "${imtar}" "${imurl}"
        clear
    fi

    # CREATE OUTPUT FOLDER FOR TAR FILES
    if [ ! -d "${imdir}" ]; then
        mkdir -p "${imdir}"
    fi

    # UNCOMPRESS SOURCE CODE TO FOLDER
    if ! tar -xf "${imtar}"; then
        extract_fail_fn
    fi

    cd "${imdir}" || exit 1

    # EXPORT THE pkg CONFIG PATHS TO ENABLE SUPPORT DURING THE BUILD
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

    del_files_fn "${ANSWER}" "${pngdir}" "${imdir}" "${pngtar}" "${imtar}"
    exit_fn
