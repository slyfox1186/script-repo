#!/usr/bin/env bash
pyenv() {
    # Wrapper to warn if trying to use pyenv while conda is active
    if [[ -n "${CONDA_PREFIX-}" ]] && [[ "${1-}" == "shell" || "${1-}" == "local" || "${1-}" == "global" ]]; then
        echo "Warning: conda environment is active (${CONDA_DEFAULT_ENV-unknown}). Deactivate conda first or use 'conda run'."
    fi
    command pyenv "$@"
}
