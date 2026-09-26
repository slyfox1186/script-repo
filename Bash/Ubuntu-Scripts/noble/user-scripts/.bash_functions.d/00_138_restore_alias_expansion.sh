#!/usr/bin/env bash
# Initialized by 00_000_setup.sh before the function modules are sourced.
# shellcheck disable=SC2154
if [[ $__bash_functions_restore_alias_expansion == true ]]; then
    shopt -s expand_aliases
fi
unset __bash_functions_restore_alias_expansion
