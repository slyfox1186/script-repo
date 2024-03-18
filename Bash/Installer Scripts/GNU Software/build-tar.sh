#!/Usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
    echo -e "\033[31mThis script must be run as root or with sudo.\033[0m"
    exit 1
fi

script_ver="1.0"
cwd="$PWD/tar-install"
gnu_ftp="https://ftp.gnu.org/gnu/tar/"
declare -A colors=( [green]="\e[32m" [red]="\e[31m" [yellow]="\e[33m" [reset]="\e[0m" )

print_color() {
    echo -e "$colors[$1]$2$colors[reset]"
}

print_banner() {
    print_color green "Tar Install script - v$script_ver"
    echo "============================================"
}

install_missing_packages() {
    print_color green "Checking and installing missing packages..."
    local pkgs=(
        autoconf automake autopoint binutils gcc
        make curl tar lzip libticonv-dev gettext
        libpth-dev
    )
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -l | grep -qw $pkg &>/dev/null; then
            apt install -y $pkg || yum install -y $pkg || zypper install -y $pkg || pacman -Sy $pkg
        fi
    done
}

find_latest_tar_tarball() {
    print_color green "Finding the latest release..."
    local latest_tar_tarball=$(
                                curl -s "$gnu_ftp" |
                                grep 'tar-[0-9].*\.tar\.gz' |
                                grep -v '.sig' | sed -n 's/.*href="\([^"]*\).*/\1/p' |
                                sort -V |
                                tail -n1
                            )
    if [[ -z $latest_tar_tarball ]]; then
        print_color red "Failed to find the latest release. Exiting..."
        exit 1
    fi
    archive_url="$gnu_ftp$latest_tar_tarball"
    archive_name="$latest_tar_tarball"
    archive_dir=$(echo $latest_tar_tarball | sed 's/.tar.gz//')
}

download_and_extract() {
    print_color green "Downloading and extracting..."
    mkdir -p "$cwd/$archive_dir" && cd "$cwd"
    wget --show-progress -cqO "$archive_name" "$archive_url"
    tar -zxf "$archive_name" -C "$cwd/$archive_dir" --strip-components 1
}

build_and_install() {
    print_color green "Building and installing..."
    cd "$cwd/$archive_dir"
    autoreconf -fi
    export FORCE_UNSAFE_CONFIGURE=1
    ./configure --prefix=/usr/local/$archive_dir \
                     --disable-nls \
                     --enable-backup-scripts \
                     --enable-gcc-warnings=no \
                     --with-libiconv-prefix=/usr/local \
                     --with-libintl-prefix=/usr \
                     CFLAGS="-g -O3 -pipe -fno-plt -march=native" \
                     CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
    make "-j$(nproc --all)"
    make install
    print_color green "Installation completed successfully."
}

link_tar() {
    print_color green "Creating softlink..."
    if ln -sf /usr/local/$archive_dir/bin/* /usr/local/bin/; then
        print_color green "Softlink created successfully."
    else
        print_color red "Softlink failed to create."
    fi
}

cleanup() {
    print_color yellow "Cleaning up..."
    rm -rf "$cwd"
}

main() {
    print_banner
    install_missing_packages
    find_latest_tar_tarball
    download_and_extract
    build_and_install
    link_tar
}

main "$@"