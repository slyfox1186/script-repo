#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/util-linux/Installer%20Scripts/GNU%20Software/build-curl
##  Purpose: Build cURL with OpenSSL QUIC enabled to support experimental HTTP3.
##  Updated: 12.03.23
##  Script version: 1.0

if [ "$EUID" -eq 0 ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables

script_ver=1.0
curl_ver=8.4.0
archive_dir=${curl_ver}
archive_dir1=${curl_ver//./_}
archive_url=https://github.com/curl/curl/releases/download/curl-${archive_dir1}/curl-$archive_dir.tar.xz
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.${archive_ext}"
cwd="$PWD"/curl-build-script
install_dir=/usr/local
cert_dir=/etc/ssl/certs
pem_file=cacert.pem
pem_out="${cert_dir}/$pem_file"
pc_type=$(gcc -dumpmachine)
web_repo=https://github.com/slyfox1186/script-repo

printf "%s\n%s\n\n" \
    "cURL Build Script - v${script_ver}" \
    '==============================================='

# Create output directory
[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

# Set the c/cxx compilers & set the compiler optimization flags

CC="gcc"
CXX="g++"
CFLAGS="-g -O2 -pipe -march=native -I/usr/local/include -I/usr/include"
CXXFLAGS="-g -O2 -pipe -march=native"
CPPFLAGS="-I/usr/include/libxml2 -I/usr/local/include/nghttp2 -I/usr/local/include/nghttp3"
LDFLAGS="-Wl,-rpath,/usr/local/lib64"
LIBS="-ldl -pthread -L/usr/lib/x86_64-linux-gnu -lnghttp3 -lcrypto -lssl -L/usr/local/lib -ljemalloc"
export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LIBS

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig"
export PATH PKG_CONFIG_PATH

# Create functions

exit_function()
{
    printf "\n%s\n\n%s\n\n" \
        "Make sure to star this repository to show your support!" \
        "$web_repo"
    exit 0
}

fail_fn()
{
    printf "\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug create an issue at: $web_repo/issues"
    exit 1
}

cleanup_fn()
{
    local choice

    printf "%s\n%s\n%s\n\n%s\n%s\n\n" \
        "============================================" \
        "  Do you want to clean up the build files?  " \
        "============================================" \
        "[1] Yes" \
        "[2] No"
    read -p "Your choices are (1 or 2): " choice
    clear

    case "${choice}" in
        1)      sudo rm -fr "$cwd";;
        2)      return 0;;
        *)
                unset choice
                clear
                cleanup_fn
                ;;
    esac
}

# Install required apt packages

pkgs=(apt-transport-https apt-utils autoconf autoconf-archive autogen automake autopoint autotools-dev
      build-essential bzip2 ca-certificates ccache clang cmake curl gfortran git google-perftools graphviz
      jq lcov libaria2-0 libaria2-0-dev libbpf-dev libc-ares-dev libcppunit-dev libcunit1-dev libcurl4
      libcurl4-openssl-dev libdmalloc-dev libec-dev libedit-dev libev-dev libevent-dev libexiv2-27 libexpat1-dev
      libgcc-12-dev libgcrypt20-dev libgexiv2-2 libgimp2.0 libgmp3-dev libgpg-error-dev libgsasl-dev libgtk-4-doc
      libgpgme-dev libicu-dev libjansson-dev libjemalloc-dev libkrb5-3 libldap2-dev libldap-dev liblttng-ust-dev
      liblzma-dev libmbedtls-dev libntlm0-dev libparted-dev libpng-dev libpsl-dev librtmp-dev librust-bzip2-dev
      librust-openssl-dev libsqlite3-dev libssh2-1-dev libssh-dev libssl-dev libtinfo5 libticonv-dev libtinfo-dev
      libtool libtool-bin libunistring-dev libunwind8 libuv1-dev libxml2-dev libzstd-dev lzip m4 nettle-dev
      default-jdk-headless openssh-server pkg-config python3-dev python3-numpy python3-packaging python3-pip
      python3-pytest python3-setuptools python3-wheel re2c rsync unzip valgrind winbind zip zlib1g-dev)

