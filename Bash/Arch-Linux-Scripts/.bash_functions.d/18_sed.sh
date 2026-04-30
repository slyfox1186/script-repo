#!/usr/bin/env bash

rpt() {
  # usage text
  local usage="Usage: rpt <find_text> <replace_text> <ext1;ext2;...> [exclude1;exclude2;...]
  
  Quickly find-and-replace across multiple file extensions.
  
  Arguments:
    find_text        The literal (or regex) text to search for
    replace_text     The text to replace it with (use '' for deletion)
    ext1;ext2;...    Semicolon-separated list of file extensions (no leading dot)
    exclude1;...     (Optional) Semicolon-separated list of path patterns to skip

  Examples:
    # strip all 'foo' in .js/.ts but skip node_modules and dist
    rpt 'foo' '' 'js;ts' 'node_modules;dist'

    # rename 'oldName'→'newName' in .py
    rpt 'oldName' 'newName' 'py'
  "

  # show help
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "%s\n" "$usage"
    return 0
  fi

  # need at least 3 args
  if [ $# -lt 3 ]; then
    printf "Error: too few arguments.\n\n%s\n" "$usage" >&2
    return 1
  fi

  local find_text="$1"
  local replace_text="$2"
  local ext_list="$3"
  local exclude_list="${4:-}"

  # build exclude regex if provided
  local exclude_regex=""
  if [ -n "$exclude_list" ]; then
    IFS=';' read -ra excludes <<< "$exclude_list"
    exclude_regex=$(printf "%s|" "${excludes[@]}")
    exclude_regex=${exclude_regex%|}
  fi

  # split extensions
  IFS=';' read -ra exts <<< "$ext_list"

  # run replace
  for ext in "${exts[@]}"; do
    find . -type f -name "*.${ext}" \
      | {
          if [ -n "$exclude_regex" ]; then
            grep -Ev "$exclude_regex"
          else
            cat
          fi
        } \
      | while IFS= read -r file; do
          sed -i "s/${find_text}/${replace_text}/g" "$file"
        done
  done
}

mysed() {
  # Check for help flag when passed as the only argument
  if [ "$#" -eq 1 ] && { [ "$1" = "--help" ] || [ "$1" = "-h" ]; }; then
    echo "Usage: mysed 'search_pattern' 'replacement' 'ext1;ext2;...'"
    echo ""
    echo "This function recursively finds files with the specified extensions and"
    echo "performs an in-place substitution of all occurrences of search_pattern"
    echo "with replacement using sed."
    echo ""
    echo "Example:"
    echo "  mysed 'https://elber-live\\.netlify\\.app' 'https://elber-ai.netlify.app/' 'ts;tsx;js'"
    return 0
  fi

  if [ "$#" -ne 3 ]; then
    echo "Usage: mysed 'search_pattern' 'replacement' 'ext1;ext2;...'"
    return 1
  fi

  local search="$1"
  local replace="$2"
  local extList="$3"

  # Convert the semicolon-separated list to an array.
  IFS=';' read -r -a exts <<< "$extList"

  # Build the find command parameters dynamically.
  local -a find_args=(.)
  find_args+=(-type f)
  
  # Begin the grouped file extension tests.
  find_args+=( \( )
  for i in "${!exts[@]}"; do
    # Trim any whitespace in the extension in case it exists.
    ext="${exts[$i]//[[:space:]]/}"
    find_args+=(-name "*.${ext}")
    if [ "$i" -lt $(( ${#exts[@]} - 1 )) ]; then
      find_args+=(-o)
    fi
  done
  find_args+=( \) )

  # Append the sed command to replace all matches in place.
  find_args+=(-exec sed -i "s|${search}|${replace}|g" {} +)

  # Execute the find command.
  find "${find_args[@]}"
}

