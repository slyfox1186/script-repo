# Prints each reminder in ~/.config/reminders.tsv at shell startup once its warning window opens.
# Line format: YYYY-MM-DD<TAB>days of warning<TAB>message. Delete a line once it's handled.
# REMINDERS_FILE overrides the path (used for testing).
_reminders_show() {
    local file="${REMINDERS_FILE:-$HOME/.config/reminders.tsv}" due lead msg due_s now_s days
    [[ -r $file ]] || return 0
    now_s=$(date -d 'today 00:00' +%s)
    while IFS=$'\t' read -r due lead msg; do
        [[ -z $due || $due == \#* ]] && continue
        if ! [[ $lead =~ ^[0-9]+$ ]] || ! due_s=$(date -d "$due" +%s 2>/dev/null); then
            printf '\e[1;31m%s: malformed line:\e[0m %s\n' "$file" "$due"
            continue
        fi
        days=$(( (due_s - now_s) / 86400 ))
        if (( days < 0 )); then
            printf '\e[1;31mOVERDUE since %s:\e[0m %s\n' "$due" "$msg"
        elif (( days <= lead )); then
            printf '\e[1;33mDue %s (%d days):\e[0m %s\n' "$due" "$days" "$msg"
        fi
    done < "$file"
}
_reminders_show
unset -f _reminders_show
