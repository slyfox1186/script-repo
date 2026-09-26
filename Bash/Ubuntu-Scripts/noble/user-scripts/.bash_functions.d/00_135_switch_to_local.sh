#!/usr/bin/env bash

# Switch Claude Code to local Qwen LLM
switch_to_local() {
    if [[ -f /home/jman/.claude/settings.json.qwen.bak ]]; then
        mv /home/jman/.claude/settings.json /home/jman/.claude/settings.json.claude.bak
        mv /home/jman/.claude/settings.json.qwen.bak /home/jman/.claude/settings.json
    elif [[ -f /home/jman/.claude/settings.json.claude.bak ]]; then
        mv /home/jman/.claude/settings.json /home/jman/.claude/settings.json.qwen.bak
        mv /home/jman/.claude/settings.json.claude.bak /home/jman/.claude/settings.json
    fi
}

alias stl='switch_to_local'
