#!/Usr/bin/env bash


GREEN='\033[0;32m'

echo -e "$GREENConverting images to ICONS...$NC"

cd "$PWD"

SIZES="256,128,64,48,32,16"

[ -d "output" ] && rm -fr "output"
mkdir "output"

find ./ -type f \( -iname "*.jpg" -o -iname "*.png" \) -print0 |
while IFS= read -r -d $'\0' file; do
    output_path="Output/$filename_without_ext.ico"

    convert -background none "$file" -define icon:auto-resize="$SIZES" "$output_path"
    if [ $? -eq 0 ]; then
        echo -e "$GREENConvert success: $file$NC"
    else
        echo -e "$REDConvert failed: $file$NC"
    fi
done
