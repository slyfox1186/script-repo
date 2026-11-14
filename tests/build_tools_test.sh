#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo/Bash/installer-scripts/github-projects/build-tools.sh"
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
checks=0
failures=0

check() {
    checks=$((checks + 1))
    if ! "$@"; then
        printf 'FAIL: %s\n' "$*" >&2
        failures=$((failures + 1))
    fi
}

# Sourcing must define the functions without running the installer
# shellcheck source=SCRIPTDIR/../Bash/installer-scripts/github-projects/build-tools.sh
NO_COLOR=1 source "$script"
trap - ERR
set +E
trap 'rm -rf -- "$sandbox"' EXIT
check test "$(type -t remove_entries)" = function

# remove_entries removes empty folders inside the prefix and stops at it,
# even when the folders above the prefix are empty too
install_dir="$sandbox/opt/tools"
mkdir -p "$install_dir/share/doc/ninja" "$install_dir/bin" "$install_dir/lib/build-tools/meson-1.0.abc/bin"
touch "$install_dir/share/doc/ninja/COPYING" "$install_dir/bin/ninja" "$install_dir/lib/build-tools/meson-1.0.abc/bin/meson"
remove_entries "$install_dir/share/doc/ninja/COPYING" "$install_dir/bin/ninja" "$install_dir/lib/build-tools/meson-1.0.abc/" 2>"$sandbox/err"
check test ! -e "$install_dir/share"
check test ! -e "$install_dir/bin"
check test ! -e "$install_dir/lib"
check test -d "$install_dir"
check test -d "$sandbox/opt"
check test ! -s "$sandbox/err"

# A non-empty folder and entries outside the prefix are left alone
mkdir -p "$install_dir/bin" "$sandbox/outside"
touch "$install_dir/bin/ninja" "$install_dir/bin/other" "$sandbox/outside/keep"
remove_entries "$install_dir/bin/ninja" "$install_dir/../../outside/keep" "$sandbox/outside/keep" 2>"$sandbox/err"
check test ! -e "$install_dir/bin/ninja"
check test -f "$install_dir/bin/other"
check test -f "$sandbox/outside/keep"
check grep -q 'Ignoring unexpected manifest entry' "$sandbox/err"

# legacy_cleanup reports every file the old pip install of Meson left,
# including under the doubled /usr/local/local prefix, and the folders to clear
legacy_prefix="$sandbox/usr/local"
# shellcheck disable=SC2034  # read by legacy_cleanup through wants
tools="meson"
legacy="$legacy_prefix"
mkdir -p "$legacy/local/bin" "$legacy/local/share/man/man1" "$legacy/share/polkit-1/actions" \
    "$legacy/local/lib/python3.12/dist-packages/mesonbuild" "$legacy/local/lib/python3.12/dist-packages/meson-1.10.1.dist-info" \
    "$legacy/lib/python3.10/dist-packages/meson-1.5.2-py3.10.egg" "$legacy/lib/python3.11/dist-packages" "$legacy/programs/cmake-3.31.0"
touch "$legacy/local/bin/meson" "$legacy/local/share/man/man1/meson.1" "$legacy/share/polkit-1/actions/com.mesonbuild.install.policy"
printf './meson-1.5.2-py3.10.egg\n' >"$legacy/lib/python3.10/dist-packages/easy-install.pth"
printf './meson-1.5.2-py3.11.egg\n./other-1.0.egg\n' >"$legacy/lib/python3.11/dist-packages/easy-install.pth"
legacy_cleanup >"$sandbox/out" 2>&1
for path in "$legacy/programs/cmake-3.31.0" "$legacy/local/bin/meson" "$legacy/local/share/man/man1/meson.1" \
            "$legacy/share/polkit-1/actions/com.mesonbuild.install.policy" \
            "$legacy/local/lib/python3.12/dist-packages/mesonbuild" "$legacy/local/lib/python3.12/dist-packages/meson-1.10.1.dist-info" \
            "$legacy/lib/python3.10/dist-packages/meson-1.5.2-py3.10.egg" "$legacy/lib/python3.10/dist-packages/easy-install.pth"; do
    check grep -qF -- " $path" "$sandbox/out"
done
# That easy-install.pth also lists another package, so it stays
check test "$(grep -c "python3.11" "$sandbox/out")" -eq 0

# Running the printed commands leaves only the folders that still hold files
rm_cmd="$(sed -n 's/^.*sudo rm -rf //p' "$sandbox/out")"
rmdir_cmd="$(sed -n 's/^.*sudo rmdir -p --ignore-fail-on-non-empty //p' "$sandbox/out")"
check test -n "$rm_cmd"
check test -n "$rmdir_cmd"
read -ra rm_paths <<<"$rm_cmd"
read -ra rmdir_paths <<<"$rmdir_cmd"
# Run them only on paths inside the sandbox, whatever the report says
for path in "${rm_paths[@]}" "${rmdir_paths[@]}"; do
    check test "${path#"$legacy"/}" != "$path"
done
for path in "${rm_paths[@]}"; do
    if [[ "$path" == "$legacy"/* ]]; then rm -rf -- "$path"; fi
done
for path in "${rmdir_paths[@]}"; do
    if [[ "$path" == "$legacy"/* ]]; then rmdir -p --ignore-fail-on-non-empty -- "$path"; fi
done
check test ! -e "$legacy/local"
check test ! -e "$legacy/share"
check test ! -e "$legacy/programs"
check test ! -e "$legacy/lib/python3.10"
check test -f "$legacy/lib/python3.11/dist-packages/easy-install.pth"

# Nothing to report on a clean prefix
rm -rf -- "$legacy"
mkdir -p "$legacy/lib/build-tools/meson-1.12.1.abc/lib/python3.14/site-packages/mesonbuild"
legacy_cleanup >"$sandbox/out" 2>&1
check test ! -s "$sandbox/out"

# The script still runs when executed, and when read from a pipe
check bash "$script" --help >/dev/null
# shellcheck disable=SC2016  # $1 belongs to the inner shell
check bash -c 'bash <"$1" -s -- --help >/dev/null' _ "$script"

printf '%d checks, %d failures\n' "$checks" "$failures"
(( failures == 0 ))
