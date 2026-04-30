#!/usr/bin/env bash

find_any() {
  local dirs=(./src/frontend ./src/backend)
  # 1) find standalone "any" in TS/TSX
  # 2) feed into awk for filtering and colouring
  grep -RIn --color=never '\bany\b' "${dirs[@]}" --exclude-dir=node_modules --include='*.ts' --include='*.tsx' | awk -F: '
  {
    file=$1; line=$2
    # Rebuild the code text (fields 3..end)
    rest = substr($0, length(file)+length(line)+3)

    # Find positions of "//" comment and the first "any"
    cpos = match(rest, /\/\//)
    apos = match(rest, /\bany\b/)

    # Debug print to stderr (will not interfere with normal output)
    # This will show you the values awk is working with for each line grep finds.
    print "DEBUG: file=" file ", line=" line ", cpos=" cpos ", apos=" apos ", rest=" rest > "/dev/stderr"

    # If any is inside a comment, skip it
    if (cpos && apos > cpos) {
      print "DEBUG: Skipping line " line " (any in comment: cpos=" cpos ", apos=" apos ")" > "/dev/stderr"
      next
    } else {
      # This message helps identify lines that are NOT skipped and why the condition failed.
      print "DEBUG: NOT skipping line " line " (cpos=" cpos ", apos=" apos ", filter_condition_false)" > "/dev/stderr"
    }

    # Highlight "any" in bold red
    gsub(/\bany\b/, "\033[31;1m&\033[0m", rest)

    # Print file:line:code with colours
    printf("\033[34m%s\033[0m:\033[33m%s\033[0m:%s\n",
           file, line, rest)
  }
  '
}

