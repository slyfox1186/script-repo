#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/Bash/misc/source-git-repo-version.sh"
bash_path=$(command -v bash)
sort_path=$(command -v sort)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/bin"
export CURL_LOG="$scratch/curl.log"
export TAGS_FILE="$scratch/tags.html"
export LATEST_STATUS=200 LATEST_TAG=v1.2.3 LATEST_EXIT=0 TAGS_EXIT=0
export LATEST_URL=''
export SORT_PATH="$sort_path" SORT_EXIT=0

cat > "$scratch/bin/sort" <<'SORT'
#!/usr/bin/env bash
if [[ $SORT_EXIT != 0 ]]; then
    exit "$SORT_EXIT"
fi
exec "$SORT_PATH" "$@"
SORT
chmod +x "$scratch/bin/sort"

cat > "$scratch/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
url=${!#}
case "$url" in
    */releases/latest)
        if [[ $LATEST_EXIT != 0 ]]; then
            printf 'curl: simulated transfer failure\n' >&2
            exit "$LATEST_EXIT"
        fi
        final_url=${url%/releases/latest}/releases/tag/$LATEST_TAG
        [[ $LATEST_STATUS != 404 ]] || final_url=$url
        printf '%s\n%s\n' "$LATEST_STATUS" "${LATEST_URL:-$final_url}"
        ;;
    */tags)
        if [[ $TAGS_EXIT != 0 ]]; then
            printf 'curl: simulated tags failure\n' >&2
            exit "$TAGS_EXIT"
        fi
        cat "$TAGS_FILE"
        ;;
    *) printf 'Unexpected request: %s\n' "$url" >&2; exit 90 ;;
esac
CURL
chmod +x "$scratch/bin/curl"
export PATH="$scratch/bin:$PATH"
: > "$TAGS_FILE"
checks=0

run() {
    : > "$CURL_LOG"
    status=0
    PATH=${SCRIPT_PATH:-$PATH} "$bash_path" "$script" "$@" > "$scratch/out" 2> "$scratch/err" || status=$?
    output=$(cat "$scratch/out")
    error=$(cat "$scratch/err")
}

check() {
    local name=$1
    shift
    if ! "$@"; then
        printf 'FAIL: %s (status=%s, stdout=%q, stderr=%q)\n' "$name" "$status" "$output" "$error" >&2
        exit 1
    fi
    checks=$((checks + 1))
}

for option in -h --help; do
    run "$option"
    check "$option exits successfully" test "$status" -eq 0
    check "$option describes usage" test "${output#*Usage:}" != "$output"
    check "$option avoids network requests" test ! -s "$CURL_LOG"
    check "$option keeps redirected help plain" test "${output//$'\033'/}" = "$output"
done

check 'plain help fits an 80-column terminal' awk 'length > 80 {exit 1}' "$scratch/out"

if command -v script >/dev/null; then
    export HELP_BASH="$bash_path" HELP_SCRIPT="$script"
    tty_help() {
        : > "$CURL_LOG"
        # The PTY's child shell expands these exported paths.
        # shellcheck disable=SC2016
        env -u NO_COLOR "$@" script --quiet --return \
            --command '"$HELP_BASH" "$HELP_SCRIPT" --help' /dev/null \
            < /dev/null > "$scratch/tty.out" 2> "$scratch/tty.err"
    }
    tty_help TERM=xterm-256color
    check 'terminal help uses colored headings' grep -Fq $'\033[1;36m' "$scratch/tty.out"
    check 'terminal help highlights examples' grep -Fq $'\033[32m' "$scratch/tty.out"
    check 'terminal help avoids network requests' test ! -s "$CURL_LOG"
    LC_ALL=C sed $'s/\033\\[[0-9;]*m//g' "$scratch/tty.out" |
        tr -d '\r' > "$scratch/tty.plain"
    check 'colored and plain help have identical content' cmp -s "$scratch/out" "$scratch/tty.plain"
    tty_help TERM=xterm-256color NO_COLOR=1
    check 'NO_COLOR suppresses terminal colors' test "$(LC_ALL=C tr -d '\033' < "$scratch/tty.out")" = "$(cat "$scratch/tty.out")"
    tty_help TERM=dumb
    check 'dumb terminals receive plain help' test "$(LC_ALL=C tr -d '\033' < "$scratch/tty.out")" = "$(cat "$scratch/tty.out")"
fi

for input in '' --bogus http://github.com/owner/repo https://example.com/owner/repo \
    https://github.com.evil/owner/repo https://github.com/owner/repo/issues \
    'https://github.com/owner/repo?ref=v1' 'https://github.com/owner/repo#tag' \
    'https://user@github.com/owner/repo' 'file:///etc/passwd' \
    'https://github.com/owner/../repo' 'https://github.com/owner/repo;touch /tmp/version-test'; do
    run "$input"
    check "invalid input exits 2: $input" test "$status" -eq 2
    check "invalid input has no stdout: $input" test -z "$output"
    check "invalid input reports an error: $input" test -n "$error"
    check "invalid input avoids network: $input" test ! -s "$CURL_LOG"
