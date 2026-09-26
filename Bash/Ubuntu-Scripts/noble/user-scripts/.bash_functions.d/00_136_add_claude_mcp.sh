#!/usr/bin/env bash

add_claude_mcp() {
    source /home/jman/.bashrc
    claude mcp add sequential-thinking -- npx @modelcontextprotocol/server-sequential-thinking
    claude mcp add --transport http context7 https://mcp.context7.com/mcp --header "CONTEXT7_API_KEY: ${CONTEXT7_API_KEY:?CONTEXT7_API_KEY is not set}"
    claude mcp add playwright npx @playwright/mcp@latest
}

alias acm='add_claude_mcp'