for pkg in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "${pkg}")"

    if [ -z "${missing_pkg}" ]; then
        missing_pkgs+=" ${pkg}"
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
    sudo apt -y autoremove
    clear
fi

# Create output directory openssl-quic
[[ -d "$cwd/openssl-quic-3.1.4" ]] && sudo rm -fr "$cwd/openssl-quic-3.1.4"
mkdir -p "$cwd/openssl-quic-3.1.4"

# Download the archive file openssl-quic
if [ ! -f "$cwd/openssl-quic-3.1.4.tar.gz" ]; then
    curl -Lso "$cwd/openssl-quic-3.1.4.tar.gz" 'https://github.com/quictls/openssl/archive/refs/tags/openssl-3.1.4-quic1.tar.gz'
fi

# Extract the archive file openssl-quic
if ! tar -zxf "$cwd/openssl-quic-3.1.4.tar.gz" -C "$cwd/openssl-quic-3.1.4" --strip-components 1; then
    fail_fn "Failed to extract: $cwd/openssl-quic-3.1.4.tar.gz"
fi

# Install openssl-quic
printf "%s\n%s\n\n" \
    "Installing OpenSSL-QUIC - v3.1.4" \
    '==============================================='

cd "$cwd/openssl-quic-3.1.4" || exit 1
./config linux-x86_64 \
         --prefix="$install_dir" \
         --openssldir="$install_dir" \
         -Wl,-rpath="$install_dir"/lib64 \
         -Wl,--enable-new-dtags \
         -DOPENSSL_USE_IPV6=0 \
         --release \
         --with-zlib-include=/usr/include \
         --with-zlib-lib=/usr/lib/x86_64-linux-gnu \
         enable-ec_nistp_64_gcc_128 \
         enable-egd \
         enable-fips \
         enable-rc5 \
         enable-sctp \
         enable-shared \
         enable-threads \
         enable-zlib \
         no-tests
sed -i 's/linux-x86_64/linux-x86_64-rpath/g' 'Makefile'
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
fi
echo
if ! sudo make install_sw; then
    fail_fn "Failed to execute: sudo make install_sw. Line: ${LINENO}"
fi

# Update ldconfig libs for openssl
sudo ldconfig '/usr/local/lib64'

# Create output directory jemalloc

if [ -d "$cwd/jemalloc-5.3.0" ]; then
    sudo rm -fr "$cwd/jemalloc-5.3.0"
fi
mkdir -p "$cwd/jemalloc-5.3.0/build"

# Download the archive file jemalloc

if [ ! -f "$cwd/jemalloc-5.3.0.tar.gz" ]; then
    curl -A "$user_agent" -Lso "$cwd/jemalloc-5.3.0.tar.gz" 'https://github.com/jemalloc/jemalloc/archive/refs/tags/5.3.0.tar.gz'
fi

# Extract the archive file jemalloc

if ! tar -zxf "$cwd/jemalloc-5.3.0.tar.gz" -C "$cwd/jemalloc-5.3.0" --strip-components 1; then
    fail_fn "Failed to extract: $cwd/jemalloc-5.3.0.tar.gz"
fi

# Install jemalloc

printf "\n%s\n%s\n\n" \
    "Installing Jemalloc - v5.3.0" \
    '==============================================='

cd "$cwd/jemalloc-5.3.0" || exit 1
./autogen.sh
cd build || exit 1
../configure --prefix="$install_dir" \
             --disable-debug \
             --disable-doc \
             --disable-fill \
             --disable-log \
             --disable-prof \
             --disable-stats \
             --enable-autogen \
             --enable-static \
             --enable-xmalloc
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
fi
echo
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: ${LINENO}"
fi

# Create output directory http 2/3

if [ -d "$cwd/ngtcp2-1.58.0" ]; then
    sudo rm -fr "$cwd/ngtcp2-1.58.0"
fi
mkdir -p "$cwd/ngtcp2-1.58.0"

if [ -d "$cwd/nghttp3-1.1.0" ]; then
    sudo rm -fr "$cwd/nghttp3-1.1.0"
fi
mkdir -p "$cwd/nghttp3-1.1.0"

# Download the archive file http 2/3

