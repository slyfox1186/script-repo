#!/usr/bin/env bash

test_clang() {
    local choice random_dir

    # CREATE A TEMPORARY C FILE TO RUN OUR TESTS AGAINST
    random_dir=$(mktemp -d)
    cat > "$random_dir/hello.c" <<'EOF'
#include <stdio.h>
int main(void)
{
   printf("Hello World!\n");
   return 0;
}
EOF

    if [[ -n "$1" ]]; then
        "$1" -v "$random_dir/hello.c" -o "$random_dir/hello" && "$random_dir/hello"
    else
        read -r -p "Enter the Clang binary you wish to test (example: clang-11): " choice
        echo
        "$choice" -v "$random_dir/hello.c" -o "$random_dir/hello" && "$random_dir/hello"
    fi
    sudo rm -fr "$random_dir"
}
