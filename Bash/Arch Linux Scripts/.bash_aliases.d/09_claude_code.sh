#!/usr/bin/env bash
alias ct='tree -C \
  -I "node_modules|dist|netlify|*functions/functions*" \
  -P "*.ts"   -P "*.tsx" \
  -P "*.js"   -P "*.json" \
  -P "*.toml" -P "*.sh"  \
  -P "*.sql"  -P "*.scss"'

alias cmcp="clear; bash /home/jman/tmp/claude_mcp_server_commands.sh"
alias cop='clear; bash /home/jman/tmp/claude_mcp_server_openrouter.sh'
alias cor="bash /home/jman/tmp/claude_mcp_server_openrouter.sh"

alias get_tree='clear; tree -P "*.tsx" -P "*.ts" -P "*.css" -P "*.scss" -P "*.toml" -P "*.sql" -P "*.json" -P "*.sh" -P "*.py" -I "node_modules" -I "dist" -I ".git" .'
alias gt='get_tree'

alias sg='clear; gemini --model gemini-2.5-pro-preview-06-05'

alias stg='clear; /home/jman/.nvm/versions/node/v20.19.1/bin/node /home/jman/tmp/gemini-cli/gemini.js --model gemini-2.5-pro-preview-06-05'

alias ccc='clear; claude --allow-dangerously-skip-permissions --model claude-opus-4-6 /clear'
alias rpr='clear; python3 run.py restart'