if [ ! -f "$cwd/nghttp3-1.1.0.tar.xz" ]; then
    curl -A "$user_agent" -Lso "$cwd/nghttp3-1.1.0.tar.xz" 'https://github.com/ngtcp2/nghttp3/releases/download/v1.1.0/nghttp3-1.1.0.tar.xz'
fi
if [ ! -f "$cwd/ngtcp2-1.58.0.tar.xz" ]; then
    curl -A "$user_agent" -Lso "$cwd/ngtcp2-1.58.0.tar.xz" 'https://github.com/nghttp2/nghttp2/releases/download/v1.58.0/nghttp2-1.58.0.tar.xz'
fi

# Extract the archive file http 2/3

if ! tar -xf "$cwd/ngtcp2-1.58.0.tar.xz" -C "$cwd/ngtcp2-1.58.0" --strip-components 1; then
    fail_fn "Failed to extract: $cwd/ngtcp2-1.58.0.tar.xz"
fi
if ! tar -xf "$cwd/nghttp3-1.1.0.tar.xz" -C "$cwd/nghttp3-1.1.0" --strip-components 1; then
    fail_fn "Failed to extract: $cwd/nghttp3-1.1.0.tar.xz"
fi

# Install http3

printf "\n%s\n%s\n\n" \
    "Installing HTTP3 - v1.1.0" \
    '==============================================='

cd "$cwd/nghttp3-1.1.0" || exit 1
autoreconf -fi
./configure --prefix="$install_dir" \
            --{build,host,target}="${pc_type}" \
            --enable-lib-only \
            --with-pic
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
fi
echo
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: ${LINENO}"
fi

# Create output directory ngtcp2

if [ -d "$cwd/ngtcp2-1.1.0" ]; then
    sudo rm -fr "$cwd/ngtcp2-1.1.0"
fi
mkdir -p "$cwd/ngtcp2-1.1.0/build"

# Download the archive file ngtcp2

if [ ! -f "$cwd/ngtcp2-1.1.0.tar.gz" ]; then
    curl -A "$user_agent" -Lso "$cwd/ngtcp2-1.1.0.tar.gz" 'https://github.com/ngtcp2/ngtcp2/releases/download/v1.1.0/ngtcp2-1.1.0.tar.xz'
fi

# Extract the archive file ngtcp2

if ! tar -xf "$cwd/ngtcp2-1.1.0.tar.gz" -C "$cwd/ngtcp2-1.1.0" --strip-components 1; then
    fail_fn "Failed to extract: $cwd/ngtcp2-1.1.0.tar.gz"
fi

# Install ngtcp2

printf "\n%s\n%s\n\n" \
    "Installing ngtcp2 - v1.1.0" \
    '==============================================='

cd "$cwd/ngtcp2-1.1.0" || exit 1
./autogen.sh
cd build || exit 1
../configure --prefix="$install_dir" \
            --{build,host,target}="${pc_type}" \
            --enable-lib-only \
            --with-pic \
            --with-jemalloc \
            --with-cunit \
            --with-libnghttp3 \
            --with-libev \
            --with-openssl
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
fi
echo
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: ${LINENO}"
fi

# Install http2

printf "\n%s\n%s\n\n" \
    "Installing HTTP2 - v1.58.0" \
    '==============================================='

cd "$cwd/ngtcp2-1.58.0" || exit 1
autoreconf -fi
./configure --prefix="$install_dir" \
            --{build,host,target}="${pc_type}" \
            --disable-examples \
            --enable-http3 \
            --enable-lib-only \
            --with-libxml2 \
            --with-openssl \
            --with-pic \
            --with-jemalloc \
            --with-libnghttp3 \
            --with-libngtcp2 \
            --with-libbpf
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
fi
echo
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: ${LINENO}"
fi

# Create output directory c-ares

if [ -d "$cwd/c-ares-1.23.0" ]; then
    sudo rm -fr "$cwd/c-ares-1.23.0"
fi
mkdir -p "$cwd/c-ares-1.23.0/build"

# Download the archive file c-ares

if [ ! -f "$cwd/c-ares-1.23.0.tar.gz" ]; then
    curl -A "$user_agent" -Lso "$cwd/c-ares-1.23.0.tar.gz" 'https://github.com/c-ares/c-ares/archive/refs/tags/cares-1_23_0.tar.gz'