done
run
check 'missing argument exits 2' test "$status" -eq 2
run https://github.com/owner/repo extra
check 'extra argument exits 2' test "$status" -eq 2

for input in https://github.com/owner/repo https://github.com/owner/repo.git \
    https://github.com/owner/repo/ https://github.com/owner/repo.git/; do
    run "$input"
    check "valid URL returns version: $input" test "$output" = 1.2.3
    check 'version output has one line' test "$(wc -l < "$scratch/out")" -eq 1
    check 'successful lookup exits 0' test "$status" -eq 0
    check 'successful lookup has no stderr' test -z "$error"
    check 'successful release requires only one curl call' test "$(wc -l < "$CURL_LOG")" -eq 1
done
check 'HTTPS enforced' grep -q -- '--proto =https --proto-redir =https' "$CURL_LOG"
check 'configured user-agent used' grep -Fq -- 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$CURL_LOG"
check 'request has a time limit' grep -q -- '--max-time 30' "$CURL_LOG"

for pair in 'V2.0:2.0' 'n8.1:8.1' 'curl-8_16_0:8_16_0' 'release-1-2-3:1-2-3' \
    'v1:1' 'releases%2Fgcc-16.2.0:16.2.0'; do
    export LATEST_TAG=${pair%:*}
    run https://github.com/owner/repo
    check "numeric tag parsed: $LATEST_TAG" test "$output" = "${pair#*:}"
done

for tag in v2.0.0-rc1 v2.0.0a1 v2.0.0-beta v2.0.0.preview nightly-2026.10 \
    v2.0.0-1 beta%2Fv2.0.0 \
    versionless 'v1.2.3;id' v1.2.3. ''; do
    export LATEST_TAG=$tag
    run https://github.com/owner/repo
    check "unsupported latest tag fails: $tag" test "$status" -eq 1
    check 'unsupported latest tag has no stdout' test -z "$output"
    check 'unsupported latest tag has no fallback' test "$(wc -l < "$CURL_LOG")" -eq 1
done

export LATEST_TAG=v1.2.3
run -- https://github.com/owner/repo
check 'option terminator accepts repository URL' test "$output" = 1.2.3

export LATEST_TAG=v1.2.3 LATEST_EXIT=28
run https://github.com/owner/repo
check 'transport failure exits 1' test "$status" -eq 1
check 'transport failure has no stdout' test -z "$output"
check 'transport failure does not fall back' test "$(wc -l < "$CURL_LOG")" -eq 1
export LATEST_EXIT=0
for code in 403 429 500 503; do
    export LATEST_STATUS=$code
    run https://github.com/owner/repo
    check "HTTP $code fails" test "$status" -eq 1
    check "HTTP $code does not fall back" test "$(wc -l < "$CURL_LOG")" -eq 1
done

export LATEST_STATUS=404
cat > "$TAGS_FILE" <<'HTML'
<a href="/owner/repo/releases/tag/v1.9.0">old</a>
<a href="/owner/repo/releases/tag/v1.10.0">new</a>
<a href="/owner/repo/releases/tag/v2.0.0rc1">preview</a>
<a href="/owner/repo/releases/tag/v9.0.0-beta">preview</a>
<a href="/other/repo/releases/tag/v99.0.0">unrelated</a>
<a href="https://evil.example/owner/repo/releases/tag/v98.0.0">foreign</a>
<a href="/owner/repo/releases/tag/nightly-2026.10">nightly</a>
HTML
run https://github.com/owner/repo
check 'no latest release falls back to numeric stable-looking tags' test "$output" = 1.10.0
check 'fallback succeeds' test "$status" -eq 0
check 'fallback makes two curl calls' test "$(wc -l < "$CURL_LOG")" -eq 2
cat > "$TAGS_FILE" <<'HTML'
<a href="/FFmpeg/FFmpeg/releases/tag/n8.1.3">maintenance</a>
<a href="/FFmpeg/FFmpeg/releases/tag/n9.0.2">stable</a>
<a href="https://github.com/FFmpeg/FFmpeg/releases/tag/n9.1-dev">preview</a>
<a href="/other/FFmpeg/releases/tag/n99.0">unrelated</a>
<a href="https://evil.example/FFmpeg/FFmpeg/releases/tag/n98.0">foreign</a>
HTML
run https://github.com/ffmpeg/ffmpeg
check 'FFmpeg canonical casing returns the stable version' test "$output" = 9.0.2
check 'FFmpeg canonical casing succeeds' test "$status" -eq 0
check 'FFmpeg lookup makes only two requests' test "$(wc -l < "$CURL_LOG")" -eq 2
printf '<a href="https://github.com/OWNER/Repo/releases/tag/V3.2.1">stable</a>\n' > "$TAGS_FILE"
run https://github.com/owner/repo
check 'absolute tag links accept canonical repository casing' test "$output" = 3.2.1
export LATEST_URL=https://github.com/renamed/project/releases/latest
printf '<a href="/renamed/project/releases/tag/v4.0">renamed</a>\n' > "$TAGS_FILE"
run https://github.com/owner/repo
check 'renamed repository without releases uses canonical tags' test "$output" = 4.0
printf '<a href="/owner/repo/releases/tag/v1.10.0">stable</a>\n' > "$TAGS_FILE"
export LATEST_STATUS=200 LATEST_URL=https://github.com/owner/repo/releases
run https://github.com/owner/repo
check 'releases-list redirect falls back to tags' test "$output" = 1.10.0
export LATEST_URL=https://github.com/renamed/project/releases/tag/v3.1
run https://github.com/owner/repo
check 'renamed repository latest release is accepted' test "$output" = 3.1
export LATEST_URL=https://evil.example/owner/repo/releases/tag/v3.1
run https://github.com/owner/repo
check 'unexpected final host fails' test "$status" -eq 1

