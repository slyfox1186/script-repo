#!/bin/bash
# Environment variables and default applications

# ====================
# ENVIRONMENT VARIABLES
# ====================
# Default applications
export EDITOR="nano"
export VISUAL="nano"
export PAGER="less"

# Performance and behavior settings
export PYTHONUTF8=1
export MAGICK_THREAD_LIMIT=16
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# PostgreSQL configuration
export PG_CONFIG="/usr/bin/pg_config"

# ====================
# API KEYS
# ====================
# Google API's - Note: Consider moving these to a separate private file
GOOGLE_API_KEY="AIzaSyD9xQLbEB6924BbgxnS1FvXpeKBmCIFyaY"
GOOGLE_CSE_ID="f2a9a9431a797430a"
OPENWEATHER_API_KEY="092269b7aa1069ab41a0210bca856b16"
export GOOGLE_API_KEY GOOGLE_CSE_ID OPENWEATHER_API_KEY