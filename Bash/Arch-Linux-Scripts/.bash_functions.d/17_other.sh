#!/usr/bin/env bash

run_cursor() {
    nohup /home/jman/tmp/Cursor-0.46.11-ae.AppImage >/dev/null 2>&1 &
    disown
    exit
}

run_linter() {
    clear
    npx eslint "client/src/**/*.{ts,tsx}" --format json
}


# Add this to ~/.bashrc or ~/.bash_aliases, then run `source ~/.bashrc`
gettime() {
  # Color setup
  local RED=$(tput setaf 1) GREEN=$(tput setaf 2) YELLOW=$(tput setaf 3)
  local CYAN=$(tput setaf 6) RESET=$(tput sgr0)

  # Time & date
  local local_time=$(date +"%H:%M:%S")
  local date_full=$(date +"%A, %d %B %Y")
  local utc_time=$(date -u +"%H:%M:%S")
  local epoch=$(date +%s)

  # Day-of-year and ISO week
  local day_year=$(date +"%j")
  local week_num=$(date +"%V")

  # Timezone detection
  if command -v timedatectl &>/dev/null; then
    local tz_name=$(timedatectl show -p Timezone --value)
  else
    local tz_name=$(date +"%Z")
  fi
  local tz_offset=$(date +"%:::z")

  # Uptime
  local up=$(uptime -p | sed 's/up //')

  # Output
  echo -e "${GREEN}🕒 ${CYAN}Local Time:${RESET}    ${local_time}"
  echo -e "${GREEN}📅 ${CYAN}Date:${RESET}          ${date_full}"
  echo -e "${GREEN}🌐 ${CYAN}Timezone:${RESET}      ${tz_name} (UTC${tz_offset})"
  echo -e "${GREEN}⏱️  ${CYAN}UTC Time:${RESET}      ${utc_time}"
  echo -e "${GREEN}� epoch:${RESET}        ${epoch}"
  echo -e "${GREEN}🔢 ${CYAN}Day of Year:${RESET}   ${day_year}"
  echo -e "${GREEN}📆 ${CYAN}ISO Week #:${RESET}    ${week_num}"
  echo -e "${GREEN}⏳ ${CYAN}Uptime:${RESET}        ${up}"
}

# Optional shortcut:
alias ti='timeinfo'

