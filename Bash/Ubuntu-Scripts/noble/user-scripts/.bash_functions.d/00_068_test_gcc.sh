#!/usr/bin/env bash

## TEST GCC & CLANG ##
test_gcc() {
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
        "$1" -Q -v "$random_dir/hello.c"
    else
        read -r -p "Enter the GCC binary you wish to test (example: gcc-11): " choice
        echo
        "$choice" -Q -v "$random_dir/hello.c"
    fi
    sudo rm -fr "$random_dir"
}
