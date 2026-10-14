#!/bin/bash
# Saves your TP-Link/Tapo account login to the macOS Keychain (service "tapo-home").
set -e
echo "Enter the email you use to log in to the Tapo app."
read -r -p "TP-Link email: " email
security delete-generic-password -s tapo-home >/dev/null 2>&1 || true
echo "Now type your Tapo password (nothing will show while you type), press Enter, then type it again."
security add-generic-password -s tapo-home -a "$email" -w
echo "Saved. Go back to the chat and say done."
