#!/usr/bin/env bash

# CREATE GLOBAL FUNCTIONS

# cd wrapper: record every directory change on the stack (pushd) so that
# `cd..` (popd) walks back to the previous folder you were in.
cd() {
    case "${1-}" in
        "") builtin pushd "$HOME" > /dev/null || return ;;    # bare `cd` -> home
        -) builtin pushd "$OLDPWD" > /dev/null || return ;;   # `cd -` -> previous dir
        *) builtin pushd "$@" > /dev/null || return ;;        # normal `cd <dir>`
    esac
}
