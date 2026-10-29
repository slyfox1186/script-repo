#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo/Bash/misc/file-editing/find-matching-strings.sh"
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
mkdir "$sandbox/bin" "$sandbox/data"
cd -- "$sandbox/data"
printf '%s\n' 'alpha [literal]' '-n' 'back\slash' '  padded query  ' > source.txt
printf '%s\n' 'alpha [literal]' 'missing' '-n' 'back\slash' '  padded query  ' > queries.txt
printf '%s\n' 'Strings found:' '==================' 'alpha [literal]' '-n' \
    'back\slash' '  padded query  ' '' 'Strings not found:' '==================' \
    'missing' > "$sandbox/expected"
checks=0
failures=0

check() {
    checks=$((checks + 1))
    if ! "$@"; then
        printf 'FAIL: %s\n' "$*" >&2
        failures=$((failures + 1))
    fi
}

run() {
    status=0
    timeout 3 bash "$script" "$@" > "$sandbox/out" 2> "$sandbox/err" || status=$?
}

run source.txt queries.txt
check test "$status" -eq 0
check grep -Fx -- 'alpha [literal]' "$sandbox/out"
check grep -Fx -- '-n' "$sandbox/out"
check grep -Fx -- 'back\slash' "$sandbox/out"
check grep -Fx -- 'missing' "$sandbox/out"
check cmp -s "$sandbox/expected" "$sandbox/out"

for option in -o --output-file; do
    run "$option" 'report with spaces.txt' source.txt queries.txt
    check test "$status" -eq 0
    check test -s 'report with spaces.txt'
    check cmp -s "$sandbox/expected" 'report with spaces.txt'

    run source.txt "$option" 'report with spaces.txt' queries.txt
    check test "$status" -eq 0

    run source.txt queries.txt "$option" 'report with spaces.txt' unexpected
    check test "$status" -eq 1

    run source.txt queries.txt "$option" 'report with spaces.txt' --help
    check test "$status" -eq 0
    check grep -q 'Usage:' "$sandbox/out"

    run source.txt queries.txt "$option"
    check test "$status" -eq 1
    check test -s "$sandbox/err"

    run source.txt queries.txt "$option" ''
    check test "$status" -eq 1
done

for arguments in '' '--unknown'; do
    run "$arguments"
    check test "$status" -eq 1
done
run absent.txt queries.txt
check test "$status" -eq 2

for option in -h --help; do
    run "$option"
    check test "$status" -eq 0
    check test ! -s "$sandbox/err"
done

printf '%s' 'missing final line' > queries.txt
run source.txt queries.txt
check test "$status" -eq 0
check grep -Fx -- 'missing final line' "$sandbox/out"

printf '%s' 'alpha' > queries.txt
run source.txt queries.txt
check test "$status" -eq 0
check grep -Fx -- 'alpha' "$sandbox/out"

: > queries.txt
run source.txt queries.txt
check test "$status" -eq 0
check test ! -s "$sandbox/err"

printf '%s\n' 'alpha' > queries.txt
run source.txt queries.txt -o absent/report.txt
check test "$status" -ne 0
check test ! -s "$sandbox/out"

if [[ -c /dev/full ]]; then
    run source.txt queries.txt -o /dev/full
    check test "$status" -ne 0
    check test ! -s "$sandbox/out"
fi

cat > "$sandbox/bin/grep" <<'MOCK'
#!/usr/bin/env bash
printf 'simulated read failure\n' >&2
exit 2
MOCK
chmod +x "$sandbox/bin/grep"
status=0
PATH="$sandbox/bin:$PATH" timeout 3 bash "$script" source.txt queries.txt \
    > "$sandbox/out" 2> "$sandbox/err" || status=$?
check test "$status" -eq 2
check test ! -s "$sandbox/out"

cp -- source.txt ./-source.txt
cp -- source.txt ./-
for source in -source.txt -; do
    run -- "$source" queries.txt
    check test "$status" -eq 0
    check grep -Fx -- 'alpha' "$sandbox/out"
done

printf '%s checks, %s failures\n' "$checks" "$failures"
((failures == 0))
