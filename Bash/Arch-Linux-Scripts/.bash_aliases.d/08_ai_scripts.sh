#!/usr/bin/env bash

alias rb='clear; bash run.sh --build'
alias rcb='clear; bash run.sh'
alias rflush='clear; redis-cli flushall'
alias long_files='clear; find . -type d -name node_modules -prune -o -type f \( -name "*.ts" -o -name "*.tsx" \) -exec wc -l {} + | sort -n'
alias startmon='clear; ./monitor.sh -a -d .'
alias ccm='clear; python3 /home/jman/tmp/clear_cuda_memory.py'

alias rl1='clear; npx tsc --noEmit --project tsconfig.json'
alias rl2='clear; npx eslint "../**/*.{ts,tsx}" --max-warnings=9999 -f unix | grep "is defined but never used"'
