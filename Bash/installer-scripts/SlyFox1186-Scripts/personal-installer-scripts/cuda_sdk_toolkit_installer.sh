#!/usr/bin/env bash
# Native CUDA toolkit installer. No drivers, reboot, or cross-release fallback.
# NVIDIA matrix and network instructions checked 2026-09-09:
# https://developer.nvidia.com/cuda-downloads
# https://docs.nvidia.com/cuda/cuda-installation-guide-linux/
# Sourceable for tests; execute with Bash to install. See --help.

BASE_URL=https://developer.download.nvidia.com/compute/cuda/repos

log() {
    local level=$1
    shift
    printf '[%s] %-5s %s\n' "$(date '+%H:%M:%S')" "$level" "$*" >&2
    if [[ -n ${LOG_FILE:-} ]]; then
        printf '[%s] %-5s %s\n' "$(date '+%H:%M:%S')" "$level" "$*" >>"$LOG_FILE"
    fi
}
die() {
    log ERROR "$*"
    exit 1
}
info() { log INFO "$*"; }
warn() { log WARN "$*"; }

usage() {
    cat <<'HELP'
Usage: bash cuda.sh [OPTIONS]

Install the newest CUDA toolkit published for the exact native OS repository,
including updates within that toolkit series. Installs a C++ compiler if needed.
Uses apt-get, dnf, tdnf or zypper. Does not install GPU drivers or reboot.

  --dry-run           Check NVIDIA's live repository and show install commands.
                      No sudo, package changes or shell-profile changes.
  --version MAJOR.MINOR
                      Select a toolkit series (example: 13.4), latest patch.
  --no-profile        Do not update the invoking user's ~/.bashrc.
  --verbose           Show each command and download URL, plus elapsed times.
                      Package-manager output is always shown and logged.
  --os ID:VERSION     Preview another OS; requires --dry-run (e.g. kylin:V11).
  --arch ARCH         Preview x86_64 or aarch64; requires --dry-run.
  -h, --help          Show this help without network access or root privileges.

Families: AlmaLinux, Amazon Linux, Azure Linux, Debian, Fedora, KylinOS,
openSUSE Leap, Oracle Linux, RHEL, Rocky, SLES and Ubuntu. Only native
architecture combinations from NVIDIA's download selector are accepted.
An exact published repository is required; its existence does not certify every
OS point release, kernel, compiler or GPU. Jetson and WSL use separate workflows.

Normal execution requests sudo when needed and accepts package-manager prompts.
A private log is retained in /tmp/cuda-install.*.log. Downloads are cleaned up.
Debian contrib and SLES PackageHub must be available when dependencies need them.
HELP
}

# Repository aliases follow the download selector, not ID_LIKE heuristics.
detect_platform() {
    DISTRO_ID=$1 DISTRO_VER=$2 MACHINE=$3
    local version=$DISTRO_VER
    [[ $DISTRO_ID == kylin ]] && version=${version#[Vv]}
    [[ $version =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "Invalid VERSION_ID '$DISTRO_VER' for '$DISTRO_ID'."
    MAJOR=${version%%.*}
    case $MACHINE in
        x86_64) ARCH=x86_64 ;;
        aarch64) ARCH=sbsa ;;
        *) die "Unsupported architecture '$MACHINE'; expected x86_64 or aarch64 (SBSA)." ;;
    esac
    case $DISTRO_ID in
        ubuntu)
            [[ $version =~ ^[0-9]{2}\.[0-9]{2}$ ]] || die "Ubuntu requires a release such as 24.04."
            PM=apt REPO_DIR=ubuntu${version//./}
            ;;
        debian) PM=apt REPO_DIR=debian$MAJOR ;;
        rhel | almalinux | rocky | ol) PM=dnf REPO_DIR=rhel$MAJOR ;;
        fedora) PM=dnf REPO_DIR=fedora$MAJOR ;;
        amzn) PM=dnf REPO_DIR=amzn$MAJOR ;;
        azurelinux) PM=tdnf REPO_DIR=azl$MAJOR ;;
        kylin) PM=dnf REPO_DIR=kylin$MAJOR ;;
        sles | sles_sap)
            PM=zypper REPO_DIR=sles$MAJOR
            [[ $MAJOR != 16 ]] || REPO_DIR=suse16
            ;;
        opensuse-leap)
            PM=zypper REPO_DIR=opensuse$MAJOR
            [[ $MAJOR != 16 ]] || REPO_DIR=suse16
            ;;
        *) die "Unsupported distribution '$DISTRO_ID'. See --help for NVIDIA's native families." ;;
    esac
    if [[ $ARCH == sbsa ]]; then
        case $DISTRO_ID in
            amzn | azurelinux | debian | kylin | rhel | sles | sles_sap | ubuntu) ;;
            *) die "NVIDIA's native ARM matrix does not list '$DISTRO_ID'." ;;
        esac
    fi
    REPO_URL=$BASE_URL/$REPO_DIR/$ARCH
}

