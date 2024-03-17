#!/usr/bin/env bash


if [ "$EUID" -ne 0 ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

exit_fn() {
    printf "\n%s\n\n%s\n\n" \
        "Make sure to star this repository to show your support!" \
        "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail_fn() {
    printf "\n\n%s\n\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug please create an issue at:" \
        "https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

cleanup_fn() {
    local choice

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        "============================================" \
        "  Do you want to clean up the build files?  " \
        "============================================" \
        "[1] Yes" \
        "[2] No"
    read -p "Your choices are (1 or 2): " choice

    case "$choice" in
        1)  rm -fr "$cwd" ;;
        2)  echo ;;
        *)
            unset choice
            clear
            cleanup_fn
            ;;
    esac
}

show_ver_fn() {
    clear
    show_ver="$(/usr/local/ssl/bin/openssl version -a | grep -Eo "[0-9\.]?+" | head -n1)"
    printf "%s\n" "The updated OpenSSL version is: $show_ver"
}

pkgs_arch_fn() {
    local missing_pkgs

    pkgs=(
        autoconf autogen automake base-devel ca-certificates ccache clang curl
        c-ares libcurl-gnutls gperftools mimalloc libgcrypt gmp libgpg-error
        jemalloc mbedtls libssh libssh2 libtool libxml2 lksctp-tools m4 zlib-ng
    )

    for pkg in "${pkgs[@]}"
    do
        if ! pacman -Qs "$pkg" >/dev/null; then
            missing_pkgs+=("$pkg ")
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        pacman -S --needed --noconfirm ${missing_pkgs[@]}
        clear
    fi
}

pkgs_fn() {
    local missing_packages available_packages unavailable_packages

    pkgs=(
        autoconf autogen automake build-essential ca-certificates ccache
        checkinstall clang curl libc-ares-dev libcurl4-openssl-dev
        libdmalloc-dev libgcrypt20-dev libgmp-dev libgpg-error-dev
        libjemalloc-dev libmbedtls-dev libsctp-dev libssh2-1-dev
        libssh-dev libssl-dev libtool libtool-bin libxml2-dev m4 perl
        zlib1g-dev
    )

    missing_packages=()
    available_packages=()
    unavailable_packages=()

    for pkg in "${pkgs[@]}"
    do
        if ! dpkg-query -W -f='$Status' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    for pkg in "${missing_packages[@]}"
    do
        if apt-cache show "$pkg" > /dev/null 2>&1; then
            available_packages+=("$pkg")
        else
            unavailable_packages+=("$pkg")
        fi
    done

        echo "Unavailable packages: ${unavailable_packages[*]}"
    fi

        echo "Installing available missing packages: ${available_packages[*]}"
        apt install "${available_packages[@]}"
    else
        printf "%s\n\n" "No missing packages to install or all missing packages are unavailable."
    fi
}

create_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}

download_file() {
    local url="$1"
    local output_file="$2"
    if [ ! -f "$output_file" ]; then
        wget -cqO "$output_file" "$url"
    fi
}

extract_archive() {
    local archive_file="$1"
    local target_dir="$2"
    if ! tar -zxf "$archive_file" -C "$target_dir" --strip-components 1; then
        printf "%s\n\n" "Failed to extract: $archive_file"
        exit 1
    fi
}

add_to_path() {
    [[ -f "/usr/local/bin/openssl" ]] && rm "/usr/local/bin/openssl"
    ln -sf "/usr/local/ssl/bin/openssl" "/usr/local/bin"
}

build_openssl() {
    cd "$1" || exit 1
    ../Configure linux-x86_64-clang \
                 -DOPENSSL_USE_IPV6=0 \
                 -Wl,-rpath="$install_dir/lib64" \
                 -Wl,--enable-new-dtags \
                 --prefix="$install_dir" \
                 --openssldir="$ssl_dir" \
                 --release \
                 --with-zlib-include="/usr/include" \
                 --with-zlib-lib="/usr/lib/x86_64-linux-gnu" \
                 enable-ec_nistp_64_gcc_128 \
                 enable-egd \
                 enable-fips \
                 enable-rc5 \
                 enable-sctp \
                 enable-shared \
                 enable-threads \
                 enable-zlib \
                 no-tests

    echo
    if ! make "-j$(nproc --all)"; then
        fail_fn "Failed to execute: make -j$(nproc --all). Line: $LINENO"
    fi

    echo
    if ! make install_sw install_fips; then
        fail_fn "Failed to execute: make install_sw install_fips. Line: $LINENO"
    else
        openssl fipsinstall
    fi
}

install_ca_certs() {
    printf "\n%s\n%s\n\n" \
        "Install the latest security certificate from cURL's website" \
        "==================================================================="
    sleep 2

    create_dir "$cert_dir"

    download_file "https://curl.se/ca/cacert.pem" "$cwd/cacert.pem"

    if ! mv "$cwd/cacert.pem" "$cert_dir/cacert.pem"; then
        fail_fn "Failed to move file: $cwd/cacert.pem >> $cert_dir/cacert.pem. Line: $LINENO"
    else
        cp "$cert_dir/cacert.pem" "/usr/local/share/ca-certificates/curl-cacert.crt"
    fi

    cp -fr /etc/ssl/certs/* "$cert_dir"

    cd "$cert_dir" || exit 1
    c_rehash .
    update-ca-certificates
}

update_ldconfig() {
    echo "$install_dir/lib64" | tee "/etc/ld.so.conf.d/openssl-compiled.conf" >/dev/null
    ldconfig "/usr/local/ssl/lib64"
}

script_ver="2.1"
openssl_ver="$(curl -s https://www.openssl.org/source/ | grep -o "openssl-3.1\.[4-9]\{1,2\}" | head -n 1)"
archive_url="https://www.openssl.org/source/$openssl_ver.tar.gz"
archive_ext="${archive_url//*./}"
archive_name="$openssl_ver.tar.$archive_ext"
cwd="$PWD/openssl-build-script"
install_dir="/usr/local/ssl"
ssl_dir="$install_dir"
cert_dir="$install_dir/certs"

printf "%s\n%s\n\n" \
    "OpenSSL LTS Build Script - v$script_ver" \
    "==============================================="
sleep 2

create_dir "$cwd"

find_lsb_release="$(find /usr/bin/ -type f -name "lsb_release")"

if [ -f "/etc/os-release" ]; then
    . "/etc/os-release"
    OS_TMP="$NAME"
    OS="$(echo "$OS_TMP" | awk "{print $1}")"
elif [ -n "$find_lsb_release" ]; then
    OS="$(lsb_release -d | awk "{print $2}")"
else
    fail_fn "Failed to define the \$OS and/or \$VER variables. Line: $LINENO"
fi

ubuntu_os_ver() {
    ln -sf "/usr/lib64/libcrypto.so.3" "/usr/lib64/libcrypto.so"
}

case "$OS" in
    Ubuntu) ubuntu_os_ver ;;
esac

if [[ "$OS" == "Arch" ]]; then
    pkgs_arch_fn
else
    pkgs_fn
fi

download_file "$archive_url" "$cwd/$archive_name"

create_dir "$cwd/$openssl_ver/build"

extract_archive "$cwd/$archive_name" "$cwd/$openssl_ver"

build_openssl "$cwd/$openssl_ver/build"

install_ca_certs

update_ldconfig

add_to_path

cleanup_fn

show_ver_fn

exit_fn
