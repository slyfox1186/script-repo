#!/Usr/bin/env bash


clear

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

if [ -f '/proc/cpuinfo' ]; then
    cpu_threads="$(grep --count ^processor '/proc/cpuinfo')"
else
    cpu_threads="$(nproc --all)"
fi

script_ver=1.2
install_prefix=/usr/local
cwd="$PWD"/download-tools-build-script
packages="$cwd"/packages
workspace="$cwd"/workspace
pc_type=$(gcc -dumpmachine)
if [ -d '/usr/local/ssl/certs' ]; then
    cert_dir='/usr/local/ssl/certs'
else
    cert_dir=/etc/ssl/certs
fi
pem_file=cacert.pem
pem_out="$cert_dir/$pem_file"
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
web_repo=https://github.com/slyfox1186/script-repo
debug=OFF

mkdir -p "$packages" "$workspace"

CC="clang"
CXX="clang++"
LDFLAGS="-L/usr/local/lib64 -L/usr/local/lib -L/usr/lib64 -L/usr/lib -L/lib64 -L/lib"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
CPPFLAGS="-I/usr/local/include -I/usr/include"
export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

LD_LIBRARY="\
/usr/local/lib64:\
/usr/share/texinfo/lib/libintl-perl/lib:\
/usr/share/texinfo/lib:\
/usr/share/gitk/lib:\
/usr/share/git-gui/lib:\
/usr/share/ghostscript/lib:\
/usr/local/lib64:\
/usr/local/lib/clang/17/lib:\
/usr/local/lib:\
/usr/lm32-elf/lib:\
/usr/lib64:\
/usr/lib32:\
/usr/lib/llvm15/lib:\
/usr/lib/gcc/x86_64-pc-linux-gnu/lib:\
/usr/lib/clang/16/lib:\
/usr/lib/bfd-plugins:\
/usr/lib:\
/lib64:\
/lib\
"
export LD_LIBRARY

LD_LIBRARY_PATH="\
/usr/local/lib64:\
/usr/share/texinfo/lib/libintl-perl/lib:\
/usr/share/texinfo/lib:\
/usr/share/gitk/lib:\
/usr/share/git-gui/lib:\
/usr/share/ghostscript/lib:\
/usr/local/lib64:\
/usr/local/lib/clang/17/lib:\
/usr/local/lib:\
/usr/lm32-elf/lib:\
/usr/lib64:\
/usr/lib32:\
/usr/lib/llvm15/lib:\
/usr/lib/gcc/x86_64-pc-linux-gnu/lib:\
/usr/lib/clang/16/lib:\
/usr/lib/bfd-plugins:\
/usr/lib:\
/lib64:\
/lib\
"
export LD_LIBRARY_PATH

add_suffix_fn() {
    clear
    printf "%s\n\n" 'If desired you can leave the input blank'
    read -p 'Enter the suffix to add to WGET: ' wsuffix
    read -p 'Enter the suffix to add to cURL: ' csuffix
    read -p 'Enter the suffix to add to aria2c: ' asuffix
    if [ -n "$wsuffix" ]; then
        wsuffix="--program-suffix=$wsuffix"
    fi
    if [ -n "$csuffix" ]; then
        csuffix="--program-suffix=$csuffix"
    fi
    if [ -n "$asuffix" ]; then
        asuffix="--program-suffix=$asuffix"
    fi
    clear
}

suffix_choice_fn() {
    local choice
    clear

    printf "%s\n\n%s\n\n%s\n%s\n\n" \
        'Do you want to add a suffix to the curl, wget, and aria2 binaries?' \
        'Example: curl will output as curl-dev if you input "-dev" (w/o quotes)' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice
    clear

    case "$choice" in
        1)      add_suffix_fn;;
        2)      clear;;
        *)
                unset choice
                suffix_choice_fn
                ;;
    esac
}
suffix_choice_fn

