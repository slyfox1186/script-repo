# OPTIMIZE AND OVERWRITE THE ORIGINAL IMAGES
imow()
{
    clear
    local i dimensions random v v_noslash

    # Delete any useless zone idenfier files that spawn from copying a file from windows ntfs into a WSL directory
    find . -name "*:Zone.Identifier" -type f -delete 2>/dev/null

    # find all jpg files and create temporary cache files from them
    for i in *.{jpg,png}
    do
        # create a variable to hold a randomized directory name to protect against crossover if running
        # this function more than once at a time
        random="$(mktemp --directory)"
        echo '========================================================================================================='
        echo
        echo "Working Directory: ${PWD}"
        echo
        printf "Converting: %s\n             >> %s\n              >> %s\n               >> %s\n" "${i}" "${i%%.jpg}.mpc" "${i%%.jpg}.cache" "${i%%.jpg}-IM.jpg"
        echo
        echo '========================================================================================================='
        echo
        dimensions="$(identify -format '%wx%h' "${i}")"
        convert "${i}" -monitor -filter 'Triangle' -define filter:support='2' -thumbnail "${dimensions}" -strip \
            -unsharp '0.25x0.08+8.3+0.045' -dither None -posterize '136' -quality '82' -define jpeg:fancy-upsampling='off' \
            -define png:compression-filter='5' -define png:compression-level='9' -define png:compression-strategy='1' \
            -define png:exclude-chunk='all' -auto-level -enhance -interlace 'none' -colorspace 'sRGB' "${random}/${i%%.jpg}.mpc"
        clear
        for i in "${random}"/*.mpc
        do
            if [ -f "${i}" ]; then
                convert "${i}" -monitor "${i%%.mpc}.jpg"
                if [ -f "${i%%.mpc}.jpg" ]; then
                    CWD="$(echo "${i}" | sed 's:.*/::')"
                    mv "${i%%.mpc}.jpg" "${PWD}/${CWD%%.*}-IM.jpg"
                    rm -f "${PWD}/${CWD%%.*}.jpg"
                    for v in "${i}"
                    do
                        v_noslash="${v%/}"
                        rm -fr "${v_noslash%/*}"
                        clear
                    done
                else
                    clear
                    echo 'Error: Unable to find the optimized image.'
                    echo
                    return 1
                fi
            fi
        done
    done

    # The text-to-speech below requries the following packages:
    # pip install gTTS; sudo apt -y install sox libsox-fmt-all
    if [ "${?}" -eq '0' ]; then
        google_speech 'Image conversion completed.'
        return 0
    else
        google_speech 'Image conversion failed.'
        return 1
    fi
}
imow
