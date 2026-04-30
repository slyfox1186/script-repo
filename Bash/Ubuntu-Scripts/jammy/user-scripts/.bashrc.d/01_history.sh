#!/bin/bash
# History configuration

# ====================
# HISTORY SETTINGS
# ====================
HISTCONTROL="ignoreboth:erasedups"  # Don't save duplicate commands or commands starting with space
HISTSIZE=100000                      # Increased history size in memory
HISTFILESIZE=200000                  # Increased history file size
HISTTIMEFORMAT="%F %T "             # Add timestamp to history
HISTIGNORE="ls:ll:cd:cd -:pwd:exit:date:* --help:clear:c:cls:history"  # Commands to not record in history

# Append to history instead of overwriting
shopt -s histappend
# Record each line of multiline commands
shopt -s cmdhist 
# Save multi-line commands as one command
shopt -s lithist

# Export history variables
export HISTCONTROL HISTSIZE HISTFILESIZE HISTTIMEFORMAT HISTIGNORE