fi

# Extract the archive file c-ares

if ! tar -zxf "$cwd/c-ares-1.23.0.tar.gz" -C "$cwd/c-ares-1.23.0" --strip-components 1; then
    fail_fn "Failed to extract: $cwd/c-ares-1.23.0.tar.gz"
fi

# Install c-ares

printf "\n%s\n%s\n\n" \
    "Installing c-ares - v1.23.0" \
    '==============================================='

cd "$cwd/c-ares-1.23.0" || exit 1
autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir" \
                     --{build,host}="${pc_type}" \
                     --disable-debug \
                     --disable-warnings \
                     --with-pic
echo
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
fi
echo
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: ${LINENO}"
fi

# Create output directory curl

if [ -d "$cwd/$archive_dir" ]; then
    sudo rm -fr "$cwd/$archive_dir"
fi
mkdir -p "$cwd/$archive_dir/build"

# Download the archive file curl

if [ ! -f "$cwd/${archive_name}" ]; then
    curl -A "$user_agent" -Lso "$cwd/${archive_name}" "${archive_url}"
fi

# Extract the archive file curl

if ! tar -xf "$cwd/${archive_name}" -C "$cwd/$archive_dir" --strip-components 1; then
    fail_fn "Failed to extract: $cwd/${archive_name}"
fi

# Install ca certs from curl's official website

printf "\n%s\n%s\n\n" \
   'Install the latest security certificate from cURL'\''s website' \
   '==================================================================='

# Download the latest cacert.pem file from the official curl website
if ! curl -A "$user_agent" -Lso "$cwd"/cacert.pem 'https://curl.se/ca/cacert.pem'; then
    fail_fn "Failed to download the latest \"cacert.pem\" file. Line: ${LINENO}"
fi

# Move the pem file to the newly created certs directory
if sudo cp -f "$cwd"/cacert.pem "${cert_dir}"/cacert.pem; then
# Copy the pem file as a crt file in the special ca-certificates folder so the command will find and use it when it is executed
    sudo cp "${cert_dir}"/cacert.pem '/usr/local/share/ca-certificates/curl-cacert.crt'
fi

# Update the security certs that were moved from the /etc/ssl/certs folder
cd "${cert_dir}" || exit 1
sudo c_rehash .
sudo update-ca-certificates

# Build curl from source

printf "\n%s\n%s\n\n" \
    "Installing cURL - v8.4.0" \
    '==============================================='

cd "$cwd/$archive_dir" || exit 1
dopts=('--disable-'{get-easy-options,shared,verbose,versioned-symbols})
eopts=('--enable-'{alt-svc,ares="$workspace",cookies})
eopts+=('--enable-'{dict,dnsshuffle,doh,file,ftp,gopher})
eopts+=('--enable-'{headers-api,hsts,http,http-auth,imap})
eopts+=('--enable-'{ipv6,ldap,ldaps,libcurl-option,libgcc,manual})
eopts+=('--enable-'{mime,mqtt,netrc,ntlm,ntlm-wb="$(sudo find /usr/ -type f -name 'ntlm_auth')"})
eopts+=('--enable-'{openssl-auto-load-config,optimize,pop3,progress-meter})
eopts+=('--enable-'{proxy,pthreads,rtsp,smb,smtp,socketpair,sspi,static,telnet})
eopts+=('--enable-'{tftp,threaded-resolver,tls-srp,unix-sockets,websockets})
wopts=('--with-'{gnutls='/usr/include',libssh2,nghttp2='/usr/local/include',nghttp3='/usr/local/include'})
wopts+=('--with-'{ca-bundle="${pem_out}",ca-fallback,ca-path="${cert_dir}",secure-transport})

autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir" \
            "${dopts[@]}" \
            "${eopts[@]}" \
            "${wopts[@]}" \
            "${csuffix}"
if ! make "-j$(nproc --all)"; then
    fail_fn "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
    exit 1
fi

if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install. Line: ${LINENO}"
    exit 1
fi

# Prompt user to clean up files
cleanup_fn

# Show exit message
exit_function
