#!/usr/bin/env bash

set -euo pipefail

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log() {
    echo -e "\\n${GREEN}[INFO]${NC} $*"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

set_compiler_flags() {
    CFLAGS="-O2 -pipe -fno-plt -march=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-I/usr/include/tirpc -D_FORTIFY_SOURCE=2"
    LDFLAGS="-L/usr/lib/x86_64-linux-gnu -ltirpc -Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,/usr/lib/squid"
    export CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

install_dependencies() {
    log "Installing required dependencies..."
    sudo apt update
    sudo apt -y install build-essential libssl-dev pkg-config libcppunit-dev \
        libxml2-dev libkrb5-dev libldap2-dev libsasl2-dev libdb-dev libcap-dev \
        libpam0g-dev libexpat1-dev libcppunit-dev libxml2-dev libkrb5-dev libldap2-dev \
        libsasl2-dev libdb-dev libnetfilter-conntrack-dev librust-nettle-dev libgnutls28-dev \
        libcap-dev libpam0g-dev libexpat1-dev wget
}

download_squid() {
    local http_calls series_seven series_six
    series_six="https://www.squid-cache.org/Versions/v6/"
    series_seven="https://www.squid-cache.org/Versions/v7/"
    http_calls="$(curl -sSL "$series_six" "$series_seven")"
    version="$(echo "$http_calls" | grep -oP 'href="[^"]*squid-\K([\d.])+(?=\.tar.xz)' | sort -ruV | head -n1)"

    if [[ "$version" =~ ^7 ]]; then
        download_url="https://www.squid-cache.org/Versions/v7/squid-$version.tar.xz"
    else
        download_url="https://www.squid-cache.org/Versions/v6/squid-$version.tar.xz"
    fi

    log "Downloading Squid source code..."
    if [[ ! -f "squid-$version.tar.xz" ]]; then
        wget --show-progress -cq "$download_url"
    fi
    [[ -d "squid-$version" ]] && sudo rm -fr "squid-$version"
    tar -Jxf "squid-$version.tar.xz"
    cd "squid-$version" || fail "Failed to change directory to squid-6.9"
}

configure_squid() {
    log "Configuring Squid with recommended options for Debian 12 Bookworm..."
    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --libexecdir=/usr/lib/squid \
        --datadir=/usr/share/squid \
        --sysconfdir=/etc/squid \
        --enable-auth \
        --enable-auth-basic="DB,LDAP,NCSA,NIS,PAM,SASL" \
        --enable-auth-digest="file,LDAP" \
        --enable-auth-negotiate="kerberos" \
        --enable-cache-digests \
        --enable-delay-pools \
        --enable-esi \
        --enable-external-acl-helpers="file_userip,LDAP_group,unix_group" \
        --enable-follow-x-forwarded-for \
        --enable-linux-netfilter \
        --enable-removal-policies="lru,heap" \
        --enable-storeio="aufs,diskd,rock,ufs" \
        --enable-url-rewrite-helpers="fake" \
        --with-default-user=proxy \
        --with-filedescriptors=65536 \
        --with-gnutls \
        --with-krb5-config=/usr/bin/krb5-config \
        --with-large-files \
        --with-libcap \
        --with-logdir=/var/log/squid \
        --with-nettle \
        --with-openssl \
        --with-pidfile=/var/run/squid.pid \
        || fail "Failed to configure Squid"
}

compile_squid() {
    log "Compiling Squid..."
    make "-j$(nproc --all)" || fail "Failed to compile Squid"
}

install_squid() {
    log "Installing Squid..."
    sudo make install || fail "Failed to install Squid"
}

configure_squid_user_and_directories() {
    log "Creating Squid user and directories..."
    sudo useradd -M -r -U -d /var/cache/squid -s /usr/sbin/nologin proxy
    sudo mkdir -p /var/cache/squid /var/log/squid
    sudo chown -R proxy:proxy /var/cache/squid /var/log/squid || fail "Failed to create Squid user and directories"
}

main() {
    set_compiler_flags
    install_dependencies
    download_squid
    configure_squid
    compile_squid
    install_squid
    configure_squid_user_and_directories
    log "Squid installation completed successfully!"
}

main