require_commands() {
    local cmd
    for cmd in "$@"; do command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' is missing."; done
}

# Bounded retries only for downloads; never replay a failed package transaction.
fetch() {
    [[ ${VERBOSE:-0} == 0 ]] || info "Download: $1"
    curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 180 --retry 2 --retry-delay 2 --retry-max-time 240 \
        --output "$2" "$1"
}

# Match complete native filenames: excludes major-only, config and cross packages.
package_names() {
    local suffix
    if [[ $PM == apt ]]; then
        if [[ $ARCH == sbsa ]]; then suffix=arm64; else suffix=amd64; fi
        grep -Eo "cuda-toolkit-[0-9]+-[0-9]+_[0-9][^\"'<>/[:space:]]*_($suffix|all)\.deb" "$1"
    else
        if [[ $ARCH == sbsa ]]; then suffix=aarch64; else suffix=x86_64; fi
        grep -Eo "cuda-toolkit-[0-9]+-[0-9]+-[0-9]+\.[0-9][^\"'<>/[:space:]]*\.($suffix|noarch)\.rpm" "$1"
    fi | sed -E 's/^(cuda-toolkit-[0-9]+-[0-9]+).*/\1/' | LC_ALL=C sort -uV
}

discover_toolkit() {
    info "[2/6] Reading $REPO_URL/"
    fetch "$REPO_URL/" "$WORKDIR/index" || die "Cannot read the exact repository. No older OS repository will be substituted: $REPO_URL/"
    local packages
    packages=$(package_names "$WORKDIR/index") || die "No native toolkit packages found in $REPO_URL/."
    if [[ -n ${REQUESTED_VERSION:-} ]]; then
        LATEST_PKG=cuda-toolkit-${REQUESTED_VERSION/./-}
        grep -Fxq "$LATEST_PKG" <<<"$packages" || die "CUDA $REQUESTED_VERSION is not published in $REPO_URL/."
    else
        LATEST_PKG=$(tail -n 1 <<<"$packages")
    fi
    [[ -n $LATEST_PKG ]] || die "Empty toolkit selection."
    CUDA_VERSION=${LATEST_PKG#cuda-toolkit-}
    CUDA_VERSION=${CUDA_VERSION/-/.}
    CUDA_HOME=/usr/local/cuda-$CUDA_VERSION
    info "Selected $LATEST_PKG (latest patch available to the package manager)."
}

run() {
    local description=$1 start=$SECONDS status=0 command_text
    shift
    info "$description"
    printf -v command_text '%q ' "$@"
    if [[ ${DRY_RUN:-0} == 1 || ${VERBOSE:-0} == 1 ]]; then
        info "Command: $command_text"
    elif [[ -n ${LOG_FILE:-} ]]; then printf 'Command: %s\n' "$command_text" >>"$LOG_FILE"; fi
    [[ ${DRY_RUN:-0} == 0 ]] || return 0
    # pipefail preserves both the command's failure and log/output failures.
    "$@" 2>&1 | tee -a "$LOG_FILE" | sed -u 's/^/    /' || status=$?
    if ((status != 0)); then
        log ERROR "$description failed (exit $status). See $LOG_FILE. No automatic retry or rollback."
        return "$status"
    fi
    [[ ${VERBOSE:-0} == 0 ]] || info "Finished in $((SECONDS - start))s."
}

prepare_repository() {
    info '[3/6] Preparing signed network repository'
    if [[ $PM == apt ]]; then
        KEYRING_DEB=$(grep -Eo 'cuda-keyring_[0-9][a-zA-Z0-9.+~_-]*_all\.deb' "$WORKDIR/index" | LC_ALL=C sort -uV | tail -n 1) ||
            die "No cuda-keyring package published by this repository."
        [[ -n $KEYRING_DEB ]] || die "Empty keyring package selection."
        fetch "$REPO_URL/$KEYRING_DEB" "$WORKDIR/$KEYRING_DEB" || die 'Keyring download failed.'
        # Inspect the bootstrap package before invoking its maintainer scripts.
        if [[ $DRY_RUN == 0 ]]; then
            [[ $(dpkg-deb -f "$WORKDIR/$KEYRING_DEB" Package) == cuda-keyring ]] || die 'Downloaded package is not cuda-keyring.'
        fi
        run 'Install NVIDIA signing key and APT source' dpkg -i "$WORKDIR/$KEYRING_DEB"
        run 'Refresh APT metadata (any repository error is fatal)' apt-get -o APT::Update::Error-Mode=any update
    else
        REPO_FILE=cuda-$REPO_DIR.repo
        fetch "$REPO_URL/$REPO_FILE" "$WORKDIR/vendor.repo" || die 'Repository configuration download failed.'
        local key_url
        key_url=$(sed -n 's/^gpgkey=//p' "$WORKDIR/vendor.repo")
        [[ $key_url == "$REPO_URL/"* && ${key_url#"$REPO_URL/"} =~ ^[[:xdigit:]]+\.pub$ ]] ||
            die 'Unexpected NVIDIA signing-key URL in repository configuration.'
        # Keep the configuration minimal: never carry unchecked options from HTML or a repo file.
        printf '[cuda-%s-%s]\nname=NVIDIA CUDA %s %s\nbaseurl=%s\nenabled=1\ngpgcheck=1\ngpgkey=%s\n' \
            "$REPO_DIR" "$ARCH" "$REPO_DIR" "$ARCH" "$REPO_URL" "$key_url" >"$WORKDIR/$REPO_FILE"
        local repo_path=/etc/yum.repos.d
        [[ $PM != zypper ]] || repo_path=/etc/zypp/repos.d
        run 'Register NVIDIA repository' install -m 0644 "$WORKDIR/$REPO_FILE" "$repo_path/$REPO_FILE"
        if [[ $PM == zypper ]]; then
            run 'Refresh NVIDIA repository and import its signing key' zypper --non-interactive --gpg-auto-import-keys refresh "cuda-$REPO_DIR-$ARCH"
        elif [[ $PM == tdnf ]]; then
            run 'Enable Azure Linux extended dependencies' tdnf -y install azurelinux-repos-extended
            run 'Refresh tdnf cached metadata' tdnf clean all
        fi
    fi
}

install_toolkit() {
    info '[4/6] Installing toolkit and host compiler'
    local -a extra=()
    case $PM in
        apt) run 'Install/update CUDA and C++ build tools' apt-get -y install "$LATEST_PKG" build-essential ;;
        dnf)
            # Enable optional dependencies for this transaction without dnf4/dnf5 plugins.
            case $DISTRO_ID in
                rhel) extra+=("--enablerepo=codeready-builder-for-rhel-$MAJOR-$MACHINE-rpms") ;;
                ol) extra+=("--enablerepo=ol${MAJOR}_codeready_builder") ;;
                rocky | almalinux)
                    if ((10#$MAJOR >= 9)); then extra+=(--enablerepo=crb); else extra+=(--enablerepo=powertools); fi
                    ;;
            esac
            run 'Install/update CUDA and C++ compiler' dnf --refresh "${extra[@]}" -y install "$LATEST_PKG" gcc-c++
            ;;
        tdnf) run 'Install/update CUDA and C++ compiler' tdnf -y install "$LATEST_PKG" gcc-c++ ;;
        zypper) run 'Install/update CUDA and C++ compiler' zypper --non-interactive install --auto-agree-with-licenses "$LATEST_PKG" gcc-c++ ;;
    esac
}

