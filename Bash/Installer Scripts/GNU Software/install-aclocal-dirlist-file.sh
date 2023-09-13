#!/usr/bin/env bash

###############################################################################################################################
##
##  Purpose: ACLOCAL has a special file that can be created in the "acdir" aka /usr/share/aclocal folder that
##           directly influences where ACLOCAL looks for m4 files when running commands such as autoconf.
##
##  Website Manual: Modifying the Macro Search Path: dirlist
##                  https://www.gnu.org/software/automake/manual/html_node/Macro-Search-Path.html#Macro-Search-Path
##
###############################################################################################################################

clear

if [ "${EUID}" -ne '0' ]; then
    printf "%s\n\n" 'You MUST run this script as root/sudo.'
    exit 1
fi

printf "%s\n\n" "Restoring ACLOCAL's dirlist file"
sleep 2

file=/usr/share/aclocal/dirlist

cat > "${file}" <<'EOF'
/usr/share/aclocal
/usr/share/aclocal-1.16
/usr/share/libtool
/usr/share/autoconf/autoconf
/usr/share/autoconf/autotest
/usr/share/autoconf/m4sugar
/usr/share/autogen
/usr/share/doc/m4/examples
/usr/share/doc/guile-3.0-dev/examples/compat
/usr/share/bison/skeletons
/usr/share/bison/m4sugar
EOF
clear

if [ -f "${file}" ]; then
    printf "%s\n\n" "Successfully created: \"${file}\":Line ${LINENO}"
    sleep 2
    exit 0
else
    printf "%s\n\n" "FAILED to create: \"${file}\":Line ${LINENO}"
    exit 1
fi
