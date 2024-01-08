#!/usr/bin/env bash

pkgs_fn()
{
    local libcpp_pkgs pkg pkgs missing_pkg missing_pkgs

    libcpp_pkg="$(sudo apt list libc++* 2>/dev/null | grep -Eo 'libc\+\+-[0-9\-]+-dev' | uniq | sort -r | head -n1)"
    libcppabi_pkg="$(sudo apt list libc++abi* 2>/dev/null | grep -Eo 'libc\+\+abi-[0-9]+-dev' | uniq | sort -r | head -n1)"
    libunwind_pkg="$(sudo apt list libunwind* 2>/dev/null | grep -Eo 'libunwind-[0-9]+-dev' | uniq | sort -r | head -n1)"

    # DEFINE AN ARRAY OF PACKAGE NAMES
    pkgs=(
          autoconf autoconf-archive autogen automake build-essential ca-certificates ccache checkinstall
          clang curl libc-ares-dev libbrotli-dev libcurl4-openssl-dev libdmalloc-dev libgcrypt20-dev
          libgmp-dev libgpg-error-dev libjemalloc-dev libmbedtls-dev libsctp-dev libssh2-1-dev libssh-dev
          libssl-dev libtool libtool-bin libxml2-dev m4 libzstd-dev zlib1g-dev libboost-all-dev libc6-dev
          libcurl4-openssl-dev libcxxtools-dev
    )

    # LOOP THROUGH THE PKGS ARRAY
    missing_pkgs=""
    for pkg in "${pkgs[@]}"
    do
        if [ "$(dpkg-query -W -f='$Status' "$pkg" 2>/dev/null | grep -c 'ok installed')" -eq 0 ]; then
            missing_pkgs+="$pkg "
        fi
    done

    # CHECK IF THERE ARE ANY PKGS TO INSTALL
    if [ -n "$missing_pkgs" ]; then
        printf "\n%s\n\n" "Installing missing apt packages..."
        sudo apt -y install $missing_pkgs
    else
        printf "\n%s\n\n" "All apt packages are already installed."
    fi

    pkgs=(
         $1 $libcppabi_pkg $libcpp_pkg $libunwind_pkg ant apt asciidoc autoconf autoconf-archive
         automake autopoint binutils bison build-essential cargo ccache checkinstall clang clang-tools
         cmake curl default-jdk-headless doxygen fcitx-libs-dev flex flite1-dev freeglut3-dev
         frei0r-plugins-dev gawk gettext gimp-data git gnome-desktop-testing gnustep-gui-runtime
         google-perftools gperf gtk-doc-tools guile-3.0-dev help2man jq junit ladspa-sdk lib32stdc++6
         libamd2 libasound2-dev libass-dev libaudio-dev libavfilter-dev libbabl-0.1-0 libbluray-dev
         libbpf-dev libbs2b-dev libbz2-dev libc6 libc6-dev libcaca-dev libcairo2-dev libcamd2
         libccolamd2 libcdio-dev libcdio-paranoia-dev libcdparanoia-dev libcholmod3 libchromaprint-dev
         libcjson-dev libcodec2-dev libcolamd2 libcrypto++-dev libcurl4-openssl-dev libdbus-1-dev
         libde265-dev libdevil-dev libdmalloc-dev libdrm-dev libdvbpsi-dev libebml-dev libegl1-mesa-dev
         libffi-dev libgbm-dev libgdbm-dev libgegl-0.4-0 libgegl-common libgimp2.0 libgl1-mesa-dev
         libgles2-mesa-dev libglib2.0-dev libgme-dev libgmock-dev libgnutls28-dev libgnutls30
         libgoogle-perftools-dev libgoogle-perftools4 libgsm1-dev libgtest-dev libgvc6 libhwy-dev
         libibus-1.0-dev libiconv-hook-dev libintl-perl libjack-dev libjemalloc-dev libladspa-ocaml-dev
         libleptonica-dev liblz-dev liblzma-dev liblzo2-dev libmathic-dev libmatroska-dev libmbedtls-dev
         libmetis5 libmfx-dev libmodplug-dev libmp3lame-dev libmusicbrainz5-dev libmysofa-dev libnuma-dev
         libopencore-amrnb-dev libopencore-amrwb-dev libopencv-dev libopenjp2-7-dev libopenmpt-dev
         libopus-dev libpango1.0-dev libperl-dev libpstoedit-dev libpulse-dev librabbitmq-dev libraqm-dev
         libraw-dev librsvg2-dev librubberband-dev librust-gstreamer-base-sys-dev libshine-dev
         libsmbclient-dev libsnappy-dev libsndfile1-dev libsndio-dev libsoxr-dev libspeex-dev
         libsqlite3-dev libsrt-gnutls-dev libssh-dev libssl-dev libsuitesparseconfig5 libsystemd-dev
         libtalloc-dev libtheora-dev libticonv-dev libtool libtool-bin libtwolame-dev libudev-dev
         libumfpack5 libv4l-dev libva-dev libvdpau-dev libvidstab-dev libvlccore-dev libvo-amrwbenc-dev
         libvpx-dev libx11-dev libx264-dev libxcursor-dev libxext-dev libxfixes-dev libxi-dev
         libxkbcommon-dev libxrandr-dev libxss-dev libxvidcore-dev libyuv-dev libzmq3-dev libzstd-dev
         libzvbi-dev libzzip-dev llvm lshw lzma-dev m4 mesa-utils meson nasm ninja-build pandoc python3
         python3-pip ragel re2c scons sudo texi2html texinfo tk-dev unzip valgrind wget xmlto zlib1g-dev
)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        if sudo apt -y install $missing_pkgs; then
            sudo apt -y autoremove
            clear
            echo 'The required APT packages were installed.'
        else
            fail_fn "These required APT packages failed to install: $missing_pkgs. Line: $LINENO"
        fi
    else
        echo 'The required APT packages are already installed.'
    fi
}
pkgs_fn
