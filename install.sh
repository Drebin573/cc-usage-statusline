#!/bin/sh
# Installer for the Claude Code usage status line.
# Idempotent: safe to run multiple times. Merges into settings.json with jq
# rather than overwriting it. Run from this directory, or pipe via curl.

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/statusline-command.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
SRC="$SCRIPT_DIR/statusline-command.sh"

# ── dependency checks ────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { echo "error: 'jq' is required but not installed." >&2; exit 1; }
command -v git >/dev/null 2>&1 || echo "warning: 'git' not found — repo/branch info will be blank." >&2

[ -f "$SRC" ] || { echo "error: statusline-command.sh not found next to this installer." >&2; exit 1; }

# ── 1. install the script ────────────────────────────────────
mkdir -p "$CLAUDE_DIR"
cp "$SRC" "$DEST"
chmod +x "$DEST"
echo "installed: $DEST"

# ── 2. merge statusLine config into settings.json ───────────
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  echo "backed up existing settings to $SETTINGS.bak"
else
  echo '{}' > "$SETTINGS"
fi

tmp=$(mktemp)
jq --arg cmd "$DEST" \
  '.statusLine = {"type": "command", "command": $cmd}' \
  "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "configured: statusLine in $SETTINGS"
echo
echo "Done. Start a new Claude Code session (or run /statusline) to see it."
