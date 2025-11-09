#!/usr/bin/env bash

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
KIMI_BACKUP="$CLAUDE_DIR/settings.json.kimi.backup"
GLM_BACKUP="$CLAUDE_DIR/settings.json.glm.backup"

# --- sanity checks ----------------------------------------------------------
[[ -d "$CLAUDE_DIR" ]] || { echo "Error: directory $CLAUDE_DIR missing" >&2; exit 1; }
[[ -f "$SETTINGS" ]]   || { echo "Error: $SETTINGS not found" >&2; exit 1; }

# --- show current state -----------------------------------------------------
echo "Directory: $CLAUDE_DIR"
for f in "$SETTINGS" "$KIMI_BACKUP" "$GLM_BACKUP"; do
    [[ -f "$f" ]] && echo "  ✓ $(basename "$f")" || echo "  ✗ $(basename "$f")"
done

# --- toggle logic -----------------------------------------------------------
if [[ -f "$KIMI_BACKUP" ]]; then
    mv "$SETTINGS" "$GLM_BACKUP" && mv "$KIMI_BACKUP" "$SETTINGS"
    echo "✅ Switched to KIMI configuration"    
elif [[ -f "$GLM_BACKUP" ]]; then
    mv "$SETTINGS" "$KIMI_BACKUP" && mv "$GLM_BACKUP" "$SETTINGS"
    echo "✅ Switched to GLM configuration"
else
    echo ""
    echo "❌ Cannot toggle. You need to create one backup first:"
    echo "   cp $SETTINGS $KIMI_BACKUP   # to save KIMI config"
    echo "   cp $SETTINGS $GLM_BACKUP    # to save GLM config"
    exit 1
fi
