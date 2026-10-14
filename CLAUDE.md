# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A local-only controller for a Tapo L530E bulb that speaks TP-Link's **TPAP** protocol. It has two halves:

- a Python HomeKit bridge (`tapo_home/`)
- a SwiftUI macOS widget app (`BulbWidget/`)

There are no tests or linters; verify against the real bulb.

## Commands

```bash
uv sync                                  # venv (Python pinned to 3.12, see below)
uv run tapo status                       # CLI: on|off|toggle|status|brightness N|color H S|temp K
uv run tapo-homekit                      # run the bridge in the foreground (stop the agent first)
./install.sh                             # deploy the bridge as LaunchAgent com.tapo-home.bridge
./uninstall.sh
tail -f ~/Library/Logs/tapo-home.log
curl -s 127.0.0.1:51828/state            # bridge's local API, used by the widget

cd BulbWidget && xcodegen generate       # project.yml is the source of truth; never hand-edit the .xcodeproj
xcodebuild -project Bulb.xcodeproj -scheme Bulb -configuration Release \
  -derivedDataPath ~/Library/Caches/BulbWidgetBuild -allowProvisioningUpdates build
```

## Architecture

- **Protocol.** `python-kasa` is pinned in `pyproject.toml` to a commit on ZeliardM's `feature/tpap` branch (upstream PR #1592). Released python-kasa reports this bulb as "unsupported". Don't swap it for the PyPI release until TPAP support lands there.
- **Credentials.** `connection.py` reads the TP-Link account from the macOS Keychain (service `tapo-home`, written by `save-credentials.sh`). It decodes hex-encoded account names, because `security` prints non-ASCII that way.
- **Process tree.** launchd starts `tapo_home.supervisor`. Every 15 s it compares the default gateway's MAC with `config.json` `home_gateway_mac`, then:
  - starts `tapo_home.bridge` as a subprocess on the home network, kills it elsewhere;
  - restarts it when the Mac's IP changes.
- **Bridge (`bridge.py`).** One HAP-python `TapoLight` accessory owns a single persistent kasa `Device`, guarded by an `asyncio.Lock`.
  - It polls the bulb every 5 s to mirror the state into HomeKit characteristics.
  - The `run_at_interval` loop also lazily starts an aiohttp server on `127.0.0.1:51828`, with `GET /state` and `POST /set`. `/set` accepts `on`, `brightness`/`delta`, and `hue`+`saturation` or `color_temp`.
  - HomeKit writes go through `_apply`; widget writes go through `apply_command`.
  - On any device error the connection is dropped and re-established on the next poll.
- **Installed copy.** `install.sh` rsyncs the code into `~/Library/Application Support/TapoHome` and runs it from there. Background agents can't read TCC-protected folders such as Desktop. The live HomeKit pairing (`homekit.state`) lives in that folder; the installer copies it from the repo only on first install. **Code changes take effect only after `./install.sh`.** A stale bridge makes the widget show "No Response" or fail to decode the new JSON fields.
- **Widget.**
  - `Shared/` is compiled into both the app and the widget extension. It holds `BulbClient` (HTTP to the bridge), `BulbIntents` (App Intents used by `Button(intent:)`) and `BulbPreset`.
  - The presets are the user's fixed Tapo favourites: Red 18%, Orange 20%, 2500K 20%, 4500K 100%. They are deliberately not user-configurable.
  - Widgets can't drag, so the sliders are stacks of tap targets (10% levels).
  - The `BulbState` JSON keys must match `TapoLight.snapshot()`.
  - Both targets are sandboxed, with `network.client` and `NSAllowsLocalNetworking`.

## Gotchas

- **Python 3.12 pin.** On iCloud-synced folders, uv's `.pth` files get the macOS hidden flag, and Python 3.13+ skips hidden `.pth` files. Keep `.python-version` at 3.12.
- **Build location.** `codesign` fails on build products inside iCloud-synced folders ("resource fork… detritus"). Build with `-derivedDataPath` outside the repo.
- **Stale widget copies.** macOS keeps serving an old widget if several `Bulb.app` copies are registered with the same build number. When shipping a widget change:
  1. Bump `CURRENT_PROJECT_VERSION` in `project.yml`.
  2. Install only to `/Applications`.
  3. `lsregister -u` and delete the other copies (`pluginkit -m -A -D -i com.egemengunel.Bulb.Widget` lists them).
  4. `killall chronod NotificationCenter`.
- **No previews.** Xcode can't preview macOS widgets. To check visuals, render `SmallBulbView`/`MediumBulbView`/`LargeBulbView` with `ImageRenderer` from a scratch Swift script.
- **Git hygiene.** `config.json` (home network details) and `homekit.state` (pairing keys) are gitignored; never commit them.
