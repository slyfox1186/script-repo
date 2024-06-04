#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/util-linux/Installer%20Scripts/GNU%20Software/build-curl-git
##  Purpose: Build cURL with OpenSSL backend
##  Updated: 03.09.24
##  Script version: 1.1

if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

# Set the variables
script_ver=1.1
archive_dir=curl-git
git_url=https://github.com/curl/curl.git
cwd="$PWD/curl-git-build-script"
install_prefix=/usr/local
pem_file=cacert.pem
certs_dir="/etc/ssl/certs"
pem_out="$certs_dir/$pem_file"

printf "%s\n%s\n\n" \
    "cURL Build Script - v$script_ver" \
    '==============================================='
sleep 2

[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -mtune=native"
CXXFLAGS="$CFLAGS"
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH

exit_function() {
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail_fn() {
    printf "\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

cleanup_fn() {
    local choice

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        '============================================' \
        '  Do you want to clean up the build files?  ' \
        '============================================' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice
    clear

    case "$choice" in
        1) rm -fr "$cwd";;
        2) ;;
        *) unset choice
           clear
           cleanup_fn
           ;;
    esac
}

install_required_packages() {
    local libgcc_ver="$(apt list libgcc-* 2>/dev/null | grep -Eo 'libgcc-[0-9]*-dev' | uniq | head -n1)"
    local libgtk_ver="$(apt list libgtk-* 2>/dev/null | grep -Eo 'libgtk-[0-9]+-doc' | head -n1)"
    local pkgs=(
            apt-transport-https apt-utils autoconf autoconf-archive autogen automake autopoint autotools-dev
            build-essential bzip2 ca-certificates ccache clang cmake curl gfortran git google-perftools graphviz
            jq lcov libaria2-0 libaria2-0-dev libc-ares-dev libcppunit-dev libcunit1-dev libcurl4 libcurl4-openssl-dev
            libdmalloc-dev libec-dev libedit-dev libev-dev libevent-dev libexiv2-27 libexpat1-dev "$libgcc_ver"
            libgcrypt20-dev libgexiv2-2 libgimp2.0 libgmp3-dev libgpg-error-dev "$libgtk_ver" libgpgme-dev libicu-dev
            libjemalloc-dev libkrb5-3 libldap2-dev libldap-dev liblttng-ust-dev liblzma-dev libmbedtls-dev libnghttp2-dev
            libnghttp3-dev libntlm0-dev libparted-dev libpng-dev libpsl-dev librtmp-dev librust-bzip2-dev librust-openssl-dev
            libsqlite3-dev libssh2-1-dev libssh-dev libssl-dev libtinfo5 libticonv-dev libtinfo-dev libtool libtool-bin
            libunistring-dev libunwind8 libuv1-dev libxml2-dev libzstd-dev lzip m4 nettle-dev default-jdk-headless openssh-server
            pkg-config python3-dev python3-numpy python3-packaging python3-pip python3-pytest python3-setuptools python3-wheel
            re2c rsync unzip valgrind zip zlib1g-dev
       )

    local missing_packages=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [ "${#Missing_packages[@]}" -gt 0 ]; then
        apt update
        apt install "${missing_packages[@]}"
    else
        log "All required packages are already installed."
    fi
}
install_required_packages

# Install certs from curl's official website
if [ ! -f "$pem_out" ]; then
    printf "%s\n%s\n\n" \
        'Download the latest security certificate' \
        '================================================'
    curl -Lso "$cwd/$pem_file" "https://curl.se/ca/$pem_file"
    cp -f "$cwd/$pem_file" "$pem_out"
fi

# Create output directory curl
if [ -d "$cwd/$archive_dir" ]; then
    rm -fr "$cwd/$archive_dir"
fi

# Download the archive file curl
git clone "$git_url" "$cwd/$archive_dir"

# Update the system security certificates before installing curl
if type -P 'update-ca-certificates' &>/dev/null; then
    update-ca-certificates
fi

cd "$cwd/$archive_dir" || exit 1
dopts=('--disable-'{get-easy-options,shared,verbose,versioned-symbols})
eopts=('--enable-'{alt-svc,ares="$workspace",cookies})
eopts+=('--enable-'{dict,dnsshuffle,doh,file,ftp,gopher})
eopts+=('--enable-'{headers-api,hsts,http,http-auth,imap})
eopts+=('--enable-'{ipv6,ldap,ldaps,libcurl-option,libgcc,manual})
eopts+=('--enable-'{mime,mqtt,netrc,ntlm,ntlm-wb='/usr/bin/ntlm_auth'})
eopts+=('--enable-'{openssl-auto-load-config,optimize,pop3,progress-meter})
eopts+=('--enable-'{proxy,pthreads,rtsp,smb,smtp,socketpair,sspi,static,telnet})
eopts+=('--enable-'{tftp,threaded-resolver,tls-srp,unix-sockets,websockets})
wopts=('--with-'{libssh2,nghttp2='/usr/include',nghttp3='/usr/include',openssl})
wopts+=('--with-'{ca-bundle="$pem_out",ca-fallback,ca-path="$certs_dir",secure-transport})
autoreconf -fi
mkdir build
cd build || exit 1
../configure --prefix="$install_prefix" \
            "${dopts[@]}" \
            "${eopts[@]}" \
            "${wopts[@]}" \
            "$csuffix"  \
             CPPFLAGS="$CPPFLAGS"
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: $LINENO"
fi
echo
if ! make install; then
    fail_fn "Failed to execute: make install. Line: $LINENO"
fi

# Prompt user to clean up files
cleanup_fn

# Show new version
curl_ver="$(/usr/local/bin/curl --version | grep -Eo '^curl [0-9\.]+' | grep -Eo '[0-9\.]+')"

printf "\n%s\n" "The updated cURL version is: $curl_ver"

# Show exit message
exit_function
