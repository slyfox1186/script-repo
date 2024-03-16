#!/usr/bin/env bash

# Function to display the help menu
display_help() {
    echo "Usage: $0 [OPTIONS] [debian_release]"
    echo
    echo "debian_release is one of stable, testing, unstable, experimental"
    echo "or a codename like etch, lenny, squeeze, wheezy, jessie, stretch, buster,"
    echo "bullseye, bookworm, trixie, sid"
    echo
    echo "Options:"
    echo "  -h, --help              Display this help menu"
    echo "  -a, --arch ARCH         Use mirrors containing arch (default: amd64)"
    echo "  -s, --sources           Include deb-src lines in generated file"
    echo "  -n, --nonfree           Use also non-free packages in OUTFILE"
    echo "  -f, --ftp               Use FTP as the protocol for OUTFILE"
    echo "  -o, --outfile OUTFILE   Use OUTFILE as the output file (default: sources.list)"
    echo "  -c, --country COUNTRY   Restrict search to servers in that country"
    echo "  -d, --debug             Enable debugging"
    echo "  -t, --tests TESTS       Number of hosts to test (default: 10)"
    echo
}

# Default values for options
arch="amd64"
outfile="/etc/apt/sources.list"
debian_release="stable"
include_sources=false
use_nonfree=false
use_ftp=false
country=""
debug=false
tests=10 # Default number of hosts to test

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            display_help
            exit 0
            ;;
        -a|--arch)
            arch="$2"
            shift 2
            ;;
        -s|--sources)
            include_sources=true
            shift
            ;;
        -n|--nonfree)
            use_nonfree=true
            shift
            ;;
        -f|--ftp)
            use_ftp=true
            shift
            ;;
        -o|--outfile)
            outfile="$2"
            shift 2
            ;;
        -c|--country)
            country="$2"
            shift 2
            ;;
        -d|--debug)
            debug=true
            shift
            ;;
        -t|--tests)
            tests="$2"
            shift 2
            ;;
        *)
            debian_release="$1"
            shift
            ;;
    esac
done

if ! command -v netselect-apt &>/dev/null; then
    sudo apt-get install netselect-apt
    clear
fi

# Build the netselect-apt command with the specified options
netselect_apt_cmd="netselect-apt"
[[ "$include_sources" == true ]] && netselect_apt_cmd+=" -s"
[[ "$use_nonfree" == true ]] && netselect_apt_cmd+=" -n"
[[ "$use_ftp" == true ]] && netselect_apt_cmd+=" -f"
[[ "$country" != "" ]] && netselect_apt_cmd+=" -c $country"
[[ "$debug" == true ]] && netselect_apt_cmd+=" -d"
netselect_apt_cmd+=" -o $outfile -a $arch -t $tests $debian_release"

# Ensure netselect-apt is installed
if ! command -v netselect-apt >/dev/null; then
    echo "netselect-apt is not installed. Please install netselect-apt."
    exit 1
fi

# Inform the user about the chosen options
echo "Running netselect-apt with the following options:"
echo "$netselect_apt_cmd"

# Run netselect-apt with the constructed command
eval "$netselect_apt_cmd"

echo "netselect-apt has completed. Check $outfile for the selected mirror."
