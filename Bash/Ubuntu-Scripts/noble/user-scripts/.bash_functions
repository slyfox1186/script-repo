# Compatibility entry point: functions and shared setup live in .bash_functions.d.
# Numeric prefixes preserve the original definition and initialization order.
if [[ -d "$HOME/.bash_functions.d" ]]; then
    for script in "$HOME/.bash_functions.d"/*.sh; do
        if [[ -f "$script" ]]; then
            # shellcheck source=/dev/null
            source "$script"
        fi
    done
fi
