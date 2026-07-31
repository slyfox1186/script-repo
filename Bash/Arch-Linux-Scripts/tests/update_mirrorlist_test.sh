#!/usr/bin/env bash
set -u

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$script_dir/update_mirrorlist.sh"
aliases="$script_dir/.bash_aliases"
failures=0

fail() {
    printf 'not ok - %s\n' "$1" >&2
    failures=$((failures + 1))
}

pass() {
    printf 'ok - %s\n' "$1"
}

assert_contains() {
    local file=$1 expected=$2 description=$3
    if grep -Fq -- "$expected" "$file"; then
        pass "$description"
    else
        fail "$description (missing: $expected)"
    fi
}

assert_fails() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then
        fail "$description"
    else
        pass "$description"
    fi
}

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mock_bin="$test_root/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_SUDO_LOG"
exec "$@"
EOF

cat >"$mock_bin/reflector" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TEST_REFLECTOR_ARGS"
[[ ${TEST_REFLECTOR_MODE:-success} == fail ]] && exit 1
save=
while (($#)); do
    if [[ $1 == --save ]]; then
        save=$2
        break
    fi
    shift
done
{
    printf '# generated test mirrorlist\n'
    case ${TEST_REFLECTOR_MODE:-success} in
        few)
            printf 'Server = https://mirror1.example/archlinux/$repo/os/$arch\n'
            printf 'Server = https://mirror2.example/archlinux/$repo/os/$arch\n'
            ;;
        http)
            printf 'Server = http://mirror1.example/archlinux/$repo/os/$arch\n'
            printf 'Server = https://mirror2.example/archlinux/$repo/os/$arch\n'
            printf 'Server = https://mirror3.example/archlinux/$repo/os/$arch\n'
            ;;
        *)
            for n in {1..10}; do
                printf 'Server = https://mirror%s.example/archlinux/$repo/os/$arch\n' "$n"
            done
            ;;
    esac
} >"$save"
EOF

cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
url=${!#}
case ${TEST_CURL_MODE:-success} in
    fail) exit 22 ;;
    two) [[ $url == *mirror1.example* || $url == *mirror2.example* ]] ;;
    *) exit 0 ;;
esac
EOF

cat >"$mock_bin/install" <<'EOF'
#!/usr/bin/env bash
args=()
for arg in "$@"; do
    case $arg in
        --owner=*|--group=*) ;;
        *) args+=("$arg") ;;
    esac
done
exec /usr/bin/install "${args[@]}"
EOF

chmod +x "$mock_bin"/*
export PATH="$mock_bin:/usr/bin:/bin"
export TEST_REFLECTOR_ARGS="$test_root/reflector.args"
export TEST_SUDO_LOG="$test_root/sudo.log"

destination="$test_root/mirrorlist"
if "$script" --non-interactive --dry-run --save "$destination" >"$test_root/out" 2>"$test_root/err"; then
    pass 'safe default dry run succeeds'
else
    fail 'safe default dry run succeeds'
fi

for expected in '--age 12' '--country United States' '--number 5' '--download-timeout 5' '--latest 20' '--protocol https' '--completion-percent 100' '--ipv4' '--exclude cicku\.me' '--sort rate'; do
    assert_contains "$TEST_REFLECTOR_ARGS" "$expected" "Reflector receives $expected"
done

assert_fails 'missing option value is rejected' "$script" --non-interactive --age
assert_fails 'nonnumeric mirror count is rejected' "$script" --non-interactive --fastest many
assert_fails 'fewer than five mirrors is rejected' "$script" --non-interactive --fastest 4
assert_fails 'plain HTTP is rejected' "$script" --non-interactive --protocols http
assert_fails 'relative destination is rejected' "$script" --non-interactive --save mirrorlist

printf 'original mirrorlist\n' >"$destination"
export TEST_REFLECTOR_MODE=fail
assert_fails 'Reflector failure leaves destination untouched' "$script" --non-interactive --save "$destination"
assert_contains "$destination" 'original mirrorlist' 'destination survives Reflector failure'

export TEST_REFLECTOR_MODE=few
assert_fails 'fewer than five generated servers is rejected' "$script" --non-interactive --save "$destination"
assert_contains "$destination" 'original mirrorlist' 'destination survives insufficient output'

export TEST_REFLECTOR_MODE=http
assert_fails 'generated HTTP server is rejected' "$script" --non-interactive --save "$destination"
assert_contains "$destination" 'original mirrorlist' 'destination survives insecure output'

export TEST_REFLECTOR_MODE=success
export TEST_CURL_MODE=two
assert_fails 'fewer than five successful mirrors is rejected' "$script" --non-interactive --save "$destination"
assert_contains "$destination" 'original mirrorlist' 'destination survives probe failure'

export TEST_CURL_MODE=success
: >"$TEST_SUDO_LOG"
if "$script" --non-interactive --save "$destination" >"$test_root/install.out" 2>"$test_root/install.err"; then
    pass 'validated candidate installs successfully'
else
    sed -n '1,120p' "$test_root/install.err" >&2
    fail 'validated candidate installs successfully'
fi
assert_contains "$destination" 'https://mirror1.example' 'installed list contains ranked HTTPS servers'
assert_contains "$TEST_SUDO_LOG" 'cp --archive' 'existing mirrorlist is backed up'
assert_contains "$TEST_SUDO_LOG" 'install --owner=root --group=root --mode=0644' 'candidate is staged with safe ownership and mode'
if compgen -G "$destination.backup-*" >/dev/null; then
    pass 'timestamped backup exists'
else
    fail 'timestamped backup exists'
fi
if compgen -G "${TMPDIR:-/tmp}/arch-mirrorlist.*" >/dev/null; then
    fail 'candidate temporary file is cleaned up'
else
    pass 'candidate temporary file is cleaned up'
fi

rr_line=$(grep -E '^alias rr=' "$aliases" || true)
if [[ $rr_line == *'update_mirrorlist.sh --non-interactive'* && $rr_line != *'reflector '* ]]; then
    pass 'rr delegates to the maintained mirror script'
else
    fail 'rr delegates to the maintained mirror script'
fi

if ((failures)); then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all tests passed\n'