printf "%s\n%s\n%s\n" \
    "Download Tools Build Script - v$script_ver" \
    "=========================================" \
    "This script will utilize ($cpu_threads) CPU threads for parallel processing to accelerate the build process."

fail_fn() {
    printf "\n%s\n%s\n%s\n\n" \
        "$1" \
        'You can enable the script'\''s debugging feature by changing the variable "debug" to "ON"' \
        "To report a bug visit: $web_repo/issues"
    exit 1
}

exit_fn() {
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

cleanup_fn() {
    local choice
 
    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to cleanup the build files?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice
    clear

    case "$choice" in
        1)      sudo rm -fr "$cwd";;
        2)      clear;;
        *)
                unset choice
                cleanup_fn
                ;;
    esac
}

success_fn() {
    local a_ver c_ver w_ver

    if [ -n "$wsuffix" ]; then
        w_ver="wget$wsuffix"
    else
        w_ver=wget
    fi
    if [ -n "$csuffix" ]; then
        c_ver="curl$csuffix"
    else
        c_ver=curl
    fi
    if [ -n "$asuffix" ]; then
        a_ver="aria2c$asuffix"
    else
        a_ver=aria2c
    fi

    w_ver="$($w_ver --version | grep -Eo '[0-9\.]+' | sed -n 1p)"
    c_ver="$($c_ver --version | grep -Eo '[0-9\.]+' | sed -n 1p)"
    a_ver="$($a_ver --version | grep -Eo '[0-9\.]+$' | sed -n 1p)"

    printf "\n%s\n\n%s\n%s\n%s\n"     \
        "The updated versions are:" \
        "aria2: $a_ver"           \
        "curl:  $c_ver"           \
        "wget:  $w_ver"
}


git_1_fn() {
    local curl_cmd github_repo github_url

    github_repo="$1"
    github_url="$2"

    if curl_cmd="$(curl -A "$user_agent" -m 10 -sSL "https://api.github.com/repos/$github_repo/$github_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_url="$(echo "$curl_cmd" | jq -r '.[0].tarball_url' 2>/dev/null)"
    fi

}

git_ver_fn() {
    local v_flag v_url v_tag url_tag t_url

    v_url="$1"
    v_tag="$2"

    if [ -n "$3" ]; then
        v_flag="$3"
        case "$v_flag" in
            T)      t_url=tags;;
            R)      t_url=releases;;
            *)      fail_fn 'Failed to pass "tags" and "releases" to the command: curl_cmd.';;
        esac
    fi

    git_1_fn "$v_url" "$t_url" 2>/dev/null
}

execute() {
    echo "$ $*"

    if [ "$debug" = 'ON' ]; then
        if ! output=$("$@"); then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail_fn "Failed to execute: $*"
        fi
    else
        if ! output=$("$@" 2>&1); then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail_fn "Failed to execute: $*"
        fi
    fi
}

