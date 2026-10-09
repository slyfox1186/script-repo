#!/usr/bin/env bash
pip() {
    if [[ "${1-}" == "install" && -x "$HOME/.local/bin/pip-aria2" ]]; then
        "$HOME/.local/bin/pip-aria2" "$@"
    else
        command pip "$@"
    fi
}
