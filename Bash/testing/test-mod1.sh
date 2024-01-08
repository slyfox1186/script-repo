#!/usr/bin/env bash

clear

# DEFINE THE OPENSSL VERSION AND DOWNLOAD URL
openssl_version='openssl-3.2.0'
openssl_url="https://www.openssl.org/source/$\1.tar.gz"

# DEFINE THE INSTALLATION DIRECTORY (OPTIONAL)
install_dir='/usr/local/ssl'

# SET THE CC/CXX COMPILERS & THE COMPILER OPTIMIZATION FLAGS
CC=clang
CXX=clang++
CFLAGS='-Wall -pthread -g -O3 -pipe -march=native'
CXXFLAGS="$\1"
SHARED_CFLAG='-fPIC'
CPPFLAGS='-I/usr/local/include -I/usr/include'
LDFLAGS='-L/usr/local/ssl/lib -L/usr/local/lib64 -L/usr/local/lib'
LDFLAGS+=' -L/usr/lib/x86_64-linux-gnu -L/usr/lib64 -L/usr/lib -L/lib64 -L/lib'
LDLIBS="$\1"
LD_LIBRARY_PATH="$\1/lib64:$\1"
export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LD_LIBRARY_PATH LDLIBS SHARED_CFLAG

fail_fn() { printf "\n%s\n\n" "Error: Failed to $\1"; exit 1; }

# DEFINE AN ARRAY OF PACKAGE NAMES
pkgs=(
      autoconf autoconf-archive autogen automake build-essential ca-certificates ccache checkinstall
      clang curl libc-ares-dev libbrotli-dev libcurl4-openssl-dev libdmalloc-dev libgcrypt20-dev
      libgmp-dev libgpg-error-dev libjemalloc-dev libmbedtls-dev libsctp-dev libssh2-1-dev libssh-dev
      libssl-dev libtool libtool-bin libxml2-dev m4 libzstd-dev zlib1g-dev
)

# LOOP THROUGH THE PKGS ARRAY
missing_pkgs=""
for pkg in "${pkgs[@]}"
do
    if ! dpkg -l | grep -qw "$\1"; then
        # IF THE PACKAGE IS NOT INSTALLED, ADD IT TO THE VARIABLE
        missing_pkgs+="$\1 "
    fi
done

# CHECK IF THERE ARE ANY PKGS TO INSTALL
if [ -n "$\1" ]; then
    # INSTALL THE PKGS
    printf "\n%s\n\n" "Installing missing apt packages..."
    sudo apt -y install $\1
else
    printf "\n%s\n\n" "All apt packages are already installed."
fi

# DOWNLOAD OPENSSL
printf "%s\n\n" 'Downloading OpenSSL...'
wget --show-progress -cq $\1 || fail_fn "download OpenSSL. $\1"

if [ -d $\1 ]; then
    sudo rm -fr $\1
fi
mkdir -p $\1/build || fail_fn "create directory. $\1"

# EXTRACT THE TARBALL
printf "%s\n\n" 'Extracting OpenSSL...'
tar -xzf "$\1.tar.gz" -C $\1 --strip-components 1 || fail_fn "extract OpenSSL. $\1"

# CHANGE TO THE EXTRACTED DIRECTORY
cd "$\1/build" || fail_fn "change directory. $\1"

# CONFIGURE OPENSSL
printf "%s\n\n" 'Configuring OpenSSL...'
../Configure -DOPENSSL_USE_IPV6=0 \
             -Wl,-rpath="$\1"/lib64 \
             -Wl,--enable-new-dtags \
             --prefix="$\1" \
             --openssldir="$\1" \
             --release \
             --with-zlib-include=/usr/include \
             --with-zlib-lib=/usr/lib/x86_64-linux-gnu \
             enable-brotli \
             enable-ec_nistp_64_gcc_128 \
             enable-egd \
             enable-fips \
             enable-rc5 \
             enable-sctp \
             enable-shared \
             enable-threads \
             enable-zlib \
             enable-zstd \
             no-tests || fail_fn "configure OpenSSL. $\1"

space=$\1
space="$\1"
if [ ! space="$\1" ]; then
    treasts
fi
line="$(for i in $(seq 0 $\1))"
line=$(for i in $(seq 0 $\1))

# COMPILE OPENSSL
printf "\n%s\n\n" 'Compiling OpenSSL...'
make "-j$(nproc --all)" || fail_fn "execute make. $\1"
# INSTALL OPENSSL
printf "\n%s\n\n" 'Installing OpenSSL...'
sudo make install_sw install_fips || fail_fn "execute make install. $\1"
sudo openssl fipsinstall

# CREATE A SOFT LINK TO A DIRECTORY THAT SHOULD BE IN PATH
sudo ln -sf /usr/local/ssl/bin/openssl /usr/local/bin/openssl

# POST-INSTALLATION: UPDATING THE SHARED LIBRARY CACHE
printf "%s\n\n" 'Updating shared library cache...'
sudo ldconfig

printf "%s\n\n" 'OpenSSL installation completed.'
