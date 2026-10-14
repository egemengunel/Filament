#!/bin/bash
# Install the Tapo HomeKit bridge as a login agent that runs only on the home network.
# Re-run after changing the code; the live HomeKit pairing in APP_DIR is kept.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Library/Application Support/TapoHome"
LABEL="com.tapo-home.bridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/tapo-home.log"
UV="$(command -v uv)"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

mkdir -p "$APP_DIR"
rsync -a --delete --exclude .venv --exclude __pycache__ --exclude homekit.state \
  "$SRC_DIR/tapo_home" "$SRC_DIR/pyproject.toml" "$SRC_DIR/uv.lock" \
  "$SRC_DIR/.python-version" "$SRC_DIR/config.json" "$APP_DIR/"
# Carry the existing pairing over on first install only
if [[ ! -f "$APP_DIR/homekit.state" && -f "$SRC_DIR/homekit.state" ]]; then
  cp "$SRC_DIR/homekit.state" "$APP_DIR/homekit.state"
fi
(cd "$APP_DIR" && "$UV" sync --frozen --quiet)

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_DIR/.venv/bin/python</string>
    <string>-m</string>
    <string>tapo_home.supervisor</string>
  </array>
  <key>WorkingDirectory</key><string>$APP_DIR</string>
  <key>EnvironmentVariables</key>
  <dict><key>PYTHONUNBUFFERED</key><string>1</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed. Logs: $LOG"
