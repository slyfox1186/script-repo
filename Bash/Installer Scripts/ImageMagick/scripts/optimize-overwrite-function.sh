#!/Usr/bin/env bash

imow() {
    local cnt_queue cnt_total dimensions pip_lock random_dir tmp_file v_noslash

    clear
    
# Required apt packages
    sudo apt-get -qq -y install libsox-dev sox
    clear
    
# Required pip packages
    pip_lock="$(find /usr/lib/python3* -name 'EXTERNALLY-MANAGED')"
    if [ -n "$pip_lock" ]; then
        sudo rm "$pip_lock"
    fi
    
    test_pip="$(pip show google_speech 2>/dev/null)"
    if [ -z "$test_pip" ]; then
        pip install google_speech
    fi
    unset pip_lock test_pip
    
# Delete any useless zone idenfier files that spawn from copying a file from windows ntfs into a wsl directory
    find . -type f -iname "*:Zone.Identifier" -delete 2>/dev/null
    
# Get the unmodified path of each matching file
    if [ -d pics-convert ]; then
        cd pics-convert || exit 1
    fi
    
# Get the file count inside the directory
    cnt_queue=$(find . -maxdepth 1 -type f -iname '*.jpg' | wc -l)
    cnt_total=$(find . -maxdepth 1 -type f -iname '*.jpg' | wc -l)
    
    clear
    for i in *.jpg
    do
        cnt_queue=$((cnt_queue-1))
    cat <<EOF
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

Working Dir: $PWD

Total files:    $cnt_total
Files in queue: $cnt_queue

Converting: $i > $i%%.jpg-IM.jpg

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF
    
        random_dir="$(mktemp -d)"
        dimensions="$(identify -format '%wx%h' "$i")"
    
        echo
        convert "$i"                            \
                -monitor                          \
                -filter Triangle                  \
                -define filter:support=2          \
                -thumbnail "$dimensions"        \
                -strip                            \
                -unsharp '0.25x0.08+8.3+0.045'    \
                -dither None                      \
                -posterize 136                    \
                -quality 82                       \
                -define jpeg:fancy-upsampling=off \
                -auto-level                       \
                -enhance                          \
                -interlace none                   \
                -colorspace sRGB                  \
                "$random_dir/$i%%.jpg.mpc"
    
        for file in "$random_dir"/*.mpc
        do
            convert "$file" -monitor "$file%%.mpc.jpg"
            tmp_file="$(echo "$file" | sed 's:.*/::')"
            mv "$file%%.mpc.jpg" "$PWD/$tmp_file%%.*-IM.jpg"
            rm -f "$PWD/$tmp_file%%.*.jpg"
    
            for v in $file
            do
                v_noslash="$v%/"
                rm -fr "$v_noslash%/*"
            done
        done
        clear
    done
    
    if [ "$?" -eq '0' ]; then
        google_speech 'Image conversion completed.' 2>/dev/null
        exit 0
    else
        google_speech 'Image conversion failed.' 2>/dev/null
        read -p 'Press enter to exit.'
        exit 1
    fi
}