export LATEST_URL='' LATEST_STATUS=404 TAGS_EXIT=22
run https://github.com/owner/repo
check 'tags HTTP failure exits 1' test "$status" -eq 1
check 'tags HTTP failure has no stdout' test -z "$output"
export TAGS_EXIT=0
: > "$TAGS_FILE"
run https://github.com/owner/repo
check 'empty tags fail' test "$status" -eq 1
check 'empty tags have no stdout' test -z "$output"
check 'empty tags report an error' test -n "$error"
printf '<a href="/owner/repo/releases/tag/v3.0.0a1">preview</a>\n' > "$TAGS_FILE"
run https://github.com/owner/repo
check 'only prerelease tags fail' test "$status" -eq 1

printf '<a href="/owner/repo/releases/tag/v1.2.3">stable</a>\n' > "$TAGS_FILE"
export SORT_EXIT=2
run https://github.com/owner/repo
check 'sort failure exits 1' test "$status" -eq 1
check 'sort failure has no stdout' test -z "$output"
check 'sort failure reports an error' test -n "$error"
export SORT_EXIT=0
mkdir "$scratch/no-curl"
export SCRIPT_PATH="$scratch/no-curl"
run https://github.com/owner/repo
check 'missing dependency exits 1' test "$status" -eq 1
check 'missing dependency has no stdout' test -z "$output"
check 'missing dependency names the command' test "${error#*curl}" != "$error"
check 'missing dependency makes no network requests' test ! -s "$CURL_LOG"
unset SCRIPT_PATH

script="$repo_root/Bash/misc/git-repo-test.sh"
export HELPER_EXIT=0 HELPER_EMPTY=0 HELPER_CANARY="$scratch/partial-helper-ran"
cat > "$scratch/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
if [[ $HELPER_EXIT != 0 ]]; then
    printf 'touch "$HELPER_CANARY"\n'
    printf 'curl: simulated failed helper download\n' >&2
    exit "$HELPER_EXIT"
fi
[[ $HELPER_EMPTY == 0 ]] || exit 0
printf 'printf "%%s\\n" "$1"\n'
CURL
run
check 'caller succeeds with downloaded helper' test "$status" -eq 0
check 'caller downloads the helper once' test "$(wc -l < "$CURL_LOG")" -eq 1
check 'caller uses the current lowercase helper URL' grep -Fq -- 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/misc/source-git-repo-version.sh' "$CURL_LOG"
check 'caller uses the required user-agent' grep -Fq -- 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$CURL_LOG"
check 'caller bounds the helper download' grep -Fq -- '--max-time 30' "$CURL_LOG"
check 'caller retains first lookup' test "${output#*ansible: https://github.com/ansible/ansible.git}" != "$output"
check 'caller retains final lookup' test "${output#*zookeeper: https://github.com/apache/zookeeper.git}" != "$output"
export HELPER_EXIT=22
run
check 'caller fails when helper download fails' test "$status" -ne 0
check 'caller prints no lookup results after failed download' test -z "$output"
check 'caller never executes a partial failed helper download' test ! -e "$HELPER_CANARY"
export HELPER_EXIT=0 HELPER_EMPTY=1
run
check 'caller rejects an empty successful helper download' test "$status" -eq 1
check 'caller prints no lookup results for an empty helper' test -z "$output"
check 'caller explains the empty helper failure' test "${error#*empty}" != "$error"

printf 'PASS: %s source-git-repo-version checks\n' "$checks"
