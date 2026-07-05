#!/bin/bash
# Cursor "stop" hook: fires when the agent finishes responding to a prompt.
# Triggers Xcode's Build & Run (Cmd+R) on the currently selected scheme.

# Drain stdin (Cursor sends JSON we don't need)
cat > /dev/null

# Only run if Xcode is actually open with this project
if ! osascript -e 'tell application "System Events" to (name of processes) contains "Xcode"' 2>/dev/null | grep -q true; then
  exit 0
fi

osascript <<'EOF'
tell application "Xcode" to activate
delay 0.3
tell application "System Events" to keystroke "r" using command down
EOF

exit 0
