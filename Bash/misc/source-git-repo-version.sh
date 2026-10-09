#!/usr/bin/env bash

set -euo pipefail

usage() {
    local heading='' command='' note='' reset=''
    if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
        heading=$'\033[1;36m'
        command=$'\033[32m'
        note=$'\033[33m'
        reset=$'\033[0m'
    fi

    cat <<HELP
${heading}GitHub release version${reset}
  Print the numeric version of a public repository's latest release.

${heading}Usage:${reset}
  ${command}source-git-repo-version.sh${reset} [OPTION] <github-url>

${heading}Options${reset}
  ${command}-h, --help${reset}    Show help without making network requests.
  ${command}--${reset}            End options before the repository URL.

${heading}Repository URL${reset}
  https://github.com/OWNER/REPO
  A .git suffix and trailing slash are accepted.

${heading}Examples${reset}
  ${command}bash source-git-repo-version.sh https://github.com/rust-lang/rust.git${reset}
  ${command}bash source-git-repo-version.sh https://github.com/curl/curl${reset}

  Capture the version in a shell variable:
  ${command}version=\$(bash source-git-repo-version.sh https://github.com/git/git) \\
    || exit 1${reset}

${heading}How the version is selected${reset}
  Follow GitHub's /releases/latest link to its designated latest full release.
  A higher tag never overrides that release. An unsupported latest tag fails.

  If no latest release exists, use the highest numeric tag on the first page.
  ${note}Tag fallback checks the first page only and cannot confirm release status.${reset}
  Preview tags such as rc1, beta, and a1 are rejected.

${heading}Supported version formats${reset}
  Numeric tags may have v/V/n/N prefixes, letter-based project prefixes
  separated by - or _, or tag namespaces:

    v1.2.3                ->  1.2.3
    curl-8_16_0           ->  8_16_0
    releases/gcc-16.2.0   ->  16.2.0

  Output preserves . _ - separators. Use one separator style per version;
  mixed separators and build metadata are unsupported.

${heading}Output and exit codes${reset}
  ${command}0${reset}  One version line on stdout, or the requested help.
  ${command}1${reset}  Lookup, dependency, or parsing failure; message on stderr.
  ${command}2${reset}  Invalid arguments; message on stderr.

  Failed lookups never print a version.

${heading}Network and requirements${reset}
  HTTPS only, with a 10-second connect timeout and 30-second transfer timeout.
  At most 5 redirects and 2 retries for transient errors. Retry time is limited
  to 30 seconds; an in-progress retry may finish after that limit.

  Requires Bash 4+, curl, grep, sed, and GNU sort (-V). No API token is used.

${heading}Display${reset}
  Color is automatic on supported terminals. Set NO_COLOR=1 for plain help.
  Redirected output and dumb terminals always receive plain text.

  Run this script with bash as shown above; do not source it into your shell.
HELP
}

error() {
    printf 'source-git-repo-version.sh: %s\n' "$*" >&2
}

numeric_version() {
    local tag=${1//%2F/\/}
    tag=${tag//%2f/\/}
    # Reject preview labels in prefixes as well as suffixes before extracting digits.
    if [[ ${tag,,} =~ (^|[-_/])(alpha|beta|dev|early|init|next|pending|pre|preview|rc[0-9]*|nightly|canary|snapshot|experimental|tentative|unstable|draft)([-_/]|$) ]]; then
        return 1
    fi
    tag=${tag##*/}
    if [[ $tag =~ ^([A-Za-z][A-Za-z_-]*[-_])?[vVnN]?([0-9]+([.][0-9]+)*|[0-9]+(_[0-9]+)*|[0-9]+(-[0-9]+)*)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[2]}"
    else
        return 1
    fi
}

get_latest_release_version() {
    local repo_url=$1 response status final_url tag version html href tag_path versions
    local repo_pattern='https://github[.]com/[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+'
    local user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36'
    local -a curl_options=(
        -q --silent --show-error --location --proto '=https' --proto-redir '=https'
        --connect-timeout 10 --max-time 30 --max-redirs 5
        --retry 2 --retry-max-time 30 --user-agent "$user_agent"
    )

    # HEAD resolves the documented permalink without downloading a release page.
    if ! response=$(curl "${curl_options[@]}" --head --output /dev/null \
        --write-out '%{http_code}\n%{url_effective}' "$repo_url/releases/latest"); then
        error 'Could not retrieve the latest release.'
        return 1
    fi
    status=${response%%$'\n'*}
    final_url=${response#*$'\n'}
    case $status in
        200)
            if [[ $final_url =~ ^($repo_pattern)/releases/tag/(.+)$ ]]; then
                tag=${BASH_REMATCH[2]}
                if version=$(numeric_version "$tag"); then
                    printf '%s\n' "$version"
                    return 0
                fi
                error 'The latest release tag has no supported numeric version.'
                return 1
            elif [[ $final_url =~ ^($repo_pattern)/releases/?$ ]]; then
                repo_url=${BASH_REMATCH[1]}
            else
                error 'GitHub returned an unexpected latest-release URL.'
                return 1
            fi
            ;;
        404)
            if [[ $final_url =~ ^($repo_pattern)/releases/latest$ ]]; then
                repo_url=${BASH_REMATCH[1]}
            else
                error 'GitHub returned an unexpected latest-release URL.'
                return 1
            fi
            ;;
        *)
            error "Latest-release lookup failed (HTTP $status)."
            return 1
            ;;
    esac

    if ! html=$(curl "${curl_options[@]}" --fail "$repo_url/tags"); then
        error 'Could not retrieve repository tags.'
        return 1
    fi
    tag_path="${repo_url#https://github.com}/releases/tag/"
    # GitHub may capitalize repository names in links after a lowercase request.
    if ! versions=$(
        { grep -oE 'href="[^"]*/releases/tag/[^"]+"' <<< "$html" || [[ $? == 1 ]]; } |
            while IFS= read -r href; do
                href=${href#href=\"}
                href=${href%\"}
                href=${href#https://github.com}
                if [[ ${href,,} == "${tag_path,,}"* ]]; then
                    numeric_version "${href:${#tag_path}}" || :
                fi
            done
    ); then
        error 'Could not parse repository tag links.'
        return 1
    fi
    if [[ -z $versions ]]; then
        error 'No supported numeric tag was found on the first tags page.'
        return 1
    fi
    if ! version=$(LC_ALL=C sort -Vr <<< "$versions" | sed -n '1p'); then
        error 'Could not sort repository versions; GNU sort with -V is required.'
        return 1
    fi
    printf '%s\n' "$version"
}

main() {
    case ${1:-} in
        -h|--help)
            if (( $# != 1 )); then
                error 'Help takes no additional arguments.'
                return 2
            fi
            usage
            return 0
            ;;
        --) shift ;;
        -*) error 'Unknown option. Run with --help for usage.'; return 2 ;;
    esac
    if (( $# != 1 )); then
        error 'Expected one GitHub repository URL. Run with --help for usage.'
        return 2
    fi

    local repo_url=${1%/} dependency repo
    repo_url=${repo_url%.git}
    if [[ ! $repo_url =~ ^https://github[.]com/[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$ ]]; then
        error 'Expected an HTTPS github.com/OWNER/REPO URL without query or fragment.'
        return 2
    fi
    repo=${repo_url##*/}
    if [[ $repo == . || $repo == .. ]]; then
        error 'Invalid GitHub repository name.'
        return 2
    fi
    for dependency in curl grep sed sort; do
        if ! command -v "$dependency" > /dev/null 2>&1; then
            error "Required command not found: $dependency"
            return 1
        fi
    done
    get_latest_release_version "$repo_url"
}

main "$@"
