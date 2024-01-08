#!/usr/bin/env bash

clear

# DEFINE THE OPENSSL VERSION AND DOWNLOAD URL
openssl_version='openssl-3.2.0'
openssl_url="https://www.openssl.org/source/${openssl_version}.tar.gz"

# DEFINE THE INSTALLATION DIRECTORY (OPTIONAL)
install_dir='/usr/local/ssl'

# SET THE CC/CXX COMPILERS & THE COMPILER OPTIMIZATION FLAGS
CC=clang
CXX=clang++
CFLAGS='-Wall -pthread -g -O3 -pipe -march=native'
CXXFLAGS="${CFLAGS}"
SHARED_CFLAG='-fPIC'
CPPFLAGS='-I/usr/local/include -I/usr/include'
LDFLAGS='-L/usr/local/ssl/lib -L/usr/local/lib64 -L/usr/local/lib'
LDFLAGS+=' -L/usr/lib/x86_64-linux-gnu -L/usr/lib64 -L/usr/lib -L/lib64 -L/lib'
LDLIBS="${LDFLAGS}"
LD_LIBRARY_PATH="${install_dir}/lib64:${LD_LIBRARY_PATH}"
export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LD_LIBRARY_PATH LDLIBS SHARED_CFLAG

fail_fn() { printf "\n%s\n\n" "Error: Failed to ${1}"; exit 1; }

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
    if ! dpkg -l | grep -qw "${pkg}"; then
        # IF THE PACKAGE IS NOT INSTALLED, ADD IT TO THE VARIABLE
        missing_pkgs+="${pkg} "
    fi
done

# CHECK IF THERE ARE ANY PKGS TO INSTALL
if [ -n "${missing_pkgs}" ]; then
    # INSTALL THE PKGS
    printf "\n%s\n\n" "Installing missing apt packages..."
    sudo apt -y install ${missing_pkgs}
else
    printf "\n%s\n\n" "All apt packages are already installed."
fi

# DOWNLOAD OPENSSL
printf "%s\n\n" 'Downloading OpenSSL...'
wget --show-progress -cq ${openssl_url} || fail_fn "download OpenSSL. ${LINENO}"

if [ -d ${openssl_version} ]; then
    sudo rm -fr ${openssl_version}
fi
mkdir -p ${openssl_version}/build || fail_fn "create directory. ${LINENO}"

# EXTRACT THE TARBALL
printf "%s\n\n" 'Extracting OpenSSL...'
tar -xzf "${openssl_version}.tar.gz" -C ${openssl_version} --strip-components 1 || fail_fn "extract OpenSSL. ${LINENO}"

# CHANGE TO THE EXTRACTED DIRECTORY
cd "${openssl_version}/build" || fail_fn "change directory. ${LINENO}"

# CONFIGURE OPENSSL
printf "%s\n\n" 'Configuring OpenSSL...'
../Configure -DOPENSSL_USE_IPV6=0 \
             -Wl,-rpath="${install_dir}"/lib64 \
             -Wl,--enable-new-dtags \
             --prefix="${install_dir}" \
             --openssldir="${install_dir}" \
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
             no-tests || fail_fn "configure OpenSSL. ${LINENO}"

# COMPILE OPENSSL
printf "\n%s\n\n" 'Compiling OpenSSL...'
make "-j$(nproc --all)" || fail_fn "execute make. ${LINENO}"
# INSTALL OPENSSL
printf "\n%s\n\n" 'Installing OpenSSL...'
sudo make install_sw install_fips || fail_fn "execute make install. ${LINENO}"
sudo openssl fipsinstall

# CREATE A SOFT LINK TO A DIRECTORY THAT SHOULD BE IN PATH
sudo ln -sf /usr/local/ssl/bin/openssl /usr/local/bin/openssl

# POST-INSTALLATION: UPDATING THE SHARED LIBRARY CACHE
printf "%s\n\n" 'Updating shared library cache...'
sudo ldconfig

printf "%s\n\n" 'OpenSSL installation completed.'
