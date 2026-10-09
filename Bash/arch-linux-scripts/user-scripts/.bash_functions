# shellcheck shell=bash
# Sources the category files in .bash_functions.d. This file is sourced after .bash_aliases,
# so alias expansion is disabled while Bash parses the function bodies; otherwise aliases such
# as `ls`, `cat`, and `chmod` are captured inside them with duplicated options or sudo.
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

if [[ -d "$HOME/.bash_functions.d" ]]; then
    for script in "$HOME/.bash_functions.d"/*.sh; do
        if [[ -f "$script" ]]; then
            # shellcheck source=/dev/null
            source "$script"
        fi
    done
    unset script
fi

if [[ $__bash_functions_restore_alias_expansion == true ]]; then
    shopt -s expand_aliases
fi
unset __bash_functions_restore_alias_expansion
