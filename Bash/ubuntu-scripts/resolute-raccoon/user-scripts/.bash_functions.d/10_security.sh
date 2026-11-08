#!/usr/bin/env bash
# SSH Key and Permission Functions

## SSH-KEYGEN ##

# Create a new SSH key pair in ~/.ssh. ssh-keygen asks for the passphrase itself, so it is
# never echoed to the screen or visible in the process list.
new_key() {
    local bits comment key_path name type
    local -a keygen_args

    read -r -p "Key type [ed25519 (default) | rsa]: " type || return 1
    type=${type:-ed25519}
    case "$type" in
        ed25519)
            keygen_args=(-t ed25519)
            ;;
        rsa)
            read -r -p "RSA key size [3072 | 4096 (default)]: " bits || return 1
            bits=${bits:-4096}
            if [[ "$bits" != 3072 && "$bits" != 4096 ]]; then
                printf 'Unsupported RSA key size: %s\n' "$bits" >&2
                return 1
            fi
            keygen_args=(-t rsa -b "$bits")
            ;;
        *)
            printf 'Unsupported key type: %s\n' "$type" >&2
            return 1
            ;;
    esac

    read -r -p "Comment (default: $USER@$HOSTNAME): " comment || return 1
    comment=${comment:-$USER@$HOSTNAME}
    read -r -p "Key file name inside ~/.ssh (default: id_$type): " name || return 1
    name=${name:-id_$type}
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
        printf 'The key name may contain only letters, digits, ".", "_" and "-": %s\n' "$name" >&2
        return 1
    fi
    key_path="$HOME/.ssh/$name"
    if [[ -e "$key_path" || -e "$key_path.pub" ]]; then
        printf 'A key named %s already exists; choose another name.\n' "$key_path" >&2
        return 1
    fi

    install -d -m 700 -- "$HOME/.ssh" || return
    ssh-keygen "${keygen_args[@]}" -C "$comment" -f "$key_path" || return
    printf '\nPrivate key: %s\nPublic key:  %s.pub\n\n' "$key_path" "$key_path"
    cat -- "$key_path.pub"
}

# Usage: keytopub [PRIVATE_KEY [PUBLIC_KEY]]
# Writes the public half of PRIVATE_KEY to PUBLIC_KEY (default: PRIVATE_KEY.pub), then offers to
# add it to ~/.ssh/authorized_keys. Existing authorized keys are always kept.
keytopub() {
    local answer authorized="$HOME/.ssh/authorized_keys" okey="${1-}" opub="${2-}" pub_line

    if [[ -z "$okey" ]]; then
        read -r -p "Private key: " okey || return 1
        read -r -p "Public key (blank for PRIVATE_KEY.pub): " opub || return 1
        echo
    fi
    if [[ ! -f "$okey" ]]; then
        printf 'Private key not found: %s\n' "$okey" >&2
        return 1
    fi
    opub=${opub:-$okey.pub}

    # ssh-keygen refuses to read a private key that other users can access.
    chmod 600 -- "$okey" || return
    pub_line=$(ssh-keygen -y -f "$okey") || return
    if [[ -f "$opub" ]] && [[ $(cut -d' ' -f1,2 < "$opub") != "$(cut -d' ' -f1,2 <<< "$pub_line")" ]]; then
        printf '%s holds a different key; leaving it unchanged.\n' "$opub" >&2
        return 1
    fi
    if [[ ! -f "$opub" ]]; then
        printf '%s\n' "$pub_line" > "$opub" && chmod 644 -- "$opub" || return
        printf 'Wrote %s\n' "$opub"
    fi

    read -r -p "Allow this key to log in to $USER on this machine? [y/N] " answer || return 1
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || return 0
    install -d -m 700 -- "$HOME/.ssh" || return
    if [[ -f "$authorized" ]] && grep -qF -- "$(cut -d' ' -f1,2 <<< "$pub_line")" "$authorized"; then
        printf 'The key is already in %s\n' "$authorized"
        return 0
    fi
    if [[ -s "$authorized" && -n $(tail -c 1 -- "$authorized") ]]; then
        printf '\n' >> "$authorized" || return
    fi
    printf '%s\n' "$pub_line" >> "$authorized" && chmod 600 -- "$authorized" || return
    printf 'Added the key to %s\n' "$authorized"
}

## FIX USER FOLDER PERMISSIONS up = user permissions
# Public keys stay readable; every other file in ~/.ssh and ~/.gnupg becomes private to you.
fix_up() {
    local file status=0

    if [[ -d "$HOME/.gnupg" ]]; then
        find "$HOME/.gnupg" -type d -exec chmod 700 {} + || status=1
        find "$HOME/.gnupg" -type f -exec chmod 600 {} + || status=1
    fi
    if [[ -d "$HOME/.ssh" ]]; then
        chmod 700 -- "$HOME/.ssh" || status=1
        for file in "$HOME"/.ssh/*; do
            [[ -f "$file" && ! -L "$file" ]] || continue
            case "$file" in
                *.pub) chmod 644 -- "$file" || status=1 ;;
                *) chmod 600 -- "$file" || status=1 ;;
            esac
        done
    fi
    return "$status"
}
