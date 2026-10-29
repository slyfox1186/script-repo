#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo/Bash/misc/functions/big_files.sh"
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
mkdir "$sandbox/data" "$sandbox/bin"
cd -- "$sandbox/data"
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
    bash "$script" "$@" > "$sandbox/out" 2> "$sandbox/err" || status=$?
}

run
check test "$status" -eq 0
check grep -Fx 'Largest Folders:' "$sandbox/out"
check grep -Fx 'Largest Files:' "$sandbox/out"
check test ! -s "$sandbox/err"

for invalid in 0 -1 1.5 text ''; do
    run "$invalid"
    check test "$status" -eq 1
    check test -s "$sandbox/err"
done
run 1 2
check test "$status" -eq 1

filename=$'file\twith\na newline and spaces'
printf '%s\n' payload > "$filename"
run 1
check test "$status" -eq 0
check test ! -s "$sandbox/err"
check grep -F -- "$sandbox/data/file" "$sandbox/out"
check grep -F -- 'a newline and spaces' "$sandbox/out"

dd if=/dev/zero of=largest.bin bs=1024 count=64 status=none
dd if=/dev/zero of=middle.bin bs=1024 count=32 status=none
run 2
check test "$status" -eq 0
sed -n '/^Largest Files:$/,$p' "$sandbox/out" > "$sandbox/files"
check test "$(wc -l < "$sandbox/files")" -eq 3
check grep -F -- "$sandbox/data/largest.bin" "$sandbox/files"
check grep -F -- "$sandbox/data/middle.bin" "$sandbox/files"
check test "$(sed -n '2s/ .*//p' "$sandbox/files")" = "$sandbox/data/largest.bin"

ln -s -- "$sandbox/data" "$sandbox/link"
cd -- "$sandbox/link"
run 1
check test "$status" -eq 0
check grep -F -- "$sandbox/data/largest.bin" "$sandbox/out"
cd -- "$sandbox/data"

folders=()
for ((i = 0; i < 2048; i++)); do
    folders+=("folder-$i-with-a-name-long-enough-to-fill-the-sort-output-pipe")
done
mkdir -- "${folders[@]}"
run 1
check test "$status" -eq 0
check grep -Fx 'Largest Files:' "$sandbox/out"
check test ! -s "$sandbox/err"

for tool in du find sort; do
    cat > "$sandbox/bin/$tool" <<'MOCK'
#!/usr/bin/env bash
printf 'simulated scan failure\n' >&2
exit 2
MOCK
    chmod +x "$sandbox/bin/$tool"
    status=0
    PATH="$sandbox/bin:$PATH" bash "$script" 1 > "$sandbox/out" 2> "$sandbox/err" || status=$?
    check test "$status" -ne 0
    check grep -F 'simulated scan failure' "$sandbox/err"
    rm -- "$sandbox/bin/$tool"
done

# Fail only the file-size scan, after the folder scan has succeeded.
du_path=$(command -v du)
cat > "$sandbox/bin/du" <<MOCK
#!/usr/bin/env bash
for argument in "\$@"; do
    if [[ \$argument == --files0-from=- ]]; then
        printf 'simulated file-size failure\n' >&2
        exit 2
    fi
done
exec "$du_path" "\$@"
MOCK
chmod +x "$sandbox/bin/du"
status=0
PATH="$sandbox/bin:$PATH" bash "$script" 1 > "$sandbox/out" 2> "$sandbox/err" || status=$?
check test "$status" -ne 0
check grep -F 'simulated file-size failure' "$sandbox/err"

printf '%s checks, %s failures\n' "$checks" "$failures"
((failures == 0))