verify_toolkit() {
    info '[5/6] Verifying package, compiler and a CUDA compilation'
    local version
    if [[ $PM == apt ]]; then
        [[ $(dpkg-query -W -f='${db:Status-Status}' "$LATEST_PKG") == installed ]] || die "$LATEST_PKG is not fully installed."
    else
        rpm -q "$LATEST_PKG" >>"$LOG_FILE" || die "$LATEST_PKG is not installed."
    fi
    [[ -x $CUDA_HOME/bin/nvcc ]] || die "Installation incomplete: $CUDA_HOME/bin/nvcc is missing."
    version=$("$CUDA_HOME/bin/nvcc" --version) || die 'nvcc cannot run.'
    [[ $version == *"release $CUDA_VERSION,"* ]] || die "nvcc does not report the selected release $CUDA_VERSION."
    run 'Check installed compiler version' "$CUDA_HOME/bin/nvcc" --version || return $?
    printf '__global__ void cuda_installer_probe() {}\n' >"$WORKDIR/probe.cu"
    run 'Compile a minimal CUDA kernel (does not execute on the GPU)' "$CUDA_HOME/bin/nvcc" -c "$WORKDIR/probe.cu" -o "$WORKDIR/probe.o" || return $?
    [[ -s $WORKDIR/probe.o ]] || die 'Compiler returned success but produced no object file.'
}

