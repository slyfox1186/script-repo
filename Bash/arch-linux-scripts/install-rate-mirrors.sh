#!/usr/bin/env bash

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this without root or sudo."
    exit
fi

# Install required package paccache through the pacman-contrib package
sudo pacman -Sy --needed --noconfirm pacman-contrib

# Enable alias expansion in the script
shopt -s expand_aliases

# Define aliases
alias ua-drop-caches='sudo paccache -rk3; yay -Sc --aur --noconfirm'
alias ua-update-all='export TMPFILE="$(mktemp)"; sudo true; \
rate-mirrors --save=$TMPFILE arch --max-delay=21600 && \
sudo mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist-backup && \
sudo mv $TMPFILE /etc/pacman.d/mirrorlist && ua-drop-caches && \
yay -Syyu --noconfirm'

update_now() {
    echo "Updating the mirror list now..."
    if ua-update-all; then
        printf "\n%s\n\n" "Update successful!"
    else
        printf "\n%s\n\n" "Update failed!"
    fi
}

# Function to append aliases to .bashrc
append_aliases_to_bashrc() {
    {
        echo
        cat <<'EOF'
alias ua-drop-caches='sudo paccache -rk3; yay -Sc --aur --noconfirm'
alias ua-update-all='export TMPFILE="$(mktemp)"; sudo true; \
rate-mirrors --save=$TMPFILE arch --max-delay=21600 && \
sudo mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist-backup && \
sudo mv $TMPFILE /etc/pacman.d/mirrorlist && ua-drop-caches && \
yay -Syyu --noconfirm'
EOF
    } >> "${HOME}/.bashrc"
    echo "Aliases added to your .bashrc file."
}

echo
read -p "To link static choose yes else choose no (y/n): " choice_install
echo
case "$choice_install" in
    [yY]) yay -S rate-mirrors-bin ;;
    [nN]) yay -S rate-mirrors ;;
esac

echo
read -p "Do you want to update the mirror list now? (recommended on first use): " choice_run
case "$choice_run" in
    [yY]) update_now ;;
    [nN]) ;;
esac

# Append the aliases to the user's ~/.bashrc file
append_aliases_to_bashrc

echo
echo "Script completed."
