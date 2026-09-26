# shellcheck shell=bash

# Expand common Conda, Git, and Pip shortcuts at the start of a command line.
_command_shortcut_completion() {
    case "${COMP_WORDS[0]}" in
        ca)    COMPREPLY=('conda activate ') ;;
        ci)    COMPREPLY=('conda install ') ;;
        cel)   COMPREPLY=('conda env list ') ;;
        cc)    COMPREPLY=('conda create --name ') ;;
        crm)   COMPREPLY=('conda env remove --name ') ;;
        cr)    COMPREPLY=('conda run --name ') ;;
        cu)    COMPREPLY=('conda update ') ;;
        gad)   COMPREPLY=('git add ') ;;
        gc)    COMPREPLY=('git clone ') ;;
        gcm)   COMPREPLY=('git commit --message ') ;;
        gp)    COMPREPLY=('git pull ') ;;
        gps)   COMPREPLY=('git push ') ;;
        gst)   COMPREPLY=('git status --short --branch ') ;;
        pipc)  COMPREPLY=('pip check ') ;;
        pipf)  COMPREPLY=('pip freeze ') ;;
        pipi)  COMPREPLY=('pip install ') ;;
        plist) COMPREPLY=('pip list ') ;;
        preq)  COMPREPLY=('pip install --requirement ') ;;
        pshow) COMPREPLY=('pip show ') ;;
        pipun) COMPREPLY=('pip uninstall ') ;;
        pipiu) COMPREPLY=('pip install --upgrade ') ;;
        *)     COMPREPLY=(); return 0 ;;
    esac

    compopt -o noquote -o nospace
}

# Keep Bash's normal command and filename completion as the fallback.
complete -o bashdefault -o default -F _command_shortcut_completion -I