download() {
    dl_path="$packages"
    dl_url="$1"

    if [[ "$dl_file" =~ tar. ]]; then
        output_dir="$dl_file%.*"
        output_dir="$3:-"${output_dir%.*"}"
    else
        output_dir="$3:-"${dl_file%.*"}"
    fi

    target_file="$dl_path/$dl_file"
    target_dir="$dl_path/$output_dir"

    if [ -f "$target_file" ]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! curl -A "$user_agent" -Lso "$target_file" "$dl_url"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! curl -A "$user_agent" -Lso "$target_file" "$dl_url"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit. Line: $LINENO"
            fi
        fi
        echo 'Download Completed'
    fi

    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    fi
    mkdir -p "$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: $LINENO"
}

download_git() {
    local dl_path dl_url dl_file target_dir

    dl_path="$packages"
    dl_url="$1"
    dl_file="$dl_file//\./-"
    target_dir="$dl_path/$dl_file"

    if [ -n "$3" ]; then
        output_dir="$dl_path/$3"
        target_dir="$output_dir"
    fi

    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    fi

    echo "Downloading $dl_url as $dl_file"

    if ! git clone -q "$dl_url" "$target_dir"; then
        printf "\n%s\n\n" "The script failed to clone the directory \"$target_dir\" and will try again in 10 seconds..."
        sleep 10
        if ! git clone -q "$dl_url" "$target_dir"; then
            fail_fn "The script failed to clone the directory \"$target_dir\" twice and will now exit the buildLine: $LINENO"
        fi
    else
        printf "%s\n\n" "Successfully cloned: $target_dir"
    fi

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: $LINENO"
}

build() {
    printf "\n%s\n%s\n" \
        "building $1 - version $2" \
        '===================================='

    if [ -f "$packages/$1.done" ]; then
        if grep -Fx "$2" "$packages/$1.done" > /dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        else
            echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $packages/$1.done lockfile."
            return 1
        fi
    fi

    return 0
}

build_done() {
    echo "$2" > "$packages/$1.done"
}

installed() {
    return $(dpkg-query -W -f '$Status\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}')
}


pkgs_fn() {
    local pkg pkgs missing_pkgs

    pkgs=("$1" apt-transport-https apt-utils autoconf autoconf-archive autogen automake
          autopoint autotools-dev build-essential bzip2 ca-certificates ccache clang cmake
          curl default-jdk-headless gfortran git google-perftools graphviz jq lcov libaria2-0
          libaria2-0-dev libc-ares-dev libcppunit-dev libcunit1-dev libcurl4 libcurl4-gnutls-dev
          libdmalloc-dev libec-dev libedit-dev libev-dev libevent-dev libexiv2-27 libexpat1-dev
          libgcc-12-dev libgcrypt20-dev libgexiv2-2 libgimp2.0 libglib2.0-dev libgmp-dev libgmp3-dev
          libgnutls28-dev libgpg-error-dev libgsasl-dev libgtk-4-doc libicu-dev libintl-perl
          libjemalloc-dev libkrb5-3 libldap-dev libldap2-dev liblttng-ust-dev liblzma-dev libmbedtls-dev
          libncurses-dev libncurses5-dev libnghttp2-dev libnghttp3-dev libngtcp2-dev libntlm0-dev
          libparted-dev libpng-dev libpsl-dev libpth-dev librtmp-dev librust-openssl-dev libsqlite3-dev
          libssh-dev libssh2-1-dev libssl-dev libticonv-dev libtinfo-dev libtinfo5 libtool
          libunistring-dev libunwind8 libuv1-dev libxml2-dev libzstd-dev lzip m4 nettle-dev
          openssh-server pkg-config python3 python3-dev python3-numpy python3-packaging python3-pip
          python3-pytest python3-setuptools python3-wheel re2c rsync sudo unzip wget zip zlib1g
          zlib1g-dev)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

   printf "\n%s\n%s\n" \
        'Installing required apt packages' \
        '================================================'

    if [ -n "$missing_pkgs" ]; then
        sudo apt install $missing_pkgs
        sudo apt -y autoremove
        printf "%s\n" 'The required APT packages were installed.'
    else
        printf "%s\n" 'The required APT packages are already installed.'
    fi
}


find_lsb_release="$(sudo find /usr -type f -name 'lsb_release')"

if [ -f /etc/os-release ]; then
    source /etc/os-release
    OS_TMP="$NAME"
    VER_TMP="$VERSION_ID"
    CODENAME="$VERSION_CODENAME"
    OS="$(echo "$OS_TMP" | awk '{print $1}')"
    VER="$(echo "$VER_TMP" | awk '{print $1}')"
elif [ -n "$find_lsb_release" ]; then
    OS="$(lsb_release -d | awk '{print $2}')"
    VER="$(lsb_release -r | awk '{print $2}')"
else
    fail_fn "Failed to define the \$OS and/or \$VER variables. Line: $LINENO"
fi


case "$OS" in
    Debian)     pkgs_fn;;
    Ubuntu)     pkgs_fn 'language-pack-en';;
    *)          fail_fn "Could not detect the OS architecture. Line: $LINENO";;
