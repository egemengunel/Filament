#!/bin/bash
# Stop and remove the login agent. The installed copy (and HomeKit pairing) is left in
# ~/Library/Application Support/TapoHome so a reinstall keeps the bulb paired.
LABEL="com.tapo-home.bridge"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Uninstalled the background service."
