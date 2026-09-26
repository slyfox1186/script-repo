#!/usr/bin/env bash
# This file is sourced after .bash_aliases. Disable alias expansion while Bash
# parses function bodies so aliases such as `ls`, `mkdir`, and `chmod` are not
# captured inside them with duplicated options or unintended privileges.
__bash_functions_restore_alias_expansion=false
if shopt -q expand_aliases; then
    __bash_functions_restore_alias_expansion=true
    shopt -u expand_aliases
fi

# EXPORT ANSI COLORS
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
export BLUE CYAN GREEN RED YELLOW NC