# Runs as the profile owner, never as root on behalf of a regular user.
# Reject ambiguous markers, symlinks and hard links; preserve the original on failure.
update_profile() (
    set -euo pipefail
    local rc=$1 cuda_home=$2 tmp='' snapshot='' backup='' block start end
    start='# >>> cuda toolkit (managed by cuda.sh) >>>'
    end='# <<< cuda toolkit (managed by cuda.sh) <<<'
    [[ ! -L $rc && (! -e $rc || -f $rc) ]] || {
        echo "Refusing non-regular or symlink profile: $rc" >&2
        exit 1
    }
    [[ ! -e $rc || $(stat -c %h "$rc") == 1 ]] || {
        echo "Refusing multiply linked profile: $rc" >&2
        exit 1
    }
    [[ -d ${rc%/*} ]] || {
        echo "Missing profile directory: ${rc%/*}" >&2
        exit 1
    }
    # These variables must expand when the user loads the profile.
    # shellcheck disable=SC2016
    printf -v block '%s\nexport CUDA_HOME=%q\n%s\n%s' "$start" "$cuda_home" \
        'case ":${PATH:-}:" in *":$CUDA_HOME/bin:"*) ;; *) export PATH="$CUDA_HOME/bin${PATH:+:$PATH}" ;; esac' "$end"
    tmp=$(mktemp "$rc.cuda-new.XXXXXX")
    trap 'rm -f -- "$tmp"; [[ -z $snapshot ]] || rm -f -- "$snapshot"' EXIT
    if [[ -e $rc ]]; then
        snapshot=$(mktemp "$rc.cuda-snapshot.XXXXXX")
        cp -p -- "$rc" "$snapshot"
        # Validate ordering/counts before replacing; substring matches are ambiguous too.
        awk -v start="$start" -v end="$end" '
            index($0,start) { if ($0 != start || opened || closed) exit 1; opened=1 }
            index($0,end) { if ($0 != end || !opened || closed) exit 1; closed=1 }
            END { if (opened != closed) exit 1 }
        ' "$snapshot" || {
            echo "Malformed CUDA markers in $rc; left unchanged." >&2
            exit 1
        }
        awk -v start="$start" -v end="$end" -v block="$block" '
            $0 == start { skip=1; replaced=1; print block; next }
            $0 == end { skip=0; next }
            !skip { print }
            END { if (!replaced) printf "\n%s\n", block }
        ' "$snapshot" >"$tmp"
        if cmp -s "$rc" "$tmp"; then
            echo "$rc already configured."
            exit 0
        fi
        backup=$(mktemp "$rc.cuda-backup.XXXXXX")
        cp -p -- "$snapshot" "$backup"
        cp --attributes-only --preserve=all -- "$snapshot" "$tmp"
        cmp -s "$rc" "$snapshot" || {
            echo 'Profile changed during update; refusing replacement.' >&2
            exit 1
        }
    else
        printf '%s\n' "$block" >"$tmp"
    fi
    mv -f -- "$tmp" "$rc"
    printf 'Updated %s%s\n' "$rc" "${backup:+ (backup: $backup)}"
)

configure_shell_env() {
    info '[6/6] Configuring Bash environment'
    [[ $NO_PROFILE == 0 ]] || {
        info 'Profile changes disabled.'
        return 0
    }
    local target_user=${SUDO_USER:-root} record target_home target_uid
    record=$(getent passwd "$target_user") || {
        warn "Cannot resolve profile owner '$target_user'."
        return 0
    }
    IFS=: read -r _ _ target_uid _ _ target_home _ <<<"$record"
    [[ $target_home == /* && -d $target_home ]] || {
        warn 'No usable home directory; skipping profile setup.'
        return 0
    }
    local -a worker=(bash --noprofile --norc -s -- "$target_home/.bashrc" "$CUDA_HOME")
    if [[ $target_uid != "$EUID" ]]; then worker=(runuser -u "$target_user" -- "${worker[@]}"); fi
    if printf '%s\n' "$(declare -f update_profile)" 'update_profile "$@"' | run 'Update CUDA_HOME and PATH atomically (with backup)' "${worker[@]}"; then
        info "Open a new Bash shell, or run: source $(printf '%q' "$target_home/.bashrc")"
    else
        warn "Toolkit verified, but profile setup failed. Add $CUDA_HOME/bin to PATH manually."
    fi
}

check_driver_health() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        if run 'Query GPU driver (15-second timeout)' timeout 15 nvidia-smi --query-gpu=name,driver_version --format=csv,noheader; then
            info 'Driver query succeeded. GPU execution and toolkit/driver compatibility still depend on the hardware and application.'
            return 0
        fi
        warn 'GPU driver query failed or timed out. The toolkit compilation check passed.'
    else
        warn 'nvidia-smi is unavailable. Toolkit compilation passed; GPU runtime is unverified.'
    fi
    info 'Driver guidance: https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/'
}

cleanup() {
    local status=$?
    trap - EXIT
    [[ -z ${WORKDIR:-} ]] || rm -rf -- "$WORKDIR"
    if ((status != 0)); then log ERROR "Stopped (exit $status). Completed package transactions are not rolled back."; fi
    [[ -z ${LOG_FILE:-} ]] || printf 'Log: %s\n' "$LOG_FILE" >&2
    exit "$status"
}

main() {
    set -Eeuo pipefail
    DRY_RUN=0 VERBOSE=0 NO_PROFILE=0 REQUESTED_VERSION=''
    LOG_FILE='' WORKDIR=''
    local preview_os='' preview_arch='' arg
    local -a original_args=("$@")
    while (($#)); do
        arg=$1
        case $arg in
            --dry-run) DRY_RUN=1 ;;
            --verbose) VERBOSE=1 ;;
            --no-profile) NO_PROFILE=1 ;;
            --version | --os | --arch)
                (($# >= 2)) && [[ $2 != --* && -n $2 ]] || die "$arg requires a value."
                case $arg in --version) REQUESTED_VERSION=$2 ;; --os) preview_os=$2 ;; --arch) preview_arch=$2 ;; esac
                shift
                ;;
            -h | --help)
                usage
                return 0
                ;;
            *) die "Unknown option: $arg (see --help)." ;;
        esac
        shift
    done
    [[ -z $REQUESTED_VERSION || $REQUESTED_VERSION =~ ^[1-9][0-9]*\.(0|[1-9][0-9]*)$ ]] || die '--version requires MAJOR.MINOR, such as 13.4.'
    [[ $DRY_RUN == 1 || (-z $preview_os && -z $preview_arch) ]] || die '--os and --arch are only allowed with --dry-run.'
    local ID='' VERSION_ID='' PRETTY_NAME=''
    [[ -r /etc/os-release ]] || die 'Cannot read /etc/os-release.'
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ -n $preview_os ]]; then
        [[ $preview_os == *:* ]] || die '--os requires ID:VERSION.'
        ID=${preview_os%%:*} VERSION_ID=${preview_os#*:} PRETTY_NAME=$preview_os
    fi
    detect_platform "$ID" "$VERSION_ID" "${preview_arch:-$(uname -m)}"
    if [[ -z $preview_os && -z $preview_arch ]]; then
        [[ ! -e /etc/nv_tegra_release ]] || die 'Jetson requires the matching JetPack CUDA instructions.'
        [[ $(uname -r) != *[Mm]icrosoft* ]] || die 'WSL requires the NVIDIA WSL workflow.'
    fi
    require_commands curl awk sed grep sort tail mktemp tee date stat cmp cp mv chmod install timeout
    if [[ $DRY_RUN == 0 && $EUID != 0 ]]; then
        require_commands sudo
        exec sudo -- bash "$(readlink -f -- "${BASH_SOURCE[0]}")" "${original_args[@]}"
    fi
    # Private root-owned lock directory prevents concurrent installer/profile edits.
    if [[ $DRY_RUN == 0 ]]; then
        require_commands flock getent runuser
        install -d -m 0700 /run/cuda-toolkit-installer
        exec 9>/run/cuda-toolkit-installer/lock
        flock -n 9 || die 'Another CUDA installer is running.'
        case $PM in
            apt) require_commands apt-get dpkg dpkg-deb dpkg-query ;;
            dnf | tdnf | zypper) require_commands "$PM" rpm ;;
        esac
    fi
    LOG_FILE=$(mktemp /tmp/cuda-install.XXXXXX.log)
    WORKDIR=$(mktemp -d /tmp/cuda-install.XXXXXX)
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    export LC_ALL=C DEBIAN_FRONTEND=noninteractive
    info "[1/6] ${PRETTY_NAME:-$DISTRO_ID $DISTRO_VER}, $MACHINE -> $REPO_DIR/$ARCH ($PM)"
    info "Log: $LOG_FILE"
    [[ $DRY_RUN == 0 ]] || info 'DRY RUN: only temporary downloads and log files will be written.'
    discover_toolkit
    [[ ! -x $CUDA_HOME/bin/cuda-uninstaller ]] || die "Runfile installation found at $CUDA_HOME. Resolve the installation-method conflict first."
    case $DISTRO_ID in
        debian) info 'Dependency prerequisite: Debian contrib must be enabled if required by the package solver.' ;;
        sles | sles_sap) info 'Dependency prerequisite: enable the matching SLES PackageHub if required by the package solver.' ;;
    esac
    prepare_repository
    install_toolkit
    if [[ $DRY_RUN == 1 ]]; then
        info "Dry run complete. A real run will verify $CUDA_HOME/bin/nvcc, compile a CUDA kernel and query the driver."
        [[ $NO_PROFILE == 1 ]] || info "A real run will also update the invoking user's .bashrc with a backup."
        return 0
    fi
    verify_toolkit
    configure_shell_env
    check_driver_health
    info "CUDA $CUDA_VERSION installed and compilation verified. No driver installation or reboot performed."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