esac


if [ ! -f "$pem_out" ]; then
    printf "%s\n%s\n\n" \
        'Download the latest security certificate' \
        '================================================'
    curl -A "$user_agent" -Lso "$packages/$pem_file" "https://curl.se/ca/$pem_file"
    sudo cp -f "$packages/$pem_file" "$pem_out"
fi



if build 'pkg-config' '0.29.2'; then
    download "https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
    execute ./configure --prefix="$workspace" \
                        --with-pc-path="$PKG_CONFIG_PATH"
    execute make "-j$cpu_threads"
    execute make install
    build_done 'pkg-config' '0.29.2'
fi


git_ver_fn 'madler/zlib' '1' 'T'
if build 'zlib' "$g_ver"; then
    download "$g_url" "zlib-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace"
    execute make "-j$cpu_threads"
    execute make install
    build_done 'zlib' "$g_ver"
fi

git_ver_fn 'akheron/jansson' '1' 'T'
if build 'jansson' "$g_ver"; then
    download "$g_url" "jansson-$g_ver.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done 'jansson' "$g_ver"
fi

if build 'gsasl' '2.2.0'; then
    download 'https://ftp.gnu.org/gnu/gsasl/gsasl-2.2.0.tar.gz' 'gsasl-2.2.0.tar.gz'
    execute ./configure --prefix="$workspace"                \
                         --disable-gtk-doc                     \
                         --disable-shared                      \
                         --disable-year2038                    \
                         --with-libiconv-prefix="$workspace" \
                         --with-openssl=auto
    execute make "-j$cpu_threads"
    execute make install
    build_done 'gsasl' '2.2.0'
fi

git_ver_fn 'c-ares/c-ares' '1' 'R'
g_ver="$g_ver//cares-/"
g_tag="$g_ver//\./_"
if build 'c-ares' "$g_ver"; then
    download "$g_url" "c-ares-$g_ver.tar.gz"
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                         --disable-shared       \
                         --disable-warnings     \
                         --enable-optimize="$CFLAGS"
    execute make "-j$cpu_threads"
    execute make install
    build_done 'c-ares' "$g_ver"
fi

git_ver_fn 'pcre2project/pcre2' '1' 'T'
if build 'pcre2' "$g_ver"; then
    download "$g_url" "pcre2-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --disable-shared
    execute make "-j$cpu_threads"
    execute make install
    build_done 'pcre2' "$g_ver"
fi

git_ver_fn 'jemalloc/jemalloc' '1' 'T'
if build 'jemalloc' "$g_ver"; then
    download "$g_url" "jemalloc-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"  \
                         --disable-debug         \
                         --disable-doc           \
                         --disable-fill          \
                         --disable-log           \
                         --disable-prof          \
                         --disable-shared        \
                         --disable-stats         \
                         --enable-autogen        \
                         --enable-static         \
                         --enable-xmalloc
    execute make "-j$cpu_threads"
    execute make install
    build_done 'jemalloc' "$g_ver"
fi

git_ver_fn 'google/brotli' '1' 'T'
if build 'brotli' '1.0.9'; then
    download 'https://github.com/google/brotli/archive/refs/tags/v1.0.9.tar.gz' 'brotli-1.0.9.tar.gz'
    execute cmake -B build                              \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release            \
                  -DBUILD_SHARED_LIBS=OFF               \
                  -DBUILD_TESTING=OFF                   \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja "-j$cpu_threads" -C build install
    build_done 'brotli' '1.0.9'
fi


