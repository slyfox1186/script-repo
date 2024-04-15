#!/usr/bin/env bash

# Execute like this: ./script.sh

configs=(asm.nanorc autoconf.nanorc awk.nanorc c.nanorc changelog.nanorc cmake.nanorc css.nanorc default.nanorc elisp.nanorc email.nanorc go.nanorc groff.nanorc guile.nanorc html.nanorc java.nanorc javascript.nanorc json.nanorc lua.nanorc makefile.nanorc man.nanorc markdown.nanorc nanohelp.nanorc nanorc.nanorc nftables.nanorc objc.nanorc ocaml.nanorc patch.nanorc perl.nanorc php.nanorc po.nanorc python.nanorc ruby.nanorc rust.nanorc sh.nanorc sql.nanorc tcl.nanorc tex.nanorc texinfo.nanorc xml.nanorc yaml.nanorc)

[[ ! -f "$HOME/.nanorc" ]] && touch "$HOME/.nanorc"
for config in ${configs[@]}; do
    echo "include /usr/share/nano/$config" >> "$HOME/.nanorc"
done
