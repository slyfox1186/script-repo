#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'HELP'
Usage: source-git-repo-version.sh [OPTION] <github-url>

Print the numeric version of a public GitHub repository's latest release.

Arguments:
  github-url      HTTPS repository URL: https://github.com/OWNER/REPO
                  An optional .git suffix and trailing slash are accepted.

Options:
  -h, --help      Show this help and exit without making network requests.
  --              End options before the repository URL.

Selection:
  Follow GitHub's /releases/latest link, which selects its latest full release.
  This respects the repository's latest-release designation. An unsupported
  latest tag is an error; a higher tag never overrides a published latest release.
  If there is no latest release, use the highest numeric tag on the first tags
  page. This fallback does not search older pages or confirm release status.
  Tags with preview suffixes (rc1, beta, a1, etc.) are rejected.

Version format:
  Accept numeric tags, optional v/V/n/N prefixes, letter-based project prefixes
  separated by - or _, and tag namespaces. Examples: v1.2.3, curl-8_16_0,
  releases/gcc-16.2.0. Print only the numeric part, preserving . _ - separators.
  Use one separator style per version; mixed styles and build metadata fail.

Network defaults:
  HTTPS only; 10-second connect timeout; 30-second transfer timeout;
  at most 5 redirects and 2 retries for transient errors. Retry time is limited
  to 30 seconds, but an in-progress retry can finish after that limit.
  No API token is used. Requires Bash 4+, curl, grep, sed, and GNU sort (-V).

Output and status:
  0  One version followed by a newline on stdout, or the requested help.
  1  Lookup, dependency, or version-parsing failure; error on stderr.
  2  Invalid arguments; error on stderr. Failures never print a version.

Examples:
  bash source-git-repo-version.sh https://github.com/rust-lang/rust.git
  bash source-git-repo-version.sh https://github.com/curl/curl
  version=$(bash source-git-repo-version.sh https://github.com/git/git) || exit 1

Run this script as a command; do not source it into your shell.
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
    # Match this repository's links only, excluding tags mentioned in unrelated content.
    if ! versions=$(
        { grep -oE 'href="[^"]*/releases/tag/[^"]+"' <<< "$html" || [[ $? == 1 ]]; } |
            while IFS= read -r href; do
                href=${href#href=\"}
                href=${href%\"}
                href=${href#https://github.com}
                if [[ $href == "$tag_path"* ]]; then
                    numeric_version "${href#"$tag_path"}" || :
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