if build 'wget' 'latest'; then
    download 'https://ftp.gnu.org/gnu/wget/wget-latest.tar.lz'
    if which update-ca-certificates &>/dev/null; then
        execute sudo update-ca-certificates
    fi
    execute autoreconf -fi
    ./configure --prefix="$install_prefix" \
                 --enable-threads            \
                 --with-cares                \
                 --with-metalink             \
                 --with-openssl=auto         \
                 --with-ssl=gnutls "$wsuffix"
    execute make "-j$cpu_threads"
    execute sudo make install
    build_done 'wget' 'latest'
fi


git_ver_fn 'curl/curl' '1' 'R'
if build 'curl' "$g_ver"; then
    download "https://curl.se/download/curl-$g_ver.tar.xz"
    dopts=('--disable-'{get-easy-options,shared,verbose,versioned-symbols})
    eopts=('--enable-'{alt-svc,ares="$workspace",cookies})
    eopts+=('--enable-'{dict,dnsshuffle,doh,file,ftp,gopher})
    eopts+=('--enable-'{headers-api,hsts,http,http-auth,imap})
    eopts+=('--enable-'{ipv6,ldap,ldaps,libcurl-option,libgcc,manual})
    eopts+=('--enable-'{mime,mqtt,netrc,ntlm,ntlm-wb='/usr/bin/ntlm_auth'})
    eopts+=('--enable-'{openssl-auto-load-config,optimize,pop3,progress-meter})
    eopts+=('--enable-'{proxy,pthreads,rtsp,smb,smtp,socketpair,sspi,static,telnet})
    eopts+=('--enable-'{tftp,threaded-resolver,tls-srp,unix-sockets,websockets})
    wopts=('--with-'{gnutls='/usr/include',libssh2,nghttp2='/usr/include',nghttp3='/usr/include'})
    wopts+=('--with-'{ca-bundle="$pem_out",ca-fallback,ca-path="$cert_dir",secure-transport})
    execute autoreconf -fi
    ./configure --prefix="$install_prefix" \
                "${dopts[@]}"                \
                "${eopts[@]}"                \
                "${wopts[@]}"                \
                "$csuffix"                 \
                 LIBS="$(pkg-config --libs libnghttp3)"
    execute make "-j$cpu_threads"
    execute sudo make install
    build_done 'curl' "$g_ver"
fi


git_ver_fn 'aria2/aria2' '1' 'T'
if build 'aria2' '1.36.0'; then
    download 'https://github.com/aria2/aria2/releases/download/release-1.36.0/aria2-1.36.0.tar.xz'
    execute sed -i 's/1, 16/1, 128/g' 'src/OptionHandlerFactory.cc'
    mkdir build
    cd build || exit 1
    ../configure --prefix="$install_dir"               \
                 --{build,host,target}="$pc_type"      \
                 --disable-nls                           \
                 --disable-shared                        \
                 --disable-werror                        \
                 --enable-libaria2                       \
                 --enable-static                         \
                 --with-ca-bundle="$pem_out"           \
                 --with-libgcrypt=/usr                   \
                 --with-libiconv-prefix=/usr             \
                 --with-libintl-prefix=/usr              \
                 --with-libuv                            \
                 --with-jemalloc                         \
                 --with-openssl                          \
                 --with-pic                              \
                 --without-gnutls                        \
                 ARIA2_STATIC=yes                        \
                 CFLAGS="$CFLAGS"                      \
                 CXXFLAGS="$CXXFLAGS"                  \
                 CPPFLAGS="$CPPFLAGS"                  \
                 EXPAT_LIBS="$(pkg-config --libs expat)" \
                 LDFLAGS="$LDFLAGS"                    \
                 LIBS="$(pkg-config --libs libuv) $(pkg-config --libs libgcrypt)"
    execute make "-j$cpu_threads"
    execute sudo make install
    build_done 'aria2' '1.36.0'
fi

sudo ldconfig 2>/dev/null

success_fn

cleanup_fn

exit_fn
