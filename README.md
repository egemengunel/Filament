# Filament

Control a TP-Link **Tapo L530E** smart bulb from Apple Home and a native macOS widget. No TP-Link cloud and no HomeKit certification needed.

- **HomeKit bridge:** exposes the bulb to Apple Home (on/off, brightness, color, white temperature), so it works with Siri, iPhone Control Center and the Home app.
- **macOS widget:** Home-style tiles in three sizes, with power, brightness and favourite color presets.
- **Local only:** talks to the bulb over your Wi-Fi using TP-Link's newer TPAP protocol.

## How it works

```
Apple Home ──HAP──▶ tapo_home.bridge ──TPAP──▶ Tapo bulb
Bulb widget ──HTTP 127.0.0.1:51828──▶ ┘
```

- `tapo_home/` is a Python package built on [python-kasa](https://github.com/python-kasa/python-kasa). It is pinned to the `feature/tpap` branch ([#1592](https://github.com/python-kasa/python-kasa/pull/1592)), because released python-kasa can't talk to TPAP firmware.
- `tapo_home.supervisor` runs as a login agent. It starts the bridge only while the Mac is on the home network, which it recognises by the router's MAC address.
- `BulbWidget/` holds the SwiftUI WidgetKit app (`Bulb.app`). Its buttons are App Intents that call the bridge's local API.

## Setup

Requirements: macOS 26+, [uv](https://docs.astral.sh/uv/), Xcode 27+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. In the Tapo app, turn on **Me → Third-Party Services → Third-Party Compatibility**.
2. Save your TP-Link login to the Keychain (service `tapo-home`):
   ```bash
   ./save-credentials.sh
   ```
3. Copy `config.example.json` to `config.json`. Fill in the bulb's IP, plus your router's MAC from `arp -n <gateway-ip>`.
4. Try it:
   ```bash
   uv run tapo status
   ```
5. Install the background bridge:
   ```bash
   ./install.sh
   ```
   Then add the accessory in the Home app with the setup code from `~/Library/Logs/tapo-home.log`.

## Usage

```bash
uv run tapo on | off | toggle | status
uv run tapo brightness 40
uv run tapo color 240 100      # hue 0-360, saturation 0-100
uv run tapo temp 2700          # 2500-6500 K
tail -f ~/Library/Logs/tapo-home.log
./uninstall.sh                 # removes the login agent, keeps the pairing
```

## Widget

```bash
cd BulbWidget
xcodegen generate
xcodebuild -project Bulb.xcodeproj -scheme Bulb -configuration Release \
  -derivedDataPath ~/Library/Caches/BulbWidgetBuild -allowProvisioningUpdates build
```

Copy `Bulb.app` to `/Applications`, open it once, then add **Bulb** from **Edit Widgets**.

## Limits

- Apple Home controls the bulb only while this Mac is at home and awake.
- Remote access, Home widgets and automations need an Apple home hub (HomePod or Apple TV).
