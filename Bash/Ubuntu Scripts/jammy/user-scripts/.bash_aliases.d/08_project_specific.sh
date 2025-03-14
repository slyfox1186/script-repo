#!/bin/bash
# Project-specific and temporary aliases

# Development workflow
alias crdis='clear; cd frontend && npm run build; cd ..;  redis-cli flushall && conda activate gguf && clear; python3 app.py'
alias rdis='redis-cli flushall && conda activate gguf && clear; python3 app.py'
alias frun='clear; npm run build && clear; npm run start'