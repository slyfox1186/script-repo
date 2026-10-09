#!/usr/bin/env bash

# Execute like this: ./add-colors-to-nano.sh
# Pass --force to re-download extra configs

# Built-in nano configs from /usr/share/nano/
configs=(
    asm.nanorc autoconf.nanorc awk.nanorc c.nanorc changelog.nanorc cmake.nanorc
    css.nanorc default.nanorc elisp.nanorc email.nanorc go.nanorc groff.nanorc
    guile.nanorc html.nanorc java.nanorc javascript.nanorc json.nanorc lua.nanorc
    makefile.nanorc man.nanorc markdown.nanorc nanohelp.nanorc nanorc.nanorc
    nftables.nanorc objc.nanorc ocaml.nanorc patch.nanorc perl.nanorc php.nanorc
    po.nanorc python.nanorc ruby.nanorc rust.nanorc sh.nanorc sql.nanorc tcl.nanorc
    tex.nanorc texinfo.nanorc xml.nanorc yaml.nanorc
)

# Extra nanorc sources: "base_url filename1 filename2 ..."
extra_sources=(
    "https://raw.githubusercontent.com/galenguyer/nano-syntax-highlighting/master
        Brewfile.nanorc Dockerfile.nanorc Rnw.nanorc apacheconf.nanorc arduino.nanorc
        asciidoc.nanorc asm.nanorc awk.nanorc batch.nanorc beancount.nanorc
        brainfuck.nanorc c.nanorc clojure.nanorc cmake.nanorc coffeescript.nanorc
        colortest.nanorc conf.nanorc conky.nanorc creole.nanorc csh.nanorc
        csharp.nanorc css.nanorc csv.nanorc cython.nanorc d.nanorc dot.nanorc
        dotenv.nanorc elixir.nanorc email.nanorc erb.nanorc etc-hosts.nanorc
        expect.nanorc fish.nanorc fortran.nanorc fsharp.nanorc gemini.nanorc
        genie.nanorc gentoo.nanorc git.nanorc gitcommit.nanorc glsl.nanorc
        go.nanorc godot.nanorc gophermap.nanorc gradle.nanorc groff.nanorc
        haml.nanorc haskell.nanorc hcl.nanorc html.j2.nanorc html.nanorc
        i3.nanorc ical.nanorc ini.nanorc inputrc.nanorc jade.nanorc java.nanorc
        jrnl.nanorc js.nanorc json.nanorc jsx.nanorc julia.nanorc keymap.nanorc
        kickstart.nanorc kotlin.nanorc ledger.nanorc lisp.nanorc lua.nanorc
        m3u.nanorc makefile.nanorc man.nanorc markdown.nanorc moonscript.nanorc
        mpdconf.nanorc mutt.nanorc nanorc.nanorc nginx.nanorc nmap.nanorc
        ocaml.nanorc octave.nanorc patch.nanorc peg.nanorc perl.nanorc perl6.nanorc
        php.nanorc pkg-config.nanorc pkgbuild.nanorc po.nanorc pov.nanorc
        powershell.nanorc privoxy.nanorc prolog.nanorc properties.nanorc pug.nanorc
        puppet.nanorc python.nanorc reST.nanorc rego.nanorc rpmspec.nanorc
        ruby.nanorc rust.nanorc scala.nanorc sed.nanorc seed7.nanorc sh.nanorc
        sieve.nanorc sls.nanorc solidity.nanorc sparql.nanorc sql.nanorc
        subrip.nanorc svn.nanorc swift.nanorc systemd.nanorc tcl.nanorc tex.nanorc
        toml.nanorc ts.nanorc twig.nanorc v.nanorc vala.nanorc verilog.nanorc
        vhdl.nanorc vi.nanorc x11basic.nanorc xml.nanorc xresources.nanorc
        yaml.nanorc yum.nanorc zeek.nanorc zig.nanorc zsh.nanorc zshrc.nanorc"
)

# Download extra nanorc files
[[ ! -d "$HOME/.nano" ]] && mkdir -p "$HOME/.nano"
for source in "${extra_sources[@]}"; do
    # shellcheck disable=SC2206
    words=($source)
    base_url="${words[0]}"
    for filename in "${words[@]:1}"; do
        dest="$HOME/.nano/$filename"
        if [[ ! -f "$dest" ]] || [[ "$1" == "--force" ]]; then
            curl -fsSL "$base_url/$filename" -o "$dest" \
                && echo "Downloaded $filename" \
                || echo "Failed to download $filename"
        fi
    done
done

# Add includes to ~/.nanorc
[[ ! -f "$HOME/.nanorc" ]] && touch "$HOME/.nanorc"

for config in "${configs[@]}"; do
    if ! grep -qF "include /usr/share/nano/$config" "$HOME/.nanorc"; then
        echo "include /usr/share/nano/$config" >> "$HOME/.nanorc"
    fi
done

for source in "${extra_sources[@]}"; do
    # shellcheck disable=SC2206
    words=($source)
    for filename in "${words[@]:1}"; do
        if ! grep -qF "include $HOME/.nano/$filename" "$HOME/.nanorc"; then
            echo "include $HOME/.nano/$filename" >> "$HOME/.nanorc"
        fi
    done
done
