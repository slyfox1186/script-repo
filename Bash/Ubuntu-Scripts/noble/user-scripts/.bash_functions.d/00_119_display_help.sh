#!/usr/bin/env bash

display_help() {
    cat <<EOF
Usage: ${FUNCNAME[0]} [OPTIONS]

Calculate the number of downvotes on a Reddit post.

Options:
  -u, --upvotes <number>         Total number of upvotes on the post
  -p, --percentage <number>      Upvote percentage (without the % sign)
  -h, --help                     Display this help message and exit

Examples:
  ${FUNCNAME[0]} --upvotes 8 --percentage 83
EOF
}
